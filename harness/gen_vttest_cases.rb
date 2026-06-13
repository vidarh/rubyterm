#!/usr/bin/env ruby
#
# Generates vttest-derived cases in cases/vttest/. These mirror the
# individual VT100 behaviours exercised by Thomas Dickey's `vttest`
# (menu 1 "cursor movements" and menu 2 "screen features"), reduced to
# clean, minimal byte streams the tmux state oracle can compare directly.
# Captured real vttest output was used as a reference for the exact
# control sequences; the cases here are the distilled per-behaviour
# checks, not the full interactive screens.
#
# Re-run only when adding cases (output is deterministic):
#   ruby harness/gen_vttest_cases.rb
#
# A case may carry a sibling <name>.meta.json (see docs/harness.md) when
# an oracle divergence is by design.

dir = File.expand_path("../cases/vttest", __dir__)
require 'fileutils'
require 'json'
FileUtils.mkdir_p(dir)

# name => bytes
CASES = {
  # --- Tab stops (HTS / TBC) -------------------------------------------
  # Default tab stops are every 8 columns. Clear the stop at col 9 with
  # TBC(0), set a new one at col 12 with HTS, then walk tabs from home.
  "tab-set-clear"   => "\e[1;9H\e[g\e[1;12H\eH\e[1;1H\tA\tB\tC",
  # TBC(3) clears ALL tab stops; a TAB with no stop remaining then runs to
  # the last column, so 'END' wraps from there.
  "tab-clear-all"   => "\e[3gstart\r\n\tEND",

  # --- Autowrap (DECAWM) ----------------------------------------------
  # With autowrap on, text past the right margin wraps to the next row.
  "autowrap-edge"   => "\e[?7h\e[1;79HXYZ\e[2;1HQ",

  # --- Cursor clamping at the margins ---------------------------------
  # CUF/CUB past the edges clamp at column 1 / last column; BS at col 1
  # does not move off the row.
  "cursor-clamp"    => "\e[1;1H\e[20DLEFT\e[1;78H\e[20CRIGHT",
  "bs-at-col1"      => "\e[2;1H\bX",

  # --- Index / Reverse Index / Next Line at region edges --------------
  # RI (ESC M) at the top of a scroll region scrolls the region DOWN,
  # leaving the cursor on the top line: 'A' moves to row 3, 'B' lands on
  # row 2.
  "ri-at-region-top"     => "\e[2;4r\e[2;1HA\eMB",
  # IND (ESC D) at the bottom of a scroll region scrolls the region UP,
  # leaving the cursor on the bottom line.
  "ind-at-region-bottom" => "\e[2;4r\e[4;1HA\eDB",
  # NEL (ESC E) returns to column 1 of the next line, scrolling at the
  # bottom margin.
  "nel-scroll"      => "\e[5;1HA\eEB\eEC",

  # --- DECSC / DECRC ---------------------------------------------------
  # Save cursor + attributes, move and change them, then restore: the
  # final write lands at the saved position. (Attribute restore is also
  # exercised; the tmux oracle does not yet compare SGR, so this checks
  # position + text.)
  "decsc-decrc"     => "\e[5;5H\e[1;31m\e7\e[10;40H\e[0mZ\e8R",
}

# Sidecars for designed oracle divergences.
METAS = {}

CASES.each do |name, bytes|
  File.binwrite(File.join(dir, "#{name}.bin"), bytes.b)
end
METAS.each do |name, meta|
  File.write(File.join(dir, "#{name}.meta.json"), JSON.pretty_generate(meta) + "\n")
end

puts "wrote #{CASES.size} vttest cases (#{METAS.size} metas) to #{dir}"
