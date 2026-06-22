#!/usr/bin/env ruby
# frozen_string_literal: true
#
# A quick colour-emoji + double-width showcase. Run it *inside* rubyterm:
#
#   rake run            # then, at the shell in the new window:
#   ruby examples/emoji_demo.rb
#
# It just writes UTF-8 + ANSI to stdout (works in any terminal), but shows off
# what the new rubyterm gained: colour emoji (from Noto Color Emoji) and
# correct double-width cells - the box borders only line up if each emoji
# occupies two cells.

def colour(code, str) = "\e[#{code}m#{str}\e[0m"

puts colour("1;36", "rubyterm emoji demo")
puts
puts "faces    \u{1F600} \u{1F642} \u{1F60E} \u{1F914} \u{1F60D}"
puts "status   #{colour('32', "pass \u{2705}")}   #{colour('31', "fail \u{274C}")}   #{colour('33', "warn \u{26A0}")}"
puts "objects  \u{1F680} \u{1F525} \u{2B50} \u{1F4A1} \u{1F4BB}"
puts "hearts   \u{2764} \u{1F9E1} \u{1F49B} \u{1F49A} \u{1F499} \u{1F49C}"
puts "animals  \u{1F436} \u{1F431} \u{1F438} \u{1F984} \u{1F419}"
puts
puts "double-width alignment (borders line up iff emoji are 2 cells wide):"
puts "  ┌──────┐"
puts "  │ \u{1F600}\u{1F389} │"
puts "  │ ab\u{1F44D} │"
puts "  │ 1234 │"
puts "  └──────┘"
