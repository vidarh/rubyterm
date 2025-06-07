require_relative 'test_helper'

class TestCharsets < Minitest::Test
  def test_default_charset_exists
    skip "Charsets not available" unless defined?(DefaultCharset)
    
    assert DefaultCharset.respond_to?(:[])
  end

  def test_graphics_charset_exists
    skip "Charsets not available" unless defined?(GraphicsCharset)
    
    assert GraphicsCharset.respond_to?(:[])
  end

  def test_default_charset_ascii
    skip "Charsets not available" unless defined?(DefaultCharset)
    
    # Test that ASCII characters pass through unchanged
    (32..126).each do |i|
      assert_equal i, DefaultCharset[i]
    end
  end

  def test_graphics_charset_special_chars
    skip "Charsets not available" unless defined?(GraphicsCharset)
    
    # Test some common VT100 graphics characters
    # These are the standard DEC Special Character Set mappings
    
    # Test horizontal line (should map to Unicode box drawing)
    result = GraphicsCharset[0x71] # 'q' -> horizontal line
    assert_equal "\u2500", result
    
    # Test vertical line
    result = GraphicsCharset[0x78] # 'x' -> vertical line  
    assert_equal "\u2502", result
    
    # Test corner characters
    result = GraphicsCharset[0x6c] # 'l' -> upper left corner
    assert_equal "\u250C", result
  end

  def test_charset_fallback
    skip "Charsets not available" unless defined?(DefaultCharset) && defined?(GraphicsCharset)
    
    # Test that unknown characters fall back gracefully
    result = DefaultCharset[999]
    assert_equal 999, result
    
    result = GraphicsCharset[999]
    assert_equal 999, result
  end
end