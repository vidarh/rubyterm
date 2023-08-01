
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
    when :csi; @state = :complete if /[[:alpha:]]|[[:cntrl:]]/.match(ch.chr)
    when :oc;  @state = :complete if ch == 7
    else
      raise "Complete";
    end
  end

  def complete?; @state == :complete; end
end

