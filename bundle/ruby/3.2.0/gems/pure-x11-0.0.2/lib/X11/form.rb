require 'ostruct'

module X11
  module Form
    # A form object is an X11 packet definition. We use forms to encode
    # and decode X11 packets as we send and receive them over a socket.
    #
    # We can create a packet definition as follows:
    #
    #   class Point < BaseForm
    #     field :x, Int8
    #     field :y, Int8
    #   end
    #
    #   p = Point.new(10,20)
    #   p.x => 10
    #   p.y => 20
    #   p.to_packet => "\n\x14"
    #
    # You can also read from a socket:
    #
    #   Point.from_packet(socket) => #<Point @x=10 @y=20>
    #
    class Form
      def self.structs
        []
      end

      def self.fields
        []
      end
    end

    class BaseForm < Form
      include X11::Type

      # initialize field accessors
      def initialize(*params)
        self.class.fields.each do |f|
          if !f.value
            param = params.shift
            #p [f,param]
            instance_variable_set("@#{f.name}", param)
          end
        end
      end

      def to_packet
        # fetch class level instance variable holding defined fields
        structs = self.class.structs

        packet = structs.map do |s|
          # fetch value of field set in initialization

          value = s.type == :unused ? nil : instance_variable_get("@#{s.name}")
          case s.type
          when :field
            if s.value
              if s.value.respond_to?(:call)
                value = s.value.call(self)
              else
                value = s.value
              end
            end
            #p [s,value]

            if value.is_a?(BaseForm)
              v = value.to_packet
            elsif value.is_a?(Symbol)
              #if !@atoms[value]
              #  reply = write_sync(X11::Forms::InternAtom.new(false, value.to_s), X11::Forms::InternAtomReply)
              #  @
              #end
              #value = @atoms[value]
              raise "FIXME"
            else
              #p [s,value]
              v = s.type_klass.pack(value)
            end
            #p v
            v
          when :unused
            sz = s.size.respond_to?(:call) ? s.size.call(self) : s.size
            "\x00" * sz
          when :length
            #p [s,value]
            #p [value.size]
            s.type_klass.pack(value.size)
          when :string
            s.type_klass.pack(value)
          when :list
            value.collect do |obj|
              if obj.is_a?(BaseForm)
                obj.to_packet
              else
                s.type_klass.pack(obj)
              end
            end
          end
        end.join
      end

      class << self
        def structs
          superclass.structs + Array(@structs) #instance_variable_get("@structs"))
        end

        # FIXME: Doing small reads from socket is a bad idea, and
        # the protocol provides length fields that makes it unnecessary.
        def from_packet(socket)
          # fetch class level instance variable holding defined fields

          form = new
          lengths = {}

          structs.each do |s|
            case s.type
            when :field
              val = if s.type_klass.superclass == BaseForm
                s.type_klass.from_packet(socket)
              else
                s.type_klass.unpack( socket.read(s.type_klass.size) )
              end
              form.instance_variable_set("@#{s.name}", val)
            when :unused
              sz = s.size.respond_to?(:call) ? s.size.call(self) : s.size
              socket.read(sz)
            when :length
              size = s.type_klass.unpack( socket.read(s.type_klass.size) )
              lengths[s.name] = size
            when :string
              val = s.type_klass.unpack(socket, lengths[s.name])
              form.instance_variable_set("@#{s.name}", val)
            when :list
              len = lengths[s.name]
              if len
                val = len.times.collect do
                  s.type_klass.from_packet(socket)
                end
              else
                val = []
                while ob = s.type_klass.from_packet(socket)
                  val << ob
                end
              end
              form.instance_variable_set("@#{s.name}", val)
            end
          end

          return form
        end

        Field = Struct.new(:name, :type, :type_klass, :value, :size, keyword_init: true)
        
        def field(name, type_klass, type = nil, value: nil)
          # name, type_klass, type = args
          class_eval do
            if value && value.respond_to?(:call)
              define_method(name.to_sym) { value.call(self) }
            else
              attr_accessor name
            end
          end

          s = Field.new
          s.name = name
          s.type = (type == nil ? :field : type)
          s.type_klass = type_klass
          s.value = value

          @structs ||= []
          @structs << s
        end

        def unused(size)
          @structs ||= []
          @structs << Field.new(size: size, type: :unused)
        end

        def fields
          super+Array(@structs).dup.delete_if{|s| s.type == :unused or s.type == :length }
        end
      end
    end

    CardinalAtom=6
    
    ##
    ## X11 Packet Defintions
    ##

    class ClientHandshake < BaseForm
      field :byte_order, Uint8
      unused 1
      field :protocol_major_version, Uint16
      field :protocol_minor_version, Uint16
      field :auth_proto_name, Uint16, :length
      field :auth_proto_data, Uint16, :length
      unused 2
      field :auth_proto_name, String8, :string
      field :auth_proto_data, String8, :string
    end

    class FormatInfo < BaseForm
      field :depth, Uint8
      field :bits_per_pixel, Uint8
      field :scanline_pad, Uint8
      unused 5
    end

    class VisualInfo < BaseForm
      field :visual_id, VisualID
      field :qlass, Uint8
      field :bits_per_rgb_value, Uint8
      field :colormap_entries, Uint16
      field :red_mask,  Uint32
      field :green_mask, Uint32
      field :blue_mask, Uint32
      unused 4
    end

    class DepthInfo < BaseForm
      field :depth, Uint8
      unused 1
      field :visuals, Uint16, :length
      unused 4
      field :visuals, VisualInfo, :list
    end

    class ScreenInfo < BaseForm
      field :root, Window
      field :default_colormap, Colormap
      field :white_pixel, Colornum
      field :black_pixel, Colornum
      field :current_input_masks, Mask
      field :width_in_pixels, Uint16
      field :height_in_pixels, Uint16
      field :width_in_millimeters, Uint16
      field :height_in_millimeters, Uint16
      field :min_installed_maps, Uint16
      field :max_installed_maps, Uint16
      field :root_visual, VisualID
      field :backing_stores, Uint8
      field :save_unders, Bool
      field :root_depth, Uint8
      field :depths, Uint8,:length
      field :depths, DepthInfo, :list
    end

    class DisplayInfo < BaseForm
      field :release_number, Uint32
      field :resource_id_base, Uint32
      field :resource_id_mask, Uint32
      field :motion_buffer_size, Uint32
      field :vendor, Uint16, :length
      field :maximum_request_length, Uint16
      field :screens, Uint8, :length
      field :formats, Uint8, :length
      field :image_byte_order, Signifigance
      field :bitmap_bit_order, Signifigance
      field :bitmap_format_scanline_unit, Uint8
      field :bitmap_format_scanline_pad, Uint8
      field :min_keycode, KeyCode
      field :max_keycode, KeyCode
      unused 4
      field :vendor, String8, :string
      field :formats, FormatInfo, :list
      field :screens, ScreenInfo, :list
    end

    class Rectangle < BaseForm
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
    end

    class Error < BaseForm
      field :error, Uint8
      field :code,  Uint8
      field :sequence_number, Uint16
      field :bad_resource_id, Uint32
      field :minor_opcode, Uint16
      field :major_opcode, Uint8
      unused 21
    end

    # XRender structures

    class DirectFormat < BaseForm
      field :red, Uint16
      field :red_mask, Uint16
      field :green, Uint16
      field :green_mask, Uint16
      field :blue, Uint16
      field :blue_mask, Uint16
      field :alpha, Uint16
      field :alpha_mask, Uint16
    end

    class PictVisual < BaseForm
      field :visual, Uint32
      field :format, Uint32
    end

    class PictDepth < BaseForm
      field :depth, Uint8
      unused 1
      field :visuals, Uint16, :length
      unused 4
      field :visuals, PictVisual, :list
    end
    
    class PictScreen < BaseForm
      field :depths, Uint32, :length
      field :fallback, Uint32
      field :depths, PictDepth, :list
    end

    class PictFormInfo < BaseForm
      field :id, Uint32
      field :type, Uint8
      field :depth, Uint8
      unused 2
      field :direct, DirectFormat
      field :colormap, Colormap
    end
    
    # Requests

    CopyFromParent = 0
    InputOutput = 1
    InputOnly = 2

    CWBackPixel = 0x0002
    CWBorderPixel = 0x0008
    CWEventMask = 0x0800
    CWColorMap  = 0x2000

    KeyPressMask           = 0x00001
    ButtonPressMask        = 0x00004
    PointerMotionMask      = 0x00040
    ExposureMask           = 0x08000
    StructureNotifyMask    = 0x20000
    SubstructureNotifyMask = 0x80000

    class CreateWindow < BaseForm
      field :opcode, Uint8, value: 1
      field :depth,  Uint8
      field :request_length, Uint16, value: ->(cw) { len = 8 + cw.value_list.length }
      field :wid, Window
      field :parent, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      field :window_class, Uint16
      field :visual, VisualID
      field :value_mask, Bitmask
      field :value_list, Uint32, :list
    end

    class MapWindow < BaseForm
      field :opcode, Uint8, value: 8
      unused 1
      field :request_length, Uint16, value: 2
      field :window, Window
    end

    class InternAtom < BaseForm
      field :opcode, Uint8, value: 16
      field :only_if_exists, Bool
      field :request_length, Uint16, value: ->(ia) {
        2+(ia.name.length+3)/4
      }
      field :name, Uint16, value: ->(ia) {
        ia.name.length
      }
      unused 2
      field :name, String8, :string
    end

    class Reply < BaseForm
      field :reply, Uint8
    end

    class InternAtomReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :atom, Atom
      unused 20
    end

    Replace = 0
    Prepend = 1
    Append = 2
    
    class ChangeProperty < BaseForm
      field :opcode, Uint8, value: 18
      field :mode, Uint8
      field :request_length, Uint16, value: ->(cp) {
        #p [:data, cp.data, :len, cp.data.length, :total, 6+(cp.data.length+3)/4]
        6+(cp.data.length+3)/4
      }
      field :window, Window
      field :property, Atom
      field :type, Atom
      field :format, Uint8
      unused 3
      field :data, Uint32, value: ->(cp) {
        cp.data.length / 4
      }
      field :data, Uint8, :list
    end

    class OpenFont < BaseForm
      field :opcode, Uint8, value: 45
      unused 1
      field :request_length, Uint16, value: ->(of) {
        3+(of.name.length+3)/4
      }
      field :fid, Font
      field :name, Uint16, :length
      unused 2
      field :name, String8, :string
    end
    
    class ListFonts < BaseForm
      field :opcode, Uint8, value: 49
      unused 1
      field :request_length, Uint16, value: ->(lf) {
        2+(lf.pattern.length+4)/4
      }
      field :max_names, Uint16
      field :length_of_pattern, Uint16,value: ->(lf) {
        lf.pattern.length
      }
      field :pattern, String8
    end

    class CreatePixmap < BaseForm
      field :opcode, Uint8, value: 53
      field :depth, Uint8
      field :request_length, Uint16, value: 4
      field :pid, Pixmap
      field :drawable, Uint32
      field :width, Uint16
      field :height, Uint16
    end

    class Str < BaseForm
      field :name, Uint8, :length, value: ->(str) { str.name.length }
      field :name, String8Unpadded, :string

      def to_s
        name
      end
    end

    class ListFontsReply < BaseForm
      field :reply, Uint8, value: 1
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :names, Uint16, :length
      unused 22
      field :names, Str, :list
    end

    FunctionMask = 0x1
    PlaneMask = 0x2
    ForegroundMask = 0x04
    BackgroundMask = 0x08
    FontMask = 0x4000

    class CreateGC < BaseForm
      field :opcode, Uint8, value: 55
      unused 1
      field :request_length, Uint16, value: ->(cw) {
        len = 4 + cw.value_list.length
      }
      field :cid, Gcontext
      field :drawable, Drawable
      field :value_mask, Bitmask
      field :value_list, Uint32, :list
    end

    class ChangeGC < BaseForm
      field :opcode, Uint8, value: 56
      unused 1
      field :request_length, Uint16, value: ->(ch) {
        3+ ch.value_list.length
      }
      field :gc, Gcontext
      field :value_mask, Bitmask
      field :value_list, Uint32, :list
    end

    class ClearArea < BaseForm
      field :opcode, Uint8, value: 61
      field :exposures, Bool
      field :request_length, Uint16, value: 4
      field :window, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
    end

    class CopyArea < BaseForm
      field :opcode, Uint8, value: 62
      unused 1
      field :request_length, Uint16, value: 7
      field :src_drawable, Drawable
      field :dst_drawable, Drawable
      field :gc, Gcontext
      field :src_x, Uint16
      field :src_y, Uint16
      field :dst_x, Uint16
      field :dst_y, Uint16
      field :width, Uint16
      field :height, Uint16
    end

    class PolyFillRectangle < BaseForm
      field :opcode, Uint8, value: 70
      unused 1
      field :request_length, Uint16, value: ->(ob) {
        len = 3 + 2*(Array(ob.rectangles).length)
      }
      field :drawable, Drawable
      field :gc, Uint32
      field :rectangles, Rectangle, :list
    end

    Bitmap = 0
    XYPixmap=1
    ZPixmap=2
    
    class PutImage < BaseForm
      field :opcode, Uint8, value: 72
      field :format, Uint8
      field :request_length, Uint16, value: ->(pi) {
        6+(pi.data.length+3)/4
      }
      field :drawable, Drawable
      field :gc, Gcontext
      field :width, Uint16
      field :height, Uint16
      field :dstx, Int16
      field :dsty, Int16
      field :left_pad, Uint8
      field :depth, Uint8
      unused 2
      field :data, String8 #, :string
    end

    class ImageText8 < BaseForm
      field :opcode, Uint8, value: 76
      field :n, Uint8, :length
      field :request_length, Uint16, value: ->(it) { 4+(it.n.length+3)/4 }
      field :drawable, Drawable
      field :gc, Gcontext
      field :x, Int16
      field :y, Int16
      field :n, String8, :string
    end

    class ImageText16 < BaseForm
      field :opcode, Uint8, value: 77
      field :n, Uint8, :length
      field :request_length, Uint16, value: ->(it) { 4+(it.n.length*2+3)/4 }
      field :drawable, Drawable
      field :gc, Gcontext
      field :x, Int16
      field :y, Int16
      field :n, String16, :string
    end

    class CreateColormap < BaseForm
      field :opcode, Uint8, value: 78
      field :alloc, Uint8
      field :request_length, Uint16, value: 4
      field :mid, Colormap
      field :window, Window
      field :visual, Uint32
    end

    class QueryExtension < BaseForm
      field :opcode, Uint8, value: 98
      unused 1
      field :request_length, Uint16, value: ->(qe) { 2+(qe.name.length+3)/4 }
      field :name, Uint16, :length
      unused 2
      field :name, String8
    end

    class QueryExtensionReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :reply_length, Uint32
      field :present, Bool
      field :major_opcode, Uint8
      field :first_event, Uint8
      field :first_error, Uint8
      unused 20
    end

    class GetKeyboardMapping < BaseForm
      field :opcode, Uint8, value: 101
      unused 1
      field :request_length, Uint16, value: 2
      field :first_keycode, Uint8
      field :count, Uint8
      unused 2
    end

    class GetKeyboardMappingReply < Reply
      field :keysyms_per_keycode, Uint8
      field :sequence_number, Uint16
      field :reply_length, Uint32
      unused 24
      field :keysyms, Keysym, :list
    end

    # Events (page ~157)
    # FIXME: Events have quite a bit of redundancy, but unfortunately
    # BaseForm can't handle subclassing well.

    Shift = 0x001
    Lock  = 0x002
    Control = 0x004
    Mod1 = 0x008
    Mod2 = 0x010
    Mod3 = 0x0020
    Mod4 = 0x0040
    Mod5 = 0x0080
    Button1 = 0x100
    Button2 = 0x200
    Button3 = 0x400
    Button4 = 0x800
    Button5 = 0x1000

    class Event < BaseForm
      field :code, Uint8
    end

    class SimpleEvent < Event
      field :detail, Uint8
      field :sequence_number, Uint16
    end

    class PressEvent < SimpleEvent
      field :time, Uint32
      field :root, Window
      field :event, Window
      field :child, Window
      field :root_x, Int16
      field :root_y, Int16
      field :event_x, Int16
      field :event_y, Int16
      field :state, Uint16
      field :same_screen, Bool
      unused 1
    end

    class ButtonPress < PressEvent
    end

    class KeyPress < PressEvent
    end

    class KeyRelease < PressEvent
    end

    class MotionNotify < PressEvent
    end
    
    class Expose < SimpleEvent
      field :window, Window
      field :x, Uint16
      field :y, Uint16
      field :width, Uint16
      field :height, Uint16
      field :count, Uint16
      unused 14
    end

    class NoExposure < SimpleEvent # 14
      field :drawable, Drawable
      field :minor_opcode, Uint16
      field :major_opcode, Uint8
      unused 21
    end

    class MapNotify < Event
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :override_redirect, Bool
      unused 19
    end

    class ConfigureNotify < Event
      unused 1
      field :sequence_number, Uint16
      field :event, Window
      field :above_sibling, Window
      field :x, Int16
      field :y, Int16
      field :width, Uint16
      field :height, Uint16
      field :border_width, Uint16
      field :override_redirect, Bool
      unused 5
    end


    # XRender extension
    # From https://cgit.freedesktop.org/xorg/proto/renderproto/tree/renderproto.h
    class XRenderQueryVersion < BaseForm
      field :req_type, Uint8
      field :render_req_type, Uint8, value: 0
      field :request_length, Uint16, value: 3
      field :major_version, Uint32
      field :minor_version, Uint32
    end

    class XRenderQueryVersionReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :request_length, Uint32
      field :major_version, Uint32
      field :minor_version, Uint32
      #unused 16
    end

    class XRenderQueryPictFormats < BaseForm
      field :req_type, Uint8
      field :render_req_type, Uint8, value: 1
      field :request_length, Uint16, value: 1
    end

    class XRenderQueryPictFormatsReply < Reply
      unused 1
      field :sequence_number, Uint16
      field :length, Uint32
      field :formats, Uint32, :length
      field :screens, Uint32, :length
      field :depths, Uint32, :length
      field :visuals, Uint32, :length
      field :subpixel, Uint32, :length
      unused 4
      field :formats, PictFormInfo, :list
      field :screens, PictScreen, :list
      field :subpixels, Uint32, :list
     end

     class XRenderCreatePicture < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 4
       field :request_length, Uint16, value: ->(cp) {
         5 + Array(cp.value_list).length
       }
       field :pid, Uint32
       field :drawable, Uint32
       field :format, Uint32
       field :value_mask, Uint32
       field :value_list, Uint32, :list
     end

     class XRenderCreateGlyphSet < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 17
       field :request_length, Uint16, value: 3
       field :gsid, Uint32
       field :format, Uint32
     end

     class GlyphInfo < BaseForm
       field :width,  Uint16
       field :height, Uint16
       field :x, Int16
       field :y, Int16
       field :x_off, Int16
       field :y_off, Int16
     end

     class XRenderAddGlyphs < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 20
       field :request_length, Uint16, value: ->(ag) {
         if ag.glyphs.length != ag.glyphids.length
           raise "Mismatch: Expected XRenderAddGlyphs glyphs and glyphids to be same length"
         end

         # GlyphInfo length == 3 + Glyphid length == 1
         3 + ag.glyphs.length * 4 + (ag.data.length+3)/4
       }
       field :glyphset, Uint32
       field :glyphs,   Uint32, :length
       field :glyphids, Uint32, :list
       field :glyphs,   GlyphInfo, :list
       field :data,     String8
     end

     class XRenderColor < BaseForm
       field :red,   Uint16
       field :green, Uint16
       field :blue,  Uint16
       field :alpha, Uint16
     end

     class GlyphElt32 < BaseForm
       field :glyphs, Uint8, :length
       unused 3
       field :delta_x, Uint16
       field :delta_y, Uint16
       field :glyphs, Uint32, :list
     end

     # This is *also* the same as XRenderCOmpositeGlyphs16 and 8 w/other render_req_type,
     # but do we care?
     class XRenderCompositeGlyphs32 < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 25
       field :request_length, Uint16, value: ->(ch) {
         7 + (ch.glyphcmds[0].glyphs.length + 2) # per glyphcmd
       }
       field :op, Uint8
       unused 3
       field :src, Uint32
       field :dst, Uint32
       field :mask_format, Uint32
       field :glyphset, Uint32
       field :xsrc, Uint16
       field :ysrc, Uint16
       # FIXME:
       # We say this is a list, because technically it is
       # But currently it'll break with more than one item.
       field :glyphcmds, GlyphElt32, :list
     end

     class XRenderFillRectangles < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 26
       field :request_length, Uint16, value: ->(fr) { 5 + fr.rects.length * 2 }
       field :op, Uint8
       unused 3
       field :dst, Uint32
       field :color, Uint32
       field :rects, Rectangle, :list
     end

     class XRenderCreateSolidFill < BaseForm
       field :req_type, Uint8
       field :render_req_type, Uint8, value: 33
       field :request_length, Uint16, value: 4
       field :fill, Uint32
       field :color, XRenderColor
     end
  end
end
