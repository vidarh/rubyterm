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
# * responses - the query replies (DSR/DA/...) the terminal wrote back,
#             fed to the tmux oracle as host input. A correct reply is
#             consumed by the host; a malformed/wrong-type one is
#             forwarded to the pane and echoed as visible garbage
#             ("escape sequences on screen"). This is a host-side
#             property the grid oracle is structurally blind to. Needs
#             the tmux oracle; otherwise skipped.
#
# The "class" field ("state" | "render") drives failure clustering.
module Harness
  module Checks
    ALL = %w[state redraw markers responses trace].freeze

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
      if checks.include?("responses")
        result["checks"]["responses"] =
          responses_check(session.responses, cols: cols, rows: rows,
                          oracle: oracle)
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

    # Faithfulness of the terminal's own query replies. A reply travels
    # terminal -> host (the pty); whether it ever reaches the screen
    # depends on the host. A host like tmux *consumes* a reply it
    # recognises as the answer to a query it sent, but forwards a
    # malformed or wrong-type reply to the foreground program, where a
    # cooked-mode reader (a shell at its prompt) echoes it as visible
    # garbage - the "escape sequences on screen" bug.
    #
    # This is irreducibly a host-side property: re-interpreting the reply
    # in our own terminal cannot see it (we simply consume our own DCS),
    # which is why the bug slipped a grid-only oracle. So the check
    # delegates to the tmux oracle's leak test. With no tmux oracle it
    # cannot be evaluated and is reported as skipped (passing), rather
    # than run a heuristic that gives false confidence.
    #
    # This is how the DA2-reply leak surfaced: a DA3 DCS (`\eP!|...\e\\`)
    # sent in answer to DA1/DA2 is not recognised by tmux and printed
    # `^[P!|00000000^[\` on screen.
    def self.responses_check(replies, cols:, rows:, oracle: nil)
      replies = (replies || "").b
      if replies.empty?
        return { "pass" => true, "oracle" => oracle.to_s, "replies" => "",
                 "leaked" => [] }
      end
      if oracle != "tmux"
        return { "pass" => true, "oracle" => "none", "skipped" => true,
                 "replies" => replies, "leaked" => [] }
      end
      # The leak test judges a reply by whether the host consumes it - but
      # a host only consumes replies to queries *it* issued (terminal
      # probing: DA1/DA2/DA3, XTVERSION). CPR (cursor position, CSI r;c R)
      # answers an *application* query the host never sends, so it would
      # always look "leaked" regardless of correctness; it is not a
      # host-probe reply and is excluded from this test.
      probed = replies.gsub(/\e\[\d+;\d+R/, "".b)
      leaked = probed.empty? ? [] :
                 OracleTmux.leaked(probed, cols: cols, rows: rows)
      { "pass" => leaked.empty?, "oracle" => "tmux",
        "replies" => replies, "leaked" => leaked }
    end

    def self.trace_check(session)
      counts = Hash.new(0)
      session.window.trace.each { |t| counts[t[:op].to_s] += 1 }
      { "pass" => true, "ops" => counts }
    end

    def self.classify(checks)
      return "state" if checks["state"] && !checks["state"]["pass"]
      if (checks["redraw"] && !checks["redraw"]["pass"]) ||
         (checks["markers"] && !checks["markers"]["pass"]) ||
         (checks["responses"] && !checks["responses"]["pass"])
        # A leaked reply is screen corruption, same visible class as a
        # render bug (the grid the case itself produced is unaffected).
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
          when "responses"
            # The leaked text itself identifies the failing reply.
            c["leaked"].sort
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
