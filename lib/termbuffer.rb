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
  def initialize
    @w = nil
    @h = nil
    clear
  end

  def clear
    @scrbuf    = []
    @lineattrs = []
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

  def lineattrs(y) = @lineattrs[y]

  def set_lineattrs(y, v)
    @lineattrs[y] = v
  end

  def each_character
    @scrbuf.each_with_index do |line,y|
      if line
        line.each_with_index do |cell, x|
          yield x,y, cell
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

  def on_resize(w,h)
    raise if !h
    @scrbuf.resize(w,h)
  end
  
  def get(x,y) (@scrbuf[y]||[])[x]; end
  def getline(y) = @scrbuf[y]

  # Yields every position *that has a set cell*
  # Will *not* yield every position
  def each_character(&block) = @scrbuf.each_character &block
  def each_character_between(spos,epos,&block) = @scrbuf.each_character_between(spos,epos,&block)
    
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

  def scroll_up;
    delete_line(@scroll_start.to_i)
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
