require 'tmpdir'
require 'shellwords'

# Semantic oracle: replays a byte stream through tmux's terminal state
# machine (a widely deployed reference implementation) and captures the
# resulting screen text and cursor position as a partial state dump in
# the harness schema. Diffing our dump against this catches
# parser/state-machine bugs without any pixel comparison.
#
# Currently text + cursor only; attribute capture (-e) is a future
# extension (needs an SGR parser mapping tmux's output onto palette
# values).
module Harness
  class OracleTmux
    class Unavailable < StandardError; end

    def self.available? = system("tmux", "-V", out: File::NULL, err: File::NULL)

    def self.run(bytes, cols:, rows:, timeout: 10)
      new(cols: cols, rows: rows, timeout: timeout).run(bytes)
    end

    def initialize(cols:, rows:, timeout: 10)
      @cols, @rows, @timeout = cols, rows, timeout
      @sock = "rterm-harness-#{Process.pid}-#{self.class.next_id}"
    end

    @id = 0
    def self.next_id = (@id += 1)

    def run(bytes)
      raise Unavailable, "tmux not found" if !self.class.available?
      Dir.mktmpdir("rterm-oracle") do |dir|
        casef = File.join(dir, "case.bin")
        flag = File.join(dir, "done")
        File.binwrite(casef, bytes)

        # `cat` interprets nothing; the pane's terminal (tmux's state
        # machine) does. `stty -echo` stops tmux's replies to queries
        # in the stream (DSR etc.) from being echoed into the pane
        # content. The flag file signals that all bytes have been
        # written to the pty; we then poll for the pane content to
        # stabilize since tmux consumes the pty asynchronously.
        shellcmd = "stty -echo; cat #{casef.shellescape}; touch #{flag.shellescape}; sleep 600"
        ok = tmux("new-session", "-d", "-x", @cols.to_s, "-y", @rows.to_s, shellcmd)
        raise Unavailable, "failed to start tmux session" if !ok

        begin
          deadline = Time.now + @timeout
          sleep 0.02 until File.exist?(flag) || Time.now > deadline
          raise Unavailable, "tmux oracle timed out" if !File.exist?(flag)

          prev = nil
          cap = nil
          loop do
            cap = capture
            break if cap == prev || Time.now > deadline
            prev = cap
            sleep 0.05
          end

          text, cursor = cap
          to_dump(text, cursor)
        ensure
          tmux("kill-server")
        end
      end
    end

    private

    def tmux(*args)
      system("tmux", "-L", @sock, "-f", "/dev/null", *args,
             out: File::NULL, err: File::NULL)
    end

    def tmux_out(*args)
      IO.popen(["tmux", "-L", @sock, "-f", "/dev/null", *args], &:read)
    end

    def capture
      text = tmux_out("capture-pane", "-p", "-t", "0")
      cursor = tmux_out("display-message", "-p", "-t", "0",
                        '#{cursor_x} #{cursor_y}')
      [text, cursor]
    end

    def to_dump(text, cursor)
      lines = text.split("\n", -1)
      lines.pop if lines.last == "" # trailing newline from capture-pane
      cx, cy = cursor.split.map(&:to_i)
      cells = (0...@rows).map do |y|
        line = lines[y] || ""
        (0...@cols).map do |x|
          ch = line[x]
          ch.nil? || ch == " " ? nil : { "ch" => ch }
        end
      end
      {
        "cols" => @cols, "rows" => @rows,
        "cursor" => { "row" => cy, "col" => cx },
        "cells" => cells,
        "oracle" => "tmux",
      }
    end
  end
end
