require 'json'

# Runs the whole corpus and enforces the ratchet: the sorted list of
# case IDs known to pass on main (ratchet.json). A patch may add IDs to
# the ratchet, never remove - any previously-passing case that fails is
# a regression and the sweep exits non-zero. This is the mechanical
# gate autonomous fixers are validated against; they self-report
# nothing.
module Harness
  module Sweep
    CASE_EXT = %w[.bin .txt].freeze

    def self.collect_cases(paths)
      paths.flat_map do |path|
        if File.directory?(path)
          Dir.glob(File.join(path, "**", "*"))
             .select { |f| File.file?(f) && CASE_EXT.include?(File.extname(f)) }
             .sort
        else
          [path]
        end
      end
    end

    def self.case_id(file, roots)
      root = roots.find { |r| File.directory?(r) && file.start_with?(r) }
      id = root ? file[root.length..].sub(%r{^/}, "") : file
      id.sub(/\.(bin|txt)$/, "")
    end

    # Optional sidecar next to a case file (<case>.meta.json):
    #   {"skip_checks": ["state"], "reason": "..."}
    # The explicit, reviewable way to record known oracle divergences
    # (e.g. tmux ignoring a DEC mode we implement per spec).
    def self.case_meta(file)
      meta = file.sub(/\.(bin|txt)\z/, "") + ".meta.json"
      File.exist?(meta) ? JSON.parse(File.read(meta)) : {}
    end

    def self.run(paths, cols:, rows:, checks:, oracle: nil,
                 chunk: Session::DEFAULT_CHUNK, ratchet: nil)
      files = collect_cases(paths)
      results = {}
      files.each do |file|
        id = case_id(file, paths)
        warn "sweep: #{id}"
        bytes = File.binread(file)
        meta = case_meta(file)
        case_checks = checks - Array(meta["skip_checks"])
        results[id] =
          begin
            r = Checks.run_case(bytes, cols: cols, rows: rows,
                                checks: case_checks, oracle: oracle,
                                chunk: chunk)
              .slice("pass", "class", "signature", "checks")
            r["skipped_checks"] = meta["skip_checks"] if meta["skip_checks"]
            r
          rescue StandardError => e
            { "pass" => false, "class" => "harness_error",
              "error" => "#{e.class}: #{e.message}" }
          end
      end

      failures = results.reject { |_, r| r["pass"] }.keys.sort
      out = {
        "total" => results.length,
        "passing" => results.length - failures.length,
        "failures" => failures,
        "results" => results,
      }

      if ratchet && File.exist?(ratchet)
        protected_ids = JSON.parse(File.read(ratchet))
        regressions = protected_ids.select { |id|
          results.key?(id) && !results[id]["pass"]
        }
        out["ratchet"] = {
          "file" => ratchet,
          "protected" => protected_ids.length,
          "regressions" => regressions,
        }
        out["pass"] = regressions.empty?
      else
        out["pass"] = failures.empty?
      end
      out
    end

    # Write the current set of passing IDs. Refuses to drop IDs that
    # are in the existing ratchet (that would hide a regression).
    def self.update_ratchet(sweep_result, ratchet_file)
      passing = sweep_result["results"].select { |_, r| r["pass"] }.keys
      if File.exist?(ratchet_file)
        old = JSON.parse(File.read(ratchet_file))
        lost = old & sweep_result["results"].keys - passing
        raise "refusing to remove regressed IDs from ratchet: #{lost.join(', ')}" if lost.any?
        passing |= old
      end
      File.write(ratchet_file, JSON.pretty_generate(passing.sort) + "\n")
      passing.sort
    end
  end
end
