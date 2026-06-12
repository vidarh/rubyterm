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
    case @state
    when :start
      return false if ch < 32
      @str << ch.chr
      case ch.chr
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
      @str << ch.chr
      @state = :complete if /[[:alpha:]]|[[:cntrl:]]|[@]/.match(ch.chr)
    when :oc
      if ch == 7 then @state = :complete
      elsif ch < 32 then return false
      else @str << ch.chr
      end
    when :string
      if ch == 7
        @state = :complete
      elsif ch == 27
        @state = :string_esc
      elsif ch < 32
        return false
      else
        @str << ch.chr
      end
    when :string_esc
      if ch.chr == '\\'
        @state = :complete
      else
        @str << 27.chr << ch.chr
        @state = :string
      end
    else
      return false
    end
    true
  end

  def complete?; @state == :complete; end
end
