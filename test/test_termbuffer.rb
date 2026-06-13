require_relative 'test_helper'
require_relative '../lib/termbuffer'

class TestTermBuffer < Minitest::Test
  def setup
    @buf = TermBuffer.new
  end

  # Helper: write a string to row y starting at column 0.
  def write_row(y, str)
    str.each_char.with_index { |ch, x| @buf.set(x, y, ch) }
  end

  # Helper: collect text from each_character_between the way the selection
  # extractor (get_selection) does.
  def text_between(sx, sy, ex, ey)
    str = ""
    ypos = nil
    @buf.each_character_between(sx..sy, ex..ey) do |x, y, cell|
      str += "\n" if ypos && y != ypos
      ypos = y
      str << (cell[0].chr(Encoding::UTF_8) rescue "")
    end
    str
  end

  def test_each_character_between_reads_live_rows
    write_row(0, "AB")
    write_row(1, "CD")
    assert_equal "AB", text_between(0, 0, 1, 0)
    assert_equal "AB\nCD", text_between(0, 0, 1, 1)
  end

  def test_each_character_between_reads_scrollback_for_negative_rows
    # Put "OLD" on row 0, scroll it off into scrollback, then write "NEW"
    # on the (now live) row 0. Selecting the scrolled-off row (buffer row
    # -1) must yield the scrollback content, not the live row.
    write_row(0, "OLD")
    @buf.scroll_up
    write_row(0, "NEW")

    assert_equal "NEW", text_between(0, 0, 2, 0), "live row 0"
    assert_equal "OLD", text_between(0, -1, 2, -1), "scrolled-off row -1"
  end

  def test_selection_spanning_scrollback_into_live_buffer
    write_row(0, "TOP")
    @buf.scroll_up
    write_row(0, "BOT")

    # Row -1 is scrollback ("TOP"), row 0 is live ("BOT").
    assert_equal "TOP\nBOT", text_between(0, -1, 2, 0)
  end

  def test_line_at_does_not_autovivify
    # line_at must be non-mutating: reading a non-existent row must not
    # grow the buffer (unlike #[], which auto-vivifies).
    scrbuf = @buf.instance_variable_get(:@scrbuf)
    before = scrbuf.scrollback_buffer.size
    assert_nil scrbuf.line_at(-5)
    assert_equal before, scrbuf.scrollback_buffer.size
  end
end
