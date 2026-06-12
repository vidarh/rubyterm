require_relative 'test_helper'
require_relative '../harness/lib/harness'

class TestTokenizer < Minitest::Test
  CASES = [
    "plain text only",
    "\e[1;2Hcursor\e[0m",
    "mixed\r\ntext\twith\econtrols\e[31m",
    "\e]0;title\x07after osc",
    "unterminated\e[1;2",
    "\e",
    "utf8 \xc3\xa6\xc3\xb8\xc3\xa5 bytes".b,
    "osc aborted by control\e]0;tit\nrest",
  ].freeze

  def test_roundtrip
    CASES.each do |input|
      tokens = Harness::Tokenizer.tokenize(input)
      assert_equal input.b, tokens.join, "roundtrip failed for #{input.inspect}"
    end
  end

  def test_escape_sequences_are_single_tokens
    tokens = Harness::Tokenizer.tokenize("ab\e[10;20Hcd")
    assert_includes tokens, "\e[10;20H".b
  end

  def test_controls_are_single_tokens
    tokens = Harness::Tokenizer.tokenize("a\r\nb")
    assert_equal ["a", "\r", "\n", "b"], tokens
  end
end

class TestDDMin < Minitest::Test
  def test_minimizes_to_relevant_subset
    items = (1..20).to_a
    # "Fails" iff both 3 and 17 are present.
    result = Harness::DDMin.minimize(items) { |s| s.include?(3) && s.include?(17) }
    assert_equal [3, 17], result.sort
  end

  def test_single_item
    result = Harness::DDMin.minimize((1..8).to_a) { |s| s.include?(5) }
    assert_equal [5], result
  end

  def test_returns_input_when_nothing_smaller_fails
    items = [1, 2]
    result = Harness::DDMin.minimize(items) { |s| s == items }
    assert_equal items, result
  end
end

class TestVirtualWindow < Minitest::Test
  def vw = Harness::VirtualWindow.new(80, 32, char_w: 8, char_h: 16)

  def test_draw_and_compare
    a, b = vw, vw
    a.draw(0, 0, "AB", 0xffffff, 0, 0)
    b.draw(0, 0, "AB", 0xffffff, 0, 0)
    cells, = Harness::VirtualWindow.compare(a.framebuffer, b.framebuffer, 8, 16)
    assert_empty cells

    b.draw(8, 0, "X", 0xffffff, 0, 0)
    cells, bbox = Harness::VirtualWindow.compare(a.framebuffer, b.framebuffer, 8, 16)
    assert_equal [[1, 0]], cells
    refute_nil bbox
  end

  def test_space_draws_background_only
    a, b = vw, vw
    a.draw(0, 0, " ", 0xffffff, 0x123456, 0)
    b.fillrect(0, 0, 8, 16, 0x123456)
    cells, = Harness::VirtualWindow.compare(a.framebuffer, b.framebuffer, 8, 16)
    assert_empty cells
  end

  def test_scroll_up_moves_content
    a = vw
    a.draw(0, 16, "Z", 0xffffff, 0, 0) # row 1
    a.scroll_up(16, 80, 16, 16)        # move row 1 to row 0
    b = vw
    b.draw(0, 0, "Z", 0xffffff, 0, 0)
    cells, = Harness::VirtualWindow.compare(a.framebuffer, b.framebuffer, 8, 16)
    assert_empty cells
  end

  def test_clear_equals_default_background
    a, b = vw, vw
    a.fillrect(0, 0, 16, 16, 0x000000)
    b.clear(0, 0, 16, 16)
    cells, = Harness::VirtualWindow.compare(a.framebuffer, b.framebuffer, 8, 16)
    assert_empty cells
  end
end

class TestSession < Minitest::Test
  def test_basic_text_and_cursor
    s = Harness::Session.new(cols: 20, rows: 5)
    s.feed("Hi\r\nthere")
    d = s.state_dump
    assert_equal ["Hi", "there", "", "", ""], Harness::StateDump.text(d)
    assert_equal 1, d["cursor"]["row"]
    assert_equal 5, d["cursor"]["col"]
  end

  def test_responses_captured
    s = Harness::Session.new(cols: 20, rows: 5)
    s.feed("\e[6n")
    assert_equal "\e[1;1R", s.responses
  end

  def test_redraw_invariant_holds_for_plain_text
    s = Harness::Session.new(cols: 20, rows: 5)
    s.feed("hello\r\nworld")
    check = Harness::Checks.redraw_check(s)
    assert check["pass"], "redraw mismatch: #{check.inspect}"
  end

  def test_gen_tracking_survives_identical_rewrite
    s = Harness::Session.new(cols: 20, rows: 5)
    s.feed("A")
    gen1 = s.termbuffer.harness_gen_for(0, 0)
    s.feed("\e[1;1HA")
    assert_equal gen1, s.termbuffer.harness_gen_for(0, 0)
    s.feed("\e[1;1HB")
    refute_equal gen1, s.termbuffer.harness_gen_for(0, 0)
  end

  def test_marker_check_passes_for_plain_text
    s = Harness::Session.new(cols: 20, rows: 5, render_mode: :markers)
    s.feed("hello\r\nworld")
    check = Harness::Checks.marker_check(s)
    assert check["pass"], "marker mismatch: #{check.inspect}"
  end
end

class TestDiffer < Minitest::Test
  def dump_for(text_rows, cursor_row: 0, cursor_col: 0, cols: 10)
    {
      "cols" => cols, "rows" => text_rows.length,
      "cursor" => { "row" => cursor_row, "col" => cursor_col },
      "cells" => text_rows.map { |r|
        (0...cols).map { |x| r[x] && r[x] != " " ? { "ch" => r[x] } : nil }
      },
    }
  end

  def test_equal_dumps_diff_empty
    a = dump_for(["abc", "def"])
    assert_empty Harness::Differ.diff(a, a)
  end

  def test_cell_difference_reported
    a = dump_for(["abc"])
    b = dump_for(["aXc"])
    diff = Harness::Differ.diff(a, b)
    assert_equal 1, diff.length
    assert_equal({ "type" => "cell", "row" => 0, "col" => 1,
                   "expected" => "b", "got" => "X" }, diff[0])
  end

  def test_pending_wrap_normalized
    a = dump_for(["x"], cursor_col: 10) # oracle reports col == cols
    b = dump_for(["x"], cursor_col: 9)
    assert_empty Harness::Differ.diff(a, b)
  end
end
