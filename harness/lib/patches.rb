# Instrumentation injected into the production classes. The production
# code deliberately carries no debug facilities; everything the harness
# needs is plugged in here via Module#prepend / class reopening.

module Harness
  # The markers check needs a per-cell "generation" - a counter bumped only
  # when a cell's content actually changes, that follows the cell through
  # scrolls and insert/delete. TermBuffer now tracks exactly that natively
  # as its damage primitive (#generation_at), so the harness just borrows
  # it under the name the check expects. (The old identity-hash tracker,
  # keyed on cell-array object identity, became impossible once cells
  # stopped being objects under columnar storage.)
  module GenTracking
    def harness_gen_for(x, y) = generation_at(x, y)
  end
end

TermBuffer.prepend(Harness::GenTracking)

class TrackChanges
  # The harness swaps the render sink to perform a full redraw into a
  # fresh VirtualWindow (the incremental-vs-full-redraw invariant).
  attr_accessor :adapter
end
