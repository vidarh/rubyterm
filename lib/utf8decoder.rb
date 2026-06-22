
  class UTF8Decoder
    attr_reader :buffer

    def initialize
      @buffer = "".b
    end

    def <<(str) = @buffer << str.b

    # Yields each complete character as a String (the original contract).
    def each(&block)
      decode { |complete| complete.each_char(&block) }
    end

    # Yields each complete character as an Integer codepoint. The hot path
    # (Term#feed) wants codepoints, not 1-char Strings: on a valid chunk
    # String#each_codepoint avoids allocating a String per character and the
    # per-character valid_encoding?/ord that #feed used to do. Validity is
    # checked once per chunk; only a chunk that actually contains bad bytes
    # falls back to the slower per-character path (rendering them as U+FFFD).
    def each_codepoint(&block)
      decode do |complete|
        if complete.valid_encoding?
          complete.each_codepoint(&block)
        else
          complete.each_char { |c| block.call(c.valid_encoding? ? c.ord : 0xFFFD) }
        end
      end
    end

    # Split @buffer into a complete-sequence prefix and a saved leftover, then
    # yield the prefix (encoding-tagged) to the caller's per-character iterator.
    # If the buffer ends partway through a multibyte sequence (it was split
    # across a pty read), those trailing bytes are held back for next time;
    # everything before them is yielded.
    private def decode
      str = @buffer
      return nil if !str || str.empty?
      yield_len = str.length

      if str[-1].ord >= 0x80
        # Find the lead byte of the final sequence by skipping back over up to
        # three continuation bytes (0x80-0xBF). If that sequence isn't yet
        # complete, hold it (and everything after the lead) for the next chunk.
        j = str.length - 1
        j -= 1 while j.positive? && (str[j].ord & 0xc0) == 0x80 && str.length - j < 4
        lead = str[j].ord
        needed =
          if    lead & 0xe0 == 0xc0 then 2
          elsif lead & 0xf0 == 0xe0 then 3
          elsif lead & 0xf8 == 0xf0 then 4
          else 0 # orphan continuation byte or not a lead - nothing to hold back
          end
        yield_len = j if needed.positive? && (str.length - j) < needed
      end

      complete = str[0, yield_len].force_encoding("UTF-8")
      @buffer  = str[yield_len..].b
      yield complete unless complete.empty?
    end

  end
  
