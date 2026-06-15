require 'set'

  BOLD          = 0x002
  FAINT         = 0x004
  ITALICS       = 0x008
  UNDERLINE     = 0x010
  BLINK         = 0x020
  RAPID_BLINK   = 0x040
  INVERSE       = 0x080
  INVISIBLE     = 0x100
  CROSSED_OUT   = 0x200
  DBL_UNDERLINE = 0x400
  OVERLINE      = 0x800


class Line < Array
end

class ScrBuf
  attr_reader :scrollback_buffer, :scrollback_lineattrs, :w
  
  def initialize
    @w = nil
    @h = nil
    clear
  end

  def clear
    @scrbuf    = []
    @lineattrs = []
    @scrollback_buffer = []
    @scrollback_lineattrs = []
  end
  
  def [](y)
    @lineattrs[y] ||= 0
    @scrbuf[y] ||= []
  end

  def []= (i, line)
    @scrbuf[i] = line
  end

  # Scrollback lines are stored compactly as a packed pair
  # [chars, styles] of parallel arrays of immediates, instead of an array
  # of [ch,fg,bg,flags] cell Arrays. Scrollback is unbounded, so
  # object-per-cell storage dominated retained-object count (and thus GC
  # mark time - see docs/bench-baseline.md); this is ~40x fewer objects
  # per scrolled-off line. fg/bg are 24-bit and flags < 2^12, so a cell's
  # attributes pack into a single fixnum.
  def pack_line(row)
    return [[], []] if !row
    n = row.length
    n -= 1 while n > 0 && row[n - 1].nil?   # drop trailing blanks
    chars  = Array.new(n)
    styles = Array.new(n)
    n.times do |x|
      c = row[x] or next
      chars[x]  = c[0]
      styles[x] = c[1].to_i | (c[2].to_i << 24) | (c[3].to_i << 48)
    end
    [chars, styles]
  end

  def unpack_line(packed)
    chars, styles = packed
    chars.map.with_index do |ch, x|
      next nil if !ch
      s = styles[x]
      [ch, s & 0xFFFFFF, (s >> 24) & 0xFFFFFF, s >> 48]
    end
  end

  # Read a line by row index, mapping negative rows into the scrollback
  # buffer (row -1 is the most recent scrolled-off line), unpacking the
  # compact form. Unlike #[] this is non-mutating and never auto-vivifies,
  # so it is safe for read-only traversal (e.g. selection extraction).
  def line_at(y)
    if y < 0 && !@scrollback_buffer.empty?
      scrollback_index = @scrollback_buffer.size + y
      return scrollback_index >= 0 ? unpack_line(@scrollback_buffer[scrollback_index]) : nil
    end
    @scrbuf[y]
  end

  def delete_line(y)
    @lineattrs.slice!(y)
    @scrbuf.slice!(y)
  end

  def insert_line(y)
    @lineattrs.insert(y, 0)
    @scrbuf.insert(y, [])
    enforce_height
  end

  def lineattrs(y)
    if y < 0 && !@scrollback_lineattrs.empty?
      # Convert negative index to scrollback buffer index
      scrollback_index = @scrollback_lineattrs.size + y
      return scrollback_index >= 0 ? @scrollback_lineattrs[scrollback_index] : 0
    end
    @lineattrs[y]
  end

  def set_lineattrs(y, v)
    @lineattrs[y] = v
  end

  def each_character(scrollback_offset = 0)
    visible_lines_used = 0
    
    if scrollback_offset > 0 && !@scrollback_buffer.empty?
      # Get scrollback lines to display
      offset = [@scrollback_buffer.size, scrollback_offset].min
      if offset > 0
        # Only show last 'offset' lines from scrollback
        scrollback_lines = @scrollback_buffer[-offset..-1] || []
        
        # Render scrollback lines (unpacked from the compact form) at the
        # top of the screen.
        scrollback_lines.each_with_index do |packed, idx|
          line = packed && unpack_line(packed)
          next if !line
          line.each_with_index do |cell, x|
            yield x, idx, cell if cell
          end
        end
        
        visible_lines_used = scrollback_lines.size
      end
    end
    
    # Then get characters from main buffer, but only render lines that will fit after scrollback
    # Add 1 to fix the off-by-one error (draw one more line)
    remaining_lines = @h ? (@h - visible_lines_used + 1) : @scrbuf.size
    
    @scrbuf.each_with_index do |line, y|
      if line && y < remaining_lines
        line.each_with_index do |cell, x|
          if cell 
            # Offset y by the number of scrollback lines already shown
            yield x, y + visible_lines_used, cell
          end
        end
      end
    end
  end

  def each_character_between(spos, epos)
    if spos.end > epos.end
      spos, epos = epos, spos
    elsif spos.end == epos.end
      if spos.first > epos.first
        spos, epos = epos, spos
      end
    end

    x = spos.first
    xend,ymax = epos.first, epos.end

    (spos.end..ymax).each do |y|
      line = line_at(y) || ""
      xmax = y == ymax ? xend+1 : line.length-1
      xmax = [xmax,line.length-1].min
      xmax = 0 if xmax < 0
      while x <= xmax
        cell = line[x]
        yield(x,y, cell)
        x+=1
      end
      y+=1
      x = 0
    end
  end

  def enforce_height
    return unless @h
    @scrbuf.slice!(@h..)
    @lineattrs.slice!(@h..)
  end

  def resize(w,h)
    @w,@h=w,h
    enforce_height
    # FIXME: Will width cause issues too?
  end
end

class TermBuffer
  attr_accessor :scroll_start, :scroll_end

  def initialize
    @scrbuf = ScrBuf.new
    clear
    @scroll_start = nil
    @scroll_end = nil
  end
  
  # Get the size of the scrollback buffer
  def scrollback_size
    @scrbuf.scrollback_buffer.size
  end

  def on_resize(w,h)
    raise if !h
    @scrbuf.resize(w,h)
  end
  
  # Negative rows route through ScrBuf#line_at, which maps them into the
  # scrollback buffer and unpacks the compact form. (The old inline
  # mapping here referenced a nonexistent @scrollback_buffer ivar and
  # would have raised on any negative y - it was dead because get is only
  # ever called with y >= 0.)
  def get(x,y)
    if y < 0
      row = @scrbuf.line_at(y)
      return row && row[x]
    end
    (@scrbuf[y]||[])[x]
  end
  def getline(y)
    return @scrbuf.line_at(y) if y < 0
    @scrbuf[y]
  end

  # Yields every position *that has a set cell*
  # Will *not* yield every position
  def each_character(scrollback_offset = 0, &block)
    @scrbuf.each_character(scrollback_offset, &block)
  end
  
  def each_character_between(spos, epos, &block)
    @scrbuf.each_character_between(spos, epos, &block)
  end
    
  def lineattrs(y) = @scrbuf.lineattrs(y.to_i)
  def set_lineattrs(y,v); @scrbuf.set_lineattrs(y,v); end
    
  def delete_line(y)
    @scrbuf.delete_line(y)
    if @scroll_start
      # In a scroll region, deleting a line shifts the region up and
      # inserts a blank line at the bottom (scroll_end), not at the top.
      @scrbuf.insert_line(@scroll_end)
    end
  end

  def insert_line(y)
    @scrbuf.insert_line(y)
    if @scroll_end
      # Inserting pushes the region down; discard the line that falls
      # just past the bottom of the region.
      @scrbuf.delete_line(@scroll_end + 1)
    end
  end

  def scroll_up
    # Save the line to scrollback (in the compact packed form) before
    # deleting it. Always store, even if empty, for consistent scrollback
    # navigation. pack_line builds fresh arrays, so it also snapshots
    # (no aliasing with the live row that delete_line removes).
    y = @scroll_start.to_i
    @scrbuf.scrollback_buffer.push(@scrbuf.pack_line(@scrbuf[y]))
    @scrbuf.scrollback_lineattrs.push(@scrbuf.lineattrs(y))
    delete_line(y)
  end

  def insert(x,y,num, cell)
    l = @scrbuf[y]
    num.times.each do |i|
      l.insert(x+i, cell)
    end
    # ICH/IRM push the rest of the line right; cells shifted past the right
    # margin are discarded (the line never grows beyond the screen width),
    # so a later DCH can't pull them back into view.
    w = @scrbuf.w
    l.slice!(w..) if w && l.length > w
  end

  # DCH: delete num cells at (x,y), shifting the remainder of the line
  # left. Vacated cells at the right become blank (a shorter line renders
  # as trailing spaces).
  def delete_chars(x, y, num)
    l = @scrbuf[y]
    num.times { l.delete_at(x) if x < l.length }
  end

  def blinky  = @blinky

  def set(x,y,ch, fg=0, bg=0, flags=0)
    if flags.anybits?(BLINK|RAPID_BLINK)
      @blinky << [x,y]
    else
      @blinky.delete([x,y])
    end


    #p [x,y,ch,fg,bg,flags]
    @scrbuf[y]||=[]
    @scrbuf[y][x] = [ch.ord,fg,bg, flags]
  end

  def clear_line(y, start_x=0, end_x=nil)
    if !end_x
      @scrbuf[y] = Array(@scrbuf[y])[0...start_x]
    else
      (start_x..end_x).each do |x|
        set(x,y,' ')
      end
    end
  end

  def clear
    @blinky  = Set.new
    @scrbuf.clear
  end
end
