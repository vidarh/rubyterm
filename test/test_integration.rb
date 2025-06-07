require_relative 'test_helper'

class TestIntegration < Minitest::Test
  def test_escape_sequence_parsing_workflow
    skip "EscapeParser not available" unless defined?(EscapeParser)
    
    parser = EscapeParser.new
    
    # Parse a complete escape sequence
    escape_chars = "\e[2J".bytes
    escape_chars.each { |byte| parser.put(byte) }
    
    assert parser.complete?
    assert_equal "[2J", parser.str
  end

  def test_utf8_decoding_workflow
    skip "UTF8Decoder not available" unless defined?(UTF8Decoder)
    
    decoder = UTF8Decoder.new
    
    # Process a string with mixed ASCII and UTF-8
    test_string = "Hello 世界!"
    decoder << test_string
    
    chars = []
    decoder.each { |c| chars << c }
    
    # Should decode properly
    expected = ['H', 'e', 'l', 'l', 'o', ' ', '世', '界', '!']
    assert_equal expected, chars
  end

  def test_color_system_integration
    skip "Palette not available" unless defined?(PALETTE_BASIC) && defined?(PALETTE256)
    
    # Test that we can work with colors from the palette
    assert PALETTE_BASIC.length >= 16
    assert PALETTE256.length == 256
    
    # Basic colors should be valid hex values
    PALETTE_BASIC.each do |color|
      assert color.is_a?(Integer)
      assert color >= 0
      assert color <= 0xffffff
    end
  end

  def test_charset_integration
    skip "Charsets not available" unless defined?(DefaultCharset) && defined?(GraphicsCharset)
    
    # Test that both charsets work
    ascii_char = DefaultCharset[65]  # 'A'
    assert_equal 65, ascii_char
    
    # Graphics charset should return something for line drawing
    graphics_char = GraphicsCharset[0x71]  # horizontal line
    assert_equal "\u2500", graphics_char
  end
end