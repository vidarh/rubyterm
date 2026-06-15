#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Terminal-in-a-terminal demo / live validation for AnsiBackend.
#
# Runs a command in a sub-terminal whose screen is rendered into a band of
# THIS terminal using AnsiBackend - i.e. the *same* Term core that drives
# the X11 terminal, rendered to a terminal instead of a window. It is the
# multiplexer-pane use case, and a live check that the backend's escapes
# reproduce a screen.
#
#   ruby examples/terminal_in_terminal.rb [-- command args...]
#
# Default command is your shell. The sub-terminal is full real-terminal
# width by N rows (full width so its scroll-region escapes are valid),
# placed a few lines down with a title bar. Exit by exiting the child
# (e.g. `exit`, or let a one-shot command finish). When stdin is not a TTY
# it runs non-interactively (no raw mode / no input forwarding) and quits
# when the child does - which is how the test harness drives it.

require 'pty'
require 'io/console'

here = __dir__
require_relative "#{here}/../lib/palette"
require_relative "#{here}/../lib/termbuffer"
require_relative "#{here}/../lib/charsets"
require_relative "#{here}/../lib/utf8decoder"
require_relative "#{here}/../lib/escapeparser"
require_relative "#{here}/../lib/term"
require_relative "#{here}/../lib/trackchanges"
require_relative "#{here}/../lib/ansibackend"

BG = "0" unless defined?(BG)
FG = "7" unless defined?(FG)

# --- geometry -------------------------------------------------------
real_rows, real_cols = ($stdout.winsize rescue [24, 80])
ROWS = [[real_rows - 6, 4].max, 16].min   # sub-terminal height
COLS = real_cols                          # full width (valid scroll region)
TOP  = 3                                   # real rows above the sub-terminal

# --- the sub-terminal: Term core + AnsiBackend ----------------------
buffer  = TermBuffer.new
backend = AnsiBackend.new(COLS, ROWS, origin_row: TOP, origin_col: 0)
tc      = TrackChanges.new(buffer, backend)
term    = Term.new(tc, backend)
term.resize(COLS, ROWS)
tc.on_resize(COLS, ROWS)

# --- spawn the child in a pty of the sub-terminal's size ------------
ENV["TERM"] = "rxvt-256color"
ARGV.shift if ARGV.first == "--"
cmd = ARGV.empty? ? [ENV["SHELL"] || "/bin/sh"] : ARGV
master, _wr, pid = PTY.spawn(*cmd)
master.winsize = [ROWS, COLS]

interactive = $stdin.tty?

def draw_frame(cols, top, rows, cmd)
  bar = " rterm AnsiBackend demo — #{cmd.join(' ')} — exit the child to quit "
  $stdout.print "\e[2J\e[H"
  $stdout.print "\e[1;1H\e[1;44;97m#{bar.ljust(cols)[0, cols]}\e[0m"
  rule = "─" * cols
  $stdout.print "\e[#{top};1H\e[90m#{rule}\e[0m"            # rule above
  $stdout.print "\e[#{top + rows + 1};1H\e[90m#{rule}\e[0m" # rule below
  $stdout.flush
end

draw_frame(COLS, TOP, ROWS, cmd)

mutex = Mutex.new
def render(term, tc, backend, mutex)
  mutex.synchronize do
    term.draw_cursor
    tc.draw_flush
    $stdout.write(backend.take)
    $stdout.flush
  end
end

restore = lambda do
  $stdin.cooked! if interactive && $stdin.tty?
  $stdout.print "\e[r\e[#{TOP + ROWS + 2};1H\e[0m\e[?25h\n"
  $stdout.flush
end
at_exit(&restore)

# pty -> sub-terminal -> AnsiBackend -> real screen
reader = Thread.new do
  loop do
    data = master.read_nonblock(4096)
    mutex.synchronize do
      term.clear_cursor
      term.feed(data)
    end
    render(term, tc, backend, mutex)
  rescue IO::EAGAINWaitReadable
    IO.select([master], nil, nil, 0.05)
    retry
  rescue Errno::EIO, EOFError
    break
  end
end

if interactive
  $stdin.raw!
  writer = Thread.new do
    loop do
      master.write($stdin.readpartial(4096))
    rescue IO::EAGAINWaitReadable, Errno::EIO, EOFError
      break
    end
  end
  reader.join
  writer.kill
else
  reader.join
end

restore.call
Process.wait(pid) rescue nil
