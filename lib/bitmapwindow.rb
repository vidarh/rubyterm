require 'skrift'
require 'zlib'
require_relative 'charwidth'

# Colour-glyph (emoji) support is optional.
begin
  require 'skrift/color'
rescue LoadError
  # skrift-color not installed; emoji render monochrome (or as tofu).
end

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

  DEFAULT_FONT  = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
  DEFAULT_EMOJI = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"

  # Routes emoji codepoints to a colour renderer and leaves everything else to
  # the monochrome path. The emoji? gate (Unicode classification) keeps text
  # that a colour font happens to map — digits, '#', '*' — rendering as text.
  ColourDelegate = Struct.new(:renderer) do
    def render(cp) = CharWidth.emoji?(cp) ? renderer.render(cp) : nil
  end

  def initialize(cols, rows, font: DEFAULT_FONT, size: 16,
                 fg: 0xcccccc, bg: 0x000000, emoji: DEFAULT_EMOJI)
    # The glyph pipeline (rasterise + cache + metrics) lives in skrift's
    # GlyphCache; colour emoji come from an optional colour delegate.
    @cache    = Skrift::GlyphCache.new(font, x_scale: size, y_scale: size,
                                       color: colour_delegate(emoji, size))
    @char_w   = @cache.cell_width
    @char_h   = @cache.cell_height
    @baseline = @cache.baseline
    @cols, @rows = cols, rows
    @fg, @bg = fg, bg
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
    cps = str.each_char.map(&:ord)
    cps.each_with_index do |cp, i|
      next if cp == 32 || cp == CharWidth::WIDE_SPACER # space / wide-glyph tail
      # A WIDE_SPACER in the next cell means this is a double-width glyph; render
      # it two cells wide so it overflows into the (skipped) spacer cell instead
      # of being shrunk into one.
      cells = cps[i + 1] == CharWidth::WIDE_SPACER ? 2 : 1
      blit_glyph(cp, x + i * @char_w, y, fg, cells)
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

  def colour_delegate(emoji, size)
    return nil unless emoji && File.exist?(emoji) && defined?(Skrift::Color::Renderer)
    cr = Skrift::Color::Renderer.new(Skrift::Font.load(emoji), x_scale: size, y_scale: size)
    cr.color? ? ColourDelegate.new(cr) : nil
  end

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

  def blit_glyph(codepoint, cx, cy, fg, cells = 1)
    g = @cache.glyph(codepoint, cells)
    return unless g
    if g.color?
      blit_rgba(g, codepoint, cx, cy)
    elsif g.alpha
      blit_alpha(g, cx, cy, fg)
    end
  end

  # Monochrome glyph: alpha mask tinted with the foreground colour.
  def blit_alpha(g, cx, cy, fg)
    alpha, gw, gh = g.alpha, g.width, g.height
    gx = cx + g.left_side_bearing
    gy = cy + @baseline - g.y_offset
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

  # Colour glyph (emoji): RGBA bitmap composited over the cells, centred in its
  # cell span (emoji are double-width, so span is two cells).
  def blit_rgba(g, codepoint, cx, cy)
    span = CharWidth.width(codepoint) * @char_w
    gx = cx + (span - g.width) / 2
    gy = cy + (@char_h - g.height) / 2
    g.height.times do |row|
      py = gy + row
      next if py < 0 || py >= @height
      base = py * @width
      grow = row * g.width
      g.width.times do |col|
        px = gx + col
        next if px < 0 || px >= @width
        rgba = g.rgba[grow + col]
        a = rgba & 0xff
        next if a.zero?
        idx = base + px
        @pixels[idx] = a == 255 ? (rgba >> 8) : over_rgb(rgba >> 8, a, @pixels[idx])
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

  # src (0xRRGGBB) over dst with alpha a (0-255).
  def over_rgb(src, a, dst)
    ia = 255 - a
    r = ((src >> 16 & 0xff) * a + (dst >> 16 & 0xff) * ia) / 255
    g = ((src >> 8 & 0xff) * a + (dst >> 8 & 0xff) * ia) / 255
    b = ((src & 0xff) * a + (dst & 0xff) * ia) / 255
    (r << 16) | (g << 8) | b
  end
end
