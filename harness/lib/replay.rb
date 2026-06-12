require 'json'
require 'base64'

# Replays a pty recording (see recorder.rb) through a headless session,
# honouring resize records and running checks at byte-count intervals.
# Only the output stream is fed; whatever replies our terminal
# generates go nowhere, which is what makes replay deterministic.
#
# Feeding semantics (chunk:):
# * nil (default) - record-faithful: each recorded pty read is fed as
#   one chunk, reproducing the chunk boundaries the live terminal saw.
# * Integer N - continuous N-byte slicing across record boundaries,
#   carrying remainders. This is byte-for-byte the same slicing
#   `run`/`minimize` apply to an extracted stream, so a failure found
#   at --chunk N can be cut out and reproduced standalone under the
#   same flag. Used by `hunt` to probe chunk-phase-dependent bugs
#   (split escape/UTF-8 sequences). Checkpoints only ever fall on
#   slice boundaries, for the same reason.
#
# Checks are suppressed inside DEC private mode 2026 (synchronized
# update) blocks - applications use it precisely to mark frames as
# intentionally incomplete, so checking there would report false
# positives. Our terminal need not *support* 2026 for this to matter;
# the recording's byte stream tells us where the quiescence points are.
#
# All failures are recorded, not just the first: stale-rendering
# failures can be transient (a later full clear masks them), so a
# bisecting minimizer needs every sweep point that failed.
module Harness
  module Replay
    SYNC_ON  = "\e[?2026h".b
    SYNC_OFF = "\e[?2026l".b

    def self.replay(rec_path, every: 65_536, cols: 80, rows: 24,
                    checks: %w[redraw], chunk: nil)
      records = File.readlines(rec_path).map { |l| JSON.parse(l) }

      # Use the recorded initial geometry if present.
      if (r = records.find { |x| x["type"] == "resize" })
        cols, rows = r["cols"], r["rows"]
      end

      session = Session.new(cols: cols, rows: rows)
      marker_session = checks.include?("markers") ?
                         Session.new(cols: cols, rows: rows,
                                     render_mode: :markers) : nil

      failures = []
      fed = 0
      last_check = 0
      in_sync = false
      sync_tail = +"".b
      pending = +"".b

      run_checks = lambda do |offset|
        rc = Checks.redraw_check(session)
        failures << { "offset" => offset, "check" => "redraw", "result" => rc } if !rc["pass"]
        if marker_session
          mc = Checks.marker_check(marker_session)
          failures << { "offset" => offset, "check" => "markers", "result" => mc } if !mc["pass"]
        end
      end

      feed_one = lambda do |slice|
        session.feed(slice, chunk: slice.bytesize)
        marker_session&.feed(slice, chunk: slice.bytesize)
        fed += slice.bytesize

        # Track 2026 sync state across slice boundaries.
        scan = sync_tail + slice
        on, off = scan.rindex(SYNC_ON), scan.rindex(SYNC_OFF)
        in_sync = on && (!off || on > off) ? true : (off ? false : in_sync)
        sync_tail = scan.byteslice(-(SYNC_ON.bytesize - 1)..) || scan.dup

        if fed - last_check >= every && !in_sync
          last_check = fed
          run_checks.call(fed)
        end
      end

      drain = lambda do |final|
        if chunk
          feed_one.call(pending.slice!(0, chunk)) while pending.bytesize >= chunk
          feed_one.call(pending.slice!(0, pending.bytesize)) if final && !pending.empty?
        elsif !pending.empty?
          feed_one.call(pending.slice!(0, pending.bytesize))
        end
      end

      records.each do |r|
        case r["type"]
        when "resize"
          drain.call(true) # flush the carry before the geometry changes
          session.resize(r["cols"], r["rows"])
          marker_session&.resize(r["cols"], r["rows"])
        when "output"
          pending << Base64.decode64(r["data_b64"])
          drain.call(false)
        end
      end
      drain.call(true)
      run_checks.call(fed)

      {
        "pass" => failures.empty?,
        "bytes" => fed,
        "geometry" => "#{session.cols}x#{session.rows}",
        "chunk" => chunk,
        "failures" => failures,
      }
    end
  end
end
