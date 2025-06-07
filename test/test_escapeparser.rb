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
end