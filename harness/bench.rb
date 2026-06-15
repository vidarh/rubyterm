#!/usr/bin/env ruby
#
# Throughput / allocation benchmark for the terminal core (Phase 1 of the
# architecture refactor; see docs/architecture-review.md §8 and
# docs/seams.md). This measures AXIS (a): raw bytes -> screen.
#
#   ruby harness/bench.rb [--mb N] [--cols C --rows R] [--chunk B]
#                         [--sink null|virtual|both] [--json]
#
# It wires the PRODUCTION core - Term (interpreter) + TrackChanges
# (damage/draw-batch) + TermBuffer (the cell grid) - against one of two
# sinks, run side by side by default:
#
#  * null    - a backend whose draw/scroll/clear are no-ops. Isolates
#              exactly what Phase 2 changes (the per-cell allocation in
#              TermBuffer#set and the draw-batch string work) from any
#              rendering cost.
#  * virtual - the FULL pipeline through the production WindowAdapter into
#              a VirtualWindow (the harness's in-memory pixel sink, which
#              mirrors Window#draw/#scroll_up/#clear). Captures the
#              cell->pixel translation, run draws, scroll blits and clears.
#
# IMPORTANT on the virtual sink: it faithfully mirrors WHICH operations
# happen and what they ALLOCATE, but NOT their cost. VirtualWindow#scroll_up
# is a pure-Ruby full-framebuffer array copy, ~120x slower than the core and
# nothing like X11's server-side blit - so its MB/s is meaningless as an X11
# proxy. Use the virtual sink for its ALLOCATION metrics (alloc/KB, retained)
# through the whole pipeline, which ARE representative; ignore its MB/s. It
# therefore runs a small fixed input (--virtual-kb, default 32) so it
# finishes quickly. Real X11 timing (X server + skrift rasterisation) is a
# separate live Xvfb benchmark - deferred (see TODO.md). AXIS (b) -
# input/Ctrl-C latency under flood - needs the live pty + threads and is
# measured separately (see the note printed at the end).
#
# Metrics per workload: MB/s, allocated objects per KB of input (the
# headline number Phase 2 should cut), GC count + GC time, and live heap
# slots retained.

require 'json'

ROOT = File.expand_path('..', __dir__)
# Top-level constants the core expects (defined in termtest.rb in prod).
BG = "0"
FG = "7"
require_relative '../lib/palette'
require_relative '../lib/termbuffer'
require_relative '../lib/charsets'
require_relative '../lib/utf8decoder'
require_relative '../lib/escapeparser'
require_relative '../lib/term'
require_relative '../lib/trackchanges'
require_relative '../lib/windowadapter'
require_relative 'lib/virtualwindow'

# A backend that satisfies the (de-facto) sink protocol with no-ops, so
# the benchmark measures interpreter + buffer + draw-batching without any
# real rendering. Cell metrics are fixed; nothing is painted.
class NullSink
  def char_w = 8
  def char_h = 16
  def scrollback_mode  = false
  def scrollback_anchor; end
  def clear; end
  def clear_area(*)  = nil
  def clear_cells(*) = nil
  def clear_line(*)  = nil
  def draw(*)        = nil
  def draw_flag_lines(*) = nil
  def scroll_up(*)   = nil
  def insert_lines(*) = nil
  def delete_lines(*) = nil
  def set_columns(*) = nil
end

# The WindowAdapter's "term" collaborator: it needs term_width (for blit
# widths), blink state, and a set_columns hook. In production this is
# RubyTerm; here a minimal stand-in.
class BenchHost
  CHAR_W = 8
  CHAR_H = 16
  attr_accessor :term_width
  def initialize(cols) = (@term_width = cols)
  def blink_state  = false
  def rblink_state = false
  def set_columns(_) = nil
end

def build_terminal(cols, rows, sink: :null)
  buffer = TermBuffer.new
  adapter =
    case sink
    when :null
      NullSink.new
    when :virtual
      win = Harness::VirtualWindow.new(cols * BenchHost::CHAR_W,
                                       rows * BenchHost::CHAR_H,
                                       char_w: BenchHost::CHAR_W,
                                       char_h: BenchHost::CHAR_H)
      WindowAdapter.new(win, BenchHost.new(cols))
    else abort "unknown sink: #{sink}"
    end
  tc   = TrackChanges.new(buffer, adapter)
  term = Term.new(tc, adapter)
  term.resize(cols, rows)
  tc.on_resize(cols, rows)
  term
end

# --- Workloads -------------------------------------------------------
# Deterministic (seeded) so runs are comparable. Each returns a byte
# string of approximately the requested size.

WORDS = %w[the quick brown fox jumps over a lazy dog lorem ipsum dolor
           sit amet consectetur adipiscing elit sed do eiusmod tempor
           incididunt ut labore et magna aliqua build compile link run
           error warning info trace module class def end require].freeze

def rng(seed) = Random.new(seed)

# Plain scrolling text: variable-length lines, mostly fitting the width,
# newline-terminated -> exercises set() + linefeed + region scroll.
def workload_plain(bytes, cols, seed = 1)
  r = rng(seed)
  out = +""
  while out.bytesize < bytes
    len = 0
    line = +""
    target = r.rand((cols * 0.5).to_i..(cols - 2))
    while len < target
      w = WORDS[r.rand(WORDS.length)]
      line << w << " "
      len += w.length + 1
    end
    out << line.rstrip << "\n"
  end
  out
end

# Coloured text (build-log / ls --color shape): SGR changes sprinkled in,
# exercising the attribute path and more draw-batch transitions.
def workload_ansi(bytes, cols, seed = 2)
  r = rng(seed)
  out = +""
  # 30-37 + reset only; bright (90-97) SGR is currently unhandled by
  # Term#set_modes and would trigger its diagnostic log, polluting the run.
  colours = [31, 32, 33, 34, 35, 36, 37, 0]
  while out.bytesize < bytes
    line = +""
    len = 0
    target = r.rand((cols * 0.5).to_i..(cols - 2))
    while len < target
      w = WORDS[r.rand(WORDS.length)]
      if r.rand(4).zero?
        line << "\e[#{colours[r.rand(colours.length)]}m" << w << "\e[0m "
      else
        line << w << " "
      end
      len += w.length + 1
    end
    out << line << "\n"
  end
  out
end

# Long lines (> width) to exercise autowrap on every row.
def workload_wrap(bytes, cols, seed = 3)
  r = rng(seed)
  out = +""
  while out.bytesize < bytes
    line = +""
    while line.length < cols * 3
      line << WORDS[r.rand(WORDS.length)] << " "
    end
    out << line << "\n"
  end
  out
end

# --- Measurement -----------------------------------------------------

def measure(bytes, cols, rows, chunk, sink)
  term = build_terminal(cols, rows, sink: sink)
  GC.start
  GC.compact if GC.respond_to?(:compact)
  a0 = GC.stat(:total_allocated_objects)
  g0 = GC.stat(:minor_gc_count) + GC.stat(:major_gc_count)
  t_gc0 = GC.stat(:time) # ms spent in GC, cumulative (Ruby 3.0+)
  live0 = GC.stat(:heap_live_slots)

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  i = 0
  n = bytes.bytesize
  while i < n
    term.feed(bytes.byteslice(i, chunk))
    i += chunk
  end
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  a1 = GC.stat(:total_allocated_objects)
  g1 = GC.stat(:minor_gc_count) + GC.stat(:major_gc_count)
  t_gc1 = GC.stat(:time)
  live1 = GC.stat(:heap_live_slots)

  secs   = t1 - t0
  allocs = a1 - a0
  {
    bytes:        n,
    secs:         secs,
    mb_per_s:     (n / 1_048_576.0) / secs,
    allocs:       allocs,
    allocs_per_kb: allocs / (n / 1024.0),
    gc_runs:      g1 - g0,
    gc_ms:        t_gc1 - t_gc0,
    live_retained: live1 - live0,
  }
end

# --- Main ------------------------------------------------------------

mb = 2.0
virtual_kb = 32
cols = 80
rows = 24
chunk = 128 # matches Controller#read's pty read size
as_json = false
sinks = [:null, :virtual]

args = ARGV.dup
until args.empty?
  case (a = args.shift)
  when "--mb"         then mb = args.shift.to_f
  when "--virtual-kb" then virtual_kb = args.shift.to_i
  when "--cols"       then cols = args.shift.to_i
  when "--rows"       then rows = args.shift.to_i
  when "--chunk"      then chunk = args.shift.to_i
  when "--json"       then as_json = true
  when "--sink"
    sinks = case args.shift
            when "null" then [:null]
            when "virtual" then [:virtual]
            else [:null, :virtual]
            end
  else abort "unknown arg: #{a}"
  end
end

# The virtual sink is ~120x slower (Ruby copy_area), so it runs a much
# smaller input; allocation rates (per-KB) stay comparable across sizes.
sink_bytes = { null: (mb * 1_048_576).to_i, virtual: virtual_kb * 1024 }

def workloads_for(bytes, cols)
  { "plain" => workload_plain(bytes, cols),
    "ansi"  => workload_ansi(bytes, cols),
    "wrap"  => workload_wrap(bytes, cols) }
end

measure(workload_plain(64 * 1024, cols), cols, rows, chunk, :null) # warmup
results = {} # {sink => {workload => metrics}}
sinks.each do |sink|
  results[sink] = {}
  workloads_for(sink_bytes[sink], cols).each do |name, data|
    results[sink][name] = measure(data, cols, rows, chunk, sink)
  end
end

if as_json
  puts JSON.pretty_generate(
    "config" => { "cols" => cols, "rows" => rows, "chunk" => chunk,
                  "mb" => mb, "virtual_kb" => virtual_kb, "ruby" => RUBY_VERSION },
    "results" => results.transform_keys(&:to_s))
else
  puts "terminal throughput — #{cols}x#{rows}, chunk=#{chunk}B, ruby #{RUBY_VERSION}"
  puts "  null    = interpreter + buffer + draw-batch, no rendering (#{mb} MB input)"
  puts "  virtual = full pipeline + WindowAdapter -> VirtualWindow (#{virtual_kb} KB input;"
  puts "            MB/s is copy_area-bound, NOT an X11 proxy — read alloc/KB, not MB/s)"
  puts
  puts "%-8s %-7s %8s %8s %12s %7s %8s %12s" %
       %w[sink load MB/s MB alloc/KB GCs GC_ms live(+)]
  results.each do |sink, by_load|
    by_load.each do |name, r|
      puts "%-8s %-7s %8.1f %8.3f %12.1f %7d %8.1f %12d" % [
        sink, name, r[:mb_per_s], r[:bytes] / 1_048_576.0, r[:allocs_per_kb],
        r[:gc_runs], r[:gc_ms], r[:live_retained]]
    end
  end
  puts
  puts "alloc/KB + live(+) are the deterministic regression metrics (compare"
  puts "to harness/bench-baseline.json). For the virtual sink read those, NOT"
  puts "MB/s (copy_area-bound). AXIS (b) — input/Ctrl-C latency under flood —"
  puts "needs the live pty + threads, measured separately."
end
