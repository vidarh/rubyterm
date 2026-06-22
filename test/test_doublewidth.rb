# frozen_string_literal: true

require_relative "test_helper"
require_relative "../harness/lib/harness"

# Double-width (wide) glyph handling in the buffer: a wide glyph occupies two
# cells (the second a WIDE_SPACER) and advances the cursor by two.
class TestDoubleWidth < Minitest::Test
  GRIN = "\u{1F600}"
  SPACER = [CharWidth::WIDE_SPACER].pack("U")

  def cells(d, row) = d["cells"][row]
  def ch(d, row, col) = (c = d["cells"][row][col]) && c["ch"]

  def test_emoji_advances_cursor_by_two
    s = Harness::Session.new(cols: 20, rows: 3)
    s.feed(GRIN)
    d = s.state_dump
    assert_equal 2, d["cursor"]["col"], "wide glyph should advance two columns"
    assert_equal GRIN, ch(d, 0, 0)
    assert_equal SPACER, ch(d, 0, 1), "second cell should be the wide spacer"
  end

  def test_cjk_is_double_width
    s = Harness::Session.new(cols: 20, rows: 3)
    s.feed("中")
    d = s.state_dump
    assert_equal 2, d["cursor"]["col"]
    assert_equal "中", ch(d, 0, 0)
    assert_equal SPACER, ch(d, 0, 1)
  end

  def test_mixed_narrow_and_wide
    s = Harness::Session.new(cols: 20, rows: 3)
    s.feed("A#{GRIN}B")
    d = s.state_dump
    assert_equal 4, d["cursor"]["col"], "1 + 2 + 1 columns"
    assert_equal "A",    ch(d, 0, 0)
    assert_equal GRIN,   ch(d, 0, 1)
    assert_equal SPACER, ch(d, 0, 2)
    assert_equal "B",    ch(d, 0, 3)
  end

  def test_wide_glyph_wraps_at_right_margin
    s = Harness::Session.new(cols: 4, rows: 3)
    s.feed("AAA#{GRIN}")
    d = s.state_dump
    # Only one column was left, so the emoji wraps to the next row.
    assert_equal 1, d["cursor"]["row"]
    assert_equal 2, d["cursor"]["col"]
    assert_equal GRIN,   ch(d, 1, 0)
    assert_equal SPACER, ch(d, 1, 1)
  end
end
