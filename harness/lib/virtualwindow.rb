# A pure-Ruby, in-memory implementation of the drawing interface that
# lib/window.rb exposes to WindowAdapter. Instead of an X11 pixmap it
# paints into a 2D array of values ("virtual pixels"), which makes
# every rendering comparison an exact-equality problem:
#
# * :glyphs mode models the real renderer: a draw fills the cell run
#   with the background colour, then paints an inset "glyph" rect for
#   each non-space character, encoded from (codepoint, fg). Trailing
#   and interior spaces paint no glyph, matching the real font
#   renderer (a space has no marks).
# * :markers mode replaces glyph drawing with a per-cell fill that
#   encodes (row, col, generation) - see Harness::GenTracking. Decoding
#   the framebuffer then directly names which buffer cell owns which
#   pixels, making stale content and misaligned blits self-describing.
#
# Scroll blits mirror Window#scroll_up/#scroll_down byte for byte
# (same copy + clear geometry), since those are exactly the operations
# the redraw invariant is designed to catch bugs in.
#
# All operations are recorded in @trace when trace_enabled, for
# under/over-draw analysis.
require_relative "../../lib/charwidth"

module Harness
  class VirtualWindow
    # Deliberately identical to fillrect's black: Window#clear paints
    # 50%-alpha black while a drawn black background is opaque, but on
    # screen they are visually equivalent (modulo window transparency,
    # which is below this model's resolution). Distinguishing them
    # would flag "cleared" vs "drew an empty cell" as a difference,
    # e.g. wherever the cursor overlay visited an empty cell.
    CLEAR = 0xff000000

    attr_reader :width, :height, :char_w, :char_h, :trace, :render_mode
    attr_accessor :gen_source, :trace_enabled

    def initialize(width, height, char_w:, char_h:, render_mode: :glyphs)
      @char_w, @char_h = char_w, char_h
      @width, @height = width, height
      @fb = Array.new(@height) { Array.new(@width, CLEAR) }
      @render_mode = render_mode
      @trace = []
      @trace_enabled = false
      @gen_source = nil
      @scrollback_count = 0
    end

    def framebuffer = @fb
    def snapshot    = @fb.map(&:dup)
    def trace_reset = (@trace = [])

    # # Window interface (the subset WindowAdapter and the session use)

    def dirty!       = nil
    def flush        = nil
    def copy_buffer  = nil
    def map_window   = nil
    def set_buffer(_) = nil
    def scrollback_mode = false
    def scrollback_count = 0

    def clear(x, y, w, h)
      record(:clear, x, y, w, h)
      fill(x, y, w, h, CLEAR)
    end

    def fillrect(x, y, w, h, fg)
      record(:fillrect, x, y, w, h, fg)
      fill(x, y, w, h, 0xff000000 | fg)
    end

    def draw_line(x, y, w, fg)
      record(:draw_line, x, y, w, fg)
      return if @render_mode == :markers # don't corrupt cell markers
      fill(x, y, w, 1, 0xff000000 | fg)
    end

    def draw(x, y, c, fg, bg, lineattrs)
      record(:draw, x, y, c.dup, fg, bg, lineattrs)
      return draw_markers(x, y, c.length) if @render_mode == :markers

      cw, chh = @char_w, @char_h
      # Double-width/height lines render each cell twice as wide AND at
      # twice the x origin, exactly like Window#draw (which passes x*2 to
      # the double-size font renderer). Without the x*2 here, runs split at
      # different column boundaries (incremental vs full redraw) overlap
      # each other and the redraw check reports phantom divergences.
      case lineattrs
      when :dbl_upper
        fill(x * 2, y, c.length * cw * 2, chh * 2, 0xff000000 | bg)
        draw_glyphs(x * 2, y, c, fg, cw * 2, chh * 2)
      when :dbl_lower
        fill(x * 2, y, c.length * cw * 2, chh * 2, 0xff000000 | bg)
        draw_glyphs(x * 2, y - chh, c, fg, cw * 2, chh * 2)
      when :dbl_single
        fill(x * 2, y, c.length * cw * 2, chh, 0xff000000 | bg)
        draw_glyphs(x * 2, y, c, fg, cw * 2, chh)
      else
        fill(x, y, c.length * cw, chh, 0xff000000 | bg)
        draw_glyphs(x, y, c, fg, cw, chh)
      end
    end

    # Mirrors Window#scroll_up exactly (including the full-width,
    # step+1-high clear).
    def scroll_up(srcy, w, h, step)
      record(:scroll_up, srcy, w, h, step)
      copy_area(0, srcy, 0, srcy - step, w, h)
      fill(0, srcy + h - step, @width, step + 1, CLEAR)
    end

    # Mirrors Window#scroll_down exactly.
    def scroll_down(srcy, w, h, step)
      record(:scroll_down, srcy, w, h, step)
      copy_area(0, srcy, 0, srcy + step, w, h)
      fill(0, srcy, w, step, CLEAR)
    end

    def resize(width, height)
      record(:resize, width, height)
      @width, @height = width, height
      @fb = Array.new(@height) { Array.new(@width, CLEAR) }
    end

    # # Inspection

    # All distinct values within a character cell's rect.
    def cell_values(col, row)
      x0, y0 = col * @char_w, row * @char_h
      vals = {}
      (y0...y0 + @char_h).each do |y|
        line = @fb[y] or next
        (x0...x0 + @char_w).each do |x|
          v = line[x]
          vals[v] = true if !v.nil?
        end
      end
      vals.keys
    end

    # Compare two framebuffer snapshots; returns [cells, bbox] where
    # cells is a sorted list of differing [col, row] character cells
    # and bbox is the overall differing pixel rect [x, y, w, h] (or nil).
    def self.compare(a, b, char_w, char_h)
      cells = {}
      minx = miny = nil
      maxx = maxy = nil
      rows = [a.length, b.length].max
      rows.times do |y|
        la, lb = a[y] || [], b[y] || []
        cols = [la.length, lb.length].max
        cols.times do |x|
          next if la[x] == lb[x]
          cells[[x / char_w, y / char_h]] = true
          minx = x if !minx || x < minx
          maxx = x if !maxx || x > maxx
          miny = y if !miny || y < miny
          maxy = y if !maxy || y > maxy
        end
      end
      bbox = minx && [minx, miny, maxx - minx + 1, maxy - miny + 1]
      [cells.keys.sort, bbox]
    end

    private

    def record(op, *args)
      @trace << { op: op, args: args } if @trace_enabled
    end

    def draw_glyphs(x, y, str, fg, cell_w, cell_h)
      str.each_char.with_index do |chr, i|
        next if chr == " " || chr.ord == CharWidth::WIDE_SPACER # space / wide tail
        gx = x + i * cell_w
        # Inset rect: background stays visible at the cell border, so
        # both wrong-background and wrong-glyph bugs are caught.
        fill(gx + 1, y + 1, cell_w - 2, cell_h - 2,
             0x1_0000_0000 | (chr.ord << 25) | fg)
      end
    end

    def draw_markers(x, y, len)
      row = y / @char_h
      col0 = x / @char_w
      len.times do |i|
        col = col0 + i
        gen = @gen_source ? @gen_source.call(col, row).to_i : 0
        fill(col * @char_w, row * @char_h, @char_w, @char_h,
             [row, col, gen].freeze)
      end
    end

    def fill(x, y, w, h, val)
      x, y, w, h = x.to_i, y.to_i, w.to_i, h.to_i
      x0 = x.clamp(0, @width)
      y0 = y.clamp(0, @height)
      x1 = (x + w).clamp(0, @width)
      y1 = (y + h).clamp(0, @height)
      (y0...y1).each do |yy|
        line = @fb[yy]
        (x0...x1).each { |xx| line[xx] = val }
      end
    end

    # Overlap-safe block copy, like XCopyArea.
    def copy_area(sx, sy, dx, dy, w, h)
      sx, sy, dx, dy, w, h = [sx, sy, dx, dy, w, h].map(&:to_i)
      src = (sy...sy + h).map do |yy|
        next nil if yy < 0 || yy >= @height
        Array(@fb[yy][sx.clamp(0, @width)...(sx + w).clamp(0, @width)])
      end
      src.each_with_index do |line, i|
        yy = dy + i
        next if !line || yy < 0 || yy >= @height
        line.each_with_index do |v, j|
          xx = dx + j
          @fb[yy][xx] = v if xx >= 0 && xx < @width
        end
      end
    end
  end
end
