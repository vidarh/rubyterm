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
  attr_reader :scrollback_buffer, :scrollback_lineattrs
  
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
        
        # Render scrollback lines at the top of the screen
        scrollback_lines.each_with_index do |line, idx|
          if line
            line.each_with_index do |cell, x|
              if cell
                # Render at position from top of screen
                yield x, idx, cell
              end
            end
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
      line = @scrbuf[y] || ""
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
    if @h
      p [:enforce_height, @h, @scrbuf.length]
      @scrbuf.slice!(@h..)
      @lineattrs.slice!(@h..)
    else
      p [:enforce_height_no_h]
    end
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
  
  def get(x,y)
    if y < 0 && !@scrollback_buffer.empty?
      # Convert negative index to scrollback buffer index
      scrollback_index = @scrollback_buffer.size + y
      return scrollback_index >= 0 ? (@scrollback_buffer[scrollback_index] || [])[x] : nil
    end
    (@scrbuf[y]||[])[x]
  end
  def getline(y)
    if y < 0 && !@scrbuf.scrollback_buffer.empty?
      # Convert negative index to scrollback buffer index
      scrollback_index = @scrbuf.scrollback_buffer.size + y
      return scrollback_index >= 0 ? @scrbuf.scrollback_buffer[scrollback_index] : nil
    end
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
      # FIXME: Do I need to check if y<@scroll_end?
      @scrbuf.insert_line(@scroll_start)
    end
    #@scrbuf.each_with_index {|l,i|
    #  p [i,Array(l).map{|cell| Array(cell)[0].to_i.chr }.join ]
    #}
  end

  def insert_line(y)
    @scrbuf.insert_line(y)
    if @scroll_end
      # FIXME: Do I need to check if y>@scroll_start?
      @scrbuf.delete_line(@scroll_end)
    end
  end

  def scroll_up
    # Save the line to scrollback buffer before deleting
    y = @scroll_start.to_i
    scrollback_line = @scrbuf[y]
    
    # Always store the line in scrollback, even if it seems empty -
    # this ensures consistent scrollback navigation
    line_to_save = scrollback_line ? scrollback_line.dup : []
    @scrbuf.scrollback_buffer.push(line_to_save)
    @scrbuf.scrollback_lineattrs.push(@scrbuf.lineattrs(y))
    
    # Add a debug marker to see what's being stored
    if ENV["DEBUG"]
      puts "Saving scrollback line: #{line_to_save.inspect}"
    end
    
    delete_line(y)
  end

  def insert(x,y,num, cell)
    l = @scrbuf[y]
    num.times.each do |i|
      l.insert(x+i, cell)
    end
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
