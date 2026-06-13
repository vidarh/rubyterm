require_relative 'test_helper'

# FG/BG are defined in termtest.rb (the X11 entrypoint we don't load here).
BG = "0" unless defined?(BG)
FG = "7" unless defined?(FG)

require_relative '../lib/palette'
require_relative '../lib/termbuffer'
require_relative '../lib/trackchanges'

# Minimal adapter that records the screen-write calls TrackChanges makes,
# with a togglable scrollback_mode.
class FakeAdapter
  attr_reader :draws, :cleared_lines, :clears, :deleted, :inserted, :anchors
  attr_accessor :scrollback_mode

  def initialize
    @draws = []; @cleared_lines = []; @clears = 0
    @deleted = []; @inserted = []; @anchors = 0
    @scrollback_mode = false
  end

  def scrollback_anchor;            @anchors += 1; end
  def draw(x,y,c,fg,bg,fl,la);      @draws << [x,y,c]; end
  def clear;                        @clears += 1; end
  def clear_line(*a);               @cleared_lines << a; end
  def delete_lines(*a);             @deleted << a; end
  def insert_lines(*a);             @inserted << a; end
end

class TestTrackChanges < Minitest::Test
  def setup
    @adapter = FakeAdapter.new
    @tc = TrackChanges.new(TermBuffer.new, @adapter)
    @adapter.draws.clear
  end

  def test_set_draws_and_updates_buffer_when_live
    @adapter.scrollback_mode = false
    @tc.set(0, 0, "A", 7, 0, 0)
    @tc.draw_flush
    refute_empty @adapter.draws, "screen should be drawn when live"
    assert_equal "A".ord, @tc.get(0, 0)[0]
  end

  def test_set_updates_buffer_but_not_screen_when_scrolled_back
    @adapter.scrollback_mode = true
    @tc.set(0, 0, "B", 7, 0, 0)
    @tc.draw_flush
    assert_empty @adapter.draws, "screen must not be painted while scrolled back"
    assert_equal "B".ord, @tc.get(0, 0)[0], "buffer must still update"
  end

  def test_clear_line_skips_screen_when_scrolled_back
    @adapter.scrollback_mode = true
    @tc.clear_line(0)
    assert_empty @adapter.cleared_lines
  end

  def test_line_ops_skip_screen_when_scrolled_back
    @adapter.scrollback_mode = true
    @tc.delete_lines(0, 1, 23)
    @tc.insert_lines(0, 1, 23)
    assert_empty @adapter.deleted
    assert_empty @adapter.inserted
  end

  def test_redraw_blink_is_suppressed_when_scrolled_back
    # A blinking cell exists, but blink repaint must be a no-op in scrollback.
    @tc.set(0, 0, "X", 7, 0, BLINK)
    @adapter.draws.clear
    @adapter.scrollback_mode = true
    @tc.redraw_blink
    assert_empty @adapter.draws
  end
end
