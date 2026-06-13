#!/usr/bin/env ruby
#
# Generates the synthetic starter corpus in cases/synthetic/. Cases are
# committed; re-run this only when adding cases (output is
# deterministic).
#
#   ruby harness/gen_cases.rb

dir = File.expand_path("../cases/synthetic", __dir__)
require 'fileutils'
FileUtils.mkdir_p(dir)

CASES = {
  # Plain text and basic line discipline
  "text-basic"      => "Hello, world!",
  "text-crlf"       => "line one\r\nline two\r\nline three",
  "text-wrap"       => ("ab" * 50) + "WRAPPED", # > 80 cols forces autowrap
  "text-utf8"       => "nærmest å være — éèê 你好",
  "backspace"       => "abcdef\b\b\bXY",
  "tabs"            => "a\tb\tc\td",

  # Cursor movement
  "cursor-cup"      => "\e[5;10HX\e[1;1HY\e[24;80HZ",
  "cursor-rel"      => "base\e[3BX\e[2AY\e[10CZ\e[5DW",
  "cursor-cha-vpa"  => "\e[4;4Hmid\e[10GX\e[5dY",
  "cursor-save"     => "\e[3;3HA\e7\e[10;10HB\e8C",

  # Erase operations
  "el-variants"     => "aaaaaaaaaa\e[1;5H\e[0K\r\nbbbbbbbbbb\e[2;5H\e[1K\r\ncccccccccc\e[3;5H\e[2K",
  "ed-below"        => "1111\r\n2222\r\n3333\r\n4444\e[2;2H\e[0J",
  "ed-above"        => "1111\r\n2222\r\n3333\r\n4444\e[3;3H\e[1J",
  "ed-all"          => "1111\r\n2222\r\n3333\e[2J\e[5;5Hclean",

  # Insert/delete
  "ich"             => "abcdefgh\e[1;3H\e[3@",
  "dch"             => "abcdefgh\e[1;3H\e[3P",
  "il"              => "one\r\ntwo\r\nthree\e[2;1H\e[2L",
  "dl"              => "one\r\ntwo\r\nthree\r\nfour\e[2;1H\e[2M",

  # Scrolling
  "scroll-lf"       => (1..30).map { |i| "line #{i}" }.join("\r\n"),
  "scroll-region"   => "\e[5;10rtop\e[10;1Hbottom" + ("\r\nfill" * 8) + "\e[r",
  "scroll-su-sd"    => "aaa\r\nbbb\r\nccc\e[2S",
  "ri-at-top"       => "\e[1;1Hfirst\eMsecond",
  "ind-nel"         => "\e[3;5Habc\eDx\eEy",

  # Attributes
  "sgr-basic"       => "\e[1mbold\e[0m \e[4munder\e[0m \e[7minv\e[0m \e[31mred\e[42mongreen\e[0m",
  "sgr-256-rgb"     => "\e[38;5;196mF196\e[48;5;21mB21\e[0m \e[38;2;1;2;3mRGB\e[0m",

  # DEC specials
  "decaln"          => "\e#8",
  "deccolm-reset"   => "before\e[?3l after",
  "origin-mode"     => "\e[5;20r\e[?6h\e[1;1HX\e[?6l\e[r",
  "autowrap-off"    => "\e[?7l" + ("x" * 100) + "END\e[?7h",
  "charset-dec"     => "\e(0lqqqk\e(B plain \x0elqk\x0f done",
  "tabstops-custom" => "\e[3g\e[1;9H\eH\e[1;17H\eH\r\na\tb\tc",
  # OSC set-title containing a multibyte glyph (✳, as in claude's spinner
  # title). The title must not corrupt the grid, and must not crash the
  # parser (bare Integer#chr raised RangeError on codepoints > 255).
  "osc-title-utf8"  => "\e]0;✳ Claude\aHi",

  # Reports: the terminal's query replies are captured and the
  # `responses` check feeds them to the tmux oracle as host input, so a
  # reply the host cannot consume (wrong type for the query) and leaks to
  # the pane fails. DA2 (`\e[>c`) is the sequence whose reply leaked
  # `^[P!|00000000^[\` on screen.
  "dsr-da"          => "ask\e[6n\e[c done",
  "da2-reply"       => "\e[>c",
}

CASES.each do |name, bytes|
  File.binwrite(File.join(dir, "#{name}.bin"), bytes.b)
end

puts "wrote #{CASES.size} cases to #{dir}"
