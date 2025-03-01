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
    else
      return false
    end
    true
  end

  def complete?; @state == :complete; end
end
