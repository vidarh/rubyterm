# Splits a raw byte stream into tokens using the terminal's own
# EscapeParser, so a token boundary never falls inside an escape
# sequence. Tokens are raw byte strings; tokens.join == input always
# holds, which is what lets the minimizer (ddmin) recombine subsets.
#
# Token kinds:
# * complete escape sequences (starting with ESC)
# * aborted/unterminated escape prefixes (kept as-is)
# * single C0 control characters
# * maximal runs of printable bytes (including multi-byte UTF-8)
module Harness
  module Tokenizer
    def self.tokenize(bytes)
      tokens = []
      text = +"".b
      esc = nil
      seq = nil
      flush_text = -> { (tokens << text; text = +"".b) if !text.empty? }

      bytes.b.each_byte do |b|
        if esc
          if esc.put(b)
            seq << b
            if esc.complete?
              tokens << seq
              esc = nil
            end
            next
          else
            # Parser rejected the byte (e.g. control char inside OSC):
            # emit the partial sequence, reprocess the byte normally,
            # mirroring Term#putchar's behaviour.
            tokens << seq
            esc = nil
          end
        end

        if b == 27
          flush_text.call
          esc = EscapeParser.new
          seq = (+"").b << 27
        elsif b < 32
          flush_text.call
          tokens << b.chr.b
        else
          text << b
        end
      end

      flush_text.call
      tokens << seq if esc # unterminated escape at EOF
      tokens
    end
  end
end
