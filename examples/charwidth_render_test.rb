#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Visual render test for character width + emoji-presentation handling.
#
#   ruby examples/charwidth_render_test.rb
#
# Run it *inside* rubyterm (or any terminal, for comparison). It writes plain
# UTF-8 + ANSI, but is designed to make width/colour bugs obvious to the eye:
# every sample is framed by box borders whose interior is exactly as many
# columns as CharWidth says the sample occupies. So:
#
#   * If a glyph stays inside its borders and the right '│' lines up with the
#     rule above it, the cell width is honoured.  CORRECT.
#   * If a glyph spills past the right '│' (e.g. a colour emoji square crammed
#     into a single cell), the border is breached.  WRONG.
#   * A trailing sentinel column ('#') sits one cell to the right of each box;
#     if it gets painted over, something overwrote the next column.
#
# The tricky cases this guards:
#   - U+FE0F (VS16) and combining marks are zero-width: a base+VS16 box must be
#     the SAME width as the base alone, and a lone selector draws nothing.
#   - Text-presentation dingbats (❤ ✔ ⚠) are width 1 and render monochrome;
#     they must NOT balloon into a 2-cell colour square.
#   - Genuine emoji-presentation codepoints (⚡ ✨ 😀) are width 2 and colour,
#     and should fill their 2-cell box exactly.

require_relative "../lib/charwidth"

def cp_width(str) = str.codepoints.sum { |c| CharWidth.width(c) }
def colour(code, s) = "\e[#{code}m#{s}\e[0m"

# A single framed sample, returned as three stacked strings (top/mid/bottom)
# plus its total drawn width including the sentinel gap, so a row of samples
# can be laid out side by side.
def box(sample)
  w = [cp_width(sample), 1].max          # at least one interior column
  top = "┌" + ("─" * w) + "┐"
  # Pad the sample on the right to its declared width so the closing border
  # sits exactly where the next cell begins. A correctly-sized glyph reaches
  # the border; an oversized one punches through it.
  pad = w - cp_width(sample)
  mid = "│" + sample + (" " * pad) + "│" + colour("90", "#")
  bot = "└" + ("─" * w) + "┘"
  [top, mid, bot]
end

# Render a labelled group of samples as a row of boxes with a caption line.
def group(title, samples)
  puts colour("1;36", title)
  rows = samples.map { |s| box(s) }
  3.times do |i|
    puts "  " + rows.map { |r| r[i] }.join("  ")
  end
  caption = samples.map do |s|
    cps = s.codepoints.map { |c| format("U+%04X", c) }.join("+")
    "#{cps} w=#{cp_width(s)}"
  end
  puts "  " + colour("90", caption.join("   "))
  puts
end

VS16 = "\u{FE0F}"          # emoji-presentation selector (zero-width)
VS15 = "\u{FE0E}"          # text-presentation selector (zero-width)

puts colour("1;37", "── CharWidth render test ──")
puts "Borders frame exactly CharWidth.width columns. Glyphs must stay inside;"
puts "the grey '#' marks the next cell and must remain untouched."
puts

# A countable ruler so you can verify column alignment by eye.
puts colour("90", "ruler   " + ("0123456789" * 4))
puts

group("emoji presentation — width 2, colour (must fill the 2-cell box):",
      ["\u{1F600}", "\u{1F680}", "\u{26A1}", "\u{2728}", "\u{2705}", "\u{274C}", "\u{2B50}"])

group("text presentation — width 1, MONOCHROME (must not overflow):",
      ["\u{2764}", "\u{2714}", "\u{2702}", "\u{26A0}", "\u{2716}", "\u{273B}"])

group("base + VS16 — same width as the base, selector is invisible & zero-width:",
      ["\u{26A0}#{VS16}", "\u{2764}#{VS16}", "\u{2714}#{VS16}", "\u{2705}#{VS16}"])

group("text selector (VS15) & combining marks — zero width:",
      ["a#{VS15}", "e\u{0301}", "n\u{0303}", "lone#{VS16}"])

group("CJK / fullwidth — width 2, NOT colour:",
      ["\u{4E00}", "\u{AC00}", "\u{FF21}"])

# The exact paste from the bug report: ⚠ + VS16 + " Separate red". The warning
# sign must render in one cell with the text flush after it — no doubled glyph.
puts colour("1;36", "bug-report line (U+26A0 U+FE0F + text):")
line = "\u{26A0}#{VS16} Separate red"
puts "  ┌" + ("─" * cp_width(line)) + "┐"
puts "  │" + line + "│"
puts "  └" + ("─" * cp_width(line)) + "┘"
puts "  " + colour("90", "drawn width = #{cp_width(line)} columns")
puts
