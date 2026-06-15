
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

    # Split @buffer into a complete-sequence prefix and a saved leftover,
    # then yield the prefix (encoding-tagged) to the caller's per-character
    # iterator.
    private def decode
      # We acknowledge that @buffer can contain
      # sequences that are invalid UTF8, and we will
      # do our best with them *unless*:
      # * @buffer[-1] starts any multibyte sequence
      # * @buffer[-2] starts a 3 or 4 byte sequence
      # * @buffer[-3] starts a 4 byte sequence.
      # In those cases, and those cases only, we
      # save those bytes for next time.

      str = @buffer
      return nil if !str || str.empty?
      last = str.length-1

      if str[-1].ord >= 0x80
        # -1 is part of a multibyte sequence (a continuation byte 0x80-0xBF
        # or a lead byte 0xC0+). NB: this must be >= 0x80, not > 0x80 - a
        # trailing 0x80 is the second byte of e.g. an em-dash (E2 80 94)
        # split across a pty read; treating it as complete dropped the
        # lead bytes and orphaned the final byte into the next chunk.
        if str.length == 1
          # Single byte that starts a multibyte sequence
            last = -2  # Process nothing, save everything
        elsif str[-2] && str[-2].ord & 0xe0 == 0xc0 # -2..-1 is a 2 byte sequence; we're good.
        elsif str[-2] && str[-2].ord & 0xe0 == 0xe0 # Start of a 3 or 4 byte sequence
          last = str.length-3
        else # -2 is *part of a 3 or 4 byte sequence
          if    str[-3] && str[-3].ord & 0xf0 == 0xe0 # -3 Starts a 3 byte sequence
          elsif str[-3] && str[-3].ord & 0xf8 == 0xf0 # -3 starts a 4 byte sequence
            last = str.length-4
          else # -2 must be the final byte of something, so we only chop the last
            last = str.length-2
          end
        end
      end
      @leftover = str[last+1..-1].b
      complete = str[0..last].force_encoding("UTF-8")
      yield complete
      @buffer = @leftover
    end

  end
  
