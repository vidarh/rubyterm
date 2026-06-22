# frozen_string_literal: true

# Character-cell width and emoji classification, by Unicode codepoint.
#
# Terminal column width must be a property of the codepoint (not the rendered
# glyph), so that applications running inside the terminal — which compute their
# own layout from the same Unicode width — stay in sync. These tables are the
# canonical East Asian Wide/Fullwidth + emoji blocks (UCD 13.0), curated to the
# substantial ranges; they're a couple of KB and drive two decisions:
#
#   * width(cp)  -> 1 or 2 cells (wide = CJK/Hangul/Kana/fullwidth + emoji)
#   * emoji?(cp) -> whether to render in colour (the non-CJK wide blocks)
#
# Combining marks (width 0) are deliberately not handled yet (treated as 1).
module CharWidth
  # Wide (two-cell) blocks: CJK, Hangul, Kana, fullwidth forms, and emoji.
  WIDE = [
    0x1100..0x115F, 0x231A..0x232A, 0x23E9..0x23F3, 0x25FD..0x27BF,
    0x2B1B..0x2B55, 0x2E80..0xA4C6, 0xA960..0xA97C, 0xAC00..0xD7A3,
    0xF900..0xFAD9, 0xFE10..0xFE6B, 0xFF01..0xFF60, 0xFFE0..0xFFE6,
    0x16FE0..0x18D08, 0x1B000..0x1B2FB, 0x1F18E..0x1F19A, 0x1F200..0x1F265,
    0x1F300..0x1F5A4, 0x1F5FB..0x1F6FC, 0x1F7E0..0x1F7EB, 0x1F90C..0x1F9FF,
    0x1FA70..0x1FAD6, 0x20000..0x2EBE0, 0x2F800..0x2FA1D, 0x30000..0x3134A
  ].freeze

  # The emoji subset of WIDE (excludes CJK/Hangul/Kana/fullwidth): these render
  # in colour when a colour font provides them. Digits, '#', '*' etc. are not
  # here, so they stay as ordinary text even though Noto maps colour keycaps.
  EMOJI = [
    0x231A..0x232A, 0x23E9..0x23F3, 0x25FD..0x27BF, 0x2B1B..0x2B55,
    0x1F18E..0x1F19A, 0x1F200..0x1F265, 0x1F300..0x1F5A4, 0x1F5FB..0x1F6FC,
    0x1F7E0..0x1F7EB, 0x1F90C..0x1F9FF, 0x1FA70..0x1FAD6
  ].freeze

  module_function

  # Number of terminal cells a codepoint occupies (1 or 2).
  def width(cp)
    return 1 if cp < 0x1100      # fast path: ASCII/Latin and most text
    in_ranges?(WIDE, cp) ? 2 : 1
  end

  def wide?(cp) = width(cp) == 2

  # Whether a codepoint should render as a colour emoji (when the font has it).
  def emoji?(cp)
    return false if cp < 0x231A
    in_ranges?(EMOJI, cp)
  end

  # Binary search over a sorted array of non-overlapping ranges.
  def in_ranges?(ranges, cp)
    lo = 0
    hi = ranges.length - 1
    while lo <= hi
      mid = (lo + hi) / 2
      r = ranges[mid]
      if cp < r.begin then hi = mid - 1
      elsif cp > r.end then lo = mid + 1
      else return true
      end
    end
    false
  end
end
