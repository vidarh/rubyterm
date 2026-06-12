require 'socket'
require 'json'
require 'base64'

# Control channel for the *live* terminal (see harness/live.rb, which
# injects this; the production code knows nothing about it). Speaks
# newline-delimited JSON over a Unix socket:
#
#   {"cmd":"dump_state"}                  -> full state dump (docs/state-schema.md)
#   {"cmd":"render_barrier"}              -> flush pending damage + paint
#   {"cmd":"feed","bytes_b64":...}        -> inject bytes as if from the pty
#   {"cmd":"tokenize","bytes_b64":...}    -> chunk bytes with the real parser
#
# Commands that read or mutate terminal state run *on the input
# processing thread* (a Proc pushed through the input queue), so a
# dump can never observe a half-processed chunk. That is a stronger
# barrier than the DA round-trip trick external drivers need.
module Harness
  class DebugServer
    def initialize(path, rterm)
      @rterm = rterm
      File.unlink(path) rescue nil
      @server = UNIXServer.new(path)
      Thread.new do
        loop do
          conn = @server.accept
          Thread.new { serve(conn) }
        end
      end
    end

    private

    # Run blk serialized with input processing; returns its value.
    def sync(&blk)
      q = Queue.new
      @rterm.write(proc { q << blk.call })
      q.pop
    end

    def term   = @rterm.instance_variable_get(:@term)
    def buffer = @rterm.instance_variable_get(:@buffer)
    def window = @rterm.instance_variable_get(:@window)

    def serve(conn)
      while line = conn.gets
        resp =
          begin
            handle(JSON.parse(line))
          rescue StandardError => e
            { "error" => "#{e.class}: #{e.message}" }
          end
        conn.puts(JSON.generate(resp))
      end
    rescue Errno::EPIPE, IOError
    ensure
      conn.close rescue nil
    end

    def handle(req)
      case req["cmd"]
      when "dump_state"
        sync { StateDump.dump(term, buffer) }
      when "render_barrier"
        sync do
          buffer.draw_flush
          window.dirty!
          window.flush
          { "ok" => true }
        end
      when "feed"
        @rterm.write(Base64.decode64(req["bytes_b64"].to_s))
        { "ok" => true }
      when "tokenize"
        tokens = Tokenizer.tokenize(Base64.decode64(req["bytes_b64"].to_s))
        { "tokens_b64" => tokens.map { |t| Base64.strict_encode64(t) } }
      else
        { "error" => "unknown cmd #{req["cmd"].inspect}" }
      end
    end
  end
end
