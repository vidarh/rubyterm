#!/usr/bin/env ruby
#
# Deterministic test harness for the terminal emulator.
# JSON on stdout, diagnostics on stderr, exit 0/1 = pass/fail.
# See docs/harness.md for the full guide.
#
#   ruby harness/cli.rb run      --case FILE [--checks state,redraw,markers,trace]
#                                [--oracle tmux|none] [--geometry 80x24]
#                                [--chunk N] [--dump]
#   ruby harness/cli.rb sweep    --cases DIR[,DIR...] [--checks ...] [--oracle ...]
#                                [--ratchet ratchet.json] [--update-ratchet]
#   ruby harness/cli.rb minimize --case FILE [--checks ...] [--oracle ...] [--out FILE]
#   ruby harness/cli.rb tokenize --case FILE
#   ruby harness/cli.rb record   --out FILE -- cmd args...
#   ruby harness/cli.rb replay   --rec FILE [--every N] [--checks redraw,markers]

require 'optparse'
require 'json'
require 'base64'

# The production code is liberal with `p` debugging output; keep stdout
# clean for the JSON contract by routing strays to stderr.
REAL_STDOUT = $stdout
$stdout = $stderr

require_relative 'lib/harness'

def emit(result, pass)
  REAL_STDOUT.puts(JSON.pretty_generate(result))
  exit(pass ? 0 : 1)
end

def parse_geometry(s)
  m = /\A(\d+)x(\d+)\z/.match(s) or abort "bad geometry #{s.inspect}"
  [m[1].to_i, m[2].to_i]
end

opts = {
  checks: %w[state redraw markers],
  oracle: "none",
  cols: 80, rows: 24,
  chunk: Harness::Session::DEFAULT_CHUNK,
  every: 65_536,
  dump: false,
  update_ratchet: false,
}

command = ARGV.shift
extra = []
parser = OptionParser.new do |o|
  o.on("--case FILE") { |v| opts[:case] = v }
  o.on("--cases DIRS") { |v| opts[:cases] = v.split(",") }
  o.on("--checks LIST") { |v| opts[:checks] = v.split(",") }
  o.on("--oracle NAME") { |v| opts[:oracle] = v }
  o.on("--geometry WxH") { |v| opts[:cols], opts[:rows] = parse_geometry(v) }
  o.on("--chunk N", Integer) { |v| opts[:chunk] = v }
  o.on("--every N", Integer) { |v| opts[:every] = v }
  o.on("--dump") { opts[:dump] = true }
  o.on("--out FILE") { |v| opts[:out] = v }
  o.on("--rec FILE") { |v| opts[:rec] = v }
  o.on("--ratchet FILE") { |v| opts[:ratchet] = v }
  o.on("--update-ratchet") { opts[:update_ratchet] = true }
end
if (i = ARGV.index("--"))
  extra = ARGV[(i + 1)..]
  parser.parse(ARGV[0...i])
else
  parser.parse!(ARGV)
end

oracle = opts[:oracle] == "none" ? nil : opts[:oracle]

case command
when "run"
  abort "run: --case required" if !opts[:case]
  bytes = File.binread(opts[:case])
  result = Harness::Checks.run_case(
    bytes, cols: opts[:cols], rows: opts[:rows], checks: opts[:checks],
    oracle: oracle, chunk: opts[:chunk], include_dump: opts[:dump])
  result["case"] = opts[:case]
  result["env"] = { "geometry" => "#{opts[:cols]}x#{opts[:rows]}",
                    "chunk" => opts[:chunk],
                    "commit" => `git rev-parse --short HEAD 2>/dev/null`.strip }
  emit(result, result["pass"])

when "sweep"
  abort "sweep: --cases required" if !opts[:cases]
  result = Harness::Sweep.run(
    opts[:cases], cols: opts[:cols], rows: opts[:rows],
    checks: opts[:checks], oracle: oracle, chunk: opts[:chunk],
    ratchet: opts[:ratchet])
  if opts[:update_ratchet]
    abort "sweep: --ratchet required with --update-ratchet" if !opts[:ratchet]
    result["ratchet_updated"] = Harness::Sweep.update_ratchet(result, opts[:ratchet])
    result["pass"] = true
  end
  emit(result, result["pass"])

when "minimize"
  abort "minimize: --case required" if !opts[:case]
  bytes = File.binread(opts[:case])
  res = Harness::Minimizer.minimize(
    bytes, cols: opts[:cols], rows: opts[:rows], checks: opts[:checks],
    oracle: oracle, chunk: opts[:chunk])
  File.binwrite(opts[:out], res.bytes) if opts[:out]
  emit({
    "case" => opts[:case],
    "original_bytes" => bytes.bytesize,
    "minimal_bytes" => res.bytes.bytesize,
    "iterations" => res.iterations,
    "minimal_b64" => Base64.strict_encode64(res.bytes),
    "minimal_inspect" => res.bytes.inspect,
    "out" => opts[:out],
    "result" => res.result,
  }, true)

when "tokenize"
  abort "tokenize: --case required" if !opts[:case]
  tokens = Harness::Tokenizer.tokenize(File.binread(opts[:case]))
  emit({
    "count" => tokens.length,
    "tokens" => tokens.map(&:inspect),
  }, true)

when "record"
  abort "record: --out required" if !opts[:out]
  abort "record: command required after --" if extra.empty?
  require_relative 'lib/recorder'
  $stdout = REAL_STDOUT # the proxied app needs the real stdout
  status = Harness::Recorder.record(opts[:out], extra)
  exit(status&.exitstatus || 0)

when "replay"
  abort "replay: --rec required" if !opts[:rec]
  result = Harness::Replay.replay(
    opts[:rec], every: opts[:every], cols: opts[:cols], rows: opts[:rows],
    checks: opts[:checks] & %w[redraw markers], chunk: opts[:chunk])
  result["rec"] = opts[:rec]
  emit(result, result["pass"])

else
  warn "usage: harness/cli.rb {run|sweep|minimize|tokenize|record|replay} [options]"
  warn "       see docs/harness.md"
  exit 2
end
