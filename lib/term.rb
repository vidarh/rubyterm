require_relative 'lib/escapeparser'

# This class is a start of untangling/extracting the *display* side
# of RubyTerm from everything else. Currently it still indirectly
# (via `adapter` in particular, but also via the `buffer`, which in
# reality is a an instances of TrackChanges) depends on the X11
# integration, but the next step is to allow this class to function
# with just a buffer with damage tracking so that it is possible to
# use it to render *either* to a terminal (which doesn't make much
# sense for the terminal directly, but would for other applications,
# or e.g. terminal multiplexers) or to an X11 window.
#
# Ideally, in the longer-term, it should also be possible to assign
# a Term instance to e.g. $stdout and optionally $stdin and have
# your application open a window.
#
# This class should know *nothing* about X11 or windows, and should
# ideally not use the `@adapter` (eventually, the "adapter" should
# be removed/combined with `TrackChanges` and the whole thing overhauled)
#
# Decoupling this will also eventually make the terminal a lot more
# testable.
#
class Term
  CURSOR = 0xff00ff

  def char_w  = @adapter.char_w
  def char_h  = @adapter.char_h

  attr_accessor :x, :y, :wraparound, :cursor, :origin_mode,
    :mouse_mode, :mouse_reporting, :tabs, :esc, :mode

  def initialize(buffer, adapter)
    @buffer = buffer
    @adapter = adapter # FIXME: Untangle

    # FIXME: I should consider whether to change origin to match the terminal handling
    # as it might be easier.
    @x = 0; @y = 0

    @term_width  = (400 / char_w).to_i
    @term_height = (400 / char_h).to_i

    @tabs = 40.times.map {|i| i * 8}

    # EscapeParser instance when an escape code is being parsed.
    # FIXME: Clearing this each time is probably slow.
    @esc = nil 


    @bg = BG
    @fg = FG
    @mode = 0

    @wraparound = true

    # Used to save the cursor position
    @cursor_pos = nil
    # Show cursor?
    @cursor = true

    # DECOM - Origin Mode - https://vt100.net/docs/vt510-rm/DECOM.html
    # FIXME: Origin mode is currently only partially respected.
    @origin_mode = false

    # LNM - Line Feed / New Line Mode - See https://vt100.net/docs/vt100-ug/chapter3.html
    # Whether LF (0x0A) will imply only vertical movement, or will also
    # reset x position to 0 (default).
    @lnm = true

    # :x10, :v200, :v200_highlight, :btn_event, :any_event
    # FIXME: Only :btn_event_mouse supported so far
    # See: https://www.xfree86.org/current/ctlseqs.html ("Mouse tracking")
    @mouse_mode = nil
    # Mouse reporting format. nil == x10, :multibyte (NOT SUPPORTED), :digits,
    # :urxvt (NOT SUPPORTED, probably never)
    @mouse_reporting = nil
    # Currently pressed mouse buttons.
    @mouse_buttons = nil
  end

  def width  = @term_width
  def height = @term_height

  def clear_to_end      = @buffer.clear_line(@y, @x)
  def clear_to_start    = @buffer.clear_line(@y, 0, @x)
  def clear_line(y=nil) = @buffer.clear_line(y||@y, 0)
  def clear_above
    (0...y).each {|y| clear_line(y) }
    clear_to_start
  end

  def clear_below
    clear_to_end
    (y+1..height).each {|y| clear_line(y)}
  end

  # Per vt100 user guide:
  # Erase all of the display –
  # all lines are erased, changed to single-width,
  # and the cursor does not move.
  #
  def clear_screen
    @buffer.scroll_start = nil
    @buffer.scroll_end   = nil
    @buffer.clear
    @adapter.clear
  end

  # ED - Erase In Display - ESC [ Ps J
  def erase_in_display(ps = 0)
    case ps.to_i
    when 0 then clear_below
    when 1 then clear_above
    when 2 then clear_screen
    when 3 then @buffer.clear  # FIXME: Not in VT100. Where is this from?
    end
  end

  # EL - Erase In Line - ESC [ Ps K
  def erase_in_line(ps = 0)
    case ps.to_i
    when 0 then clear_to_end
    when 1 then clear_to_start
    when 2 then clear_line
    else
      p @esc
    end
  end

  def insert_lines(num) = @buffer.insert_lines(@y, num||1, height)

  def delete
    @x = clampw(@x - 1)
    @buffer.set(@x,@y, 66, fg, bg, @mode)
  end
    
  # FIXME (still broken) Emacs uses this to scroll up
  def delete_lines(num) = @buffer.delete_lines(@y, num, height)

  # ESC [ Pn A / B
  # FIXME: Should these not use clamph?
  def cursor_up(lines)   = (@y = clamph(@y - lines.to_i.clamp(1,height)))
  def cursor_down(lines) = (@y = clamph(@y + lines.to_i.clamp(1,height)))

  def decaln
    # DEC alignment; only purpose served here is for vttest
    # so doesn't need to be efficient
    @buffer.scroll_start = nil
    @buffer.scroll_end   = nil
    width.times.each do |x|
      height.times.each do |y|
        @buffer.set(x,y,'E',fg,bg,0)
      end
    end
    @buffer.draw_flush
  end

  def resize(w,h)
    @term_width = w
    @term_height = h
  end

  def scroll_up(num=1)
    num.times do
      @buffer.draw_flush
      @buffer.scroll_up
      @adapter.scroll_up(@buffer.scroll_start.to_i, @buffer.scroll_end || height)
    end
  end

  def scroll_if_needed
    dy = @y - (@buffer.scroll_end || height)
    if dy > 0
      scroll_up(dy)
      @y -= dy
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

  
  def wrap_if_needed
    if @x >= width
      if @wraparound
        @x = 0
        @y += 1
      else
        @x = width-1
      end
    elsif @x < 0
      if @wraparound
        @y -= 1
        @x = width-1
      else
        @x = 0
      end
    end
  end

  def clear_cursor
    return if !@cursor_pos
    @buffer.redraw(*@cursor_pos)
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
    if x >= width
      y+=1
    end
    @buffer.redraw_with(x,y, bg: CURSOR)
    @cursor_pos = [x,y]
  end

  # FIXME: Redrawing full spans would be better.
  def redraw_line_from_cursor
    clear_cursor
    (@x..width).each {|x| @buffer.redraw(x,@y) }
    draw_cursor
  end

  def set_width_and_clear(w)
    # FIXME: Need to *either* resize window or rescale font
    # to work properly.
    # FIXME: Verify if clear_screen is appropriate.
    resize(set ? 132 : 80, height)
    clear_screen
  end

  def origin =  @origin_mode ? (@buffer.scroll_start || 0) : 0
  def bottom =  @origin_mode ? (@buffer.scroll_end   || height) : height
  def clampw(i) = i.clamp(0,width-1)
  def clamph(i) = i.clamp(origin,bottom)
  
  def linefeed
    @x = 0 if @lnm
    @buffer.draw_flush
    @y = clamph(@y) + 1
    scroll_if_needed
  end
    
  def handle_dec(s) # CSI '?' -> DEC private modes
    args = s[2..-2].split(/[:;]/).map{|i| i.empty? ? nil : i.to_i }
    case s[-1]
    when "h","l"
      set = s[-1] == "h"
      args.each do |code|
        case code
        when 3  then set_width_and_clear(set ? 132 : 80)
        when 6  then @origin_mode = set
        when 7  then @wraparound  = set
        when 9
          # FIXME: Unsupported X10 mouse reporting mode
        when 20 then @lnm = set
        when 25
          @cursor = set
          clear_cursor if !set
        when 47;
          # Start/end alternate screen mode
          # FIXME: Save/restore
          # FIXME: Scrollback should be disabled/enabled.
          clear_screen

        # Extended mouse modes
        # See https://terminalguide.namepad.de/mouse/
        when 1000 then @mouse_mode = set ? :vt200 : nil
        when 1001 then @mouse_mode = set ? :vt200_highlight : nil
        when 1002 then @mouse_mode = set ? :btn_event : nil
        when 1003 then @mouse_mode = set ? :any_event : nil
        when 1006 then @mouse_reporting = set ? :digits : nil
        when 2004
          # FIXME: Bracketed paste.
        end
      end
    end
  end

  CSI_MAP = {
    "J" => :erase_in_display,
    "K" => :erase_in_line
  }

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
      redraw_line_from_cursor
    when "A" then cursor_up(args[0])
    when "B" then cursor_down(args[0])
    when "C"
      @x = clampw(@x + args[0].to_i.clamp(1,width))
    when "D"
      @x = clampw(@x - args[0].to_i.clamp(1,width))
    when "G"
      @x = clampw((args[0]||1)-1)
    when "H", "f"
      @y = (origin + args[0].to_i.clamp(1,99999))-1
      @x = (args[1]||1)-1
    #when "J" then erase_in_display(args[0])
    #when "K" then erase_in_line(args[0])
    when "L" then insert_lines(args[0])
    when "M" then delete_lines(args[0]||1)
    when "P"
      p @esc
      # delete_chars(args[0]||1)
    when "S" then scroll_up(args[0]||1)
    when "T"; # Scroll down
    when "c"
      yield(:device_report) if block_given?
    when "d"
      @y = clamph(origin+(args[0]||1) - 1) # FIXME: Should these be clamped
    when "g"
      case args[0].to_i
      when 0 then @tabs.delete(@x)
      when 3 then @tabs = []
      end
    when "m"; set_modes(args.empty? ? [0] : args)
    when "n"
      case args[0]
      when 6
        yield(:report_position) if block_given?
      else
        p @esc
      end
    when "r"
      p [:SET_SCROLL, args]
      @buffer.scroll_start = (args[0] || 1)-1
      @buffer.scroll_end   = (args[1] || height)-1
    else
      p @esc
    end
    nil
  end


  # This is the *preferred* public interface:

  def write(str)
  end

  private


end
  
