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
    [0x1F600, 0x1F44D, 0x1F389, 0x1F680].each do |cp|
      assert_equal 2, CharWidth.width(cp), format("U+%04X", cp)
    end
  end

  # Text-presentation dingbats (no VS16) occupy one column, matching tmux. A
  # wrong width here shifts every line that uses the character. U+273B (✻) is a
  # plain dingbat: width 1, not an emoji.
  def test_text_presentation_emoji_and_dingbats_are_single_width
    [0x2764, 0x2702, 0x2716, 0x273B, 0x26A0, 0x2714].each do |cp|
      assert_equal 1, CharWidth.width(cp), format("U+%04X", cp)
    end
  end

  def test_emoji_predicate_true_for_emoji
    # Emoji-presentation codepoints: in an emoji block AND width 2, so a square
    # colour glyph fits. (Flags/ZWJ sequences are a deferred non-goal, so lone
    # regional indicators stay text for now.)
    [0x1F600, 0x1F44D, 0x1F389, 0x26A1, 0x2728, 0x2705, 0x1F525, 0x1F680].each do |cp|
      assert CharWidth.emoji?(cp), format("U+%04X should be emoji", cp)
    end
  end

  def test_emoji_predicate_false_for_text_and_cjk
    # Digits, '#', '*' (Noto maps colour keycaps for these — must stay text),
    # CJK (wide but not colour), and width-1 text-presentation dingbats: a
    # colour glyph is ~2 cells wide, so colouring a 1-cell char would overflow
    # the next column (U+2764 ❤, U+2714 ✔, U+26A0 ⚠ render as plain text).
    [0x30, 0x39, 0x23, 0x2A, 0x41, 0x20, 0x4E00, 0xAC00,
     0x2764, 0x2714, 0x26A0, 0x2702].each do |cp|
      refute CharWidth.emoji?(cp), format("U+%04X must not be emoji", cp)
    end
  end

  # Variation selectors and combining marks are zero-width: they modify the
  # preceding glyph and must not advance the cursor. tmux reports cursor_x=0
  # for a lone U+FE0F and keeps base+VS16 at the base's own width.
  def test_zero_width_modifiers
    [0x0301,   # combining acute accent
     0xFE0F,   # VS16 (emoji presentation selector)
     0xFE0E,   # VS15 (text presentation selector)
     0x200D,   # zero-width joiner
     0x200B,   # zero-width space
     0xE0101   # variation selector supplement
    ].each do |cp|
      assert_equal 0, CharWidth.width(cp), format("U+%04X", cp)
    end
  end
end
