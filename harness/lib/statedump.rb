# Serializes the terminal's internal state to the harness's canonical
# JSON-able schema (see docs/state-schema.md). This is the contract
# that all state comparisons diff against; the oracle emits the same
# shape.
module Harness
  module StateDump
    ATTR_BITS = {
      "bold" => BOLD, "faint" => FAINT, "italics" => ITALICS,
      "underline" => UNDERLINE, "blink" => BLINK,
      "rapid_blink" => RAPID_BLINK, "inverse" => INVERSE,
      "invisible" => INVISIBLE, "crossed_out" => CROSSED_OUT,
      "dbl_underline" => DBL_UNDERLINE, "overline" => OVERLINE,
    }.freeze

    # term:   Term instance
    # buffer: TrackChanges instance wrapping the TermBuffer
    def self.dump(term, buffer)
      width, height = term.width, term.height
      termbuf = buffer.buffer

      cells = (0...height).map do |y|
        (0...width).map do |x|
          cell = buffer.get(x, y)
          next nil if !cell
          ch, fg, bg, flags = cell
          gen = termbuf.respond_to?(:harness_gen_for) ?
                  termbuf.harness_gen_for(x, y) : nil
          {
            "ch" => [ch.is_a?(Integer) ? ch : ch.ord].pack("U"),
            "fg" => fg, "bg" => bg,
            "attrs" => attrs(flags),
            "gen" => gen,
          }
        end
      end

      g = term.instance_variable_get(:@g)
      {
        "cols" => width, "rows" => height,
        "cursor" => {
          "row" => term.y, "col" => term.x,
          "visible" => !!term.cursor,
          "pending_wrap" => term.x >= width,
        },
        "scroll_region" => [buffer.scroll_start || 0,
                            buffer.scroll_end || height - 1],
        "modes" => {
          "origin" => !!term.origin_mode,
          "autowrap" => !!term.wraparound,
          "lnm" => !!term.instance_variable_get(:@lnm),
        },
        "tabstops" => term.tabs.dup,
        "charsets" => {
          "g0" => charset_name(g && g[0]),
          "g1" => charset_name(g && g[1]),
          "active" => term.instance_variable_get(:@gl),
        },
        "cells" => cells,
        "scrollback_len" => termbuf.scrollback_size,
      }
    end

    # Plain-text view of a dump's screen, one string per row, for
    # comparison against text-level oracles and for human triage.
    def self.text(dump)
      dump["cells"].map do |row|
        row.map { |c| c ? c["ch"] : " " }.join.rstrip
      end
    end

    def self.attrs(flags)
      flags = flags.to_i
      ATTR_BITS.filter_map { |name, bit| name if flags.allbits?(bit) }
    end

    def self.charset_name(cs)
      case cs
      when GraphicsCharset then "0"
      when DefaultCharset, nil then "B"
      else "?"
      end
    end
  end
end
