require_relative 'test_helper'

class TestEscapeParser < Minitest::Test
  def setup
    @parser = create_escape_parser
  end

  def test_initialization
    skip "EscapeParser not available" unless @parser
    
    refute @parser.complete?
    assert_equal "", @parser.str
  end

  def test_simple_escape_sequence
    skip "EscapeParser not available" unless @parser
    
    # ESC [ 2 J (clear screen)
    @parser.put(0x1b)  # ESC
    refute @parser.complete?
    
    @parser.put(?[.ord)
    refute @parser.complete?
    
    @parser.put(?2.ord)
    refute @parser.complete?
    
    @parser.put(?J.ord)
    assert @parser.complete?
    assert_equal "[2J", @parser.str
  end

  def test_escape_with_parameters
    skip "EscapeParser not available" unless @parser
    
    # ESC [ 10 ; 20 H (cursor position)
    @parser.put(0x1b)  # ESC
    @parser.put(?[.ord)
    @parser.put(?1.ord)
    @parser.put(?0.ord)
    @parser.put(?;.ord)
    @parser.put(?2.ord)
    @parser.put(?0.ord)
    @parser.put(?H.ord)
    
    assert @parser.complete?
    assert_equal "[10;20H", @parser.str
  end

  def test_dec_private_mode
    skip "EscapeParser not available" unless @parser
    
    # ESC [ ? 25 h (show cursor)
    @parser.put(0x1b)  # ESC
    @parser.put(?[.ord)
    @parser.put(??.ord)
    @parser.put(?2.ord)
    @parser.put(?5.ord)
    @parser.put(?h.ord)
    
    assert @parser.complete?
    assert_equal "[?25h", @parser.str
  end

  def test_simple_escape
    skip "EscapeParser not available" unless @parser
    
    # ESC D (line feed)
    @parser.put(0x1b)  # ESC
    @parser.put(?D.ord)
    
    assert @parser.complete?
    assert_equal "D", @parser.str
  end

  def test_dcs_terminated_by_st
    skip "EscapeParser not available" unless @parser

    # ESC P ! | 00000000 ESC \ (DA2-style DCS response)
    "\eP!|00000000\e\\".each_byte do |b|
      @parser.put(b)
    end

    assert @parser.complete?
    assert_equal "P!|00000000", @parser.str
  end

  def test_dcs_terminated_by_bel
    skip "EscapeParser not available" unless @parser

    # ESC P ! | 00000000 BEL
    "\eP!|00000000\a".each_byte do |b|
      @parser.put(b)
    end

    assert @parser.complete?
    assert_equal "P!|00000000", @parser.str
  end

  def test_osc_title_with_multibyte_codepoint
    skip "EscapeParser not available" unless @parser

    # OSC set-title carrying a multibyte glyph (U+2733 ✳, as in claude's
    # spinner title). The decoder delivers it as one codepoint, not raw
    # bytes; bare Integer#chr raises RangeError on codepoints > 255.
    [0x1b, ?].ord, ?0.ord, ?;.ord, 0x2733, ?X.ord, 7].each { |cp| @parser.put(cp) }

    assert @parser.complete?
    assert_equal "]0;✳X", @parser.str
  end
end