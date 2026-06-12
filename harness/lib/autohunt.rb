require 'json'
require 'base64'
require 'fileutils'
require 'time'

# Long-running, progressively deepening bug hunt. Tries the cheapest
# configurations first (tiny geometries, small chunk sizes, redraw-only)
# and saves every distinct minimal repro it finds. A live manifest is
# updated after each find so a human can pick up the smallest known
# issue while the hunt keeps running.
#
# Crashes during candidate evaluation are treated as real bugs and are
# allowed to propagate: the hunt stops and records the crash in the
# manifest so it can be fixed before resuming.
module Harness
  module AutoHunt
    DEFAULT_GEOMETRIES = ["3x3", "5x5", "10x8", "20x10", "40x12"].freeze
    DEFAULT_CHUNKS = [1, 2, 4, 8, 16, 32, 64, 128].freeze
    DEFAULT_TIMEOUT = 3600

    def self.run(rec_path,
                 out_dir: nil,
                 geometries: DEFAULT_GEOMETRIES,
                 checks: %w[redraw],
                 timeout: DEFAULT_TIMEOUT)
      out_dir ||= "/tmp/autohunt-#{Time.now.to_i}"
      FileUtils.mkdir_p(out_dir)

      records = File.readlines(rec_path).map { |l| JSON.parse(l) }
      stream = records.filter_map { |r|
        Base64.decode64(r["data_b64"]) if r["type"] == "output"
      }.join.b

      geo_records = records.select { |r| r["type"] == "resize" }
      recorded_cols, recorded_rows =
        if (r = geo_records.first)
          [r["cols"], r["rows"]]
        else
          [80, 24]
        end

      all_geometries = geometries.map { |g| parse_geometry(g) }
      all_geometries << [recorded_cols, recorded_rows]

      manifest = {
        "rec" => rec_path,
        "out_dir" => out_dir,
        "started_at" => Time.now.iso8601,
        "stopped_at" => nil,
        "reason" => nil,
        "crash" => nil,
        "repros" => [],
        "smallest" => nil,
      }

      seen = {}
      deadline = timeout && Time.now + timeout
      reason = "complete"

      all_geometries.each do |cols, rows|
        chunks_for_geo =
          if cols == recorded_cols && rows == recorded_rows
            DEFAULT_CHUNKS + [Harness::Session::DEFAULT_CHUNK]
          else
            DEFAULT_CHUNKS
          end

        chunks_for_geo.each do |chunk|
          warn "autohunt: #{cols}x#{rows} chunk=#{chunk}"

          if deadline && Time.now >= deadline
            reason = "timeout"
            break
          end

          begin
            rep = Replay.replay(rec_path, every: [stream.bytesize / 8, 256].max,
                                cols: cols, rows: rows,
                                checks: checks & %w[redraw markers],
                                chunk: chunk)
          rescue StandardError => e
            reason = "crash"
            manifest["crash"] = crash_info(e)
            break
          end

          next if rep["pass"]

          rep["failures"].each do |f|
            offset = f["offset"]
            check = f["check"]

            if deadline && Time.now >= deadline
              reason = "timeout"
              break
            end

            begin
              minimized = Minimizer.minimize(stream.byteslice(0, offset),
                                             cols: cols, rows: rows,
                                             checks: [check], chunk: chunk)
            rescue ArgumentError
              next # transient: cut passes standalone
            rescue StandardError => e
              reason = "crash"
              manifest["crash"] = crash_info(e)
              break
            end

            sig = minimized.result["signature"]
            next if !sig || seen[sig]
            seen[sig] = true

            dir = File.join(out_dir, sig)
            FileUtils.mkdir_p(dir)
            bin_path = File.join(dir, "repro.bin")
            meta_path = File.join(dir, "repro.meta.json")
            File.binwrite(bin_path, minimized.bytes)
            meta = {
              "geometry" => "#{cols}x#{rows}",
              "chunk" => chunk,
              "check" => check,
              "signature" => sig,
              "bytes" => minimized.bytes.bytesize,
              "iterations" => minimized.iterations,
              "source_offset" => offset,
              "source_rec" => rec_path,
            }
            File.write(meta_path, JSON.pretty_generate(meta) + "\n")

            entry = {
              "signature" => sig,
              "geometry" => "#{cols}x#{rows}",
              "chunk" => chunk,
              "check" => check,
              "bytes" => minimized.bytes.bytesize,
              "bin_path" => bin_path,
              "meta_path" => meta_path,
              "minimal_inspect" => minimized.bytes.inspect,
            }
            manifest["repros"] << entry
            manifest["repros"].sort_by! { |e| [e["bytes"], e["signature"]] }
            manifest["smallest"] = manifest["repros"].first
            write_manifest(out_dir, manifest)

            warn "autohunt: saved #{minimized.bytes.bytesize}-byte #{check} repro #{sig} @ #{cols}x#{rows} chunk=#{chunk}"
          end

          break if %w[timeout crash].include?(reason)
        end

        break if %w[timeout crash].include?(reason)
      end

      manifest["stopped_at"] = Time.now.iso8601
      manifest["reason"] = reason
      write_manifest(out_dir, manifest)

      manifest
    end

    def self.parse_geometry(s)
      m = /\A(\d+)x(\d+)\z/.match(s) or abort "bad geometry #{s.inspect}"
      [m[1].to_i, m[2].to_i]
    end

    def self.crash_info(e)
      {
        "class" => e.class.name,
        "message" => e.message,
        "backtrace" => e.backtrace&.first(20),
      }
    end

    def self.write_manifest(out_dir, manifest)
      path = File.join(out_dir, "manifest.json")
      tmp = "#{path}.tmp"
      File.write(tmp, JSON.pretty_generate(manifest) + "\n")
      File.rename(tmp, path)
    end
  end
end
