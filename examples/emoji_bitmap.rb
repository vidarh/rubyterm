#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Renders a few lines of text + colour emoji through the real Term core into
# the headless BitmapWindow backend, and saves a PNG. Demonstrates the 4-byte
# UTF-8 path, double-width cells, the emoji colour gate, and RGBA compositing -
# no X server required.
#
#   ruby examples/emoji_bitmap.rb [out.png]
#
# Needs a monospace font (DejaVu Sans Mono) and, for colour, Noto Color Emoji.

require "stringio"

here = __dir__
# Allow running from a source checkout with sibling skrift gems.
%w[skrift skrift-color skrift-boxdrawing].each do |g|
  d = File.expand_path("#{here}/../../#{g}/lib")
  $LOAD_PATH.unshift(d) if File.directory?(d)
end
require_relative "#{here}/../lib/termbuffer"
require_relative "#{here}/../lib/term"
require_relative "#{here}/../lib/trackchanges"
require_relative "#{here}/../lib/windowadapter"
require_relative "#{here}/../lib/bitmapwindow"

# Minimal host the WindowAdapter needs.
class Host
  attr_accessor :term_width
  def initialize(c) = (@term_width = c)
  def blink_state = false
  def rblink_state = false
  def set_columns(_) = nil
end

COLS = 28
ROWS = 6
out  = ARGV[0] || "emoji.png"

win = BitmapWindow.new(COLS, ROWS, size: 28)
tc  = TrackChanges.new(TermBuffer.new, WindowAdapter.new(win, Host.new(COLS)))
term = Term.new(tc)
term.resize(COLS, ROWS)
tc.on_resize(COLS, ROWS)

lines = [
  "\e[1;33mruby-term\e[0m emoji \u{1F600}\u{1F389}",
  "build passing \u{2705}  failed \u{274C}",
  "deploy \u{1F680}  fire \u{1F525}  star \u{2B50}",
  "hearts \u{2764}\u{1F49B}\u{1F49A}  weather \u{2600}\u{26C8}",
  "mix: a\u{1F44D}b\u{1F436}c done.",
]

old = $stdout
$stdout = StringIO.new # quiet skrift's compound-glyph debug
term.feed("\e[2J\e[H".b)
lines.each_with_index { |l, i| term.feed("\e[#{i + 1};1H#{l}".b) }
tc.draw_flush
$stdout = old

win.save_png(out)
puts "wrote #{out} (#{win.width}x#{win.height})"
