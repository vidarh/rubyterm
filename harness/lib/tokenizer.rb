# Splits a raw byte stream into tokens using the terminal's own
# EscapeParser, so a token boundary never falls inside an escape
# sequence. Tokens are raw byte strings; tokens.join == input always
# holds, which is what lets the minimizer (ddmin) recombine subsets.
#
# Token kinds:
# * complete escape sequences (starting with ESC)
# * aborted/unterminated escape prefixes (kept as-is)
# * single C0 control characters
# * individual UTF-8 characters (including ASCII)
#
# Text is split at UTF-8 character boundaries so ddmin never removes
# part of a multi-byte glyph. This avoids wasting iterations on
# malformed UTF-8 decoder states that are unrelated to the bug being
# minimized.
module Harness
  module Tokenizer
    def self.tokenize(bytes)
      tokens = []
      text = +"".b
      esc = nil
      seq = nil
      flush_text = -> { tokens.concat(split_text(text)); text = +"".b }

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

    # Split a run of printable (non-escape, non-control) bytes into
    # tokens that respect UTF-8 boundaries. Maximal ASCII runs are kept
    # together to keep the token count low; multi-byte UTF-8 characters
    # are individual tokens so ddmin never removes part of a glyph. On
    # malformed UTF-8, keep the whole run as a single token so ddmin
    # never makes it worse.
    def self.split_text(text)
      chars = []
      i = 0
      bs = text.bytes
      while i < bs.length
        b = bs[i]
        if b < 0x80
          # Keep ASCII runs together: removing whole words/spaces does
          # not break UTF-8 and keeps ddmin's search space manageable.
          j = i
          j += 1 while j < bs.length && bs[j] < 0x80
          chars << bs[i...j].pack("C*").b
          i = j
        else
          len =
            if (b & 0xe0) == 0xc0 then 2
            elsif (b & 0xf0) == 0xe0 then 3
            elsif (b & 0xf8) == 0xf0 then 4
            else return [text]
            end
          return [text] if i + len > bs.length
          (1...len).each do |j|
            return [text] if (bs[i + j] & 0xc0) != 0x80
          end
          chars << bs[i, len].pack("C*").b
          i += len
        end
      end
      chars
    end
  end
end
