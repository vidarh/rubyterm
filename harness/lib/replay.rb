require 'json'
require 'base64'

# Replays a pty recording (see recorder.rb) through a headless session,
# honouring resize records and running checks at byte-count intervals.
# Only the output stream is fed; whatever replies our terminal
# generates go nowhere, which is what makes replay deterministic.
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
                    checks: %w[redraw], chunk: Session::DEFAULT_CHUNK)
      records = File.readlines(rec_path).map { |l| JSON.parse(l) }

      # Use the recorded initial geometry if present.
      if (r = records.find { |x| x["type"] == "resize" })
        cols, rows = r["cols"], r["rows"]
      end

      session = Session.new(cols: cols, rows: rows)
      marker_session = checks.include?("markers") ?
                         Session.new(cols: cols, rows: rows, render_mode: :markers) : nil

      failures = []
      fed = 0
      last_check = 0
      in_sync = false
      tail = +"".b

      run_checks = lambda do |offset|
        rc = Checks.redraw_check(session)
        failures << { "offset" => offset, "check" => "redraw", "result" => rc } if !rc["pass"]
        if marker_session
          mc = Checks.marker_check(marker_session)
          failures << { "offset" => offset, "check" => "markers", "result" => mc } if !mc["pass"]
        end
      end

      records.each do |r|
        case r["type"]
        when "resize"
          session.resize(r["cols"], r["rows"])
          marker_session&.resize(r["cols"], r["rows"])
        when "output"
          data = Base64.decode64(r["data_b64"])
          session.feed(data, chunk: chunk)
          marker_session&.feed(data, chunk: chunk)
          fed += data.bytesize

          # Track 2026 sync state across chunk boundaries.
          scan = tail + data
          on, off = scan.rindex(SYNC_ON), scan.rindex(SYNC_OFF)
          in_sync = on && (!off || on > off) ? true : (off ? false : in_sync)
          tail = scan[-(SYNC_ON.length - 1)..] || scan

          if fed - last_check >= every && !in_sync
            last_check = fed
            run_checks.call(fed)
          end
        end
      end
      run_checks.call(fed)

      {
        "pass" => failures.empty?,
        "bytes" => fed,
        "geometry" => "#{session.cols}x#{session.rows}",
        "failures" => failures,
      }
    end
  end
end
