
require 'skrift'
module Skrift
  module X11
    # XRender constants currently not defined in pure-x11.
    # FIXME.
    PictOpSrc=1
    PictOpOver=3
    CPRepeat = 1

    class Glyphs

      def initialize dpy, font, x_scale:, y_scale:, pic: nil, fixed: nil
        @dpy = dpy
        @sft = SFT.new(font)
        @sft.x_scale = x_scale
        @sft.y_scale = y_scale
        @pic = pic
        @fixed = fixed

        @glyphcache = {}
        @colcache   = {}
        @chcache = {}

        @lm = @sft.lmetrics

        # The glyph set
        @gfmt     = @dpy.render_find_standard_format(:a8).id
        @glyphset = @dpy.render_create_glyph_set(@gfmt)
      end

      attr_accessor :lm
      def gm(ch)
        gid = @sft.lookup(ch.ord)
        @sft.gmetrics(gid)
      end
    

      def fill_for_col(col)
        return @colcache[col] if @colcache[col]
        r = col >> 16
        r |= r << 8
        g = (col >> 8) & 0xff
        g |= g << 8
        b = col & 0xff
        b |= b << 8
        
        @colcache[col] ||= @dpy.render_create_solid_fill(r,g,b,0xffff)
      end

      def fixed_width
        return @fixed_width if @fixed_width
        if @fixed
          # *Ensure* that the glyphs are equal width.
          g = gm("M")
          @fixed_width = g.advance_width.ceil
        else
          nil
        end
      end
    
  
      def cache_glyph(gid, baseline)
        return if gid.nil?
        mtx = @sft.gmetrics(gid)

        # FIXME: Not sure what to do if mtx.nil? here.
        # Maybe use x/y scale?
        w = fixed_width || mtx.min_width || 0
        h = mtx.min_height || 1
        #p [w,h]
        img = Image.new((w+3)&~3, h)
        if !@sft.render(gid, img)
          #STDERR.puts "Unable to render #{gid}\n"
          data = "\0"*(w*h)
        else
          data = img.pixels.pack("C*")
        end
        
        yoff = mtx.y_offset || baseline
        
        info = ::X11::Form::GlyphInfo.new(
          img.width,              # w
          img.height,             # h
          -mtx.left_side_bearing, # x
          yoff-baseline,          # y
          fixed_width || mtx.advance_width, # || mtx.advance_width,      # x_off
          0
        )

        @dpy.render_add_glyphs(@glyphset, gid, info, data)
        @glyphcache[gid] = mtx.advance_width#-mtx.left_side_bearing
      end

      def text_width(str)
        gl = map_glyphs(str)
        # We *presume* that if you call text_width, you intend
        # to render the string. Maybe we shouldn't?
        cache_glyphs(gl)
        gl.inject(0) {|sum,gl|
          @glyphcache[gl].to_i + sum
        }
      end
      
      def map_glyphs(str)
        # FIXME: Should probably cache by character rather than
        # glyph
        str.to_s.each_char.map do |ch|
          @chcache[ch] ||= @sft.lookup(ch.ord).to_i
        end
      end
      
      def cache_glyphs(gl)
        gl.each do |gid|
          data = @glyphcache[gid]
          if !data
            data = cache_glyph(gid, @lm.ascender)
          end
        end
      end
      
      def render_str(pic, col, x,y, str)
        fill = fill_for_col(col)
        gl = map_glyphs(str)
        cache_glyphs(gl)
        @dpy.render_composite_glyphs32(
          PictOpOver, fill, pic, @gfmt,
          @glyphset, 0,0, [x, y, gl]
        )
      end
    end
  end
end
