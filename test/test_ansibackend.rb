require_relative 'test_helper'

BG = "0" unless defined?(BG)
FG = "7" unless defined?(FG)

require_relative '../lib/termbuffer'
require_relative '../lib/term'
require_relative '../lib/trackchanges'
require_relative '../lib/ansibackend'

# Round-trip / metamorphic test for AnsiBackend: feeding bytes through
# Term -> AnsiBackend produces escape sequences that, replayed through a
# fresh grid terminal, must reproduce the same screen. This validates the
# backend with no external oracle - it is the "Screen -> AnsiBackend ->
# Term' -> same Screen" invariant.
class TestAnsiBackend < Minitest::Test
  COLS = 40
  ROWS = 12

  # A no-op render sink, so a grid terminal populates its buffer without
  # any actual rendering.
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

  def build(adapter)
    buffer = TermBuffer.new
    tc = TrackChanges.new(buffer, adapter)
    term = Term.new(tc, adapter)
    term.resize(COLS, ROWS)
    tc.on_resize(COLS, ROWS)
    [term, tc, buffer]
  end

  def feed(term, tc, bytes, chunk: 128)
    off = 0
    while off < bytes.bytesize
      term.feed(bytes.byteslice(off, chunk))
      off += chunk
      tc.draw_flush
    end
  end

  # A space on the default background with no flags renders identically to
  # an unset cell (both are blank). Normalise so the round-trip compares
  # what's *visible*, not internal representation - e.g. clear_cursor over
  # an unset cell draws a space, invisible on the real terminal.
  def normalize(cell)
    return nil if cell.nil?
    ch, _fg, bg, flags = cell
    return nil if ch == 32 && bg == 0 && (flags.nil? || flags.zero?)
    cell
  end

  # Visible grid of a terminal fed +bytes+, as a comparable nested array.
  def grid_cells(bytes)
    term, tc, buffer = build(NullSink.new)
    feed(term, tc, bytes)
    (0...ROWS).map { |y| (0...COLS).map { |x| normalize(buffer.get(x, y)) } }
  end

  def ansi_escapes(bytes)
    term, tc, = build(backend = AnsiBackend.new(COLS, ROWS))
    feed(term, tc, bytes)
    term.draw_cursor
    tc.draw_flush
    backend.output
  end

  def assert_roundtrip(bytes, msg = nil)
    bytes = bytes.b
    ref = grid_cells(bytes)
    replay = grid_cells(ansi_escapes(bytes))
    assert_equal ref, replay, msg || "round-trip mismatch"
  end

  def test_plain_text
    assert_roundtrip "Hello, world!\r\nSecond line here."
  end

  def test_sgr_colours_and_attributes
    assert_roundtrip "\e[31mred\e[0m \e[32mgreen\e[0m \e[1mbold\e[0m " \
                     "\e[4munderline\e[0m \e[7minverse\e[0m \e[33;44myel/blu\e[0m"
  end

  def test_cursor_addressing
    assert_roundtrip "\e[2J\e[5;10HX\e[1;1HA\e[12;40HZ\e[3;3Hmid"
  end

  def test_erase_in_line
    assert_roundtrip "\e[2J\e[1;1HABCDEFGH\e[1;4H\e[0K" \
                     "\e[2;1HIJKLMNOP\e[2;5H\e[1K"
  end

  def test_scrolling_lines
    body = (1..30).map { |i| "line #{i}" }.join("\r\n")
    assert_roundtrip "\e[2J\e[H" + body
  end

  def test_scroll_region
    assert_roundtrip "\e[2J\e[3;8r\e[3;1H" + (1..20).map { |i| "row#{i}\r\n" }.join
  end

  def test_unicode
    assert_roundtrip "\e[2J\e[H em-dash: \xE2\x80\x94  box: \xE2\x94\x8C\xE2\x94\x80\xE2\x94\x90"
  end

  def test_overwrite_same_cells
    assert_roundtrip "\e[2J\e[1;1HAAAAA\e[1;1HBB\e[1;4HCC"
  end

  # Render across MULTIPLE frames (take per chunk, with the live cursor
  # cycle), accumulating output - the path the terminal-in-terminal demo
  # uses. Catches cross-frame state bugs (a stale tracked cursor after the
  # trailing cursor-reposition, or a wrong cursor after the startup clear)
  # that a single-frame round-trip cannot.
  def ansi_escapes_framed(chunks)
    term, tc, = build(backend = AnsiBackend.new(COLS, ROWS))
    out = +"".b
    chunks.each do |chunk|
      term.clear_cursor
      term.feed(chunk.b)
      term.draw_cursor
      tc.draw_flush
      out << backend.take
    end
    out
  end

  def test_multi_frame_rendering
    chunks = ["\e[2J\e[Hframe one\r\n", "\e[31mframe two\e[0m\r\n",
              "\e[5;1Hjump here\r\nand more text"]
    ref = grid_cells(chunks.join.b)
    replay = grid_cells(ansi_escapes_framed(chunks))
    assert_equal ref, replay, "multi-frame (per-take) round-trip"
  end
end
