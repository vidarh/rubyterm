#!/usr/bin/env ruby
#
# Debug/instrumented entrypoint for the *live* terminal: loads the
# production terminal unchanged (termtest.rb does not auto-run when
# loaded from here), injects the harness instrumentation, and serves
# the debug control channel on a Unix socket.
#
#   ruby harness/live.rb [terminal args...]
#
# Socket path: $RTERM_DEBUG_SOCKET or /tmp/rterm-debug-<pid>.sock
# (printed on startup). Protocol: see harness/lib/debugserver.rb.
#
# The production code carries no debug facilities; everything here is
# plugged in via Module#prepend from the outside.

require_relative '../lib/rubyterm'   # loads the engine + X11 front end + RubyTerm

require_relative 'lib/patches'
require_relative 'lib/statedump'
require_relative 'lib/tokenizer'
require_relative 'lib/debugserver'

# Lets the DebugServer push barrier Procs through the input queue so
# state dumps are serialized with input processing.
module Harness
  module QueueBarriers
    def process_chunk(str)
      return str.call if str.is_a?(Proc)
      super
    end
  end
end
RubyTerm.prepend(Harness::QueueBarriers)

socket_path = ENV["RTERM_DEBUG_SOCKET"].to_s.strip
socket_path = "/tmp/rterm-debug-#{Process.pid}.sock" if socket_path.empty?

rterm = RubyTerm.new(ARGV)
Harness::DebugServer.new(socket_path, rterm)
STDERR.puts "rterm debug socket: #{socket_path}"
rterm.run(ARGV)
