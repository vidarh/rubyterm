require 'skrift'
require 'zlib'

# A third implementation of the drawing interface WindowAdapter targets
# (alongside the X11 Window and the harness's VirtualWindow): it rasterises
# real glyphs with skrift and composites them into an in-memory RGB buffer.
# Wrapped by WindowAdapter it is a full "bitmap backend" - the same Term
# core, rendered to a pixel buffer with no X server - useful for headless
# visual testing and for embedding the terminal anywhere a bitmap can go.
#
#   win = BitmapWindow.new(80, 24)
#   adapter = WindowAdapter.new(win, host)   # host: term_width/blink_state...
#   ... feed the terminal ...
#   win.save_png("screen.png")
class BitmapWindow
  attr_reader :width, :height, :pixels

  DEFAULT_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

  def initialize(cols, rows, font: DEFAULT_FONT, size: 16,
                 fg: 0xcccccc, bg: 0x000000)
    @font = Font.load(font)
    @sft = SFT.new(@font)
    @sft.x_scale = size
    @sft.y_scale = size
    lm = @sft.lmetrics
    @char_h   = (lm.ascender - lm.descender + lm.line_gap).ceil
    @baseline = lm.ascender.round
    @char_w   = @sft.gmetrics(@sft.lookup("M".ord)).advance_width.round
    @cols, @rows = cols, rows
    @fg, @bg = fg, bg
    @glyphs = {}
    resize(cols * @char_w, rows * @char_h)
  end

  def char_w = @char_w
  def char_h = @char_h

  def resize(w, h)
    @width, @height = w, h
    @pixels = Array.new(@width * @height, @bg)
  end

  # # Window interface used by WindowAdapter / the host loop

  # Live-loop hooks: a bitmap has no separate front buffer / event channel.
  def dirty!        = nil
  def flush         = nil
  def copy_buffer   = nil
  def map_window    = nil
  def set_buffer(_) = nil
  def scrollback_mode  = false
  def scrollback_count = 0

  def fillrect(x, y, w, h, col)
    x0 = x.clamp(0, @width); x1 = (x + w).clamp(0, @width)
    y0 = y.clamp(0, @height); y1 = (y + h).clamp(0, @height)
    (y0...y1).each do |py|
      base = py * @width
      (x0...x1).each { |px| @pixels[base + px] = col }
    end
  end

  def clear(x, y, w, h)  = fillrect(x, y, w, h, @bg)
  def draw_line(x, y, w, col) = fillrect(x, y, w, 1, col)

  # x,y are pixel coordinates (WindowAdapter has already multiplied by the
  # cell size). lineattrs (double width/height) is rendered as normal width
  # for now - it does not affect correctness of the text, only its scale.
  def draw(x, y, str, fg, bg, _lineattrs = nil)
    fillrect(x, y, str.length * @char_w, @char_h, bg)
    str.each_char.with_index do |ch, i|
      next if ch == " "
      blit_glyph(ch.ord, x + i * @char_w, y, fg)
    end
  end

  # Mirror Window#scroll_up / #scroll_down: move a block of pixel rows and
  # clear the vacated strip (geometry comes from WindowAdapter).
  def scroll_up(srcy, w, h, step)
    move_rows(srcy, srcy - step, h)
    clear(0, srcy + h - step, @width, step + 1)
  end

  def scroll_down(srcy, w, h, step)
    move_rows(srcy, srcy + step, h)
    clear(0, srcy, @width, step)
  end

  # # Output

  def save_png(path)
    raw = +"".b
    @height.times do |y|
      raw << "\0"               # filter: none
      base = y * @width
      @width.times do |x|
        p = @pixels[base + x]
        raw << ((p >> 16) & 0xff).chr << ((p >> 8) & 0xff).chr << (p & 0xff).chr
      end
    end
    png = +"\x89PNG\r\n\x1a\n".b
    png << png_chunk("IHDR", [@width, @height, 8, 2, 0, 0, 0].pack("NNC5"))
    png << png_chunk("IDAT", Zlib::Deflate.deflate(raw))
    png << png_chunk("IEND", "")
    File.binwrite(path, png)
    path
  end

  private

  def png_chunk(type, data)
    body = type.b + data.b
    [data.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
  end

  # Overlap-safe block copy of +h+ pixel rows from srcy to dsty.
  def move_rows(srcy, dsty, h)
    rows = (0...h).to_a
    rows.reverse! if dsty > srcy   # copy bottom-up when shifting down
    rows.each do |i|
      sy = srcy + i; dy = dsty + i
      next if sy < 0 || sy >= @height || dy < 0 || dy >= @height
      @pixels[dy * @width, @width] = @pixels[sy * @width, @width]
    end
  end

  def blit_glyph(codepoint, cx, cy, fg)
    alpha, gw, gh, lsb, yoff = glyph(codepoint)
    return unless alpha
    gx = cx + lsb
    gy = cy + @baseline - yoff
    gh.times do |row|
      py = gy + row
      next if py < 0 || py >= @height
      base = py * @width
      grow = row * gw
      gw.times do |col|
        a = alpha[grow + col]
        next if a.nil? || a.zero?
        px = gx + col
        next if px < 0 || px >= @width
        idx = base + px
        @pixels[idx] = blend(@pixels[idx], fg, a)
      end
    end
  end

  # fg over dst, coverage a (0-255).
  def blend(dst, fg, a)
    ia = 255 - a
    r = ((fg >> 16 & 0xff) * a + (dst >> 16 & 0xff) * ia) / 255
    g = ((fg >> 8 & 0xff) * a + (dst >> 8 & 0xff) * ia) / 255
    b = ((fg & 0xff) * a + (dst & 0xff) * ia) / 255
    (r << 16) | (g << 8) | b
  end

  # [alpha_bytes, width, height, left_bearing, y_offset] for a codepoint,
  # cached; or [nil] if it has no outline (e.g. space).
  def glyph(codepoint)
    @glyphs[codepoint] ||= begin
      gid = @sft.lookup(codepoint)
      m = gid && @sft.gmetrics(gid)
      if m.nil? || m.min_width.nil? || m.min_height.nil?
        [nil]
      else
        img = Image.new((m.min_width + 3) & ~3, m.min_height)
        if @sft.render(gid, img) && img.pixels
          [img.pixels, img.width, img.height, m.left_side_bearing.round, m.y_offset]
        else
          [nil]
        end
      end
    end
  end
end
