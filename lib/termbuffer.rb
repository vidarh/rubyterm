require 'set'

  BOLD          = 0x002
  FAINT         = 0x004
  ITALICS       = 0x008
  UNDERLINE     = 0x010
  BLINK         = 0x020
  RAPID_BLINK   = 0x040
  INVERSE       = 0x080
  INVISIBLE     = 0x100
  CROSSED_OUT   = 0x200
  DBL_UNDERLINE = 0x400
  OVERLINE      = 0x800

# The screen buffer: a grid of styled cells + scrollback + scroll region.
#
# Storage is COLUMNAR. A row is not an array of [ch,fg,bg,flags] cell
# objects; it is split across three parallel arrays of tagged immediates,
# held per row:
#
#   @chars[y][x] - codepoint Integer (nil = unset/blank cell)
#   @style[y][x] - packed Integer: fg(24) | bg(24)<<24 | flags<<48
#   @gen[y][x]   - per-cell generation Integer (the damage primitive)
#
# Integers in the fixnum range and nil are stored in the VALUE word with no
# heap allocation, so writing a cell allocates nothing (vs. an Array per
# glyph before). fg/bg are 24-bit and flags < 2^12, so a cell's attributes
# pack into one fixnum. See docs/architecture-review.md §8.
#
# @gen is a monotonic per-cell version, bumped only when a cell's content
# actually changes. It is the damage primitive a backend consumes to know
# which cells to repaint; the harness's markers check reads it too
# (generation_at), but it is genuine production state, not debug-only
# weight. Because @gen is stored and moved alongside @chars/@style, the
# generation follows a cell through scrolls and line/char insert+delete for
# free - no separate bookkeeping.
#
# Scrollback lines reuse the exact columnar representation: a scrolled-off
# line is the pair [chars_row, style_row], moved straight into history (no
# per-cell objects, ~40x fewer retained objects than the old form).
class TermBuffer
  attr_accessor :scroll_start, :scroll_end
  attr_reader :w, :scrollback_buffer, :scrollback_lineattrs, :generation

  def initialize
    @w = nil
    @h = nil
    @generation = 0
    clear
    @scroll_start = nil
    @scroll_end = nil
  end

  def clear
    @chars     = []
    @style     = []
    @gen       = []
    @lineattrs = []
    @scrollback_buffer = []
    @scrollback_lineattrs = []
    @blinky = Set.new
    # NB: @generation is deliberately NOT reset - it stays monotonic across
    # clears so a redrawn-after-clear cell never collides with a stale gen.
  end

  def scrollback_size = @scrollback_buffer.size
  def blinky          = @blinky

  def on_resize(w, h)
    raise if !h
    @w, @h = w, h
    enforce_height
  end
  alias resize on_resize

  # # Packing helpers

  def pack_style(fg, bg, flags)
    (fg.to_i & 0xFFFFFF) | ((bg.to_i & 0xFFFFFF) << 24) | (flags.to_i << 48)
  end

  def cell(ch, style)
    [ch, style & 0xFFFFFF, (style >> 24) & 0xFFFFFF, style >> 48]
  end

  # Reconstruct a [chars, styles] scrollback pair into an array of cells.
  def unpack_line(packed)
    chars, styles = packed
    chars.map.with_index { |ch, x| ch && cell(ch, styles[x]) }
  end

  private def ensure_row(y)
    @chars[y]     ||= []
    @style[y]     ||= []
    @gen[y]       ||= []
    @lineattrs[y] ||= 0
  end

  # Rebuild row y as an array of cells (nil for unset positions), or nil if
  # the row has never been written. Non-mutating.
  private def reconstruct_row(y)
    chars = @chars[y] or return nil
    styles = @style[y]
    chars.map.with_index { |ch, x| ch && cell(ch, styles[x]) }
  end

  # # Reads

  def get(x, y)
    if y < 0
      row = line_at(y)
      return row && row[x]
    end
    chars = @chars[y] or return nil
    ch = chars[x] or return nil
    cell(ch, @style[y][x])
  end

  # Whole row of cells. Negative rows come from scrollback.
  def getline(y)
    return line_at(y) if y < 0
    reconstruct_row(y) || []
  end

  # Like #getline but non-vivifying and nil (not []) for an absent row, and
  # mapping negative rows into the (unpacked) scrollback. Safe for read-only
  # traversal such as selection extraction across scrollback.
  def line_at(y)
    if y < 0 && !@scrollback_buffer.empty?
      i = @scrollback_buffer.size + y
      return i >= 0 ? unpack_line(@scrollback_buffer[i]) : nil
    end
    reconstruct_row(y)
  end

  def lineattrs(y)
    y = y.to_i
    if y < 0 && !@scrollback_lineattrs.empty?
      i = @scrollback_lineattrs.size + y
      return i >= 0 ? @scrollback_lineattrs[i] : 0
    end
    @lineattrs[y]
  end

  # The damage primitive: the generation at which (x,y) last changed, or
  # nil for an unset cell. Scrollback is not damage-tracked.
  def generation_at(x, y)
    return nil if y < 0
    g = @gen[y] and g[x]
  end

  # Yield [x, y, ch, fg, bg, flags] for every cell whose content changed
  # after +since_gen+ - the damage since the last flush - as scalars, no
  # cell Array allocated. A damage-driven renderer walks this instead of
  # being told to draw eagerly on every #set. Returns the current
  # generation so the caller can advance its watermark. (Walks all rows;
  # row-level dirty tracking is a later optimisation.)
  def each_damaged(since_gen)
    @gen.each_index do |y|
      gens = @gen[y] or next
      chars = @chars[y]
      styles = @style[y]
      gens.each_index do |x|
        g = gens[x]
        next if !g || g <= since_gen
        ch = chars[x] or next
        s = styles[x]
        yield x, y, ch, s & 0xFFFFFF, (s >> 24) & 0xFFFFFF, s >> 48
      end
    end
    @generation
  end

  # True if (x,y) currently holds exactly this content. Lets the draw path
  # skip identical repaints without reconstructing a cell Array (the prior
  # `new == get(x,y)` allocated one per character).
  def cell_eq?(x, y, ch, fg, bg, flags)
    chars = @chars[y] or return false
    chars[x] == ch && @style[y][x] == pack_style(fg, bg, flags)
  end

  # True if (x,y) has never been written (blank).
  def unset?(x, y)
    chars = @chars[y]
    !chars || chars[x].nil?
  end

  # Yields [x, y, cell] for every *set* cell, scrollback (if offset>0) first
  # at the top, then the live grid below it.
  def each_character(scrollback_offset = 0)
    used = 0
    if scrollback_offset > 0 && !@scrollback_buffer.empty?
      offset = [@scrollback_buffer.size, scrollback_offset].min
      if offset > 0
        lines = @scrollback_buffer[-offset..-1] || []
        lines.each_with_index do |packed, idx|
          chars, styles = packed
          chars.each_with_index do |ch, x|
            yield x, idx, cell(ch, styles[x]) if ch
          end
        end
        used = lines.size
      end
    end

    # +1 mirrors the historical off-by-one (draw one extra row).
    remaining = @h ? (@h - used + 1) : @chars.size
    @chars.each_with_index do |chars, y|
      next if !chars || y >= remaining
      styles = @style[y]
      chars.each_with_index do |ch, x|
        yield x, y + used, cell(ch, styles[x]) if ch
      end
    end
  end

  def each_character_between(spos, epos)
    if spos.end > epos.end
      spos, epos = epos, spos
    elsif spos.end == epos.end && spos.first > epos.first
      spos, epos = epos, spos
    end

    x = spos.first
    xend, ymax = epos.first, epos.end
    (spos.end..ymax).each do |y|
      line = line_at(y) || ""
      xmax = y == ymax ? xend + 1 : line.length - 1
      xmax = [xmax, line.length - 1].min
      xmax = 0 if xmax < 0
      while x <= xmax
        yield(x, y, line[x])
        x += 1
      end
      x = 0
    end
  end

  # # Writes

  def set(x, y, ch, fg = 0, bg = 0, flags = 0)
    ch = ch.ord
    if flags.anybits?(BLINK | RAPID_BLINK)
      @blinky << [x, y]
    else
      @blinky.delete([x, y])
    end
    ensure_row(y)
    style = pack_style(fg, bg, flags)
    # Bump the generation only on an actual content change (identical
    # rewrites keep their gen, so a cell that didn't change isn't seen as
    # damaged).
    if @chars[y][x] != ch || @style[y][x] != style
      @gen[y][x] = (@generation += 1)
    end
    @chars[y][x] = ch
    @style[y][x] = style
  end

  def set_lineattrs(y, v) = (@lineattrs[y] = v)

  # ICH / IRM: open a gap of +num+ cells at x by inserting +cell+, shifting
  # the rest of the line right; cells pushed past the right margin are
  # discarded (the line never grows beyond width). Inserted cells carry no
  # generation (they did not go through #set); they are blanks the caller
  # repaints.
  def insert(x, y, num, cell)
    ensure_row(y)
    ch = cell[0]
    style = pack_style(cell[1], cell[2], cell[3])
    num.times do
      @chars[y].insert(x, ch)
      @style[y].insert(x, style)
      @gen[y].insert(x, nil)
    end
    if @w && @chars[y].length > @w
      @chars[y].slice!(@w..)
      @style[y].slice!(@w..)
      @gen[y].slice!(@w..)
    end
  end

  # DCH: delete +num+ cells at (x,y), shifting the remainder left (gens
  # follow their cells). Vacated cells at the right become blank.
  def delete_chars(x, y, num)
    chars = @chars[y] or return
    num.times do
      break if x >= chars.length
      chars.delete_at(x)
      @style[y].delete_at(x)
      @gen[y].delete_at(x)
    end
  end

  def clear_line(y, start_x = 0, end_x = nil)
    if !end_x
      # Clear to end of line: truncate the row at start_x. Dropped cells
      # become unset (gen nil), so a stale on-screen tail is detectable.
      if @chars[y]
        @chars[y] = @chars[y][0...start_x]
        @style[y] = (@style[y] || [])[0...start_x]
        @gen[y]   = (@gen[y]   || [])[0...start_x]
      end
    else
      (start_x..end_x).each { |x| set(x, y, ' ') }
    end
  end

  # # Line operations (region-aware)

  private def raw_delete_line(y)
    @chars.slice!(y)
    @style.slice!(y)
    @gen.slice!(y)
    @lineattrs.slice!(y)
  end

  private def raw_insert_line(y)
    @chars.insert(y, nil)
    @style.insert(y, nil)
    @gen.insert(y, nil)
    @lineattrs.insert(y, 0)
    enforce_height
  end

  def delete_line(y)
    raw_delete_line(y)
    # In a scroll region, deleting a line shifts the region up and inserts a
    # blank line at the bottom (scroll_end), not at the top.
    raw_insert_line(@scroll_end) if @scroll_start
  end

  def insert_line(y)
    raw_insert_line(y)
    # Inserting pushes the region down; discard the line that falls just
    # past the bottom of the region.
    raw_delete_line(@scroll_end + 1) if @scroll_end
  end

  def scroll_up
    # Move the top line of the region into scrollback - the columnar
    # [chars, style] arrays ARE the packed scrollback form, so this is a
    # straight handoff (delete_line then drops the live references). The
    # gen row is discarded (scrollback is not damage-tracked).
    y = @scroll_start.to_i
    @scrollback_buffer.push([@chars[y] || [], @style[y] || []])
    @scrollback_lineattrs.push(lineattrs(y))
    delete_line(y)
  end

  def enforce_height
    return unless @h
    @chars.slice!(@h..)
    @style.slice!(@h..)
    @gen.slice!(@h..)
    @lineattrs.slice!(@h..)
  end
end
