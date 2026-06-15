require_relative 'palette'      # PALETTE_BASIC, FG, BG
require_relative 'escapeparser'
require_relative 'utf8decoder'
require_relative 'charsets'

# The escape/control interpreter: it turns a byte stream into operations on
# a buffer, and knows *nothing* about X11, windows, or how its buffer is
# rendered. It talks only to its buffer (a TrackChanges, which owns the
# render backend). The same interpreter therefore drives a terminal that
# renders to an X11 window or to a terminal (AnsiBackend), or for a
# multiplexer / TUI library, depending only on the backend behind the
# buffer. It carries no pixel/colour constants and no rendering: even the
# cursor is just a position it reports (#draw_cursor) for the buffer to
# render as an overlay.
class Term
  attr_accessor :x, :y, :wraparound, :cursor, :origin_mode,
    :mouse_mode, :mouse_reporting, :tabs, :esc, :mode, :mouse_buttons

  # Object receiving terminal query replies (DSR/DA). Must respond to
  # #report_position(x,y) and the three Device Attributes replies
  # #device_attr_primary / #device_attr_secondary / #device_attr_tertiary.
  # In the live terminal this is the Controller (which writes to the
  # pty); in the test harness it is a Session capturing responses.
  attr_accessor :responder

  def initialize(buffer)
    @buffer = buffer

    # FIXME: I should consider whether to change origin to match the terminal handling
    # as it might be easier.
    @x = 0; @y = 0

    # Initial size only; the host resizes to the real geometry before use.
    @term_width  = 80
    @term_height = 24

    @tabs = 40.times.map {|i| i * 8}

    # EscapeParser instance when an escape code is being parsed.
    # FIXME: Clearing this each time is probably slow.
    @esc = nil 


    @bg = BG
    @fg = FG
    @mode = 0

    @wraparound = true

    # Show cursor?
    @cursor = true

    # DECOM - Origin Mode - https://vt100.net/docs/vt510-rm/DECOM.html
    # FIXME: Origin mode is currently only partially respected.
    @origin_mode = false

    # LNM - Line Feed / New Line Mode - See https://vt100.net/docs/vt100-ug/chapter3.html
    # LNM (line feed/new line mode). When reset (the VT100 default), LF/VT/FF
    # only move down; when set, they also return to column 0. The pty's
    # ONLCR already turns a program's "\n" into "\r\n", so off is both
    # correct and what tmux/xterm do.
    @lnm = false
    # IRM (insert/replace mode). When set, printed characters are inserted
    # at the cursor, shifting the rest of the line right, rather than
    # overwriting. Default replace (off).
    @irm = false

    # :x10, :v200, :v200_highlight, :btn_event, :any_event
    # FIXME: Only :btn_event_mouse supported so far
    # See: https://www.xfree86.org/current/ctlseqs.html ("Mouse tracking")
    @mouse_mode = nil
    # Mouse reporting format. nil == x10, :multibyte (NOT SUPPORTED), :digits,
    # :urxvt (NOT SUPPORTED, probably never)
    @mouse_reporting = nil
    # Currently pressed mouse buttons.
    @mouse_buttons = nil

    # Character set state (GL/GR designation per vt100/vt220).
    @gl = 0
    @gr = nil # FIXME: GR shifting not implemented
    @g = [DefaultCharset, nil, nil, nil]
    @saved = nil # Saved cursor state (ESC 7 / ESC 8)

    @decoder = UTF8Decoder.new
    @responder = nil
  end

  def charset = @g[@gl] || DefaultCharset

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
    @buffer.clear   # the buffer (TrackChanges) also clears the backend
  end

  # RIS - Reset to Initial State (ESC c). Full reset: restore margins,
  # modes, charsets, tab stops and attributes to their defaults, home the
  # cursor and clear the screen.
  def reset
    @x = @y = 0
    @tabs = 40.times.map {|i| i * 8}
    @fg = FG; @bg = BG; @mode = 0
    invalidate_colours
    @wraparound  = true
    @cursor      = true
    @origin_mode = false
    @lnm = false
    @irm = false
    @mouse_mode = nil
    @mouse_reporting = nil
    @gl = 0; @gr = nil
    @g  = [DefaultCharset, nil, nil, nil]
    @saved = nil
    clear_screen   # also resets the scroll region and clears
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
      unhandled(:erase_in_line, ps)
    end
  end

  def insert_lines(num) = @buffer.insert_lines(@y, num||1, height)

  def delete
    @x = clampw(@x - 1)
    @buffer.set(@x,@y, 66, fg, bg, @mode)
  end
    
  # FIXME (still broken) Emacs uses this to scroll up
  def delete_lines(num) = @buffer.delete_lines(@y, num, height)

  # DCH - delete characters at the cursor, shifting the line left.
  def delete_chars(num)
    @buffer.delete_chars(@x, @y, num || 1)
    redraw_line_from_cursor
  end

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
    # The buffer (TrackChanges) drives the backend scroll - the blit and the
    # scrolled-back-view handling are rendering concerns, not interpreter
    # ones.
    num.times { @buffer.scroll_up }
  end

  def scroll_if_needed
    # Scroll at the scroll-region bottom margin, which (like IND/RI)
    # applies regardless of origin mode - LF and wrap both scroll the
    # region, not the whole screen, when a region is set.
    dy = @y - region_bottom
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


  # Resolved fg/bg are recomputed only when an SGR (or reset) changes
  # @fg/@bg/@mode - not per character. putchar resolves the colour for every
  # printable glyph, so doing the String/palette dance each time showed up
  # in the profile; memoise and invalidate via #invalidate_colours.
  def fg
    @fg_resolved ||=
      @fg.is_a?(String) ? PALETTE_BASIC[@fg.to_i + (@mode.allbits?(BOLD) ? 8:0)] : @fg
  end
  def bg
    @bg_resolved ||= @bg.is_a?(String) ? PALETTE_BASIC[@bg.to_i] : @bg
  end
  def invalidate_colours; @fg_resolved = @bg_resolved = nil; end
    
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
      else return unhandled(:sgr, c)
      end
    end
  ensure
    invalidate_colours
  end

  
  def wrap_if_needed
    if @x >= line_width
      if @wraparound
        @x = 0
        @y += 1
      else
        @x = line_width-1
      end
    elsif @x < 0
      if @wraparound
        @y -= 1
        @x = line_width-1
      else
        @x = 0
      end
    end
  end

  # The cursor is a render-time overlay, not interpreter state: the
  # interpreter just reports where the cursor is (and whether it's shown);
  # the buffer/backend renders it. (See docs/architecture-review.md Phase 4.)
  def clear_cursor = @buffer.clear_cursor

  def draw_cursor
    x, y = @x, @y
    y += 1 if x >= width   # pending-wrap: the cursor shows on the next row
    @buffer.draw_cursor(x, y, @cursor)
  end

  # FIXME: Redrawing full spans would be better.
  def redraw_line_from_cursor
    clear_cursor
    (@x..width).each {|x| @buffer.redraw(x,@y) }
    draw_cursor
  end

  # Set a line's width/height attribute (DECDHL/DECDWL/DECSWL) and re-render
  # the whole line: a single/double switch changes the size of glyphs
  # already on the line, so the cells written before the attribute must be
  # repainted (vttest sets the attribute *after* writing the text).
  def set_line_attrs(attr)
    @buffer.set_lineattrs(@y, attr)
    clear_cursor
    # Repaint this line and its neighbours from their own attributes. A
    # (previous) double-height attribute on this line draws into the row
    # above/below; switching to a shorter attribute must clear those
    # spilled halves, which only repainting the neighbour rows does.
    [@y - 1, @y, @y + 1].each do |row|
      next if row < 0 || row >= height
      (0...width).each {|x| @buffer.redraw(x, row) }
    end
    @buffer.draw_flush
    draw_cursor
  end

  def set_width_and_clear(w)
    # DECCOLM. Set the logical width, then let the display layer actually
    # realise the column change - by rescaling the font or resizing the
    # window (RubyTerm#set_columns); a no-op in the headless harness.
    resize(w, height)
    @buffer.set_columns(w)
    clear_screen
  end

  def origin =  @origin_mode ? (@buffer.scroll_start || 0) : 0
  # Inclusive bottom row of the active region.  CSI scroll_end is already
  # stored as an inclusive index; when unset the active region is the
  # whole screen, so the last valid row is height - 1.
  def bottom =  @origin_mode ? (@buffer.scroll_end || height - 1) : height - 1
  # The scroll region margins. Unlike #origin/#bottom these are NOT gated
  # on origin mode: DECSTBM governs IND/RI/LF scrolling whether or not
  # DECOM is set (origin mode only affects cursor addressing).
  def region_top    = @buffer.scroll_start || 0
  def region_bottom = @buffer.scroll_end   || height - 1
  # Usable column count of the current line. Double-width/height lines show
  # each cell twice as wide, so only width/2 columns fit; the cursor's last
  # valid column is therefore line_width-1.
  def line_width
    case @buffer.lineattrs(@y)
    when :dbl_upper, :dbl_lower, :dbl_single then width / 2
    else width
    end
  end
  def clampw(i) = i.clamp(0,line_width-1)
  def clamph(i) = i.clamp(origin,bottom)

  # IND - index: down one line; at the bottom margin scroll the region up.
  def index
    if @y >= region_bottom
      @y = region_bottom
      scroll_up(1)
    else
      @y += 1
    end
  end

  # RI - reverse index: up one line; at the top margin scroll the region
  # down (insert a blank line at the top, discarding the region's last).
  def reverse_index
    if @y <= region_top
      @y = region_top
      insert_lines(1)
    else
      @y -= 1
    end
  end
  
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
    when "P" then delete_chars(args[0]||1)
    when "S" then scroll_up(args[0]||1)
    when "T"; # Scroll down
    when "c"
      # Device Attributes. The reply type depends on the private prefix;
      # answering DA1/DA2 with the wrong kind (e.g. a DA3 DCS) means a
      # host like tmux fails to recognise it and leaks it to the pane.
      #   CSI c   / CSI 0 c  -> primary   (DA1), reply CSI ? ... c
      #   CSI > c / CSI > 0 c-> secondary (DA2), reply CSI > ... c
      #   CSI = c            -> tertiary  (DA3), reply DCS ! | ... ST
      if block_given?
        case s[1]
        when ">" then yield(:device_attr_secondary)
        when "=" then yield(:device_attr_tertiary)
        else          yield(:device_attr_primary)
        end
      end
    when "d"
      @y = clamph(origin+(args[0]||1) - 1) # FIXME: Should these be clamped
    when "g"
      case args[0].to_i
      when 0 then @tabs.delete(@x)
      when 3 then @tabs = []
      end
    when "h", "l"
      # Standard (non-DEC-private) modes - SM/RM. 4 = IRM, 20 = LNM.
      set = s[-1] == "h"
      args.each do |code|
        case code
        when 4  then @irm = set
        when 20 then @lnm = set
        end
      end
    when "m"; set_modes(args.empty? ? [0] : args)
    when "n"
      case args[0]
      when 6
        yield(:report_position) if block_given?
      else
        unhandled(:dsr, args)
      end
    when "r"
      @buffer.scroll_start = (args[0] || 1)-1
      @buffer.scroll_end   = (args[1] || height)-1
      # DECSTBM homes the cursor: to the origin (region top) in origin
      # mode, otherwise to screen home.
      @x = 0
      @y = origin
    else
      unhandled(:csi, s)
    end
    nil
  end


  # This is the *preferred* public interface:
  #
  # Feed raw bytes (as read from the pty) into the terminal. Handles
  # UTF-8 decoding, control characters and escape sequences. This is
  # synchronous: when it returns, all bytes have been interpreted and
  # the buffer updated (rendering may still be batched in TrackChanges
  # until #draw_flush is called on the buffer).
  def feed(str)
    @decoder << str
    # each_codepoint yields Integer codepoints directly (the decoder already
    # maps bytes it can't decode to U+FFFD), so the hot path allocates no
    # per-character String and does no per-character valid_encoding?/ord.
    @decoder.each_codepoint { |cp| putchar(cp) }
  rescue StandardError
    # Last-resort guard so a malformed sequence can't take down the input
    # thread; stays silent (no debug output to the pane/stderr).
  end
  alias write feed

  def putchar(ch)
    if ch.is_a?(String)
      STDERR.puts "WARNING: Should be int"
      ch = ch.ord
    end
    if @esc&.put(ch)
      handle_escape(ch)
    elsif ch < 32
      handle_control(ch)
    else
      wrap_if_needed
      scroll_if_needed
      return if ch == 127   # DEL is ignored in the data stream

      # IRM (insert mode): shift the rest of the line right and repaint it,
      # then drop the new glyph into the gap.
      if @irm
        @buffer.insert(@x, @y, 1, [32,0,0,0])
        @buffer.set(@x, @y, charset[ch], fg, bg, @mode)
        redraw_line_from_cursor
      else
        @buffer.set(@x, @y, charset[ch], fg, bg, @mode)
      end
      @y = clamph(@y)
      @x += 1
      scroll_if_needed
    end
  end

  def handle_escape(ch)
    return false if !@esc.complete?
    s = @esc.str
    if s[0] == ?[
      handle_csi(s) {|op| respond(op) }
      @esc = nil
      return
    end

    case s
    when "D"; index            # IND
    when "E"; index; @x = 0     # NEL
    when "H"; @tabs = (@tabs << @x).sort.uniq
    when "M"; reverse_index     # RI
    when "#3"; set_line_attrs(:dbl_upper)   # DECDHL top half
    when "#4"; set_line_attrs(:dbl_lower)   # DECDHL bottom half
    when "#5"; set_line_attrs(0)            # DECSWL single width
    when "#6"; set_line_attrs(:dbl_single)  # DECDWL double width
    when "c"; reset            # RIS
    when "#8"; decaln
    when "(B"; @g[0] = DefaultCharset
    when ")B"; @g[1] = DefaultCharset
    when "(0"; @g[0] = GraphicsCharset
    when ")0"; @g[1] = GraphicsCharset
    when "7";  @saved = [@x,@y,@gl,@gr,@g.dup]
    when "8"
      # DECRC with no prior DECSC: default to home position and default
      # charsets rather than leaving @x/@y nil (which crashes draw_cursor).
      sx, sy, sgl, sgr, sg = @saved || [0, 0, 0, nil, [DefaultCharset, nil, nil, nil]]
      @x, @y, @gl, @gr, @g = sx, sy, sgl, sgr, sg
    else
      unhandled(:escape, s)
    end

    @esc = nil
  end

  def handle_control(ch)
    case ch
    when 1,2;
    when 7; unhandled(:bell)
    when 8;
      # Backspace. From the pending-wrap state (cursor parked past the last
      # column after printing there) BS clears the pending wrap and stays on
      # the last column, rather than stepping back two.
      if    @x >= line_width then @x = line_width - 1
      elsif @x > 0           then @x -= 1
      end
    when 9
      if i = @tabs.index {|t| t > @x}
        # FIXME: This is only right behaviour if wrap is off, is it not?
        @x = clampw(@tabs[i])
      else
        # No tab stop to the right (e.g. all stops cleared via TBC): HT
        # advances to the last column, per VT100.
        @x = line_width - 1
      end
    when 10, 11
      linefeed
    when 12; @x = 0; @y = 0
    when 13; @x = 0
    when 14; @gl = 1
    when 15; @gl = 0
    when 16..26;
    when 27; @esc = EscapeParser.new # FIXME: Is this right if !@esc.nil? ?
    when 28..31;
    end
  end

  private

  # Observability seam for input the terminal does not (yet) implement:
  # unknown escape/control sequences, SGR parameters, query types. A no-op
  # in production - it is deliberately SILENT (programs constantly emit
  # things we don't handle, e.g. OSC title sets and bright-colour SGR;
  # printing them spewed debug noise to stderr). The harness overrides this
  # to collect what real programs use that we don't support yet.
  def unhandled(kind, detail = nil)
  end

  # Dispatch a terminal query reply request (yielded by handle_csi)
  # to the responder, if one is attached.
  def respond(op)
    return if !@responder
    case op
    when :report_position        then @responder.report_position(@x, @y)
    when :device_attr_primary    then @responder.device_attr_primary
    when :device_attr_secondary  then @responder.device_attr_secondary
    when :device_attr_tertiary   then @responder.device_attr_tertiary
    else
      unhandled(:respond, op)
    end
  end

end
  
