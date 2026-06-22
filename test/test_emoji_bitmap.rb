# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

HAVE_EMOJI =
  begin
    require_relative "../lib/termbuffer"
    require_relative "../lib/term"
    require_relative "../lib/trackchanges"
    require_relative "../lib/windowadapter"
    require_relative "../lib/bitmapwindow"
    File.exist?(BitmapWindow::DEFAULT_FONT) &&
      File.exist?(BitmapWindow::DEFAULT_EMOJI) &&
      defined?(Skrift::Color::Renderer)
  rescue LoadError
    false
  end

# End-to-end: a colour emoji font (CBDT) rendered through the real Term +
# BitmapWindow pipeline, exercising the 4-byte UTF-8 decode, double-width
# cells, the emoji? colour gate, and RGBA compositing.
class TestEmojiBitmap < Minitest::Test
  COLS = 12
  ROWS = 2

  class Host
    attr_accessor :term_width
    def initialize(c) = (@term_width = c)
    def blink_state = false
    def rblink_state = false
    def set_columns(_) = nil
  end

  def setup
    skip "emoji font / skrift-color not available" unless HAVE_EMOJI
    @win  = BitmapWindow.new(COLS, ROWS, size: 28)
    @tc   = TrackChanges.new(TermBuffer.new, WindowAdapter.new(@win, Host.new(COLS)))
    @term = Term.new(@tc)
    @term.resize(COLS, ROWS)
    @tc.on_resize(COLS, ROWS)
  end

  def feed(s)
    old = $stdout
    $stdout = StringIO.new
    @term.feed(s.b)
    @tc.draw_flush
  ensure
    $stdout = old
  end

  def cell_pixels(col, row)
    cw = @win.char_w; ch = @win.char_h; px = @win.pixels
    out = []
    (row * ch...(row + 1) * ch).each do |y|
      (col * cw...(col + 1) * cw).each { |x| out << px[y * @win.width + x] }
    end
    out
  end

  def ink?(col, row) = cell_pixels(col, row).any? { |p| p != 0x000000 }

  # Max channel spread in a cell: ~0 for monochrome text, large for colour.
  def max_saturation(col, row)
    cell_pixels(col, row).map { |p| ch = [p >> 16 & 0xff, p >> 8 & 0xff, p & 0xff]; ch.max - ch.min }.max
  end

  def test_emoji_renders_in_colour_across_two_cells
    feed("\e[2J\e[H\u{1F600}")            # grinning face at (0,0)
    assert ink?(0, 0), "emoji left cell has ink"
    assert ink?(1, 0), "emoji right cell has ink (double-width)"
    assert max_saturation(0, 0) > 60, "emoji should be colourful, not monochrome"
  end

  def test_digit_stays_monochrome_despite_noto_colour_keycap
    # Noto Color Emoji has a colour bitmap for '0', but it isn't emoji-
    # presentation, so the gate must keep it as plain (grey) text.
    feed("\e[2J\e[H0")
    assert ink?(0, 0), "digit has ink"
    assert_operator max_saturation(0, 0), :<, 40, "digit must stay monochrome"
  end

  def test_text_and_emoji_mix
    feed("\e[2J\e[HA\u{1F389}B")          # A, party-popper (wide), B
    assert max_saturation(1, 0) > 60, "emoji colourful"
    assert ink?(3, 0), "B sits after the two-cell emoji"
    assert_operator max_saturation(0, 0), :<, 40, "A monochrome"
    assert_operator max_saturation(3, 0), :<, 40, "B monochrome"
  end
end
