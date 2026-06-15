require_relative 'test_helper'

class TestUTF8Decoder < Minitest::Test
  def setup
    @decoder = create_utf8_decoder
  end

  def test_ascii_characters
    skip "UTF8Decoder not available" unless @decoder
    
    @decoder << "Hello"
    chars = []
    @decoder.each { |c| chars << c }
    
    assert_equal ['H', 'e', 'l', 'l', 'o'], chars
  end

  def test_utf8_characters
    skip "UTF8Decoder not available" unless @decoder
    
    # Test with UTF-8 encoded string
    @decoder << "café"
    chars = []
    @decoder.each { |c| chars << c }
    
    assert_equal ['c', 'a', 'f', 'é'], chars
  end

  def test_partial_utf8_sequence
    skip "UTF8Decoder not available" unless @decoder
    
    # Send partial UTF-8 sequence
    @decoder << "\xc3"  # First byte of é
    chars = []
    @decoder.each { |c| chars << c }
    
    # Should not yield anything yet
    assert_empty chars
    
    # Complete the sequence
    @decoder << "\xa9"  # Second byte of é
    @decoder.each { |c| chars << c }
    
    assert_equal ['é'], chars
  end

  def test_buffer_management
    skip "UTF8Decoder not available" unless @decoder
    
    @decoder << "test"
    assert_equal "test", @decoder.buffer
    
    # After consuming characters, buffer should be cleared
    @decoder.each { |c| }
    assert_equal "", @decoder.buffer
  end

  def test_mixed_ascii_and_utf8
    skip "UTF8Decoder not available" unless @decoder

    @decoder << "Hello 世界"
    chars = []
    @decoder.each { |c| chars << c }

    expected = ['H', 'e', 'l', 'l', 'o', ' ', '世', '界']
    assert_equal expected, chars
  end

  def collect
    chars = []
    @decoder.each { |c| chars << c }
    chars
  end

  # A 3-byte char (em-dash U+2014 = E2 80 94) split between two pty reads
  # AFTER its second byte must still decode as one character. The trailing
  # 0x80 was previously treated as a complete sequence (the guard used
  # > 0x80, not >= 0x80), dropping E2 80 and orphaning 0x94 into the next
  # chunk - exactly what corrupted a `cat` of a doc full of em-dashes.
  def test_three_byte_split_after_second_byte
    skip "UTF8Decoder not available" unless @decoder
    @decoder << "a\xE2\x80".b
    assert_equal ['a'], collect, "only the complete prefix is emitted"
    @decoder << "\x94b".b
    assert_equal ['—', 'b'], collect
  end

  def test_three_byte_split_after_lead
    skip "UTF8Decoder not available" unless @decoder
    @decoder << "a\xE2".b
    assert_equal ['a'], collect
    @decoder << "\x80\x94".b
    assert_equal ['—'], collect
  end

  def test_complete_three_byte_sequence_not_held_back
    skip "UTF8Decoder not available" unless @decoder
    @decoder << "\xE2\x80\x94".b
    assert_equal ['—'], collect
  end
end