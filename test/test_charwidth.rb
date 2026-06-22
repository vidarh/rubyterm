# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/charwidth"

class TestCharWidth < Minitest::Test
  def test_ascii_and_latin_are_single_width
    "Ai0 #*~é".each_char { |c| assert_equal 1, CharWidth.width(c.ord), c.inspect }
  end

  def test_cjk_hangul_kana_fullwidth_are_double_width
    [0x4E00, 0x3042, 0xAC00, 0xFF21, 0x6F22].each do |cp|
      assert_equal 2, CharWidth.width(cp), format("U+%04X", cp)
    end
  end

  def test_emoji_are_double_width
    [0x1F600, 0x1F44D, 0x1F389, 0x1F680, 0x2764].each do |cp|
      assert_equal 2, CharWidth.width(cp), format("U+%04X", cp)
    end
  end

  def test_emoji_predicate_true_for_emoji
    # Single-codepoint emoji. (Flags/ZWJ sequences are a deferred non-goal, so
    # lone regional indicators stay text for now.)
    [0x1F600, 0x1F44D, 0x1F389, 0x2764, 0x1F525, 0x1F680].each do |cp|
      assert CharWidth.emoji?(cp), format("U+%04X should be emoji", cp)
    end
  end

  def test_emoji_predicate_false_for_text_and_cjk
    # Digits, '#', '*' (Noto maps colour keycaps for these — must stay text),
    # and CJK (wide but not colour).
    [0x30, 0x39, 0x23, 0x2A, 0x41, 0x20, 0x4E00, 0xAC00].each do |cp|
      refute CharWidth.emoji?(cp), format("U+%04X must not be emoji", cp)
    end
  end

  def test_combining_marks_treated_as_width_one_for_now
    assert_equal 1, CharWidth.width(0x0301) # combining acute (deferred)
  end
end
