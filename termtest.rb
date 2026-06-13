
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
    # Coalesce redraw-causing events (resize/expose): a drag fires a
    # flood of ConfigureNotify + Expose, and repainting on each one makes
    # the display lag while it drains the backlog. Keep at most one
    # redraw request queued, always for the latest pending size.
    @redraw_mutex = Mutex.new
    @redraw_pending = false
    @pending_resize = nil

    # DECCOLM (80/132 column switch) mode: :font rescales the glyph cell to
    # fit the new column count in the current window (reliable everywhere);
    # :window asks the WM to resize the window. Default :font.
    @deccolm_mode = (@config[:deccolm] || "font").to_s.to_sym

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
    # A full repaint draws only buffer content; restore the selection
    # overlay on top so it survives resizes, exposes and scrollback redraws.
    reapply_selection
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

  # DECCOLM: realise an 80/132 column switch (called via the adapter from
  # Term#set_width_and_clear). font mode rescales the glyph cell so `cols`
  # columns fit the current window, keeping the row count; window mode asks
  # the WM to resize. Either way the pty is told the new size.
  def set_columns(cols)
    return if @deccolm_mode == :off   # ignore DECCOLM entirely
    cols = cols.to_i
    return if cols <= 0 || @pixelw.to_i <= 0

    if @deccolm_mode == :window
      # WM-driven: the resulting ConfigureNotify completes the change via resize().
      @window.request_pixel_size(cols * char_w, @pixelh.to_i)
      return
    end

    rows = @term.height
    @window.fit_columns(cols, @pixelw.to_i)
    @buffer.on_resize(cols, rows)
    @term.resize(cols, rows)
    @controller.report_size(cols, rows)
    redraw
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
    when :blink      then return blink
    when :flush      then return @window.flush
    when :do_redraw  then return coalesced_redraw
    end

    # FIXME: Could be smarter about this; it's only needed if the
    # first character being written won't clear the same square.
    @term.clear_cursor

    @term.feed(str)

    # FIXME: Do this only when a) queue is empty or b)
    # a certain amount of time has elapsed.
    @term.draw_cursor
    @buffer.draw_flush # Ensure everything has been rendered
    # Output just repainted cells without the selection overlay; re-stamp
    # it so a streaming program (top, full-screen apps) doesn't erase the
    # highlight out from under an in-progress copy.
    reapply_selection
  end

  # Request a redraw (from the event thread). Records the latest pending
  # size and enqueues a single :do_redraw marker; while one is already
  # queued, further requests just update the target. This collapses a
  # drag's flood of ConfigureNotify+Expose into one repaint per
  # processing slot at the most recent size, instead of one per event.
  def request_redraw(size = nil)
    enqueue = false
    @redraw_mutex.synchronize do
      @pending_resize = size if size
      enqueue = true unless @redraw_pending
      @redraw_pending = true
    end
    @queue << :do_redraw if enqueue
  end

  # Process a coalesced redraw on the processing thread: resize to the
  # latest pending size if it changed, otherwise just repaint.
  def coalesced_redraw
    size = @redraw_mutex.synchronize do
      @redraw_pending = false
      @pending_resize
    end
    if size && size != @last_resize
      @last_resize = size
      resize(size[0], size[1]) # resize repaints as needed
    else
      redraw
    end
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
      exit_scrollback
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
        exit_scrollback
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
    payload = keysym_to_vt102(ks) || str
    # Only snap to the live screen when we're actually sending input;
    # bare modifiers (Ctrl/Shift) produce no payload and must not disturb
    # scrollback (e.g. while setting up a Ctrl+Shift+C copy from history).
    exit_scrollback unless payload.nil? || payload.empty?
    @controller.keypress(payload)
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

  # Sending input to the pty must snap the view back to the live screen;
  # otherwise typed/echoed output is drawn over the scrolled-back display.
  def exit_scrollback
    redraw if @window.scrollback_reset
  end

  def redraw_positions(positions) = positions.each { |pos| @buffer.redraw(*pos) }

  # Re-stamp the active selection highlight on top of freshly drawn
  # content. The selection is an overlay that is NOT stored in the buffer,
  # so any output - or a full redraw - that repaints those cells erases the
  # highlight. Re-applying it after each draw keeps the selection visible
  # while a program streams output (e.g. top repainting, or a full-screen
  # app), which a one-shot paint at mouse-time cannot do.
  def reapply_selection
    return unless @select_startpos && @select_endpos
    sb = @window.scrollback_count
    @buffer.each_character_between(@select_startpos[0]..@select_startpos[1], @select_endpos[0]..@select_endpos[1]) do |x,y,cell|
      sy = y + sb
      next if sy < 0 || sy >= @term.height
      @buffer.redraw_cell_at(x, sy, cell, fg: 0xffffff, bg: 0xff00ff)
    end
    @buffer.draw_flush
  end

  # FIXME: Cursor, selection etc. are "special" overlays on top of attributes.
  # Allow the terminal to set a set of positions + fg/bg, and a set of ranges.
  def render_selection
    # Selection positions are in *buffer* coordinates (negative rows are
    # scrollback); the screen row is buffer_row + scrollback_count. Damage
    # is tracked in screen coordinates so it can be repainted later.
    sb = @window.scrollback_count
    olddamage = @selection_damage || Set.new
    @selection_damage = Set.new
    @buffer.each_character_between(@select_startpos[0]..@select_startpos[1], @select_endpos[0]..@select_endpos[1]) do |x,y,cell|
      sy = y + sb
      next if sy < 0 || sy >= @term.height
      @selection_damage << [x,sy]
      @buffer.redraw_cell_at(x, sy, cell, fg: 0xffffff, bg: 0xff00ff)
    end
    # Repaint cells that left the selection with their displayed content.
    (olddamage - @selection_damage).each { |x,sy| @buffer.redraw_display(x, sy, sb) }
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
      str << (cell[0].chr(Encoding::UTF_8) rescue "")
    end
    str
  end

  def clear_selection_if_set
    return if !@select_startpos
    sb = @window.scrollback_count
    (@selection_damage || []).each { |x,sy| @buffer.redraw_display(x, sy, sb) }
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
    # Holding Shift forces a local text selection even when the
    # application has grabbed the mouse (mouse reporting on - e.g. Claude's
    # agent picker, or any full-screen app with clickable UI). This is the
    # standard xterm override so you can always select/copy.
    shift = pkt.state.anybits?(0x01) # ShiftMask
    case shift ? nil : @term.mouse_mode
    when nil
      # Selection works in buffer coordinates: when scrolled back, the
      # row under the pointer is a scrollback line (buffer row
      # screen_y - scrollback_count, negative for scrollback). Without
      # this, selection/copy reads the live screen instead of what is
      # actually displayed.
      y -= @window.scrollback_count
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
    when X11::Form::ConfigureNotify
      # Real size change: pkt.width/height are the new window size.
      request_redraw([pkt.width, pkt.height])
    when X11::Form::Expose
      # Damage, NOT a size change: pkt.width/height are the exposed
      # rectangle, not the window. Repaint only; never resize here (that
      # would shrink the terminal to the strip size).
      request_redraw
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
