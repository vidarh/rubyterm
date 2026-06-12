# Instrumentation injected into the production classes. The production
# code deliberately carries no debug facilities; everything the harness
# needs is plugged in here via Module#prepend / class reopening.

module Harness
  # Tracks a per-cell "generation": a monotonically increasing write
  # counter, bumped only when a cell's *content* actually changes.
  # Identical rewrites keep their generation, which keeps the tracker
  # consistent with TrackChanges' skip-identical-redraw optimization.
  #
  # Generations are stored in an identity hash keyed on the cell arrays
  # themselves, so they follow cells through scrolls and line
  # insert/delete without mirroring any buffer operations.
  module GenTracking
    def harness_gen_for(x, y)
      cell = get(x, y)
      cell && @harness_gens ? @harness_gens[cell] : nil
    end

    def set(x, y, ch, fg = 0, bg = 0, flags = 0)
      old = get(x, y)
      super
      cell = get(x, y)
      return if !cell
      @harness_gens ||= {}.compare_by_identity
      @harness_gen ||= 0
      if old && old[0, 4] == cell[0, 4] && @harness_gens.key?(old)
        @harness_gens[cell] = @harness_gens[old]
      else
        @harness_gens[cell] = (@harness_gen += 1)
      end
    end
  end
end

TermBuffer.prepend(Harness::GenTracking)

class TrackChanges
  # The harness swaps the render sink to perform a full redraw into a
  # fresh VirtualWindow (the incremental-vs-full-redraw invariant).
  attr_accessor :adapter
end
