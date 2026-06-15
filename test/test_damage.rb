require_relative 'test_helper'

BG = "0" unless defined?(BG)
FG = "7" unless defined?(FG)

require_relative '../lib/termbuffer'
require_relative '../lib/term'
require_relative '../lib/trackchanges'
require_relative '../lib/ansibackend'

# Validates the damage-driven (defer) render path against the proven eager
# path, WITHOUT changing the live default. Feeding the same bytes through a
# deferred TrackChanges - where #set only mutates and #draw_flush walks the
# buffer's damage (generation) - must produce the same on-screen result as
# the eager path, compared via the AnsiBackend round-trip. This is the
# safety gate for eventually flipping #set from eager-draw to
# flush-walks-damage.
class TestDamage < Minitest::Test
  COLS = 40
  ROWS = 12

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

  def build(adapter, defer: false)
    buffer = TermBuffer.new
    tc = TrackChanges.new(buffer, adapter)
    tc.defer = defer
    term = Term.new(tc, adapter)
    term.resize(COLS, ROWS)
    tc.on_resize(COLS, ROWS)
    [term, tc, buffer]
  end

  def normalize(cell)
    return nil if cell.nil?
    ch, _fg, bg, flags = cell
    return nil if ch == 32 && bg == 0 && (flags.nil? || flags.zero?)
    cell
  end

  def snapshot(buffer)
    (0...ROWS).map { |y| (0...COLS).map { |x| normalize(buffer.get(x, y)) } }
  end

  # Eager cycle: set draws as it goes; flush emits the batch.
  def feed_eager(term, tc, bytes, chunk: 128)
    off = 0
    while off < bytes.bytesize
      term.clear_cursor
      term.feed(bytes.byteslice(off, chunk))
      off += chunk
      term.draw_cursor
      tc.draw_flush
    end
  end

  # Deferred cycle: set only mutates; draw_flush walks the damage. The
  # content flush must run BEFORE draw_cursor so the cursor stays on top.
  def feed_defer(term, tc, bytes, chunk: 128)
    off = 0
    while off < bytes.bytesize
      term.clear_cursor
      term.feed(bytes.byteslice(off, chunk))
      off += chunk
      tc.draw_flush       # draw the chunk's damaged content
      term.draw_cursor
      tc.draw_flush       # then the cursor overlay
    end
  end

  # Reference grid (feed straight into a buffer, no rendering).
  def grid_cells(bytes)
    term, tc, buffer = build(NullSink.new)
    feed_eager(term, tc, bytes)
    snapshot(buffer)
  end

  # The screen produced by rendering +bytes+ through AnsiBackend (eager or
  # deferred), recovered by replaying its escapes through a fresh grid.
  def ansi_screen(bytes, defer:)
    term, tc, = build(backend = AnsiBackend.new(COLS, ROWS), defer: defer)
    defer ? feed_defer(term, tc, bytes) : feed_eager(term, tc, bytes)
    grid_cells(backend.output)
  end

  def assert_damage_matches(bytes, msg = nil)
    bytes = bytes.b
    ref = grid_cells(bytes)
    assert_equal ref, ansi_screen(bytes, defer: false),
                 "eager AnsiBackend diverged from reference (#{msg})"
    assert_equal ref, ansi_screen(bytes, defer: true),
                 "DAMAGE-DRIVEN render diverged from reference (#{msg})"
  end

  def test_plain_text
    assert_damage_matches "Hello, world!\r\nSecond line here."
  end

  def test_colours_and_attrs
    assert_damage_matches "\e[31mred\e[0m \e[1;32mbold-green\e[0m \e[7minv\e[0m"
  end

  def test_cursor_addressing
    assert_damage_matches "\e[2J\e[5;10HX\e[1;1HA\e[12;40HZ\e[3;3Hmid"
  end

  def test_overwrite_cells
    assert_damage_matches "\e[2J\e[1;1HAAAAA\e[1;1HBB\e[1;4HCC"
  end

  def test_erase
    assert_damage_matches "\e[2J\e[1;1HABCDEFGH\e[1;4H\e[0K\e[2;1HIJKL\e[2;3H\e[1K"
  end

  def test_scrolling
    assert_damage_matches "\e[2J\e[H" + (1..30).map { |i| "line #{i}" }.join("\r\n")
  end

  def test_scroll_region
    assert_damage_matches "\e[2J\e[3;8r\e[3;1H" + (1..20).map { |i| "row#{i}\r\n" }.join
  end

  def test_insert_delete_line
    assert_damage_matches "\e[2J\e[1;1HONE\e[2;1HTWO\e[3;1HTHREE\e[2;1H\e[1L\e[1;1H\e[1M"
  end

  def test_unicode
    assert_damage_matches "\e[2J\e[H em-dash \xE2\x80\x94 box \xE2\x94\x8C\xE2\x94\x80\xE2\x94\x90"
  end

  def test_mixed_movement_and_scroll
    s = +"\e[2J\e[H"
    s << "top line\r\n"
    s << "\e[31msome \e[32mcolour\e[0m\r\n"
    20.times { |i| s << "scrolling row #{i}\r\n" }
    s << "\e[2;5Hpatched"
    assert_damage_matches s
  end
end
