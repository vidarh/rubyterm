
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

    w = w/char_w
    h = h/char_h
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

  # Escape/control/character interpretation lives in Term (lib/term.rb).
  # RubyTerm only owns the X11 window, the pty controller and the
  # threading; this keeps the terminal core testable headlessly (see
  # harness/).

  def write(str)
    @queue << str
  end

  def process_queue = process_chunk(@queue.shift)

  # Everything that touches the buffer/window runs here, on the single
  # input-processing thread. The blink and flush timers enqueue :blink
  # and :flush rather than touching the buffer from their own threads:
  # the buffer/renderer is not thread-safe, and concurrent mutation
  # (e.g. blink's redraw racing a feed mid-scroll) corrupts cells
  # non-deterministically. Serializing through the queue is the
  # synchronization.
  def process_chunk(str)
    case str
    when :blink then return blink
    when :flush then return @window.flush
    when Array  then return resize(str[1], str[2]) if str[0] == :resize
    end

    # FIXME: Could be smarter about this; it's only needed if the
    # first character being written won't clear the same square.
    @term.clear_cursor

    @term.feed(str)

    # FIXME: Do this only when a) queue is empty or b)
    # a certain amount of time has elapsed.
    @term.draw_cursor
    @buffer.draw_flush # Ensure everything has been rendered
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
      @controller.mouse_report(@term.mouse_reporting, event, x,y, release)
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
      # resize/redraw mutates the buffer; run it on the processing
      # thread (via the queue) rather than here on the event thread, or
      # it races a concurrent feed and corrupts cells.
      @queue << [:resize, pkt.width, pkt.height]
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
    @term.responder = @controller

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
        sleep(0.1)
        # Enqueue rather than calling blink directly: blink redraws and
        # so touches the buffer, which must only be mutated on the
        # processing thread. blink self-gates on elapsed time, so a
        # fixed tick is fine.
        @queue << :blink
      end
    end

    # Flush on the processing thread too, so the @buf->window copy never
    # races a concurrent buffer mutation.
    threads << Thread.new do
      loop do
        @queue << :flush
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

RubyTerm.new(ARGV).run(ARGV) if $0 == __FILE__
