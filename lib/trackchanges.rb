
# FIXME: Roll this into the actual buffer.
class TrackChanges
  def initialize buffer, adapter
    @buffer = buffer
    @adapter = adapter
    clear
  end

  attr_reader :buffer

  def clear
    clear_changes
    @cleared = true

    @buffer.clear
    @adapter.clear
  end

  def clear_changes
    @cleared = false
    @changes = Set.new
    @scroll = []
  end

  # FIXME: Organize these in lines and spans
  def changes = @changes

  # Methods that does not alter the buffer
  def lineattrs(y)  = @buffer.lineattrs(y)
  def get(x,y)      = @buffer.get(x,y)
  def scroll_start  = @buffer.scroll_start
  def scroll_end    = @buffer.scroll_end
  def blinky        = @buffer.blinky
  def each_character(scrollback_offset = 0, &block)
    @buffer.each_character(scrollback_offset, &block)
  end

  # # Mutation
  #
  def scroll_up
    @scroll << [:up, @buffer.scroll_start, @buffer.scroll_end]
    # FIXME: Need to "scroll" @blinky and @changes as well
    # so that they are "net" of scrolling.
    @buffer.scroll_up
  end

  def delete_lines(y, num, maxy)
    draw_flush
    num.times.each {|i| @buffer.delete_line(y+i) }
    @adapter.delete_lines(y, num, @buffer.scroll_end||maxy)
  end

  def insert_lines(y, num, maxy)
    draw_flush
    num.times.each {|i| @buffer.insert_line(y+i) }
    @adapter.insert_lines(y, num, @buffer.scroll_end || maxy)
  end

  def clear_line(*args)
    @buffer.clear_line(*args)
    @adapter.clear_line(*args)
  end

  def set(x,y,c,fg,bg,mode)
    @changes << [x,y]

    # MUST be before the @buffer.set below,
    # as it currently uses @buffer.get to compare and
    # avoid unnecessary redraws
    draw_buffered(x,y,[c,fg,bg,mode])
    @buffer.set(x,y,c,fg,bg,mode)
  end

  def on_resize(w,h)
    raise if !h
    # FIXME: Window is currently resized separately.
    @buffer.on_resize(w,h)
  end
  
  def method_missing(sym, *args, &block)
    p [:TRACK, sym, *args, block]
    @buffer.send(sym, *args, &block)
  end

  def redraw_blink
    b = @buffer.blinky
    return nil if b.empty?
    b.each { |x,y| redraw(x,y) }
    draw_flush
  end

  def redraw(x,y) = draw_buffered(x,y, @buffer.get(x,y), true)

  def redraw_all(scrollback_offset = 0)
    @buffer.each_character(scrollback_offset) { |*args| draw_buffered(*args, true) }
    draw_flush
  end

  def redraw_with(x,y, fg: nil, bg: nil)
    cell = Array(@buffer.get(x,y)).dup
    cell[0] ||= " "
    cell[1] = fg if fg
    cell[2] = bg if bg
    draw_buffered(x,y, cell, true)
  end

  def draw_flush
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


  $saved = 0

  # This is a hack
  def draw_buffered(x,y,cell, force=false)
    @last_x ||= -255
    @last_y ||= -255
    @buf ||= ["",PALETTE_BASIC[7], PALETTE_BASIC[0],0]
    cell ||= [" "]

    #p [:buffered, x, y, cell, @bufx, @bufy, @buf, force]
    if @buf[0] && @buf[0].length > 160
      draw_flush
    elsif @last_y != y || @last_x + 1 != x
      draw_flush
    elsif (@buf[1] != cell[1]) or (@buf[2] != cell[2]) or (@buf[3] != cell[3])
      draw_flush
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
      bcell = Array(@buffer.get(x,y))
      
      # FIXME: Make this more deliberate about *background* attributes
      # Currently it gradually fills in unless we add the cell[2] == BG part
      # But when we then do that, it *renders* that instead of just clearing
      # the background. Also distinction between drawing the background and
      # clearing it. Improved slightly by rstrip'ing the string in the rendering
      # code.
      match = (cell[0] == 32 && bcell.empty? && cell[2] == BG) || cell == bcell

      #p [cell, bcell, match]
    end

    # FIXME: The #to_s here is a workaround for thread sync issues.
    if @buf[0].to_s.empty?
      if match
        $saved += 1
        p $saved if $saved % 500 == 0
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
        draw_flush
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
