# Reduces a failing case to a smaller repro using fast bisection +
# refinement. We are looking for *any one* failure, not a 1-minimal
# subset of every failing property.
#
# Algorithm:
# 1. Test the whole input. If it passes, there is nothing to minimize.
# 2. Split the current chunk into N parts (starting with 2, then 3, 5,
#    7, 11, ...) at token boundaries. Test each part in order.
# 3. If any part fails, make it the new current chunk and go to 2.
# 4. If no part fails for any split count, stop and return the current
#    chunk.
#
# Split counts are prime-ish because a power-of-two bisection can land
# on boundaries that accidentally keep two independent failure causes
# together; odd splits shake the boundary alignment loose.
#
# Candidate evaluation is run with stdout/stderr silenced: the
# production terminal is full of `p` debugging statements, and at
# small chunk sizes they produce gigabytes of stderr that slows every
# iteration to a crawl. The final result is still computed normally so
# diagnostics are available for the returned repro.
module Harness
  module Minimizer
    Result = Struct.new(:bytes, :result, :iterations, keyword_init: true)

    # Split counts to try, in order.  We stop when the count exceeds the
    # number of tokens in the current chunk.
    SPLIT_COUNTS = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47].freeze

    def self.minimize(bytes, cols:, rows:, checks:, oracle: nil,
                      chunk: Session::DEFAULT_CHUNK, quiet: true,
                      signature_match: false)
      original = evaluate(bytes, cols: cols, rows: rows,
                          checks: checks, oracle: oracle, chunk: chunk,
                          quiet: quiet)
      raise ArgumentError, "case does not fail; nothing to minimize" if original["pass"]
      want = signature_match ? original["signature"] : nil

      tokens = Tokenizer.tokenize(bytes)
      current = tokens.dup
      iterations = 1

      # Phase 1: fast bisection / multi-split. Repeatedly find a smaller
      # contiguous part that still fails. Split counts include 3, 5, 7,
      # ... because a pure power-of-two bisection can land on boundaries
      # that keep two independent failure causes together.
      while current.length > 1
        reduced = try_splits(current, cols: cols, rows: rows,
                             checks: checks, oracle: oracle, chunk: chunk,
                             quiet: quiet, want: want)
        break unless reduced

        iterations += reduced[:iterations]
        current = reduced[:tokens]
      end

      # Phase 2: trim irrelevant prefix / suffix tokens. This is cheap
      # and often removes most of the input before we start expensive
      # internal deletion.
      trimmed = trim_ends(current, cols: cols, rows: rows,
                          checks: checks, oracle: oracle, chunk: chunk,
                          quiet: quiet, want: want)
      iterations += trimmed[:iterations]
      current = trimmed[:tokens]

      # Phase 3: internal deletion. Try dropping chunks from the middle
      # of the chunk while keeping it failing. This removes bytes splits
      # cannot. Any crash here is a real bug and is allowed to propagate
      # so it can be fixed.
      deleted = delete_redundant_tokens(current, cols: cols, rows: rows,
                                        checks: checks, oracle: oracle,
                                        chunk: chunk, quiet: quiet, want: want)
      iterations += deleted[:iterations]
      current = deleted[:tokens]

      out = current.join
      Result.new(bytes: out,
                 result: Checks.run_case(out, cols: cols, rows: rows,
                                         checks: checks, oracle: oracle,
                                         chunk: chunk),
                 iterations: iterations)
    end

    # Try each split count in SPLIT_COUNTS. Return the first failing
    # part found, or nil if no part fails.
    def self.try_splits(tokens, cols:, rows:, checks:, oracle:, chunk:, quiet:, want:)
      SPLIT_COUNTS.each do |n|
        break if n > tokens.length
        parts = split_into(tokens, n)
        parts.each do |part|
          next if part.empty?
          r = evaluate(part.join, cols: cols, rows: rows,
                       checks: checks, oracle: oracle, chunk: chunk,
                       quiet: quiet)
          next if r["pass"]
          next if want && r["signature"] != want
          return { tokens: part, iterations: 1 }
        end
      end
      nil
    end

    # Split an array of tokens into N contiguous, roughly-equal parts at
    # token boundaries. Splits are cumulative so the concatenation of
    # all parts equals the original input.
    def self.split_into(tokens, n)
      size = tokens.length.to_f / n
      n.times.map do |i|
        start = (i * size).to_i
        finish = ((i + 1) * size).to_i
        tokens[start...finish]
      end
    end

    # Trim tokens from the start and end of the chunk while it keeps
    # failing. This is O(n) and often removes the bulk of an app
    # recording's preamble/epilogue.
    def self.trim_ends(tokens, cols:, rows:, checks:, oracle:, chunk:, quiet:, want:)
      current = tokens.dup
      iterations = 0

      # Trim prefix.
      while current.length > 1
        iterations += 1
        candidate = current[1..]
        r = evaluate(candidate.join, cols: cols, rows: rows,
                     checks: checks, oracle: oracle, chunk: chunk,
                     quiet: quiet)
        break if r["pass"] || (want && r["signature"] != want)
        current = candidate
      end

      # Trim suffix.
      while current.length > 1
        iterations += 1
        candidate = current[0...-1]
        r = evaluate(candidate.join, cols: cols, rows: rows,
                     checks: checks, oracle: oracle, chunk: chunk,
                     quiet: quiet)
        break if r["pass"] || (want && r["signature"] != want)
        current = candidate
      end

      { tokens: current, iterations: iterations }
    end

    # Remove tokens from the middle of the chunk in decreasing chunk
    # sizes. Start with ~10% of the original length; do one greedy pass
    # at that size, then halve and repeat down to single tokens. This is
    # O(n log n) and avoids the cost of restarting at 10% after every
    # removal.
    def self.delete_redundant_tokens(tokens, cols:, rows:, checks:, oracle:,
                                     chunk:, quiet:, want:)
      current = tokens.dup
      iterations = 0
      chunk_size = [current.length / 10, 1].max

      while chunk_size >= 1
        i = 0
        while i + chunk_size <= current.length
          iterations += 1
          candidate = current[0...i] + current[(i + chunk_size)..]
          r = evaluate(candidate.join, cols: cols, rows: rows,
                       checks: checks, oracle: oracle, chunk: chunk,
                       quiet: quiet)
          if !r["pass"] && (!want || r["signature"] == want)
            current = candidate
            # do not advance i; the chunk at i has been removed
          else
            i += 1
          end
        end

        break if chunk_size == 1
        chunk_size = [chunk_size / 2, 1].max
      end

      { tokens: current, iterations: iterations }
    end

    def self.evaluate(bytes, cols:, rows:, checks:, oracle:, chunk:, quiet:)
      return Checks.run_case(bytes, cols: cols, rows: rows,
                             checks: checks, oracle: oracle, chunk: chunk) unless quiet

      silence_io do
        Checks.run_case(bytes, cols: cols, rows: rows,
                        checks: checks, oracle: oracle, chunk: chunk)
      end
    end

    def self.silence_io
      old_stdout = $stdout.dup
      old_stderr = $stderr.dup
      $stdout.reopen(File::NULL, "w")
      $stderr.reopen(File::NULL, "w")
      yield
    ensure
      $stdout.reopen(old_stdout)
      $stderr.reopen(old_stderr)
      old_stdout.close
      old_stderr.close
    end
  end
end
