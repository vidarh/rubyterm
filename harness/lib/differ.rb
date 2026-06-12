# Diffs two state dumps (ours vs the oracle's) into a structured list
# of mismatches. The oracle dump may be partial - only the fields it
# provides are compared - so the same differ serves the full-schema
# self-comparison (save/load round trips) and the text-level tmux
# oracle.
#
# Normalizations are explicit and centralized here so suppressions are
# visible and reviewable:
# * a nil cell is equivalent to a space (cleared vs never-written)
# * cursor col is clamped to cols-1 on both sides: implementations
#   represent the deferred-wrap state differently (tmux reports
#   cursor_x == cols, we keep x == width), and pending_wrap is the
#   single most common differential-testing discrepancy between
#   terminal implementations
# * an expected cell that maps onto the got cell through the DEC
#   special graphics charset counts as equal: tmux's capture-pane
#   emits the *undesignated* character ("q"), while we translate at
#   write time ("─"). Cost: a missing-translation bug in our terminal
#   is invisible to the text oracle (the marker/redraw checks and
#   future attribute capture still apply).
module Harness
  module Differ
    # expected: oracle dump, got: our dump.
    # Returns a list of {"type" =>, "row" =>, "col" =>, "expected" =>, "got" =>}
    def self.diff(expected, got)
      out = []

      if expected["cells"]
        rows = [expected["cells"].length, got["cells"].length].max
        rows.times do |y|
          erow = expected["cells"][y] || []
          grow = got["cells"][y] || []
          cols = [erow.length, grow.length].max
          cols.times do |x|
            e = cell_ch(erow[x])
            g = cell_ch(grow[x])
            next if e == g
            next if GraphicsCharset[e.ord] == g # see normalization note
            out << { "type" => "cell", "row" => y, "col" => x,
                     "expected" => e, "got" => g }
          end
        end
      end

      if ec = expected["cursor"]
        gc = got["cursor"]
        maxcol = (got["cols"] || expected["cols"]) - 1
        ecol = [ec["col"], maxcol].min
        gcol = [gc["col"], maxcol].min
        if ec["row"] != gc["row"] || ecol != gcol
          out << { "type" => "cursor",
                   "expected" => { "row" => ec["row"], "col" => ecol },
                   "got" => { "row" => gc["row"], "col" => gcol } }
        end
      end

      out
    end

    def self.cell_ch(cell)
      ch = cell && cell["ch"]
      ch.nil? || ch.empty? ? " " : ch
    end
  end
end
