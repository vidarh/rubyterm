require 'pty'
require 'io/console'
require_relative 'term'

PALETTE256=[
  0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xc0c0c0,
  0x808080, 0xff0000, 0x00ff00, 0xffff00, 0x0000ff, 0xff00ff, 0x00ffff, 0xffffff]+
  [0,0x5f, 0x87, 0xaf, 0xd7, 0xff].repeated_permutation(3).sort.map{|ary| (ary[0]<<16)+(ary[1]<<8)+ary[2]}+
  (8..244).step(10).map{|n| (n<<16)+(n<<8)+n}

class EscapeParser
  attr_reader :str

  def initialize
    @state = :start
    @str = ""
  end

  def put(ch)
    @str << ch.chr
    case @state
    when :start
      if ch == 91; then @state = :csi
      elsif ch == 93; then @state = :oc
      elsif /\w/.match(ch.chr); then @state = :complete; end
    when :csi
      @state = :complete if /[[:alpha:]]|[[:cntrl:]]/.match(ch.chr)
    when :oc;  @state = :complete if ch == 7
    else
      raise "Complete";
    end
  end

  def complete?; @state == :complete; end
end

class RubyTerm
  SHELL = "/bin/bash"
  CURSOR = 0xff00ff
  CHAR_W = 6
  CHAR_H = 12

  PALETTE_BASIC = [ # dim(0..7) + bright(8..15)
    0x20201d, 0xd73737, 0x60ac39, 0xae9513, 0x6684e1, 0xb854d4, 0x1fad83, 0xffffff,
    0x7d7a68, 0xd73737, 0x60ac39, 0xae9513, 0x6684e1, 0xb854d4, 0x1fad83, 0xffffff]
  BOLD=1

  def initialize
    init
    @x = 0; @y = 0
    @master, @wr, pid = *PTY.spawn(SHELL)
    @term_width  = 80
    @term_height = 1000
    @scrbuf = []
    @bg = PALETTE_BASIC[0]
    @fg = PALETTE_BASIC[7]
    @mode = 0
  end

  def scrbuf_set(x,y,ch, fg=0, bg=0)
    @scrbuf[y]||=[]
    @scrbuf[y][x] = [ch.ord,fg,bg]
  end

  def scrbuf_get(x,y); (@scrbuf[y]||[])[x]; end
  def scrbuf_scroll_up; @scrbuf.shift; end
  def draw_cursor(x,y); xfillrect(x,y, CURSOR); end

  def draw(x,y,cell)
    xfillrect(x,y, (cell && cell[2]) || PALETTE_BASIC[4])
    xclear(x,y, CHAR_W, CHAR_H) if !cell || !cell[2]
    if cell && cell[0] != 0
      xdrawch(x,y, cell[0], cell[1] || PALETTE_DEFAULT[7], cell[2] || PALETTE_DEFAULT[0])
    end
  end

  def redraw_line y; (0...@term_width).each {|x| draw(x,y, scrbuf_get(x,y)); }; end

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
    else;   PALETTE_BASIC[0];
    end
  end

  def set_modes(codes)
    while c = codes.shift
      case c
      when 0;       @mode = 0; @fg = PALETTE_BASIC[7]; @bg = PALETTE_BASIC[0]
      when 1;       @mode |= BOLD
      when 2..8;    p [:set_mode, c]
      when 22;
      when 30..37;  @fg = PALETTE_BASIC[c-30 + (@mode & BOLD ? 8:0)]
      when 38;      @fg = parse_color(codes)
      when 39;      @fg = PALETTE_BASIC[7]
      when 40..47;  @bg = PALETTE_BASIC[c-40 + (@mode & BOLD ? 8:0)]
      when 48;      @bg = parse_color(codes)
      when 49;      @bg = PALETTE_BASIC[0]
      else return p [:set_modes, c, codes]
      end
    end
  end

  def handle_escape(ch)
    @esc.put(ch)
    if @esc.complete?
      s = @esc.str
      if s == "[H"
        @x = 0
        @y = 0
      elsif s[0] == "[" && s[-1] == "H"
        y,x = *s[1..-2].split(";")
        @x = x.to_i-1
        @y = y.to_i-1
      elsif s == "[0K" || s == "[K"
        (@x...@term_width).each {|x| scrbuf_set(x,@y,0) }
        xclear(@x,@y, 0, CHAR_H)
      elsif s == "[3J"
        @scrbuf = []
        redraw
      elsif s[0] == "[" && s[-1] == "m"
        codes = s[1..-2].split(";").map(&:to_i)
        set_modes(codes)
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
      when 8
        @x -= 1
        @x = 0 if @x < 0
        scrbuf_set(@x, @y, 0)
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
        scrbuf_set(@x, @y, ch, @fg, @bg)
        @x += 1
        if @x >= @term_width
          @x = 0
          @y += 1
        end
      end
    end
    if @y >= @term_height
      scrbuf_scroll_up
      @y -= 1
      redraw
    end
    c = scrbuf_get(ox,oy) || [32,0,0]
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
    m = @master

    loop do
      rs, ws = IO.select([f, m])
      rs.each do |s|
        case s.fileno
        when m.fileno # PTY
          write(m.read_nonblock(1024).force_encoding("UTF-8"))
          flush
        else # X11
          self.process
        end
      end
    end
  end
end

RubyTerm.new.run
