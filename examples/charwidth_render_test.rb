#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Visual render test for character width + emoji-presentation handling.
#
#   ruby examples/charwidth_render_test.rb           # in a checkout
#   bundle exec rubyterm 'ruby examples/charwidth_render_test.rb'
#
# Run it *inside* rubyterm (or any terminal, for comparison). It writes plain
# UTF-8 + ANSI, but is designed to make width/colour bugs obvious to the eye:
# every sample is framed by box borders whose interior is exactly as many
# columns as CharWidth says the sample occupies. Read it like this:
#
#   * Borders line up in neat columns and each glyph sits fully inside its
#     box, not touching or crossing the right '│'  ->  width is honoured.
#   * A glyph that spills past its right '│' (e.g. a colour-emoji square
#     crammed into a single cell) is overflowing  ->  WRONG.
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

# One framed sample as three stacked strings (top / middle / bottom). All three
# are exactly the same display width, so a row of boxes stays column-aligned.
def box(sample)
  w   = [cp_width(sample), 1].max         # at least one interior column
  pad = " " * (w - cp_width(sample))      # right-pad to the declared width
  ["┌" + ("─" * w) + "┐",
   "│" + sample + pad + "│",
   "└" + ("─" * w) + "┘"]
end

# A labelled row of boxes plus a caption listing each sample's codepoints/width.
def group(title, samples)
  puts colour("1;36", title)
  rows = samples.map { |s| box(s) }
  3.times { |i| puts "  " + rows.map { |r| r[i] }.join("   ") }
  caption = samples.map do |s|
    s.codepoints.map { |c| format("U+%04X", c) }.join("+") + " w=#{cp_width(s)}"
  end
  puts "  " + colour("90", caption.join("    "))
  puts
end

VS16 = "\u{FE0F}"          # emoji-presentation selector (zero-width)
VS15 = "\u{FE0E}"          # text-presentation selector (zero-width)

puts colour("1;37", "── CharWidth render test ──")
puts "Each glyph must sit fully inside its box. Borders should line up in"
puts "columns; a glyph crossing its right '│' is overflowing its cell."
puts

group("emoji presentation — width 2, colour (must fill the 2-cell box):",
      ["\u{1F600}", "\u{1F680}", "\u{26A1}", "\u{2728}", "\u{2705}", "\u{274C}", "\u{2B50}"])

group("text presentation — width 1, MONOCHROME (must not overflow):",
      ["\u{2764}", "\u{2714}", "\u{2702}", "\u{26A0}", "\u{2716}", "\u{273B}"])

group("base + VS16 — same width as the base, selector is invisible & zero-width:",
      ["\u{26A0}#{VS16}", "\u{2764}#{VS16}", "\u{2714}#{VS16}", "\u{2705}#{VS16}"])

group("text selector (VS15) & combining marks — zero width:",
      ["a#{VS15}", "e\u{0301}", "n\u{0303}", "lo#{VS16}ng"])

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
