# A complete headless terminal: TermBuffer + TrackChanges +
# WindowAdapter + Term, rendering into a VirtualWindow instead of X11.
# Feeding bytes is synchronous and single-threaded, so unlike the live
# terminal no sync barriers (DA round-trips etc.) are ever needed:
# when #feed returns, everything has been interpreted and rendered.
#
# The session plays the roles RubyTerm plays in the live terminal:
# it is the WindowAdapter's "term" (blink state, dimensions) and the
# Term's responder, capturing the query replies (DSR/DA/...) the live
# terminal would write back to the pty into #responses.
#
# Those replies are not rendered here (in the live terminal they go to
# the host/application, not the screen), but capturing them is what lets
# the `responses` check feed them to the tmux oracle as host input and
# see whether the host consumes them or leaks them to the pane as
# visible garbage ("escape sequences on screen") - a host-side property
# a grid-only oracle cannot see. The reply bytes MUST stay byte-identical
# to Controller's (lib/controller.rb) or the check is testing a fiction.
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
      @buffer.defer = true # damage-driven rendering (mirrors the live terminal)
      @term = Term.new(@buffer, @adapter)
      @term.resize(cols, rows)
      @buffer.on_resize(cols, rows)
      @term.responder = self
      @responses = +"".b
    end

    # # WindowAdapter's "term" interface
    def blink_state  = false
    def rblink_state = false
    def term_width   = @term.width
    def term_height  = @term.height

    # # Term's responder interface. These mirror Controller's replies
    # # (lib/controller.rb): the live terminal writes them to the pty;
    # # here we capture them so the `responses` check can interpret them
    # # the way an echoing application would.
    def report_position(x, y) = @responses << "\e[#{y + 1};#{x + 1}R"
    def device_attr_primary   = @responses << "\e[?1;2c"
    def device_attr_secondary = @responses << "\e[>0;10;1c"
    def device_attr_tertiary  = @responses << "\x1bP!|00000000\x1b\\"

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
        @buffer.draw_flush  # draw the chunk's damaged content...
        @term.draw_cursor
        @buffer.draw_flush  # ...then the cursor overlay on top
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
