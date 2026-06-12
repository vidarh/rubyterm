require 'digest'

# Runs the configured checks for one input byte stream and reduces
# every comparison to structured pass/fail JSON. No check ever needs a
# human (or vision) in the loop, which is what allows fully scripted
# sweep -> minimize -> cluster -> fix pipelines on top.
#
# Checks:
# * state   - our grid/cursor vs the tmux oracle (semantic bugs).
#             Without an oracle it degrades to "interpreting the bytes
#             did not crash".
# * redraw  - live incremental framebuffer vs a fresh full redraw of
#             the same buffer (incremental-rendering bugs; no oracle
#             needed).
# * markers - re-runs the case in marker render mode and decodes the
#             framebuffer: every cell must show the (row, col, gen)
#             marker matching the buffer cell that owns it (stale
#             content / misaligned blit bugs, self-describing).
# * trace   - records all render-sink calls and reports op statistics
#             (informational; over-draw is a perf smell, not a failure).
#
# The "class" field ("state" | "render") drives failure clustering.
module Harness
  module Checks
    ALL = %w[state redraw markers trace].freeze

    def self.run_case(bytes, cols: 80, rows: 24, checks: ALL,
                      oracle: nil, chunk: Session::DEFAULT_CHUNK,
                      include_dump: false)
      checks = checks & ALL
      result = { "checks" => {} }

      session = Session.new(cols: cols, rows: rows)
      session.window.trace_enabled = checks.include?("trace")
      session.feed(bytes, chunk: chunk)

      if checks.include?("state")
        result["checks"]["state"] = state_check(session, bytes, oracle)
      end
      if checks.include?("redraw")
        result["checks"]["redraw"] = redraw_check(session)
      end
      if checks.include?("markers")
        result["checks"]["markers"] =
          marker_check(Session.new(cols: cols, rows: rows,
                                   render_mode: :markers)
                         .feed(bytes, chunk: chunk))
      end
      if checks.include?("trace")
        result["checks"]["trace"] = trace_check(session)
      end

      result["pass"] = result["checks"].values.all? { |c| c["pass"] }
      result["class"] = classify(result["checks"])
      result["signature"] = signature(result)
      result["dump"] = session.state_dump if include_dump
      result["screen"] = StateDump.text(session.state_dump)
      result
    end

    def self.state_check(session, bytes, oracle)
      dump = session.state_dump
      case oracle
      when "tmux"
        odump = OracleTmux.run(bytes, cols: session.cols, rows: session.rows)
        diff = Differ.diff(odump, dump)
        { "pass" => diff.empty?, "oracle" => "tmux", "diff" => diff }
      else
        { "pass" => true, "oracle" => "none" }
      end
    end

    def self.redraw_check(session)
      live = session.window.snapshot
      fresh = session.full_redraw
      cells, bbox = VirtualWindow.compare(live, fresh.framebuffer,
                                          Session::CHAR_W, Session::CHAR_H)
      { "pass" => cells.empty?, "cells" => cells, "bbox" => bbox }
    end

    # Marker-mode rules (per cell):
    # * no buffer cell        -> CLEAR, or this cell's own gen-0 marker
    #                            (the cursor overlay repaints empty
    #                            cells it visits); anything else is
    #                            stale content
    # * space cell            -> CLEAR or a marker with the right gen
    #                            both fine (clears and space draws are
    #                            visually identical)
    # * non-space cell        -> exactly one marker, gen must match;
    #                            non-uniform cells reveal misaligned
    #                            blits, and the foreign marker names
    #                            the cell the content leaked from
    def self.marker_check(session)
      vw = session.window
      bad = []
      session.rows.times do |row|
        session.cols.times do |col|
          cell = session.buffer.get(col, row)
          gen = session.termbuffer.harness_gen_for(col, row)
          vals = vw.cell_values(col, row)
          markers = vals.grep(Array)
          problem =
            if !vals.all? { |v| v.is_a?(Array) || v == VirtualWindow::CLEAR }
              "foreign_pixels" # glyph-mode values can't occur here
            elsif cell.nil?
              "stale" if markers.any? { |m| m != [row, col, 0] }
            elsif markers.length > 1
              "nonuniform"
            elsif markers.empty?
              "missing" if cell[0] != 32
            elsif markers[0][2] != gen.to_i
              "stale_gen"
            elsif markers[0][0] != row || markers[0][1] != col
              # Provenance differs but content (gen) is right: the
              # pixels were moved here by a blit, which is fine.
              nil
            end
          next if !problem
          bad << { "row" => row, "col" => col, "problem" => problem,
                   "expected_gen" => gen,
                   "got" => markers.map { |m|
                     { "row" => m[0], "col" => m[1], "gen" => m[2] } } }
        end
      end
      { "pass" => bad.empty?, "cells" => bad }
    end

    def self.trace_check(session)
      counts = Hash.new(0)
      session.window.trace.each { |t| counts[t[:op].to_s] += 1 }
      { "pass" => true, "ops" => counts }
    end

    def self.classify(checks)
      return "state" if checks["state"] && !checks["state"]["pass"]
      if (checks["redraw"] && !checks["redraw"]["pass"]) ||
         (checks["markers"] && !checks["markers"]["pass"])
        return "render"
      end
      nil
    end

    # Stable identity of *how* a case fails, for clustering and for the
    # minimizer's fails-the-same-way predicate. Built from the failure
    # class plus the sorted mismatch coordinates of each failing check.
    #
    # Render checks (redraw/markers) normalize coordinates relative to
    # the top-left failing cell: removing prefix tokens shifts content
    # around the screen, but the *shape* of the incremental-rendering
    # bug stays the same. Without this normalization ddmin rejects
    # almost every candidate and minimization barely progresses.
    def self.signature(result)
      return nil if result["pass"]
      sig = [result["class"]]
      result["checks"].each do |name, c|
        next if c["pass"]
        coords =
          case name
          when "state"
            c["diff"].map { |d| [d["type"], d["row"], d["col"]] }
          when "redraw"
            normalize_cells(c["cells"])
          when "markers"
            normalize_markers(c["cells"])
          end
        sig << [name, coords&.sort_by(&:to_s)]
      end
      Digest::SHA256.hexdigest(sig.inspect)[0, 16]
    end

    def self.normalize_cells(cells)
      return cells if cells.empty?
      min_col = cells.map(&:first).min
      min_row = cells.map(&:last).min
      cells.map { |col, row| [col - min_col, row - min_row] }
    end

    def self.normalize_markers(cells)
      return cells if cells.empty?
      min_col = cells.map { |b| b["col"] }.min
      min_row = cells.map { |b| b["row"] }.min
      cells.map { |b| [b["col"] - min_col, b["row"] - min_row, b["problem"]] }
    end
  end
end
