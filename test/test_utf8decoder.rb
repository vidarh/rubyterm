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
end