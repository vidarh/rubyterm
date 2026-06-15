
# FIXME: Roll this into the actual buffer.
class TrackChanges
  # The cursor is rendered as an overlay - a cell repainted with this
  # background. The AnsiBackend recognises it and turns it into a real
  # terminal cursor; the X11 backend paints the block.
  CURSOR = 0xff00ff

  def initialize buffer, adapter
    @buffer = buffer
    @adapter = adapter
    @cursor_pos = nil   # where the cursor overlay was last painted
    # When true, #set only mutates the buffer; rendering is deferred to the
    # next #draw_flush, which walks the buffer's damage (generation) instead
    # of drawing eagerly per cell. Default off (the proven eager path) while
    # the damage-driven path is validated against it; see test_damage.rb.
    @defer = false
    @last_flush_gen = 0
    @rows = 24      # overwritten by on_resize before use
    # When true, ALL rendering is suppressed (the buffer still mutates):
    # used to jump-scroll a flood of output by interpreting many chunks and
    # then doing ONE full redraw of the final screen, skipping the
    # intermediate frames the user would never see. The model (incl.
    # scrollback) stays correct; only the framebuffer is batched.
    @suspend = false
    clear
  end

  attr_reader :buffer
  attr_accessor :defer, :suspend

  # Rendering is off either because we're viewing scrollback history or
  # because output is being jump-scrolled.
  def suppressed? = @suspend || @adapter.scrollback_mode

  def clear
    # Flush any batched text first: otherwise pending draws are emitted to
    # the screen AFTER the clear and survive it (stale content; the buffer
    # is already correct, so only the incremental render diverges).
    draw_flush
    @buffer.clear
    @adapter.clear unless suppressed?
  end

  # Methods that does not alter the buffer
  def lineattrs(y)  = @buffer.lineattrs(y)
  def get(x,y)      = @buffer.get(x,y)
  def scroll_start  = @buffer.scroll_start
  def scroll_end    = @buffer.scroll_end
  def blinky        = @buffer.blinky
  # Backend-facing queries the interpreter routes through the buffer rather
  # than reaching the adapter directly (so Term talks only to its buffer).
  def scrollback_mode = @adapter.scrollback_mode
  def set_columns(cols) = @adapter.set_columns(cols)
  def each_character(scrollback_offset = 0, &block)
    @buffer.each_character(scrollback_offset, &block)
  end

  # # Mutation
  #
  # Scroll the region up one line: draw pending damage, scroll the model,
  # then drive the backend - a blit, or (when scrolled back) just anchor the
  # viewport so the frozen history lines stay in place. The blit's inclusive
  # bottom row is the scroll region's, or the last screen row when unset.
  def scroll_up
    draw_flush
    start  = @buffer.scroll_start.to_i
    bottom = @buffer.scroll_end || (@rows - 1)
    @buffer.scroll_up
    return if @suspend
    if @adapter.scrollback_mode
      @adapter.scrollback_anchor
    else
      @adapter.scroll_up(start, bottom)
    end
  end

  def delete_lines(y, num, maxy)
    draw_flush
    # Delete repeatedly at the SAME row: each delete shifts the rows below
    # up into y, so deleting at y+i would skip every other line.
    num.times { @buffer.delete_line(y) }
    @adapter.delete_lines(y, num, @buffer.scroll_end||maxy) unless suppressed?
  end

  def insert_lines(y, num, maxy)
    draw_flush
    num.times.each {|i| @buffer.insert_line(y+i) }
    @adapter.insert_lines(y, num, @buffer.scroll_end || maxy) unless suppressed?
  end

  def clear_line(*args)
    draw_flush
    @buffer.clear_line(*args)
    @adapter.clear_line(*args) unless suppressed?
  end

  def set(x,y,c,fg,bg,mode)
    # MUST be before the @buffer.set below, as draw_buffered compares
    # against the buffer's *current* content to avoid redundant redraws.
    # Skipped while scrolled back so live output does not paint over the
    # scrolled-back view (the buffer still updates).
    #
    # draw_buffered reads the cell's four fields synchronously and never
    # retains the array, so we reuse a per-instance scratch cell instead of
    # allocating [c,fg,bg,mode] per character. Safe: a single processing
    # thread, with no re-entrancy back into #set.
    unless @defer || @adapter.scrollback_mode
      s = (@scratch ||= [])
      s[0], s[1], s[2], s[3] = c, fg, bg, mode
      draw_buffered(x, y, s)
    end
    @buffer.set(x,y,c,fg,bg,mode)
  end

  def on_resize(w,h)
    raise if !h
    @rows = h   # used as the default scroll-region bottom in scroll_up
    # FIXME: Window is currently resized separately.
    @buffer.on_resize(w,h)
  end
  
  # Explicit delegations to the underlying buffer, replacing a catch-all
  # method_missing so the buffer's surface through TrackChanges is
  # knowable. Each is a model-only mutation whose on-screen redraw the
  # caller drives separately (Term#redraw_line_from_cursor after
  # insert/delete_chars; Term#set_line_attrs after set_lineattrs) or a
  # read-only query - none of them paint, which is why they bypass the
  # adapter. (The scroll_start/scroll_end getters are defined above; only
  # the setters delegate.)
  def insert(*args)        = @buffer.insert(*args)
  def delete_chars(*args)  = @buffer.delete_chars(*args)
  def set_lineattrs(*args) = @buffer.set_lineattrs(*args)
  def scroll_start=(v); @buffer.scroll_start = v; end
  def scroll_end=(v);   @buffer.scroll_end = v;   end
  def scrollback_size      = @buffer.scrollback_size
  def each_character_between(*args, &block) = @buffer.each_character_between(*args, &block)

  def redraw_blink
    return nil if @adapter.scrollback_mode
    b = @buffer.blinky
    return nil if b.empty?
    b.each { |x,y| redraw(x,y) }
    draw_flush
  end

  def redraw(x,y) = draw_buffered(x,y, @buffer.get(x,y), true)

  # Render the cursor overlay at (x,y) if +visible+, after restoring the
  # cell under its previous position. A no-op while scrolled back, so the
  # live cursor doesn't paint over the frozen history view.
  def draw_cursor(x, y, visible)
    return if @adapter.scrollback_mode
    clear_cursor
    return unless visible
    redraw_with(x, y, bg: CURSOR)
    @cursor_pos = [x, y]
  end

  def clear_cursor
    return if @adapter.scrollback_mode
    return unless @cursor_pos
    redraw(*@cursor_pos)
    @cursor_pos = nil
  end

  def redraw_all(scrollback_offset = 0)
    @buffer.each_character(scrollback_offset) { |*args| draw_buffered(*args, true) }
    # We just force-drew every cell, so nothing is damaged relative to now:
    # advance the watermark before flushing so the damage walk doesn't redraw
    # it all again (and so the next incremental flush only sees new changes).
    @last_flush_gen = @buffer.generation
    draw_flush
  end

  def redraw_with(x,y, fg: nil, bg: nil)
    cell = Array(@buffer.get(x,y)).dup
    cell[0] ||= " "
    cell[1] = fg if fg
    cell[2] = bg if bg
    draw_buffered(x,y, cell, true)
  end

  # Draw an already-resolved cell at a *screen* position, optionally
  # overriding fg/bg. Used when the cell's buffer row and its screen row
  # differ (selection highlighting while scrolled back into scrollback).
  def redraw_cell_at(screen_x, screen_y, cell, fg: nil, bg: nil)
    cell = Array(cell).dup
    cell[0] ||= " "
    cell[1] = fg if fg
    cell[2] = bg if bg
    draw_buffered(screen_x, screen_y, cell, true)
  end

  # Repaint whatever is currently displayed at a screen position, given the
  # active scrollback offset (so scrollback rows repaint their scrolled-off
  # content rather than the live buffer's).
  def redraw_display(screen_x, screen_y, scrollback_offset = 0)
    buffer_y = screen_y - scrollback_offset
    draw_buffered(screen_x, screen_y, @buffer.get(screen_x, buffer_y), true)
  end

  # Public flush point. In the default (eager) mode draws already happened
  # on #set, so this just emits the pending run. In damage-driven (defer)
  # mode #set only mutates, so a flush first walks the buffer's damage and
  # draws the changed cells (run-batched) before emitting. Either way it
  # then emits the run buffer, which also carries force-redraws (cursor,
  # ICH/DCH, blink, selection).
  def draw_flush
    return if @suspend   # jump-scrolling: defer all rendering to the redraw
    if @defer && !@adapter.scrollback_mode
      @buffer.each_damaged(@last_flush_gen) do |x, y, ch, fg, bg, flags|
        s = (@scratch ||= [])
        s[0], s[1], s[2], s[3] = ch, fg, bg, flags
        draw_buffered(x, y, s, true)
      end
      @last_flush_gen = @buffer.generation
    end
    flush_buf
  end

  # Emit the batched run and reset the batch. Internal: draw_buffered calls
  # this on a run break, so it must NOT re-enter the damage walk above.
  def flush_buf
    if @bufx && @buf && @buf[0] && !@buf[0].empty?
      c = @buf[0]
      fg = @buf[1] || PALETTE_BASIC[7]
      bg = @buf[2] || PALETTE_BASIC[0]
      if c == " " && fg == 0 && bg == 0 # Why?
      else
        lineattrs = @buffer.lineattrs(@bufy)
        flags = @buf[3].to_i
        #p [:flush, fg, c]
        @adapter.draw(@bufx, @bufy, c, fg, bg, flags, lineattrs)
      end
    end
    @buf = []
    @bufx = nil
    @bufy = nil
    @last_x = -2
    @last_y = -2
  end


  # This is a hack
  def draw_buffered(x,y,cell, force=false)
    @last_x ||= -255
    @last_y ||= -255
    @buf ||= ["",PALETTE_BASIC[7], PALETTE_BASIC[0],0]
    cell ||= [" "]

    #p [:buffered, x, y, cell, @bufx, @bufy, @buf, force]
    if @buf[0] && @buf[0].length > 160
      flush_buf
    elsif @last_y != y || @last_x + 1 != x
      flush_buf
    elsif (@buf[1] != cell[1]) or (@buf[2] != cell[2]) or (@buf[3] != cell[3])
      flush_buf
    else
    end

    # FIXME: It is possible this is called from multiple threads.
    # Uh oh. That *will* be trouble. Either changes must be serialized -
    # they certainly must be for the backend screen buffer - or
    # this must be made thread local.
    #
    @buf[0] ||= ""

    # This is to get better performance out of applications that
    # carelessly prints far more than they ought to.
    # *cough* my editor *cough*
    if force
      match = false
    else
      # Skip the draw if the buffer already holds this exact cell, or if
      # we're writing a default-background space over an unset cell.
      # Compared against the buffer's columnar storage directly, so no cell
      # Array is reconstructed per character.
      # FIXME: Make this more deliberate about *background* attributes.
      match = (cell[0] == 32 && cell[2] == BG && @buffer.unset?(x, y)) ||
              @buffer.cell_eq?(x, y, cell[0], cell[1], cell[2], cell[3])
    end

    # FIXME: The #to_s here is a workaround for thread sync issues.
    if @buf[0].to_s.empty?
      if match
        return
      else
        #p [:diff, x,y, cell, bcell]
      end
    elsif match
      # This heuristic could probably be better:
      # * Keep a count, and trigger on the *number of matches*
      #   instead of on the number of characters. This to e.g. prevent a
      #   single coinciding character from splitting up the rendering into
      #   8-char chunks
      #p [:match_non_empty, @buf[0].length]
      if @buf[0]&.length.to_i > 8
        # If flushing here, chop the buffer down to the point of the first
        # match.
        flush_buf
        return
      end
    end

    c = cell[0]

    @buf[1] ||= cell[1]
    @buf[2] ||= cell[2]
    @buf[3] ||= cell[3]
    @buf[0] ||= ""
    @buf[0] << (c || "")
    @bufx ||= x
    @bufy ||= y
    @last_x = x
    @last_y = y
  end

end
