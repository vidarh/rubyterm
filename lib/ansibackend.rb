require_relative 'termbuffer' # flag constants (BOLD, UNDERLINE, ...)

# A rendering backend that emits ANSI escape sequences instead of painting
# pixels: a drop-in for WindowAdapter (it satisfies the same draw / scroll /
# clear / clear_line / insert_lines / delete_lines interface the run-batcher
# in TrackChanges drives, plus the cell-metric and scrollback hooks Term
# queries). It turns the terminal's damage stream - changed runs of cells,
# plus scroll/clear ops - into the minimal escape sequences that reproduce
# the screen on a real terminal. This is the "render economically to a
# terminal, like Emacs" backend, and the basis for letting a TUI app render
# to a terminal OR an X11 window from the same code.
#
# Colours arrive already resolved to 24-bit RGB (Term#fg/#bg), so they are
# emitted as truecolor SGR. The run-batcher only hands us cells that
# changed, so only changed runs are emitted (CUP + minimal SGR + text). The
# cursor overlay (a cell drawn with the CURSOR background) is recognised and
# turned into a real cursor position rather than a coloured cell.
class AnsiBackend
  CURSOR_BG = 0xff00ff # must match Term::CURSOR

  # flag bit -> SGR set-code
  SGR_FLAGS = {
    BOLD => 1, FAINT => 2, ITALICS => 3, UNDERLINE => 4, BLINK => 5,
    RAPID_BLINK => 6, INVERSE => 7, INVISIBLE => 8, CROSSED_OUT => 9,
    DBL_UNDERLINE => 21, OVERLINE => 53,
  }.freeze

  def initialize(cols, rows)
    @cols, @rows = cols, rows
    @out = +"".b
    reset_state
  end

  def reset_state
    @cx = @cy = nil          # tracked cursor (nil = unknown -> force CUP)
    @fg = @bg = @flags = nil # tracked SGR (nil = unknown)
    @region = nil
    @cursor_pos = nil
  end

  # # cell metrics: a text cell is one character
  def char_w = 1
  def char_h = 1
  def scrollback_mode = false
  def scrollback_anchor; end
  def set_columns(_); end

  # The escape sequence produced so far, with a trailing reposition to the
  # cursor overlay if one was seen. Non-destructive.
  def output
    @cursor_pos ? @out + cup(@cursor_pos[1], @cursor_pos[0]) : @out.dup
  end

  # Take the output and reset the buffer for the next frame.
  def take
    s = output
    @out = +"".b
    @cursor_pos = nil
    s
  end

  def draw(x, y, str, fg, bg, flags, _lineattrs = nil)
    if bg == CURSOR_BG
      @cursor_pos = [x, y] # cursor overlay - the real cursor shows position
      return
    end
    move(y, x)
    @out << sgr(fg, bg, flags)
    @out << str
    @cx = x + str.length
    @cy = y
  end

  def clear
    @out << "\e[H\e[2J"
    reset_state
    @cx = @cy = 0
  end

  def clear_line(y, from_x, to_x = nil)
    if to_x
      # Erase to start (from_x is 0 in practice): emit EL-1 rather than
      # synthesising spaces, so the replay's clear_to_start reproduces the
      # exact same cells (raw default attributes, not a resolved \e[0m).
      move(y, to_x)
      @out << "\e[1K"
    else
      move(y, from_x)
      @out << "\e[0K" # erase to end of line (buffer truncates the row)
    end
  end

  def scroll_up(scroll_start, scroll_end)
    set_region(scroll_start, scroll_end)
    @out << "\e[S" # scroll the region up one line
  end

  def insert_lines(y, num, maxy)
    set_region(@region ? @region[0] : 0, maxy)
    move(y, 0)
    @out << "\e[#{num}L"
  end

  def delete_lines(y, num, maxy)
    set_region(@region ? @region[0] : 0, maxy)
    move(y, 0)
    @out << "\e[#{num}M"
  end

  private

  def cup(row, col) = "\e[#{row + 1};#{col + 1}H"

  def move(y, x)
    return if @cx == x && @cy == y
    @out << cup(y, x)
    @cx, @cy = x, y
  end

  def set_region(top, bot)
    return if @region == [top, bot]
    @out << "\e[#{top + 1};#{bot + 1}r"
    @region = [top, bot]
    @cx = @cy = nil # DECSTBM homes the cursor
  end

  # Reset + set everything explicitly on any change. Correct and compact for
  # uniform runs (one SGR per changed run); skipped entirely when the run's
  # attributes match the current terminal state.
  def sgr(fg, bg, flags)
    return "" if fg == @fg && bg == @bg && flags == @flags
    @fg, @bg, @flags = fg, bg, flags
    codes = [0]
    SGR_FLAGS.each { |bit, code| codes << code if flags & bit != 0 }
    codes.concat([38, 2, (fg >> 16) & 0xff, (fg >> 8) & 0xff, fg & 0xff])
    codes.concat([48, 2, (bg >> 16) & 0xff, (bg >> 8) & 0xff, bg & 0xff])
    "\e[#{codes.join(';')}m"
  end
end
