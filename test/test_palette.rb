require_relative 'test_helper'

class TestPalette < Minitest::Test
  def test_basic_palette_constants
    skip "Palette not available" unless defined?(PALETTE_BASIC)
    
    # Test that basic palette colors are defined
    assert PALETTE_BASIC.is_a?(Array)
    assert_equal 16, PALETTE_BASIC.length
  end

  def test_256_color_palette
    skip "Palette not available" unless defined?(PALETTE256)
    
    # Test that 256-color palette is defined
    assert PALETTE256.is_a?(Array)
    assert_equal 256, PALETTE256.length
  end

  def test_basic_color_values
    skip "Palette not available" unless defined?(PALETTE_BASIC)
    
    # Test some basic colors
    assert_equal 0x000000, PALETTE_BASIC[0]  # Black
    assert_equal 0xffffff, PALETTE_BASIC[15] # Bright white
  end

  def test_palette256_includes_basic_colors
    skip "Palette not available" unless defined?(PALETTE256) && defined?(PALETTE_BASIC)
    
    # First 16 colors should match basic palette
    16.times do |i|
      assert_equal PALETTE_BASIC[i], PALETTE256[i]
    end
  end

  def test_palette256_grayscale_ramp
    skip "Palette not available" unless defined?(PALETTE256)
    
    # Colors 232-255 should be grayscale
    (232..255).each do |i|
      color = PALETTE256[i]
      r = (color >> 16) & 0xff
      g = (color >> 8) & 0xff
      b = color & 0xff
      
      # In grayscale, R, G, B should be equal
      assert_equal r, g
      assert_equal g, b
    end
  end
end