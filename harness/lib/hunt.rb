require 'json'
require 'base64'

# Deterministic bug hunt over a recording: everything between "I have
# a recording of a glitch" and "I have a minimal repro + the exact
# configuration it fails under" is a fixed search procedure, so no
# judgment (human or model) belongs in it.
#
# The search:
# 1. Scan ALL feed chunk sizes (default first, then progressively
#    smaller - bugs in escape/UTF-8 sequence reassembly are
#    *chunk-phase dependent* and often only fire when a sequence is
#    split across pty reads). Per chunk size:
#    a. replay the recording with redraw+markers checks at intervals
#    b. additionally diff the end state against the tmux oracle
#       (only when the recording has at most one geometry; mid-stream
#       resizes can't be reproduced in the oracle pane yet)
#    The scan is cheap (in-process replays + one oracle run per chunk
#    size); minimization is not, so scan first, choose targets after.
# 2. Choose one minimization target per failing check, preferring the
#    in-process checks: a state minimization runs the tmux oracle on
#    every ddmin iteration, so it is only used when nothing cheaper
#    fails anywhere (a pure state bug). Cut the stream at the failing
#    offset and ddmin under that exact configuration.
# 3. Emit minimal repros + ready-to-promote .meta.json sidecars
#    recording the geometry/chunk they fail under.
module Harness
  module Hunt
    DEFAULT_CHUNKS = [Session::DEFAULT_CHUNK, 4096, 64, 16, 4, 3, 2, 1].freeze
    CHEAP_CHECKS = %w[redraw markers].freeze

    def self.hunt(rec_path, checks: %w[state redraw markers],
                  chunks: DEFAULT_CHUNKS, every: nil, out_dir: "/tmp")
      records = File.readlines(rec_path).map { |l| JSON.parse(l) }
      stream = records.filter_map { |r|
        Base64.decode64(r["data_b64"]) if r["type"] == "output"
      }.join.b
      geometries = records.select { |r| r["type"] == "resize" }
                          .map { |r| [r["cols"], r["rows"]] }.uniq
      cols, rows = geometries.first || [80, 24]
      every ||= [stream.bytesize / 16, 512].max.clamp(512, 65_536)
      replay_checks = checks & CHEAP_CHECKS
      state_at_end = checks.include?("state") && geometries.length <= 1

      # Phase 1: scan. First a record-faithful replay (informational:
      # does it fail with exactly the chunk boundaries the live
      # terminal saw? not a minimization target - standalone repro
      # can't reproduce per-record boundaries), then the continuous
      # chunk sizes, whose failures are reproducible by run/minimize.
      attempts = []
      failing = [] # {chunk:, check:, to:}
      if replay_checks.any?
        rep0 = Replay.replay(rec_path, every: every, checks: replay_checks)
        attempts << { "chunk" => "rec", "replay_pass" => rep0["pass"],
                      "state_pass" => nil }
      end
      chunks.uniq.each do |chunk|
        warn "hunt: scanning chunk=#{chunk}"
        rep = replay_checks.any? &&
              Replay.replay(rec_path, every: every, chunk: chunk,
                            checks: replay_checks)
        state = state_at_end &&
                Checks.run_case(stream, cols: cols, rows: rows,
                                checks: %w[state], oracle: "tmux",
                                chunk: chunk)
        attempts << { "chunk" => chunk,
                      "replay_pass" => rep ? rep["pass"] : nil,
                      "state_pass" => state ? state["pass"] : nil }
        if rep
          CHEAP_CHECKS.each do |chk|
            f = rep["failures"].find { |x| x["check"] == chk }
            failing << { chunk: chunk, check: chk, to: f["offset"] } if f
          end
        end
        if state && !state["pass"]
          failing << { chunk: chunk, check: "state", to: stream.bytesize }
        end
      end

      base = { "rec" => rec_path, "geometry" => "#{cols}x#{rows}",
               "every" => every, "attempts" => attempts }
      if failing.empty?
        return base.merge(
          "found" => false,
          "note" => state_at_end ? nil :
            "state check skipped: recording has #{geometries.length} geometries")
      end

      # Phase 2: choose targets - first config (in scan order) per
      # check; drop the expensive state target when a cheap check
      # fails anywhere.
      targets = (CHEAP_CHECKS + %w[state]).filter_map { |chk|
        failing.find { |f| f[:check] == chk }
      }
      targets.reject! { |t| t[:check] == "state" } if targets.any? { |t| t[:check] != "state" }

      # Phase 3: minimize
      repros = minimize_targets(targets, stream, cols, rows, out_dir)
      base.merge(
        "found" => true,
        "repros" => repros,
        "note" => repros.empty? ?
          "failures found but none survived standalone minimization (transient); see attempts" : nil)
    end

    def self.minimize_targets(targets, stream, cols, rows, out_dir)
      seen = {}
      targets.filter_map do |t|
        chunk = t[:chunk]
        warn "hunt: minimizing #{t[:check]} failure at #{t[:to]} (chunk=#{chunk})"
        oracle = t[:check] == "state" ? "tmux" : nil
        begin
          res = Minimizer.minimize(stream.byteslice(0, t[:to]),
                                   cols: cols, rows: rows,
                                   checks: [t[:check]], oracle: oracle,
                                   chunk: chunk)
        rescue ArgumentError
          next # transient: cut passes standalone; nothing to minimize
        end
        sig = res.result["signature"]
        next if seen[sig]
        seen[sig] = true

        base = File.join(out_dir, "hunt-#{t[:check]}-#{sig}")
        File.binwrite("#{base}.bin", res.bytes)
        meta = { "geometry" => "#{cols}x#{rows}", "chunk" => chunk,
                 "reason" => "minimized from recording by harness hunt" }
        File.write("#{base}.meta.json", JSON.pretty_generate(meta) + "\n")

        { "check" => t[:check], "signature" => sig,
          "case_path" => "#{base}.bin", "meta_path" => "#{base}.meta.json",
          "geometry" => "#{cols}x#{rows}", "chunk" => chunk,
          "bytes" => res.bytes.bytesize,
          "minimal_inspect" => res.bytes.inspect,
          "failing_detail" => res.result["checks"][t[:check]],
          "iterations" => res.iterations }
      end
    end
  end
end
