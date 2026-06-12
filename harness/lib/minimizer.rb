# Reduces a failing case to a minimal repro: ddmin over *tokens* (so
# subsets never split an escape sequence - see Tokenizer), accepting a
# candidate only when it fails with the same signature as the original
# failure. Without signature matching ddmin happily minimizes into a
# different bug.
module Harness
  module Minimizer
    Result = Struct.new(:bytes, :result, :iterations, keyword_init: true)

    def self.minimize(bytes, cols:, rows:, checks:, oracle: nil,
                      chunk: Session::DEFAULT_CHUNK)
      original = Checks.run_case(bytes, cols: cols, rows: rows,
                                 checks: checks, oracle: oracle, chunk: chunk)
      raise ArgumentError, "case does not fail; nothing to minimize" if original["pass"]
      want = original["signature"]

      iterations = 0
      tokens = Tokenizer.tokenize(bytes)
      minimal = DDMin.minimize(tokens) do |subset|
        iterations += 1
        r = Checks.run_case(subset.join, cols: cols, rows: rows,
                            checks: checks, oracle: oracle, chunk: chunk)
        !r["pass"] && r["signature"] == want
      rescue StandardError
        # A candidate that crashes the harness machinery itself is not
        # "the same failure".
        false
      end

      out = minimal.join
      Result.new(bytes: out,
                 result: Checks.run_case(out, cols: cols, rows: rows,
                                         checks: checks, oracle: oracle,
                                         chunk: chunk),
                 iterations: iterations)
    end
  end
end
