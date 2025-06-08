
require 'pty'
require 'io/console'

require_relative 'bundle/bundler/setup'
#$: << "/home/vidarh/.gem/ruby/3.2.2/gems/skrift-0.1.0/lib"

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

#require 'pry'

$> = $stderr

require_relative 'lib/windowadapter'
require_relative 'lib/trackchanges'
require_relative 'lib/term'

BG="0"
FG="7"


class RubyTerm
  TOPMOST= 0
  LEFTMOST=0
  
  attr_reader :blink_state, :rblink_state
  
  def charset = @g[@gl] || DefaultCharset
  def char_w  = @adapter.char_w
  def char_h  = @adapter.char_h
  def term_width = @term.width
  def term_height = @term.height

  def initconfig
    cname = File.expand_path("~/.config/rterm/config.toml")
    if File.exist?(cname)
      @config = TomlRB.load_file(cname, symbolize_keys: true)
    end
    @config ||= {}
  end

  def inspect = "<RubyTerm #{self.object_id}>"

  def get_x = @term.x
  def get_y = @term.y
    
  def initialize(args)
    initconfig

    pp(:config,@config)

    @queue = Queue.new
    
    @window = Window.new(fonts: @config[:fonts], fontsize: @config[:fontsize])
    @adapter = WindowAdapter.new(@window, self)

    @gl = 0
    @g = [DefaultCharset,nil,nil,nil] # Alternate charsets

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

    @buffer = TrackChanges.new(TermBuffer.new, @adapter)
    @term = Term.new(@buffer, @adapter)
    @buffer.on_resize(@term.width, @term.height)

    # Give window access to the buffer for scrollback
    @window.set_buffer(@buffer)

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
    @term.draw_cursor
  end

  def render_text_buffer
    (0...@term.height).each {|y|
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
    #if w != @term.width && h == @term.height
    @buffer.on_resize(w,h)
    ow, oh = @term.width, @term.height

    if ow != w || oh != h
      @term.resize(w,h)
      @controller.report_size(w,h)
    end

    if should_redraw
      redraw
    end
  end


  def fg = @term.fg
  def bg = @term.bg

  # # Editing operations


  # # Handle escapes


  def origin =  @term.origin_mode ? @buffer.scroll_start || 0 : 0
  def bottom =  @term.origin_mode ? @buffer.scroll_end || @term.height : @term.height
  def clampw(i) = i.clamp(0,@term.width-1)
  def clamph(i) = i.clamp(origin,bottom)


  def report_position = @controller.report_position(@term.x,@term.y)
  def device_report   = @controller.device_report

  def handle_escape(ch)
    return false if !@term.esc.complete?
    s = @term.esc.str
    if s[0] == ?[
      @term.handle_csi(s) {|op| send(op) }
      @term.esc = nil
      return
    end

    case s
    when "D"; @term.y += 1
    when "E"; @term.y += 1; @term.x = 0
    when "H"; @term.tabs = (@term.tabs << @x).sort.uniq
    when "M"
      @term.y -= 1
      if @term.y < 0
        @term.y=0
        @term.insert_lines(1)
      end
    when "#3"; @buffer.set_lineattrs(@term.y, :dbl_upper) # FIXME: Flags
    when "#4"; @buffer.set_lineattrs(@term.y, :dbl_lower) # FIXME: Flags
    when "#5"; @buffer.set_lineattrs(@term.y, 0) # FIXME: Flags
    when "#6"; @buffer.set_lineattrs(@term.y, :dbl_single) # FIXME: Flags
    when "#8"; @term.decaln
    when "(B"; @g[0] = DefaultCharset
    when ")B"; @g[1] = DefaultCharset
    when "(0"; @g[0] = GraphicsCharset
    when ")0"; @g[1] = GraphicsCharset        
    when "7";  @saved = [@term.x,@term.y,@gl,@gr,@g.dup]
    when "8";  @term.x,@term.y,@gl,@gr,@g = *Array(@saved)
    else
      p @term.esc
    end

    @term.esc = nil
  end

  def handle_control(ch)
    case ch
    when 1,2;
    when 7; p :bell
    when 8;
      if    @term.x >= @term.width then @term.x -= 2
      elsif @term.x > 0 then @term.x -= 1
      end
    when 9
      if i = @term.tabs.index {|t| t>@term.x}
        t = @term.tabs[i]
        # FIXME: This is only right behaviour if wrap is off, is it not?
        @term.x = clampw(t) if t > @term.x
      end
    when 10, 11
      @term.linefeed
    when 12; @term.x = 0; @term.y = 0
    when 13; @term.x = 0
    when 14; @gl = 1
    when 15; @gl = 0
    when 16..26;
    when 27; @term.esc = EscapeParser.new # FIXME: Is this right if !@esc.nil? ?
    when 28..31;
    end
  end
  
  def putchar(ch)
    ox,oy=@term.x,@term.y
    if ch.is_a?(String)
      STDERR.puts "WARNING: Should be int"
      ch = ch.ord
    end
    if @term.esc&.put(ch)
      handle_escape(ch)
    elsif ch.ord < 32
      handle_control(ch)
    else
      @term.wrap_if_needed
      @term.scroll_if_needed
      return @term.delete if ch == 127

      @buffer.set(@term.x, @term.y, charset[ch], fg, bg, @term.mode)
      @term.y = clamph(@term.y)
      @term.x += 1
      @term.scroll_if_needed
    end
  end


  def write(str)
    @queue << str
  end

  def process_queue
    str = @queue.shift
    @decoder ||= UTF8Decoder.new
    @decoder << str

    # FIXME: Could be smarter about this; it's only needed if the
    # first character being written won't clear the same square.
    @term.clear_cursor

    @decoder.each do|c|
      begin
        putchar(c.ord)
      rescue Exception => e
        p [c, e, @decoder]
        p e.backtrace
        putchar(' ')
      end
    end

    # FIXME: Do this only when a) queue is empty or b)
    # a certain amount of time has elapsed.
    @term.draw_cursor
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
        @term.clear_cursor
        # Force draw cursor again
        @term.draw_cursor
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
    p [@term.mouse_mode,@term.mouse_reporting]
    @term.mouse_buttons = button = pkt.detail > 0 ? pkt.detail : @term.mouse_buttons
    release = pkt.is_a?(X11::Form::ButtonRelease)
    p [pkt.class, pkt.is_a?(X11::Form::ButtonRelease)]
    x = pkt.event_x / char_w
    y = pkt.event_y / char_h
    case @term.mouse_mode
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

    @controller = Controller.new(self, @config)
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
