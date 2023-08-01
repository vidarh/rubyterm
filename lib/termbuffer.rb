
class TermBuffer
  def initialize
    @scrbuf = []
  end

  def get(x,y) (@scrbuf[y]||[])[x]; end
  def scroll_up; @scrbuf.shift; end
  def set(x,y,ch, fg=0, bg=0)
    @scrbuf[y]||=[]
    @scrbuf[y][x] = [ch.ord,fg,bg]
  end

  def clear; @scrbuf = []; end
end
