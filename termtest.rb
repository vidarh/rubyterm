
require 'pty'
require 'io/console'

require_relative 'bundle/bundler/setup'
#$: << "/home/vidarh/.gem/ruby/3.2.2/gems/skrift-0.1.0/lib"

require_relative 'lib/escapeparser'
require_relative 'lib/palette'
require_relative 'lib/termbuffer'
require_relative 'lib/keymap'
require_relative 'lib/window'
require_relative 'lib/charsets'
require_relative 'lib/utf8decoder'
require_relative 'lib/controller'

require 'X11'
require 'skrift'
require 'skrift/x11'
require 'citrus/file'
require 'toml-rb'

require 'pry'

$> = $stderr

require_relative 'lib/windowadapter'
require_relative 'lib/trackchanges'

  BG="0"
  FG="7"


class RubyTerm
  CURSOR = 0xff00ff
  TOPMOST= 0
  LEFTMOST=0
  
  attr_reader :term_width, :term_height, :blink_state, :rblink_state
  
  def charset = @g[@gl] || DefaultCharset
  def char_w  = @adapter.char_w
  def char_h  = @adapter.char_h

  def initconfig
    cname = File.expand_path("~/.config/rterm/config.toml")
    if File.exist?(cname)
      @config = TomlRB.load_file(cname, symbolize_keys: true)
    end
    @config ||= {}
  end

  def inspect = "<RubyTerm #{self.object_id}>"

  def initialize(args)
    initconfig

    pp(:config,@config)

    @queue = Queue.new
    
    @window = Window.new(fonts: @config[:fonts], fontsize: @config[:fontsize])
    @adapter = WindowAdapter.new(@window, self)
    #@term = Term.new(@window)

    # FIXME: I should consider whether to change origin to match the terminal handling
    # as it might be easier.
    @x = 0; @y = 0

    @gl = 0
    @g = [DefaultCharset,nil,nil,nil] # Alternate charsets

    # See https://vt100.net/docs/vt100-ug/chapter3.html "LNM"
    @lnm = true #false

    @wraparound = true

    @tabs = 40.times.map {|i| i * 8}

    @origin_mode = false

    # :x10, :v200, :v200_highlight, :btn_event, :any_event
    # FIXME: Only :btn_event_mouse supported so far
    # See: https://www.xfree86.org/current/ctlseqs.html ("Mouse tracking")
    @mouse_mode = nil
    # Mouse reporting format. nil == x10, :multibyte (NOT SUPPORTED), :digits,
    # :urxvt (NOT SUPPORTED, probably never)
    @mouse_reporting = nil
    
    # Yes, this is "bad" and we should define our
    # own, however, I'd prefer to match rxvt or similar
    # sufficiently that we can rely on a TERM setting that
    # "everyone" already has in their termcap. rxvt seems to
    # work better than xterm, but will adjust and consider
    # providing multiple modes
    ENV["TERM"] = "rxvt-256color"
    ENV["COLORTERM"] = "truecolor"

    while args[0].to_s[0] == ?-
      case args[0]
      when "--"
        args.shift
        break
      when "-c"
        args.shift
        @term_instance = args.shift
      else break
      end
    end

    @window.dpy.change_property(:replace,
      @window.wid, "WM_CLASS",
      @window.dpy.atom("STRING"), 8, "rterm\0#{@term_instance||'rterm'}\0".unpack("C*"))

    @window.map_window

    @term_width  = (400 / char_w).to_i
    @term_height = (400 / char_h).to_i

    @buffer = TrackChanges.new(TermBuffer.new, @adapter)
    @buffer.on_resize(@term_width, @term_height)
    
    # Give window access to the buffer for scrollback
    @window.set_buffer(@buffer)

    @bg = BG
    @fg = FG
    @mode = 0
    @cursor = true
  end

  def clear_cursor
    return if !@cursor_pos
    @buffer.redraw(*@cursor_pos)
    #@buffer.draw_flush
    @cursor_pos = nil
  end
  
  def draw_cursor
    # If the old cursor is still on screen,
    # we clear it. Note that this does not take into account
    # scrolling at present, so you can't *rely* on it.
    clear_cursor
    
    x,y=@x,@y
    return if !@cursor
    # FIXME: Is this needed?
    if x >= @term_width
      y+=1
    end
    @buffer.redraw_with(x,y, bg: CURSOR)
    #@buffer.draw_flush
    @cursor_pos = [x,y]
  end

  def redraw
    # Always clear the entire screen before redrawing to ensure all areas are cleaned up
    # This ensures no artifacts remain at the ends of lines
    @window.clear(0, 0, @window.width, @window.height)
    
    if @window.scrollback_mode
      @buffer.redraw_all(@window.scrollback_count)
    else
      @buffer.redraw_all(0)
    end
    
    # Make sure changes are rendered and cursor is shown
    @buffer.draw_flush
    draw_cursor
  end

  def render_text_buffer
    (0...@term_height).each {|y|
      puts @buffer.buffer.getline(y).map {|a| a ? a[0].chr(Encoding::UTF_8):" " }.join
    }
  end

  def each_character(&block) = @buffer.each_character(&block)

  def resize(w,h)
    @pixelw||=0
    @pixelh||=0
    should_redraw = w >= @pixelw || h >= @pixelh
    p [:should_redraw] if should_redraw
    @pixelw=w
    @pixelh=h
    @window.on_resize(w,h)

    w = w/char_w - 1
    h = h/char_h - 1
    return if w <= 0 || h <= 0 # FIXME: WTF?!?
    #if w != @term_width && h == @term_height
    @buffer.on_resize(w,h)
    ow, oh = @term_width, @term_height

    if ow != w || oh != h
      @term_width, @term_height = w,h
      @controller.report_size(w,h)
    end

    if should_redraw
      redraw
    end
  end


  def parse_color(codes)
    case c = codes.shift
    when 5; PALETTE256[codes.shift]
    when 2; codes.shift << 16 | codes.shift << 8 | codes.shift
    else;   BG
    end
  end

  def fg = @fg.is_a?(String) ? PALETTE_BASIC[@fg.to_i + (@mode.allbits?(BOLD) ? 8:0)] : @fg
  def bg = @bg.is_a?(String) ? PALETTE_BASIC[@bg.to_i] : @bg
    
  def set_modes(codes)
    while c = codes.shift
      case c
      when 0;       @mode = 0; @fg = FG; @bg = BG
      when 1;       @mode |= BOLD
      when 2;       @mode |= FAINT
      when 3;       @mode |= ITALICS # FIXME
      when 4;       @mode |= UNDERLINE
      when 5;       @mode |= BLINK
      when 6;       @mode |= RAPID_BLINK
      when 7;       @mode |= INVERSE
      when 8;       @mode |= INVISIBLE
      when 9;       @mode |= CROSSED_OUT
      when 21;      @mode |= DBL_UNDERLINE
      when 22;      @mode &= ~BOLD & ~FAINT
      when 23;      @mode &= ~ITALICS
      when 24;      @mode &= ~UNDERLINE & ~DBL_UNDERLINE
      when 25;      @mode &= ~BLINK & ~RAPID_BLINK
      when 27;      @mode &= ~INVERSE
      when 28;      @mode &= ~INVISIBLE
      when 29;      @mode &= ~CROSSED_OUT
      when 30..37;  @fg = (c-30).to_s # FIXME: Hack
      when 38;      @fg = parse_color(codes)
      when 39;      @fg = FG
      when 40..47;  @bg = (c-40).to_s # FIXME: Hack
      when 48;      @bg = parse_color(codes)
      when 49;      @bg = BG
      when 53;      @mode |= OVERLINE
      when 55;      @mode &= ~OVERLINE
      else return p [:set_modes, c, codes]
      end
    end
  end

  # # Editing operations

  def clear_to_end      = @buffer.clear_line(@y, @x)
  def clear_to_start    = @buffer.clear_line(@y, 0, @x)
  def clear_line(y=nil) = @buffer.clear_line(y||@y, 0)

  def clear_above
    (0...@y).each {|y| clear_line(y) }
    clear_to_start
  end

  def clear_below
    clear_to_end
    (@y+1..@term_height).each {|y| clear_line(y)}
  end

  def insert_lines(num) = @buffer.insert_lines(@y, num, @term_height)
  
  # FIXME (still broken) Emacs uses this to scroll up
  def delete_lines(num) = @buffer.delete_lines(@y, num, @term_height)

  def decaln
    # DEC alignment; only purpose served here is for vttest
    # so doesn't need to be efficient
    @buffer.scroll_start = nil
    @buffer.scroll_end   = nil
    @term_width.times.each do |x|
      @term_height.times.each do |y|
        @buffer.set(x,y,'E',fg,bg,0)
      end
    end
    @buffer.draw_flush
  end
  
  # # Handle escapes

  def clear_screen
    p :clear_screen
    @buffer.scroll_start = nil
    @buffer.scroll_end   = nil
    @buffer.clear
    @x=0
    @y=0
    @window.clear(0,0,@pixelw,@pixelh)
    #@window.flush
  end
  
  def handle_dec(s) # CSI '?' -> DEC private modes
    args = s[2..-2].split(/[:;]/).map{|i| i.empty? ? nil : i.to_i }
    case s[-1]
    when "h","l"
      set = s[-1] == "h"
      args.each do |code|
        case code
        when 3;
          @term_width  = set ? 132 : 80 # FIXME: Resize window or rescale font
          clear_screen
        when 6;  @origin_mode = set
        when 7;  @wraparound  = set
        when 9   # FIXME: Unsupported X10 mouse reporting mode
        when 20; @lnm = set
        when 25;
          @cursor = set
          clear_cursor if !set
        when 47;
          # Start/end alternate screen mode
          # FIXME: Save/restore
          # Also when adding scrollback, will need to turn that on/off
          clear_screen

        # Extended mouse modes
        # See https://terminalguide.namepad.de/mouse/
        when 1000 then @mouse_mode = set ? :vt200 : nil
        when 1001 then @mouse_mode = set ? :vt200_highlight : nil
        when 1002 then @mouse_mode = set ? :btn_event : nil
        when 1003 then @mouse_mode = set ? :any_event : nil
        when 1006 then @mouse_reporting = set ? :digits : nil
        when 2004
          # Bracketed paste.
        end
      end
    end
  end

  def origin =  @origin_mode ? @buffer.scroll_start || 0 : 0
  def bottom =  @origin_mode ? @buffer.scroll_end || @term_height : @term_height
  def clampw(i) = i.clamp(0,@term_width-1)
  def clamph(i) = i.clamp(origin,bottom)

  # FIXME: Move to trackchanges
  def redraw_line_from(startx)
    clear_cursor
    (startx..@term_width).each {|x| @buffer.redraw(x,@y) }
    draw_cursor
  end

  def move_up(lines) = (@y = clamph(@y - lines.to_i.clamp(1,@term_height)))
  def report_position = @controller.report_position(@x,@y)
  def device_report = @controller.device_report

  CSI_MAP = {}
  
  def handle_csi(s)
    return handle_dec(s) if s[1] == "?"
    args = s[1..-2].split(/[:;]/).map{|i| i.empty? ? nil : i.to_i }

    cmd = s[-1]
    if CSI_MAP[cmd]
      return send(CSI_MAP[cmd], *args)
    end
    
    case s[-1]
    when "@";
      @buffer.insert(@x,@y,args[0] || 1,[32,0,0,0])
      redraw_line_from(@x)
    when "A" then move_up(args[0])
    when "B"; @y = clamph(@y + args[0].to_i.clamp(1,@term_height))
    when "C"; @x = clampw(@x + args[0].to_i.clamp(1,@term_width))
    when "D"; @x = clampw(@x - args[0].to_i.clamp(1,@term_width))
    when "G"; @x = clampw((args[0]||1)-1)
    when "H"
      @y = (origin + args[0].to_i.clamp(1,99999))-1
      @x = (args[1]||1)-1
      #p [:H, @x, @y]
    when "J"
      case args[0] || 0
      when 0 then clear_below
      when 1 then clear_above
      when 2 then clear_screen  
      when 3 then @buffer.clear
      end
    when "K"
      case args[0] || 0
      when 0 then clear_to_end
      when 1 then clear_to_start
      when 2 then clear_line
      else
        p @esc
      end
    when "L" then insert_lines(args[0]||1)
    when "M" then delete_lines(args[0]||1)
    when "P";
      p @esc
      # delete_chars(args[0]||1)
    when "S" then scroll_up(args[0]||1)
    when "T"; # Scroll down
    when "c" then device_report
    when "d"; @y = clamph(origin+(args[0]||1) - 1) # FIXME: Should these be clamped
    when "f"; @y = clamph(origin+(args[0]||1) -1); @x = (args[1]||1) -1 # FIXME: Shoul these be clamped?
    when "g"
      case args[0].to_i
      when 0; @tabs.delete(@x)
      when 3; @tabs = []
      end
    when "m"; set_modes(args.empty? ? [0] : args)
    when "n"
      case args[0]
      when 6 then report_position
      else p @esc
      end
    when "r"
      p [:SET_SCROLL, args]
      @buffer.scroll_start = (args[0] || 1)-1
      @buffer.scroll_end   = (args[1] || @term_height)-1
    else
      p @esc
    end
  end

  def handle_escape(ch)
    return false if !@esc.complete?
    s = @esc.str
    if s[0] == ?[
      handle_csi(s)
    else
      case s
      when "D"; @y += 1
      when "E"; @y += 1; @x = 0
      when "H"; @tabs = (@tabs << @x).sort.uniq
      when "M"; @y -= 1
        if @y < 0
          @y=0
          insert_lines(1)
        end
      when "#3"; @buffer.set_lineattrs(@y, :dbl_upper) # FIXME: Flags
      when "#4"; @buffer.set_lineattrs(@y, :dbl_lower) # FIXME: Flags
      when "#5"; @buffer.set_lineattrs(@y, 0) # FIXME: Flags
      when "#6"; @buffer.set_lineattrs(@y, :dbl_single) # FIXME: Flags
      when "#8"; decaln
      when "(B"; @g[0] = DefaultCharset
      when ")B"; @g[1] = DefaultCharset
      when "(0"; @g[0] = GraphicsCharset
      when ")0"; @g[1] = GraphicsCharset        
      when "7";  @saved = [@x,@y,@gl,@gr,@g.dup]
      when "8";  @x,@y,@gl,@gr,@g = *Array(@saved)
      else
        p @esc
      end
    end
    @esc = nil
  end

  def wrap_if_needed
    if @x >= @term_width
      if @wraparound
        @x = 0
        @y += 1
      else
        @x = @term_width-1
      end
    elsif @x < 0
      if @wraparound
        @y -= 1
        @x = @term_width-1
      else
        @x = 0
      end
    end
  end

  def scroll_up(num=1)
    num.times do
      @buffer.draw_flush
      @buffer.scroll_up
      @window.scroll_up(
        char_h*((@buffer.scroll_start||0)+1),
        @term_width * char_w,
        ((@buffer.scroll_end||@term_height)-@buffer.scroll_start.to_i)*char_h,
        char_h
      )
    end
  end
  
  def scroll_if_needed
    while @y > (@buffer.scroll_end || @term_height)
      scroll_up
      @y -= 1
    end
  end

  def handle_control(ch)
    case ch
    when 1,2;
    when 7; p :bell
    when 8;
      if    @x >= @term_width then @x -= 2
      elsif @x > 0 then @x -= 1
      end
    when 9
      if i = @tabs.index {|t| t>@x}
        t = @tabs[i]
        # FIXME: This is only right behaviour if wrap is off, is it not?
        @x = clampw(t) if t > @x
      end
    when 10, 11
      if @lnm
        @x = 0
      end
      @buffer.draw_flush
      #p [:lf, @y,@term_height]
      @y = clamph(@y) + 1
      #p [:lfa, @y,@term_height]
      scroll_if_needed
    when 12; @x = 0; @y = 0
    when 13; @x = 0
    when 14; @gl = 1
    when 15; @gl = 0
    when 16..26;
    when 27; @esc = EscapeParser.new # FIXME: Is this right if !@esc.nil? ?
    when 28..31;
    end
  end
  
  def putchar(ch)
    ox,oy=@x,@y
    if ch.is_a?(String)
      STDERR.puts "WARNING: Should be int"
      ch = ch.ord
    end
    if @esc&.put(ch)
      handle_escape(ch)
    elsif ch.ord < 32
      handle_control(ch)
    else
      wrap_if_needed
      scroll_if_needed
      if ch == 127
        @x = clampw(@x - 1)
        ox,oy=@x,@y
        c = ' '
      else
        ox,oy=@x,@y
        @y = clamph(@y) #@y.clamp(origin,@term_height)
        @x += 1
        c = charset[ch]
      end

      @buffer.set(ox, oy, c, fg, bg, @mode)

      scroll_if_needed
    end
  end


  def write(str)
    @queue << str
  end

  def process_queue
    str = @queue.shift
    @decoder ||= UTF8Decoder.new
    @decoder << str

    p [:write, @decoder.buffer] if ENV["DEBUG"].to_s != ""
    # FIXME: Could be smarter about this; it's only needed if the
    # first character being written won't clear the same square.
    clear_cursor

    @decoder.each do|c|
      begin
        putchar(c.ord)
      rescue Exception => e
        p [c, e, @decoder]
        putchar(' ')
      end
    end

    # FIXME: Do this only when a) queue is empty or b)
    # a certain amount of time has elapsed.
    draw_cursor
    @buffer.draw_flush # Ensure everything has been rendered
    # FIXME: This is likely too extreme:
#    if @queue.empty?
#      STDERR.puts :flush
      #@window.flush
#    end
  end

  def adjust_fontsize(delta)
    @window.adjust_fontsize(delta)
    resize(@pixelw,@pixelh)
    @window.clear(0,0,@pixelw,@pixelh)
    redraw
  end

  def key(event)
    #p event
    ks, str = lookup_string(@window.dpy, event)
    case ks
      
    when :"ctrl_+" then adjust_fontsize(1.0)
    when :"ctrl_-" then adjust_fontsize(-1.0)
    when :shift_page_up
      @window.scrollback_page_up
      # Full redraw to show scrollback buffer
      redraw
      return
    when :shift_page_down
      # Don't do anything if not in scrollback mode
      return if !@window.scrollback_mode
      
      # If we're exiting scrollback mode or still in it
      changed = @window.scrollback_page_down
      
      # Redraw everything from scratch
      redraw
      
      # Explicitly force cursor to be redrawn if exiting scrollback mode
      if changed
        # Clear cursor if it exists
        clear_cursor
        # Force draw cursor again
        draw_cursor
        # Ensure changes are flushed
        @buffer.draw_flush
        @window.flush
      end
      return
    when :XK_Insert  # Paste primary selection
      # FIXME: Giant hack
      primary = `xsel -p`
      if primary.chomp.empty?
        primary = @primary
      else
        @primary = primary
      end
      @controller.paste(primary)
      return
    when "C"
      # FIXME. Cstrl + shift + c
      if str == "\x03"  # Copy primary selection into clipboard
        system("xsel -o -p | xsel -i -b")
        return
      end
    when "V"
      # FIXME. Cstrl + shift + v
      if str == "\x16"  # Paste clipboard
        clipboard = `xsel -b`
        if clipboard.chomp.empty?
          clipboard = @clipboard
        else
          @clipboard = clipboard
        end
        @controller.paste(clipboard)
        return
      end
    when :XK_Menu;
      # FIXME: Want deskmenu here, but as long as we're not running the shell, we don't know pwd.
      puts "FIXME: deskmenu"
      # FIXME: In the meantime we use it as a debugging tool to force redraw.
      redraw
      render_text_buffer
    end
    @controller.keypress(keysym_to_vt102(ks) || str)
  end

  def blink
    t = Time.now
    doblink = false
    #p [@blink_state, @rblink_state, @lastblink, @lastrblink]
    if ((t - @lastblink)*10).to_i > 6
      @lastblink = t
      @blink_state = !@blink_state
      doblink = true
    end
    if ((t - @lastrblink)*10).to_i >= 2
      @lastrblink = t
      @rblink_state = !@rblink_state
      doblink = true
    end
    # FIXME: It bugs out at some point?
    @buffer.redraw_blink if doblink
  end

  def redraw_positions(positions) = positions.each { |pos| @buffer.redraw(*pos) }

  # FIXME: Cursor, selection etc. are "special" overlays on top of attributes.
  # Allow the terminal to set a set of positions + fg/bg, and a set of ranges.
  def render_selection
    # This should work reasonably well
    olddamage = @selection_damage || Set.new
    @selection_damage = Set.new
    @buffer.each_character_between(@select_startpos[0]..@select_startpos[1], @select_endpos[0]..@select_endpos[1]) do |x,y,cell|
      @selection_damage << [x,y]
      @buffer.redraw_with(x,y, fg: 0xffffff, bg: 0xff00ff)
    end
    redraw_positions(olddamage - @selection_damage)
    @buffer.draw_flush
    #@window.flush
  end

  def get_selection
    startpos = @select_startpos
    endpos   = @select_endpos
    str = ""
    ypos = nil
    @buffer.each_character_between(startpos[0]..startpos[1], endpos[0]..endpos[1]) do |x,y,cell|
      str += "\n" if ypos && y != ypos
      ypos = y
      str << cell[0].chr rescue ""
    end
    str
  end

  def clear_selection_if_set
    return if !@select_startpos
    redraw_positions(@selection_damage)
    @select_startpos = nil
    # FIXME
    redraw
  end
  
  def handle_mouse(pkt)
    p pkt
    p [@mouse_mode,@mouse_reporting]
    @mouse_buttons = button = pkt.detail > 0 ? pkt.detail : @mouse_buttons
    release = pkt.is_a?(X11::Form::ButtonRelease)
    p [pkt.class, pkt.is_a?(X11::Form::ButtonRelease)]
    x = pkt.event_x / char_w
    y = pkt.event_y / char_h
    case @mouse_mode
    when nil
      # New selection, but the old has not been cleared yet
      if @released
        clear_selection_if_set
        @released = false
      end
      
      @select_startpos ||= [x,y]
      if [x,y] != @select_endpos
        @select_endpos = [x,y]
        # FIXME: Optimize rendering of selection further
        render_selection
      end

      p :HERE, release
      if release
        @released = true
        if @select_startpos != @select_endpos
          sel = get_selection
          io = IO.popen("xsel -i", "a+")
          io.write(sel)
          io.close
        else
          clear_selection_if_set
        end
      end
    when :vt200, :btn_event
      # FIXME: This is only right for  @mouse_reporting == :digits
      # FIXME: Report modifiers.
      # Not reporting release for scroll wheel
      return if release && button >= 4
      event = [0,1,2,64,65][button-1]
      event += 32 if pkt.is_a?(X11::Form::MotionNotify)
      #button = [0,1,2,4,5][button-1]
      @controller.mouse_report(@mouse_reporting, event, x,y, release)
    end
  end
  
  def process(pkt)
  #  p pkt
    case pkt
    when X11::Form::ButtonPress, X11::Form::MotionNotify, X11::Form::ButtonRelease
      handle_mouse(pkt)
    when X11::Form::KeyPress
      key(pkt)
    when X11::Form::KeyRelease,
         X11::Form::NoExposure
      # Intentionally ignored
    when X11::Form::Expose, X11::Form::ConfigureNotify
      resize(pkt.width,pkt.height)
      #@window.dirty!#@window.flush
    else
      p pkt
    end
  end

  def event_thread
    Thread.new do
      loop do
        pkt = @window.dpy.next_packet
        process(pkt)
        Thread.pass
      end
    end
  end


  def run(args)
    puts "RUNNING; args: #{args.inspect}"

    @controller = Controller.new(self)
    @controller.run(*args)
   
    @lastblink  ||= Time.now
    @lastrblink ||= Time.now

    Thread.abort_on_exception = true
    threads =[]
    
    threads << Thread.new do
      loop do
        process_queue
        Thread.pass
      end
    end

    threads << event_thread
    
    threads << Thread.new do
      loop do
        timeout = @buffer.blinky.empty? ? 1 : 0.2
        sleep(timeout)
        # FIXME: This draws changes, and so touches
        # the buffer.
        blink
      end
    end

    # FIXME: This is ... extreme
    threads << Thread.new do
      loop do
        @window.flush
        sleep(1/30.0)
      end
    end

    if ENV["DEBUG"].to_s.strip != ""
      while cmd = STDIN.gets&.strip
        binding.pry if cmd == "pry"
      end
    end

    threads.each(&:join)
  end
end

RubyTerm.new(ARGV).run(ARGV)
