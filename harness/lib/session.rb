# A complete headless terminal: TermBuffer + TrackChanges +
# WindowAdapter + Term, rendering into a VirtualWindow instead of X11.
# Feeding bytes is synchronous and single-threaded, so unlike the live
# terminal no sync barriers (DA round-trips etc.) are ever needed:
# when #feed returns, everything has been interpreted and rendered.
#
# The session plays the roles RubyTerm plays in the live terminal:
# it is the WindowAdapter's "term" (blink state, dimensions) and the
# Term's responder (capturing DSR/DA replies in #responses).
module Harness
  class Session
    CHAR_W = 8
    CHAR_H = 16
    # Matches Controller#read's read_nonblock(128): the live terminal
    # never feeds larger chunks, and cursor draw + render flush runs
    # between chunks, so this exercises the same incremental paths.
    DEFAULT_CHUNK = 128

    attr_reader :term, :buffer, :termbuffer, :window, :adapter,
                :responses, :cols, :rows, :render_mode

    def initialize(cols: 80, rows: 24, render_mode: :glyphs)
      @cols, @rows = cols, rows
      @render_mode = render_mode
      @window = new_window
      @adapter = WindowAdapter.new(@window, self)
      @termbuffer = TermBuffer.new
      @buffer = TrackChanges.new(@termbuffer, @adapter)
      @term = Term.new(@buffer, @adapter)
      @term.resize(cols, rows)
      @buffer.on_resize(cols, rows)
      @term.responder = self
      @responses = +""
    end

    # # WindowAdapter's "term" interface
    def blink_state  = false
    def rblink_state = false
    def term_width   = @term.width
    def term_height  = @term.height

    # # Term's responder interface (captures replies the live terminal
    # # would write to the pty)
    def report_position(x, y) = @responses << "\e[#{y + 1};#{x + 1}R"
    def device_report         = @responses << "\eP!|00000000"

    # Feed bytes through the same per-chunk cycle the live terminal's
    # process_queue uses (clear cursor, interpret, draw cursor, flush).
    def feed(bytes, chunk: DEFAULT_CHUNK)
      bytes = bytes.b
      off = 0
      while off < bytes.bytesize
        slice = bytes.byteslice(off, chunk)
        off += chunk
        @term.clear_cursor
        @term.feed(slice)
        @term.draw_cursor
        @buffer.draw_flush
      end
      self
    end

    def resize(cols, rows)
      @cols, @rows = cols, rows
      @window.resize(cols * CHAR_W, rows * CHAR_H)
      @term.resize(cols, rows)
      @buffer.on_resize(cols, rows)
      redraw
    end

    # Full redraw from buffer state, like RubyTerm#redraw.
    def redraw
      @window.clear(0, 0, @window.width, @window.height)
      @buffer.redraw_all(0)
      @buffer.draw_flush
      @term.draw_cursor
      @buffer.draw_flush
    end

    def state_dump = StateDump.dump(@term, @buffer)

    # Render the current buffer state from scratch into a fresh
    # VirtualWindow and return it. Any difference between this and the
    # live (incrementally maintained) framebuffer is an
    # incremental-update bug: the "incremental == full redraw"
    # metamorphic invariant needs no external oracle.
    def full_redraw
      fresh = new_window
      fresh_adapter = WindowAdapter.new(fresh, self)
      old_adapter = @buffer.adapter
      @buffer.adapter = fresh_adapter
      begin
        @buffer.redraw_all(0)
        @buffer.draw_flush
        @term.draw_cursor
        @buffer.draw_flush
      ensure
        @buffer.adapter = old_adapter
      end
      fresh
    end

    private

    def new_window
      w = VirtualWindow.new(@cols * CHAR_W, @rows * CHAR_H,
                            char_w: CHAR_W, char_h: CHAR_H,
                            render_mode: @render_mode)
      w.gen_source = ->(col, row) { @termbuffer.harness_gen_for(col, row) }
      w
    end
  end
end
