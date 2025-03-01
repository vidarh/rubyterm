
  class UTF8Decoder
    attr_reader :buffer

    def initialize
      @buffer = "".b
    end

    def <<(str) = @buffer << str.b

    def each(&block)
      # We acknowledge that @buffer can contain
      # sequences that are invalid UTF8, and we will
      # do our best with them *unless*:
      # * @buffer[-1] starts any multibyte sequence
      # * @buffer[-2] starts a 3 or 4 byte sequence
      # * @buffer[-3] starts a 4 byte sequence.
      # In those cases, and those cases only, we
      # save those bytes for next time.

      str = @buffer
      return nil if str.empty?
      last = str.length-1
      if str[-1].ord > 0x80
        # -1 is part of a multibyte sequence
        if    str[-2] && str[-2].ord & 0xe0 == 0xc0 # -2..-1 is a 2 byte sequence; we're good.
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
      last = 0 if last < 0
      @last = last # For debugging
      @leftover = str[last+1..-1].b
      @buffer = str[0..last].force_encoding("UTF-8")
      @buffer.each_char(&block)
      @buffer = @leftover
      #p [:leftover, @buffer.length, @buffer] if @buffer.length > 0
    end

  end
  
