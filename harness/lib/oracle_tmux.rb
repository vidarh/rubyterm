require 'tmpdir'
require 'shellwords'
require 'pty'
require 'io/console'

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

    # Host-side faithfulness for query replies. Feeds `replies` to a tmux
    # pane *as keyboard input* (a master write is what the host treats a
    # terminal's reply as) while a cooked-mode reader (`cat`) is
    # foreground, then returns the visible text tmux leaked into the
    # pane. A reply tmux recognises as the answer to a query it sent is
    # consumed (no leak); a malformed or wrong-type reply - e.g. a DA3
    # DCS sent in answer to DA1/DA2 - is forwarded to the pane and echoed
    # as visible caret-notation garbage. This is exactly the path that
    # put `^[P!|00000000^[\` on screen, and it cannot be modelled by
    # re-interpreting the reply in our own terminal (which simply
    # consumes the DCS).
    def self.leaked(replies, cols:, rows:, timeout: 6)
      new(cols: cols, rows: rows, timeout: timeout).leaked(replies)
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

    # See the class-method doc above. Drives a real pty so the reply
    # travels the genuine terminal->host input path (a master write is
    # how the host sees a terminal's reply), exercising tmux's
    # query-reply recognition - which `send-keys` would bypass, making
    # every reply look leaked.
    def leaked(replies)
      raise Unavailable, "tmux not found" if !self.class.available?
      replies = (replies || "").b
      return [] if replies.empty?
      visible = []
      PTY.spawn("tmux", "-L", @sock, "-f", "/dev/null", "new-session",
                "-x", @cols.to_s, "-y", @rows.to_s, "cat") do |r, w, pid|
        w.winsize = [@rows, @cols] rescue nil
        deadline = Time.now + @timeout
        sent = false
        quiet_since = nil # last time we saw fresh tmux output
        loop do
          break if Time.now > deadline
          rs, = IO.select([r], nil, nil, 0.1)
          if rs
            begin
              r.read_nonblock(4096)
              quiet_since = Time.now
            rescue IO::WaitReadable
            rescue EOFError, Errno::EIO
              break
            end
          elsif quiet_since
            idle = Time.now - quiet_since
            if !sent && idle > 0.2
              # tmux has emitted its startup queries (incl. DA) and gone
              # quiet: it is now in the window where it awaits a reply.
              w.write(replies)
              sent = true
              quiet_since = Time.now
            elsif sent && idle > 0.3
              break # reply consumed/forwarded and pane settled
            end
          end
        end
        visible = leaked_lines
        Process.kill("KILL", pid) rescue nil
      end
      visible
    ensure
      tmux("kill-server")
    end

    private

    # Visible pane text minus tmux's own status line and blank rows: any
    # remaining content is a reply tmux failed to consume and echoed.
    def leaked_lines
      text = tmux_out("capture-pane", "-p", "-t", "0").to_s
      text.lines.map(&:chomp).reject do |l|
        l.strip.empty? || l =~ /\A\[\d+\]\s+\d+:(cat|bash)/
      end
    end

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
