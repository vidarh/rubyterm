require 'pty'
require 'io/console'

require_relative 'term'
require_relative 'lib/escapeparser'
require_relative 'lib/palette'
require_relative 'lib/termbuffer'

class RubyTerm
  SHELL = "/bin/bash"
  CURSOR = 0xff00ff
  CHAR_W = 6
  CHAR_H = 12

  BOLD=1

  BG=PALETTE_BASIC[0]
  FG=PALETTE_BASIC[7]

  def initialize
    init
    @x = 0; @y = 0
    @master, @wr, pid = *PTY.spawn(SHELL)
    @term_width  = 80
    @term_height = 1000
    @buffer = TermBuffer.new
    @bg = BG
    @fg = FG
    @mode = 0
    @cursor = true
  end

  def clear_cursor(x,y); xclear(x,y, CHAR_W, CHAR_H); end

  def draw(x,y,cell)
    xfillrect(x,y, (cell && cell[2]) || PALETTE_BASIC[4])
    xclear(x,y, CHAR_W, CHAR_H) if !cell || !cell[2]
    if cell && cell[0] != 0
      xdrawch(x,y, cell[0], cell[1] || FG, cell[2] || BG)
    end
  end

  def draw_cursor(x,y);
    cell = @buffer.get(x,y)
    xfillrect(x,y, CURSOR)
    xdrawch(x,y, cell[0], BG, CURSOR) if cell && cell[0]>31
  end

  def redraw_line y; (0...@term_width).each {|x| draw(x,y, @buffer.get(x,y)); }; end

  def redraw
    xclear(0,0,0,0)
    (0...@term_height).each {|y| redraw_line(y) }
    draw_cursor(@x,@y); flush
  end

  def resize(w,h)
    return if w <= 0 || h <= 0 # FIXME: WTF?!?
    @term_width, @term_height = w,h
    @master.winsize = [h,w]
    redraw
  end

  def parse_color(codes)
    case c = codes.shift
    when 5; PALETTE256[codes.shift]
    when 2; codes.shift << 16 | codes.shift << 8 | codes.shift
    else;   BG
    end
  end

  def set_modes(codes)
    while c = codes.shift
      case c
      when 0;       @mode = 0; @fg = FG; @bg = BG
      when 1;       @mode |= BOLD
      when 2..8;    p [:set_mode, c]
      when 22;
      when 30..37;  @fg = PALETTE_BASIC[c-30 + (@mode & BOLD ? 8:0)]
      when 38;      @fg = parse_color(codes)
      when 39;      @fg = FG
      when 40..47;  @bg = PALETTE_BASIC[c-40 + (@mode & BOLD ? 8:0)]
      when 48;      @bg = parse_color(codes)
      when 49;      @bg = BG
      else return p [:set_modes, c, codes]
      end
    end
  end

  def handle_escape(ch)
    @esc.put(ch)
    if @esc.complete?
      s = @esc.str
      if s[0] == ?[
        if s[1] != "?"
          args = s[1..-2].split(/[:;]/).map(&:to_i)
          #p [s[-1], args]
          if s[-1] == "A"
            @y -= args[0] || 1
            @y = 0 if @y < 0
          elsif s[-1] == "B"
            @y += args[0] || 1
            @y = @term_height if @y > @term_height
          elsif s[-1] == "C"
            @x += args[0] || 1
            @x = @term_width if @x > @term_width
          elsif s[-1] == "D"
            @x -= args[0] || 1
            @x = 0 if @x < 0
          elsif s == "[H"
            @x = 0
            @y = 0
          elsif s[-1] == "H"
            y,x = *s[1..-2].split(";")
            @x = x.to_i-1
            @y = y.to_i-1
          elsif s[-1] == "d"
            @y = s[1..-2].to_i
          elsif s == "[0K" || s == "[K"
            (@x...@term_width).each {|x| @buffer.set(x,@y,0) }
            xclear(@x,@y, 0, CHAR_H)
          elsif s == "[3J"
            @buffer.clear
            redraw
          elsif s[-1] == "m"
            codes = s[1..-2].split(";").map(&:to_i)
            set_modes(codes)
          else
            p @esc
          end
        elsif s[1] == "?"
          if s[-1] == "h"
            s[1..-2].split(";").map(&:to_i).each do |code|
              case code
              when 25
                @cursor = false
                clear_cursor(@x,@y)
              end
            end
          elsif s[-1] == "l"
            s[1..-2].split(";").map(&:to_i).each do |code|
              case code
              when 25; @cursor = true
              end
            end
          end
        else
          p @esc
        end
      else
        p @esc
      end
      @esc = nil
    end
  end

  def putchar(ch)
    ox,oy=@x,@y
    if @esc
      handle_escape(ch)
    else
      case ch
      when 7
        p :bell
      when 127
        @x -= 1
        @x = 0 if @x < 0
        @buffer.set(@x, @y, 0)
      when 8
        @x -= 1
        @x = 0 if @x < 0
      when 9
        write(" "*((4-@x)%4))
      when 10
        @y += 1
      when 11
        p [:huh]
      when 12
        @x = 0
        @y = 0
      when 13
        @x = 0
      when 14..26,28..31
      when 27
        @esc = EscapeParser.new
      else
        @buffer.set(@x, @y, ch, @fg, @bg)
        @x += 1
        if @x >= @term_width
          @x = 0
          @y += 1
        end
      end
    end
    if @y > @term_height
      @buffer.scroll_up
      @y -= 1
      redraw
    end
    c = @buffer.get(ox,oy) || [32,0,0]
    draw(ox,oy,c)
    draw_cursor(@x,@y)
  end

  # Map X key events to escapes
  KEYMAP = {
    65361 => "\x1b[D",
    65362 => "\x1b[A",
    65363 => "\x1b[C",
    65364 => "\x1b[B",
    65365 => "\x1b[5~",
    65366 => "\x1b[6~",
  }

  def keyevent ksym, buf; @wr.write(KEYMAP[ksym] || buf); end

  def write(str)
    str.each_char {|ch| c = ch.ord rescue 'X'; putchar(c); }
  end

  def run
    f = IO.new(self.fd)
    loop do
      rs, ws = IO.select([f, @master])
      rs.each do |s|
        case s.fileno
        when @master.fileno # PTY
          write(@master.read_nonblock(1024).force_encoding("UTF-8"))
        else # X11
          process
        end
      end
      flush
    end
  end
end

RubyTerm.new.run
