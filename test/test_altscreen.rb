require_relative 'test_helper'

require_relative '../lib/termbuffer'
require_relative '../lib/term'
require_relative '../lib/trackchanges'

# DEC private mode 1049 (and 1048) must save the cursor on entry (h) and
# restore it on leave (l), like ESC 7 / ESC 8. Without this, the cursor
# left wherever an intervening move put it instead of being restored.
class TestAltScreen < Minitest::Test
  COLS = 100
  ROWS = 33

  class NullSink
    def char_w = 1
    def char_h = 1
    def scrollback_mode = false
    def scrollback_anchor; end
    def clear; end
    def clear_line(*) = nil
    def draw(*) = nil
    def scroll_up(*) = nil
    def insert_lines(*) = nil
    def delete_lines(*) = nil
    def set_columns(*) = nil
  end

  def build
    buffer = TermBuffer.new
    tc = TrackChanges.new(buffer, NullSink.new)
    term = Term.new(tc)
    term.resize(COLS, ROWS)
    tc.on_resize(COLS, ROWS)
    term
  end

  def test_1049_restores_cursor_on_leave
    term = build
    # Enter alt screen (saves cursor at home), move, leave (restores).
    term.feed("\e[?1049h".b)
    term.feed("\e[31;3H".b)
    term.feed("\e[?1049l".b)
    assert_equal 0, term.x
    assert_equal 0, term.y
  end

  def test_1049_saves_nondefault_cursor
    term = build
    term.feed("\e[5;7H".b)        # move to row 5, col 7 (0-based 4,6)
    term.feed("\e[?1049h".b)      # save cursor
    term.feed("\e[20;20H".b)      # move away
    term.feed("\e[?1049l".b)      # restore
    assert_equal 6, term.x
    assert_equal 4, term.y
  end

  def test_1048_save_restore_cursor
    term = build
    term.feed("\e[10;15H".b)      # 0-based 9,14
    term.feed("\e[?1048h".b)      # save
    term.feed("\e[2;2H".b)        # move away
    term.feed("\e[?1048l".b)      # restore
    assert_equal 14, term.x
    assert_equal 9, term.y
  end
end
