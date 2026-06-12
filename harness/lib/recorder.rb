require 'pty'
require 'io/console'
require 'json'
require 'base64'

# A pty proxy: sits between an application and whatever terminal you
# are running it in, forwarding bytes both ways and logging framed
# records (newline-delimited JSON):
#
#   {"type":"output","ts":...,"data_b64":...}  app -> terminal (the test case)
#   {"type":"input","ts":...,"data_b64":...}   terminal -> app
#   {"type":"resize","ts":...,"cols":...,"rows":...}
#
# Input is recorded even though replay never uses it: when a recording
# behaves oddly you want to see what query responses (DA/DSR/...) the
# app got at record time, because that is why it emitted what it
# emitted.
#
# Usage: ruby harness/cli.rb record --out session.rec -- emacs -nw
# Use the app until it glitches, exit (or Ctrl-C); the recording is the
# test case for `replay`.
module Harness
  module Recorder
    def self.record(out_path, cmd)
      File.open(out_path, "w") do |log|
        emit = lambda do |h|
          log.puts(JSON.generate(h))
          log.flush
        end

        rows, cols = (STDOUT.winsize rescue [24, 80])
        emit.call("type" => "resize", "ts" => Time.now.to_f,
                  "cols" => cols, "rows" => rows)

        master, slave_writer, pid = PTY.spawn(*cmd)
        master.winsize = [rows, cols] rescue nil

        trap("WINCH") do
          r, c = STDOUT.winsize
          master.winsize = [r, c]
          emit.call("type" => "resize", "ts" => Time.now.to_f,
                    "cols" => c, "rows" => r)
        end

        raw = STDIN.tty? ? STDIN.method(:raw) : ->(&b) { b.call }
        status = nil
        begin
          raw.call do
            loop do
              ready = IO.select([master, STDIN]).first
              if ready.include?(master)
                begin
                  data = master.read_nonblock(4096)
                  STDOUT.write(data)
                  STDOUT.flush
                  emit.call("type" => "output", "ts" => Time.now.to_f,
                            "data_b64" => Base64.strict_encode64(data))
                rescue IO::WaitReadable
                rescue EOFError, Errno::EIO
                  break
                end
              end
              if ready.include?(STDIN)
                data = STDIN.read_nonblock(4096) rescue nil
                if data
                  slave_writer.write(data)
                  emit.call("type" => "input", "ts" => Time.now.to_f,
                            "data_b64" => Base64.strict_encode64(data))
                end
              end
            end
          end
        ensure
          trap("WINCH", "DEFAULT")
          Process.kill("HUP", pid) rescue nil
          status = (Process.wait2(pid).last rescue nil)
        end
        status
      end
    end
  end
end
