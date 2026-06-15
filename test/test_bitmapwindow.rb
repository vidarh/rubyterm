require_relative 'test_helper'
require 'stringio'

BG = "0" unless defined?(BG)
FG = "7" unless defined?(FG)

require_relative '../lib/termbuffer'
require_relative '../lib/term'
require_relative '../lib/trackchanges'
require_relative '../lib/windowadapter'

# Skrift may not be available in every environment; skip cleanly if not.
HAVE_SKRIFT =
  begin
    require_relative '../lib/bitmapwindow'
    File.exist?(BitmapWindow::DEFAULT_FONT)
  rescue LoadError
    false
  end

# BitmapWindow is the third implementation of the Window drawing interface
# (after X11 Window and the harness VirtualWindow). Wrapped by
# WindowAdapter it is a full bitmap backend. These tests confirm the same
# Term core renders real glyphs into the pixel buffer at the right cells
# and colours - i.e. the backend seam is genuinely backend-agnostic.
class TestBitmapWindow < Minitest::Test
  COLS = 20
  ROWS = 6

  class Host
    attr_accessor :term_width
    def initialize(c) = (@term_width = c)
    def blink_state  = false
    def rblink_state = false
    def set_columns(_) = nil
  end

  def setup
    skip "skrift / default font not available" unless HAVE_SKRIFT
    @win = BitmapWindow.new(COLS, ROWS)
    adapter = WindowAdapter.new(@win, Host.new(COLS))
    buffer = TermBuffer.new
    @tc = TrackChanges.new(buffer, adapter)
    @tc.defer = true
    @term = Term.new(@tc)
    @term.resize(COLS, ROWS)
    @tc.on_resize(COLS, ROWS)
  end

  # Feed with the cursor cycle, suppressing skrift's compound-glyph debug
  # output ([flags, glyph] from font.rb) so the test stays quiet.
  def feed(s)
    old = $stdout
    $stdout = StringIO.new
    @term.clear_cursor
    @term.feed(s.b)
    @tc.draw_flush
    @term.draw_cursor
    @tc.draw_flush
  ensure
    $stdout = old
  end

  # Pixels of cell (col,row), excluding the cursor cell (its background is
  # the CURSOR colour, not content).
  def cell_pixels(col, row)
    cw = @win.char_w
    ch = @win.char_h
    px = @win.pixels
    out = []
    (row * ch...(row + 1) * ch).each do |y|
      (col * cw...(col + 1) * cw).each { |x| out << px[y * @win.width + x] }
    end
    out
  end

  def ink?(col, row)
    cell_pixels(col, row).any? { |p| p != 0x000000 }
  end

  def test_renders_glyphs_in_the_right_cells
    feed("\e[2J\e[HHi")
    assert ink?(0, 0), "cell (0,0) 'H' should have ink"
    assert ink?(1, 0), "cell (1,0) 'i' should have ink"
    refute ink?(5, 0), "an unwritten cell should be blank"
    refute ink?(0, 2), "an unwritten row should be blank"
  end

  def test_foreground_colour
    feed("\e[2J\e[H\e[31mR")            # red R
    reddest = cell_pixels(0, 0).max_by { |p| (p >> 16) & 0xff }
    r = (reddest >> 16) & 0xff
    g = (reddest >> 8) & 0xff
    b = reddest & 0xff
    assert r > 100, "expected a red glyph pixel, got ##{format('%06x', reddest)}"
    assert r > g && r > b, "red should dominate, got ##{format('%06x', reddest)}"
  end

  def test_clear_screen_blanks_everything
    feed("\e[2J\e[Hsome text here")
    assert ink?(0, 0), "precondition: text drawn"
    feed("\e[2J\e[H")  # clear + home, so the cursor sits on (0,0)
    (0...ROWS).each do |row|
      (0...COLS).each do |col|
        next if col.zero? && row.zero? # the cursor cell
        refute ink?(col, row), "cell (#{col},#{row}) should be blank after clear"
      end
    end
  end

  def test_scrolling_moves_content_up
    feed("\e[2J\e[Hrow0\r\nrow1")
    before = cell_pixels(0, 1).dup   # 'r' of row1 at row 1
    feed("\r\n")                      # cursor at row 2; no scroll yet
    feed("\e[6;1Hbottom\r\n")         # force a scroll from the last row
    # The scroll blit moved row 1's pixels up into row 0.
    assert_equal before, cell_pixels(0, 0),
                 "row 1's content should have scrolled up into row 0"
  end
end
