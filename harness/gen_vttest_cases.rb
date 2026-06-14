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
  # Backspace from the pending-wrap state (after printing in the last
  # column, the cursor parks past it) clears the pending wrap and stays on
  # the last column rather than stepping back two: 'B' lands in the last
  # column, BS returns to it, the space overwrites 'B', and 'b' then wraps
  # to the next row. (From vttest's autowrap test.)
  "bs-pending-wrap" => "\e[?7h\e[1;80HB\b b",

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

  # --- Control characters inside escape sequences ---------------------
  # A C0 control byte inside a CSI is executed immediately while the CSI
  # keeps parsing (vttest "cursor-control chars inside ESC sequences").
  # The BS inside the SGR moves the cursor back, so Z overwrites 'c' -> abZ.
  "ctrl-in-csi"     => "abc\e[\b41mZ",
  # A CR inside the CSI returns to column 0 mid-sequence; the CUP then still
  # completes. 'Y' lands at the CUP target, 'Z' (after) at column 1.
  "cr-in-csi"       => "abcdef\e[1\r;3HY",
  # vttest "cursor-control characters inside ESC sequences": the four lines
  # must render identically ("A B C D E F G H I"). Each uses a different C0
  # control embedded in a CSI - BS, CR, and VT. The VT line first resets LNM
  # (CSI 20 l) so VT only moves down (no carriage return), letting the CSI A
  # (cursor up) cancel it; this needs LNM default-off and standard CSI 20 l.
  "csi-embedded-controls" =>
    "\e[2J\e[1;1HA B C D E F G H I" \
    "\e[3;1HA\e[2\bCB\e[2\bCC\e[2\bCD\e[2\bCE\e[2\bCF\e[2\bCG\e[2\bCH\e[2\bCI\e[2\bC" \
    "\e[5;1HA \e[\r2CB\e[\r4CC\e[\r6CD\e[\r8CE\e[\r10CF\e[\r12CG\e[\r14CH\e[\r16CI" \
    "\e[7;1H\e[20lA \e[1\vAB \e[1\vAC \e[1\vAD \e[1\vAE \e[1\vAF \e[1\vAG \e[1\vAH \e[1\vAI \e[1\vA",

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
