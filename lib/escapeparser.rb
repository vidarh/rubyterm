# See:
# https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Controls-beginning-with-ESC
#
class EscapeParser
  attr_reader :str, :state

  def initialize
    @state = :start
    @str = ""
  end

  def put(ch)
    # ch is a codepoint, which for OSC/DCS string payloads (e.g. a window
    # title) can be a multibyte UTF-8 character - decode it as UTF-8.
    # Bare Integer#chr only handles 0..255 and raises RangeError on
    # anything larger (e.g. a spinner glyph in claude's title sequence).
    c = ch.chr(Encoding::UTF_8)
    case @state
    when :start
      return false if ch < 32
      @str << c
      case c
      when '['
        @state = :csi
      when ']'
        @state = :oc
      when 'P', 'X', '^', '_'
        # DCS, SOS, PM, APC - string sequences terminated by ST (ESC \) or BEL
        @state = :string
      when /\w|[=>|}~6-9]/
        @state = :complete
      end
    when :csi
      @str << c
      @state = :complete if /[[:alpha:]]|[[:cntrl:]]|[@]/.match(c)
    when :oc
      if ch == 7 then @state = :complete
      elsif ch < 32 then return false
      else @str << c
      end
    when :string
      if ch == 7
        @state = :complete
      elsif ch == 27
        @state = :string_esc
      elsif ch < 32
        return false
      else
        @str << c
      end
    when :string_esc
      if c == '\\'
        @state = :complete
      else
        @str << 27.chr << c
        @state = :string
      end
    else
      return false
    end
    true
  end

  def complete?; @state == :complete; end
end
