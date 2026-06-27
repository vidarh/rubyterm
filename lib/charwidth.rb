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
module CharWidth
  # Codepoint stored in the second cell of a double-width glyph: a blank,
  # advancing placeholder. The terminal writes it after a wide char so the
  # next column is reserved; the X11 backend renders codepoint 0 as a blank
  # advancing glyph and the bitmap/virtual backends skip it.
  WIDE_SPACER = 0

  # Zero-width (combining) codepoints. These modify the preceding base glyph
  # rather than advancing the cursor, so they occupy no column — matching tmux
  # (a lone U+FE0F reports cursor_x=0; a base+U+FE0F sequence stays the base's
  # width). Notably this includes the variation selectors: U+FE0F (VS16, emoji
  # presentation) and U+FE0E (VS15, text presentation) request a presentation
  # for the preceding char but are themselves invisible and zero-width. Treating
  # them as width 1 gave each its own cell, drawing a stray glyph over the next
  # column. Per-script combining marks beyond these blocks are a deferred
  # non-goal (still treated as width 1).
  ZERO = [
    0x0300..0x036F,  # combining diacritical marks
    0x1AB0..0x1AFF,  # combining diacritical marks extended
    0x1DC0..0x1DFF,  # combining diacritical marks supplement
    0x200B..0x200F,  # ZWSP, ZWNJ, ZWJ, LRM, RLM (zero-width format)
    0x20D0..0x20FF,  # combining diacritical marks for symbols
    0xFE00..0xFE0F,  # variation selectors (incl. VS15/VS16)
    0xFE20..0xFE2F,  # combining half marks
    0xE0100..0xE01EF # variation selectors supplement
  ].freeze

  # Wide (two-cell) blocks: CJK, Hangul, Kana, fullwidth forms, and emoji.
  #
  # In the BMP symbol zone (Misc Symbols, Dingbats, Misc Symbols & Arrows)
  # only the East Asian Wide + emoji-presentation codepoints are double-width;
  # the surrounding text dingbats are single-width. A broad 0x25FD..0x27BF (and
  # peers) wrongly widened text characters like U+273B (the spinner ✻ used by
  # TUIs), shifting the cursor one column on every line that contained one and
  # corrupting incremental redraws. These ranges now match tmux exactly.
  WIDE = [
    0x1100..0x115F,
    0x231A..0x231B, 0x2329..0x232A, 0x23E9..0x23EC, 0x23F0..0x23F0,
    0x23F3..0x23F3, 0x25FD..0x25FE, 0x2614..0x2615, 0x2648..0x2653,
    0x267F..0x267F, 0x2693..0x2693, 0x26A1..0x26A1, 0x26AA..0x26AB,
    0x26BD..0x26BE, 0x26C4..0x26C5, 0x26CE..0x26CE, 0x26D4..0x26D4,
    0x26EA..0x26EA, 0x26F2..0x26F3, 0x26F5..0x26F5, 0x26FA..0x26FA,
    0x26FD..0x26FD, 0x2705..0x2705, 0x270A..0x270B, 0x2728..0x2728,
    0x274C..0x274C, 0x274E..0x274E, 0x2753..0x2755, 0x2757..0x2757,
    0x2795..0x2797, 0x27B0..0x27B0, 0x27BF..0x27BF, 0x2B1B..0x2B1C,
    0x2B50..0x2B50, 0x2B55..0x2B55,
    0x2E80..0xA4C6, 0xA960..0xA97C, 0xAC00..0xD7A3,
    0xF900..0xFAD9, 0xFE10..0xFE6B, 0xFF01..0xFF60, 0xFFE0..0xFFE6,
    0x16FE0..0x18D08, 0x1B000..0x1B2FB, 0x1F18E..0x1F19A, 0x1F200..0x1F265,
    0x1F300..0x1F5A4, 0x1F5FB..0x1F6FC, 0x1F7E0..0x1F7EB, 0x1F90C..0x1F9FF,
    0x1FA70..0x1FAD6, 0x20000..0x2EBE0, 0x2F800..0x2FA1D, 0x30000..0x3134A
  ].freeze

  # Emoji code blocks (excludes CJK/Hangul/Kana/fullwidth): a codepoint renders
  # in colour only if it is BOTH in one of these blocks AND wide (width 2) —
  # see emoji?. The width-2 gate is what distinguishes emoji-presentation
  # codepoints (⚡ U+26A1, ✨ U+2728 — colour, width 2) from text-presentation
  # dingbats that merely share a block (❤ U+2764, ✔ U+2714, ⚠ U+26A0 — width 1).
  # Both properties derive from the same Unicode Emoji_Presentation flag, so
  # this is not "width deciding colour": rather, colour is the subset of these
  # blocks that is wide enough to render a square colour glyph without spilling
  # into the next cell. Digits, '#', '*' are absent, so they stay ordinary text
  # even though Noto maps colour keycaps.
  EMOJI = [
    0x231A..0x232A, 0x23E9..0x23F3, 0x25FD..0x27BF, 0x2B1B..0x2B55,
    0x1F18E..0x1F19A, 0x1F200..0x1F265, 0x1F300..0x1F5A4, 0x1F5FB..0x1F6FC,
    0x1F7E0..0x1F7EB, 0x1F90C..0x1F9FF, 0x1FA70..0x1FAD6
  ].freeze

  module_function

  # Number of terminal cells a codepoint occupies (0, 1 or 2).
  def width(cp)
    return 1 if cp < 0x0300      # fast path: ASCII/Latin-1 (no combining below)
    return 0 if in_ranges?(ZERO, cp)
    return 1 if cp < 0x1100      # fast path: most other text
    in_ranges?(WIDE, cp) ? 2 : 1
  end

  def wide?(cp) = width(cp) == 2

  # Whether a codepoint should render as a colour emoji (when the font has it).
  # Gated to width-2 emoji: a colour glyph is rasterised square (~2 cells wide),
  # so colouring a width-1 cell would overflow and corrupt the next column.
  def emoji?(cp)
    return false if cp < 0x231A
    in_ranges?(EMOJI, cp) && width(cp) == 2
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
