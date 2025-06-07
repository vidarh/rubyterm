#!/usr/bin//ruby --disable-did_you_mean

require("pty")
require("io/console")
(("Ignoring rbconfig"; unless defined?(Gem)
  module Gem
    def self.ruby_api_version
      RbConfig::CONFIG["ruby_version"]
    end

    def self.extension_api_version
      if "no" == RbConfig::CONFIG["ENABLE_SHARED"]
        "#{ruby_api_version}-static"
      else
        ruby_api_version
      end
    end
  end
end; if Gem.respond_to?(:discover_gems_on_require=)
  Gem.discover_gems_on_require=false
else
  kernel = (class << ::Kernel
    self
  end)
  [kernel, ::Kernel].each { |k|
    if k.private_method_defined?(:gem_original_require)
      private_require = k.private_method_defined?(:require)
      k.send(:remove_method, :require)
      k.send(:define_method, :require, k.instance_method(:gem_original_require))
      if private_require
        k.send(:private, :require)
      end
    end
  }
end; $:.unshift(File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/citrus-3.0.2/lib")); $:.unshift("/home/vidarh/src/repos/ruby-x11/lib"); $:.unshift("/home/vidarh/Desktop/Projects/fonts/skrift/lib"); $:.unshift("/home/vidarh/Desktop/Projects/skrift-x11/lib"); $:.unshift(File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/toml-rb-2.2.0/lib"))))
(class EscapeParser
  attr_reader(:str)

  def initialize
    @state = :start
    @str = ""
  end

  def put(ch)
    @str << ch.chr
    case @state
    when :start
      case ch.chr
      when "["
        @state = :csi
      when "]"
        @state = :oc
      when /\w|[=>|}~6-9]/
        @state = :complete
      end
    when :csi
      if /[[:alpha:]]|[[:cntrl:]]|[@]/.match(ch.chr)
        @state = :complete
      end
    when :oc
      if ch == 7
        @state = :complete
      end
    else
      raise("Complete")
    end
  end

  def complete?
    @state == :complete
  end
end)
((PALETTE256 = [0, 8388608, 32768, 8421376, 128, 8388736, 32896, 12632256, 8421504, 16711680, 65280, 16776960, 255, 16711935, 65535, 16777215] + [0, 95, 135, 175, 215, 255].repeated_permutation(3).sort.map { |ary|
  (ary[0] << 16) + (ary[1] << 8) + ary[2]
} + (8..244).step(10).map { |n|
  (n << 16) + (n << 8) + n
}; PALETTE_BASIC = [0, 14104375, 6335545, 11441427, 6718689, 12080340, 2076035, 13421772, 8223336, 16725815, 8444985, 16773139, 6722815, 14177535, 2088355, 16777215]))
((((class Set
  include(Enumerable)

  def self.[](*ary)
    new(ary)
  end

  def initialize(enum = nil, &block)
    @hash ||= Hash.new(false)
    enum.nil? and return
    if block
      do_with_enum(enum) { |o|
        add(block[o])
      }
    else
      merge(enum)
    end
  end

  def compare_by_identity
    if @hash.respond_to?(:compare_by_identity)
      @hash.compare_by_identity
      self
    else
      raise(NotImplementedError, "#{self.class.name}##{__method__} is not implemented")
    end
  end

  def compare_by_identity?
    @hash.respond_to?(:compare_by_identity?) && @hash.compare_by_identity?
  end

  def do_with_enum(enum, &block)
    if enum.respond_to?(:each_entry)
      if block
        enum.each_entry(&block)
      end
    else
      if enum.respond_to?(:each)
        if block
          enum.each(&block)
        end
      else
        raise(ArgumentError, "value must be enumerable")
      end
    end
  end
  private(:do_with_enum)
  nil
  if Kernel.instance_method(:initialize_clone).arity != 1
    nil
  else
    nil
  end

  def freeze
    @hash.freeze
    super
  end

  def size
    @hash.size
  end
  alias :length :size

  def empty?
    @hash.empty?
  end

  def clear
    @hash.clear
    self
  end

  def replace(enum)
    if enum.instance_of?(self.class)
      @hash.replace(enum.instance_variable_get(:@hash))
      self
    else
      do_with_enum(enum)
      clear
      merge(enum)
    end
  end

  def to_a
    @hash.keys
  end
  nil

  def flatten_merge(set, seen = Set.new)
    set.each { |e|
      if e.is_a?(Set)
        if seen.include?(e_id = e.object_id)
          raise(ArgumentError, "tried to flatten recursive Set")
        end
        seen.add(e_id)
        flatten_merge(e, seen)
        seen.delete(e_id)
      else
        add(e)
      end
    }
    self
  end
  protected(:flatten_merge)

  def flatten
    self.class.new.flatten_merge(self)
  end
  nil

  def include?(o)
    @hash[o]
  end
  alias :member? :include?

  def superset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:>=)
      @hash >= set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size >= set.size && set.all? { |o|
        include?(o)
      }
    else
      raise(ArgumentError, "value must be a set")
    end
  end
  alias :>= :superset?

  def proper_superset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:>)
      @hash > set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size > set.size && set.all? { |o|
        include?(o)
      }
    else
      raise(ArgumentError, "value must be a set")
    end
  end
  alias :> :proper_superset?

  def subset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:<=)
      @hash <= set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size <= set.size && all? { |o|
        set.include?(o)
      }
    else
      raise(ArgumentError, "value must be a set")
    end
  end
  alias :<= :subset?

  def proper_subset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:<)
      @hash < set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size < set.size && all? { |o|
        set.include?(o)
      }
    else
      raise(ArgumentError, "value must be a set")
    end
  end
  alias :< :proper_subset?

  def <=>(set)
    unless set.is_a?(Set)
      return
    end
    case size <=> set.size
    when -1
      if proper_subset?(set)
        -1
      end
    when 1
      if proper_superset?(set)
        1
      end
    else
      if self == set
        0
      end
    end
  end

  def intersect?(set)
    case set
    when Set
      if size < set.size
        any? { |o|
          set.include?(o)
        }
      else
        set.any? { |o|
          include?(o)
        }
      end
    when Enumerable
      set.any? { |o|
        include?(o)
      }
    else
      raise(ArgumentError, "value must be enumerable")
    end
  end
  nil

  def each(&block)
    block or return enum_for(__method__) {
      size
    }
    @hash.each_key(&block)
    self
  end

  def add(o)
    @hash[o] = true
    self
  end
  alias :<< :add
  nil

  def delete(o)
    @hash.delete(o)
    self
  end

  def delete?(o)
    if include?(o)
      delete(o)
    end
  end

  def delete_if
    block_given? or return enum_for(__method__) {
      size
    }
    select { |o|
      yield(o)
    }.each { |o|
      @hash.delete(o)
    }
    self
  end

  def keep_if
    block_given? or return enum_for(__method__) {
      size
    }
    reject { |o|
      yield(o)
    }.each { |o|
      @hash.delete(o)
    }
    self
  end

  def collect!
    block_given? or return enum_for(__method__) {
      size
    }
    set = self.class.new
    each { |o|
      set << yield(o)
    }
    replace(set)
  end
  alias :map! :collect!

  def reject!(&block)
    block or return enum_for(__method__) {
      size
    }
    n = size
    delete_if(&block)
    if size != n
      self
    end
  end

  def select!(&block)
    block or return enum_for(__method__) {
      size
    }
    n = size
    keep_if(&block)
    if size != n
      self
    end
  end
  alias :filter! :select!

  def merge(enum)
    if enum.instance_of?(self.class)
      @hash.update(enum.instance_variable_get(:@hash))
    else
      do_with_enum(enum) { |o|
        add(o)
      }
    end
    self
  end

  def subtract(enum)
    do_with_enum(enum) { |o|
      delete(o)
    }
    self
  end

  def |(enum)
    dup.merge(enum)
  end
  alias :+ :|
  alias :union :|

  def -(enum)
    dup.subtract(enum)
  end
  alias :difference :-

  def &(enum)
    n = self.class.new
    if enum.is_a?(Set)
      if enum.size > size
        each { |o|
          if enum.include?(o)
            n.add(o)
          end
        }
      else
        enum.each { |o|
          if include?(o)
            n.add(o)
          end
        }
      end
    else
      do_with_enum(enum) { |o|
        if include?(o)
          n.add(o)
        end
      }
    end
    n
  end
  alias :intersection :&

  def ^(enum)
    n = Set.new(enum)
    each { |o|
      unless n.delete?(o)
        n.add(o)
      end
    }
    n
  end

  def ==(other)
    if self.equal?(other)
      true
    else
      if other.instance_of?(self.class)
        @hash == other.instance_variable_get(:@hash)
      else
        if other.is_a?(Set) && self.size == other.size
          other.all? { |o|
            @hash.include?(o)
          }
        else
          false
        end
      end
    end
  end

  def hash
    @hash.hash
  end

  def eql?(o)
    unless o.is_a?(Set)
      return false
    end
    @hash.eql?(o.instance_variable_get(:@hash))
  end

  def reset
    if @hash.respond_to?(:rehash)
      @hash.rehash
    else
      if frozen?
        raise(FrozenError, "can't modify frozen #{self.class.name}")
      end
    end
    self
  end
  alias :=== :include?

  def classify
    block_given? or return enum_for(__method__) {
      size
    }
    h = {}
    each { |i|
      (h[yield(i)] ||= self.class.new).add(i)
    }
    h
  end
  nil

  def join(separator = nil)
    to_a.join(separator)
  end
  InspectKey = :__inspect_key__

  def inspect
    ids = (Thread.current[InspectKey] ||= [])
    if ids.include?(object_id)
      return sprintf("#<%s: {...}>", self.class.name)
    end
    ids << object_id

    begin
      return sprintf("#<%s: {%s}>", self.class, to_a.inspect[1..-2])
    ensure
      ids.pop
    end
  end
  alias :to_s :inspect
  nil
  nil
end; module Enumerable
  unless method_defined?(:to_set)
    nil
  end
end; autoload(:SortedSet, "#{__dir__}/set/sorted_set"))); BOLD = 2; FAINT = 4; ITALICS = 8; UNDERLINE = 16; BLINK = 32; RAPID_BLINK = 64; INVERSE = 128; INVISIBLE = 256; CROSSED_OUT = 512; DBL_UNDERLINE = 1024; OVERLINE = 2048; class Line < Array
end; class ScrBuf
  def initialize
    @scrbuf = []
    @lineattrs = []
  end

  def [](y)
    @lineattrs[y] ||= 0
    @scrbuf[y] ||= []
  end

  def []=(i, line)
    @scrbuf[i] = line
  end

  def delete_line(y)
    @lineattrs.slice!(y)
    @scrbuf.slice!(y)
  end

  def insert_line(y)
    @lineattrs.insert(y, 0)
    @scrbuf.insert(y, [])
  end

  def lineattrs(y)
    @lineattrs[y]
  end

  def set_lineattrs(y, v)
    @lineattrs[y] = v
  end

  def each_character
    @scrbuf.each_with_index { |line, y|
      if line
        line.each_with_index { |cell, x|
          yield(x, y, cell)
        }
      end
    }
  end

  def each_character_between(spos, epos)
    if spos.end > epos.end
      (spos, epos) = [epos, spos]
    else
      if spos.end == epos.end
        if spos.first > epos.first
          (spos, epos) = [epos, spos]
        end
      end
    end
    x = spos.first
    (xend, ymax) = [epos.first, epos.end]
    (spos.end..ymax).each { |y|
      line = @scrbuf[y] || ""
      xmax = if y == ymax
        xend + 1
      else
        line.length - 1
      end
      xmax = [xmax, line.length - 1].min
      if xmax < 0
        xmax = 0
      end
      while x <= xmax
        cell = line[x]
        yield(x, y, cell)
        x += 1
      end
      y += 1
      x = 0
    }
  end
end; class TermBuffer
  attr_accessor(:scroll_start, :scroll_end)

  def initialize
    clear
    @scroll_start = nil
    @scroll_end = nil
  end

  def get(x, y)
    (@scrbuf[y] || [])[x]
  end

  def each_character(&block)
    @scrbuf.each_character(&block)
  end

  def each_character_between(spos, epos, &block)
    @scrbuf.each_character_between(spos, epos, &block)
  end

  def lineattrs(y)
    @scrbuf.lineattrs(y)
  end

  def set_lineattrs(y, v)
    @scrbuf.set_lineattrs(y, v)
  end

  def delete_line(y)
    @scrbuf.delete_line(y)
    if @scroll_start
      @scrbuf.insert_line(@scroll_start)
    end
  end

  def insert_line(y)
    @scrbuf.insert_line(y)
    if @scroll_end
      @scrbuf.delete_line(@scroll_end)
    end
  end

  def scroll_up
    delete_line(@scroll_start.to_i)
  end

  def insert(x, y, num, cell)
    l = @scrbuf[y]
    num.times.each { |i|
      l.insert(x + i, cell)
    }
  end

  def blinky
    @blinky
  end

  def set(x, y, ch, fg = 0, bg = 0, flags = 0)
    if flags.anybits?(BLINK | RAPID_BLINK)
      @blinky << [x, y]
    else
      @blinky.delete([x, y])
    end
    @scrbuf[y] ||= []
    @scrbuf[y][x] = [ch.ord, fg, bg, flags]
  end

  def clear_line(y, start_x = 0, end_x = nil)
    if !end_x
      @scrbuf[y] = Array(@scrbuf[y])[0...start_x]
    else
      (start_x..end_x).each { |x|
        set(x, y, " ")
      }
    end
  end

  def clear
    @blinky = Set.new
    @scrbuf = ScrBuf.new
  end
end))
(($kmap = nil; def update_keymap(dpy)
  reply = dpy.get_keyboard_mapping
  if reply
    $kmap = reply.keysyms.map { |c|
      if c == 0
        nil
      else
        if X11::KeySyms[c]
          X11::KeySyms[c]
        else
          if c < 256
            c.chr(Encoding::ISO_8859_1)
          else
            if c.between?(65456, 65465)
              "KP_#{c - 65456}".to_sym
            else
              if c.between?(65470, 65504)
                "f#{c - 65470 + 1}".to_sym
              else
                if c.between?(65288, 65535)
                  raise("keyboard_#{c.to_s(16)}".to_s)
                else
                  if c.between?(16777472, 17891327)
                    (c - 16777472).chr(Encoding::UTF_32) rescue c.to_s(16)
                  else
                    STDERR.puts("keymap: unknown_#{c.to_s(16)}")
                  end
                end
              end
            end
          end
        end
      end
    }.each_slice(reply.keysyms_per_keycode).to_a
    p($kmap[47 - dpy.display_info.min_keycode])
  end
end; def lookup_keysym(dpy, event)
  if !$kmap
    update_keymap(dpy)
  end
  $kmap[event.detail - dpy.display_info.min_keycode] rescue nil
end; SPECIALS = { "+" => :"ctrl_+", "-" => :"ctrl_-" }; def lookup_string(dpy, event)
  ks = Array(lookup_keysym(dpy, event))
  str = ""
  shift = event.state.anybits?(1)
  meta = event.state.anybits?(8)
  ctrl = event.state.anybits?(4)
  i = if shift && ks[1]
    1
  else
    0
  end
  if ctrl && SPECIALS[ks[i]]
    return SPECIALS[ks[i]]
  end
  if shift
    case ks[i]
    when :XK_Down
      return :shift_down, nil
    when :XK_Up
      return :shift_up, nil
    end
  end
  if ks[i].is_a?(String)
    if ctrl
      str = (ks[i][0].ord & 159).chr
    else
      if meta
        str = "\e#{ks[i]}"
      else
        str = ks[i]
      end
    end
  end
  p([ks[i], str])
  return ks[i], str
end; KEYMAP = { enter: "\r", backspace: "\u007F", tab: "\t", f1: "\e[11~", f2: "\e[12~", f3: "\e[13~", f4: "\e[14~", f5: "\e[15~", f6: "\e[16~", f7: "\e[17~", f8: "\e[18~", f9: "\e[19~", f10: "\e[20~", f11: "\e[21~", f12: "\e[22~", shift_up: "\e[1;2A", shift_down: "\e[1;2B", XK_Left: "\e[D", XK_Right: "\e[C", XK_Down: "\e[B", XK_ISO_Left_Tab: "\t", XK_Up: "\e[A", XK_Delete: "\e[P", XK_Page_Up: "\e[5~", XK_Page_Down: "\e[6~" }; def keysym_to_vt102(ks)
  KEYMAP[ks]
end))
((((GMetrics = Struct.new(:advance_width, :left_side_bearing, :y_offset, :min_width, :min_height); LMetrics = Struct.new(:ascender, :descender, :line_gap); Image = Struct.new(:width, :height, :pixels); Kerning = Struct.new(:x_shift, :y_shift); (module Skrift
  VERSION = "0.2.0"
end); (class SFT
  DOWNWARD_Y = 1
  attr_accessor(:font, :x_scale, :y_scale, :x_offset, :y_offset, :flags)

  def initialize(font)
    @font = font
    @x_scale = 32
    @y_scale = 32
    @x_offset = 0
    @y_offset = 0
    @flags = SFT::DOWNWARD_Y
  end

  def lookup(codepoint)
    return font.glyph_id(codepoint)
  end

  def glyph_bbox(outline)
    box = @font.glyph_bbox(outline)
    if !box
      raise
    end
    xs = @x_scale.to_f / @font.units_per_em
    ys = @y_scale.to_f / @font.units_per_em
    box[0] = (box[0] * xs + @x_offset).floor
    box[1] = (box[1] * ys + @y_offset).floor
    box[2] = (box[2] * xs + @x_offset).ceil
    box[3] = (box[3] * ys + @y_offset).ceil
    return box
  end

  def gmetrics(glyph)
    if glyph.nil?
      return nil
    end
    if glyph < 0
      raise("out of bounds")
    end
    xs = @x_scale.to_f / @font.units_per_em
    (adv, lsb) = @font.hor_metrics(glyph)
    if adv.nil?
      return nil
    end
    metrics = GMetrics.new(adv * xs, lsb * xs + @x_offset)
    outline = @font.outline_offset(glyph)
    if outline.nil?
      return metrics
    end
    bbox = glyph_bbox(outline)
    if !bbox
      return nil
    end
    metrics.min_width=bbox[2] - bbox[0] + 1
    metrics.min_height=bbox[3] - bbox[1] + 1
    metrics.y_offset=if @flags & SFT::DOWNWARD_Y != 0
      bbox[3]
    else
      bbox[1]
    end
    return metrics
  end

  def lmetrics
    hhea = font.reqtable("hhea")
    factor = @y_scale.to_f / @font.units_per_em
    LMetrics.new(font.geti16(hhea + 4) * factor, font.geti16(hhea + 6) * factor, font.geti16(hhea + 8) * factor)
  end

  def render(glyph, image)
    outline = @font.outline_offset(glyph)
    if outline.nil?
      return false
    end
    if outline.nil?
      return true
    end
    bbox = glyph_bbox(outline)
    if !bbox
      return false
    end
    xr = [@x_scale.to_f / @font.units_per_em, 0.0, @x_offset - bbox[0]]
    ys = @y_scale.to_f / @font.units_per_em
    if @flags.allbits?(SFT::DOWNWARD_Y)
      transform = [xr, [0.0, -ys, bbox[3] - @y_offset]]
    else
      transform = [xr, [0.0, +ys, @y_offset - bbox[1]]]
    end
    outl = @font.decode_outline(outline)
    if outl
      outl.render(transform, image)
    end
  end

  def kerning(left_glyph, right_glyph)
    @font.kerning[[left_glyph, right_glyph].pack("n*")]
  end
end); ((def midpoint(a, b)
  (a + b) * 0.5
end; def transform_points(trf, pts)
  pts.each { |pt|
    pt[0] = trf[0][0] * pt[0] + trf[0][1].*(pt[1]) + trf[0][2]
    pt[1] = trf[1][0] * pt[0] + trf[1][1].*(pt[1]) + trf[1][2]
  }
end; class Outline
  Segment = Struct.new(:beg, :end, :ctrl)
  attr_reader(:points, :segments)

  def initialize
    (@points, @segments) = [[], []]
  end

  def clip_points(width, height)
    @points.each { |pt|
      pt[0] = pt[0].clamp(0, width.pred)
      pt[1] = pt[1].clamp(0, height.pred)
    }
  end

  def render(transform, image)
    transform_points(transform, @points)
    clip_points(image.width, image.height)
    buf = Raster.new(image.width, image.height)
    @segments.each { |seg|
      if seg.ctrl
        tesselate_curve(seg)
      else
        buf.draw_line(@points[seg.beg], @points[seg.end])
      end
    }
    image.pixels=buf.post_process
    return image
  end

  def tesselate_curve(curve)
    if is_flat(curve)
      @segments << Segment.new(curve.beg, curve.end)
      return
    end
    ctrl0 = @points.length
    @points << midpoint(@points[curve.beg], @points[curve.ctrl])
    ctrl1 = @points.length
    @points << midpoint(@points[curve.ctrl], @points[curve.end])
    pivot = @points.length
    @points << midpoint(@points[ctrl0], @points[ctrl1])
    tesselate_curve(Segment.new(curve.beg, pivot, ctrl0))
    tesselate_curve(Segment.new(pivot, curve.end, ctrl1))
  end

  def is_flat(curve)
    g = @points[curve.ctrl] - @points[curve.beg]
    h = @points[curve.end] - @points[curve.beg]
    (g[0] * h[1] - g[1].*(h[0])).abs <= 2.0
  end
end)); (class Raster
  Cell = Struct.new(:area, :cover)

  class Vector
    def initialize(x, y)
      @x = x
      @y = y
    end

    def [](i)
      if i == 0
        return @x
      end
      if i == 1
        return @y
      end
      if i > 1
        raise
      end
    end

    def []=(i, v)
      if i == 0
        @x = v
      end
      if i == 1
        @y = v
      end
      if i > 1
        raise
      end
    end

    def *(f)
      Vector.new(@x * f, @y * f)
    end

    def +(other)
      Vector.new(@x + other[0], @y + other[1])
    end

    def -(other)
      Vector.new(@x - other[0], @y - other[1])
    end

    def min
      if @x < @y
        @x
      else
        @y
      end
    end
  end

  def initialize(width, height)
    @width = width
    @height = height
    @cells = (0..(width * height - 1)).map {
      Cell.new(0.0, 0.0)
    }
  end

  def post_process
    accum = 0.0
    (@width * @height).times.collect { |i|
      cell = @cells[i]
      value = (accum + cell.area).abs
      value = [value, 1.0].min * 255.0 + 0.5
      accum += cell.cover
      value.to_i & 255
    }
  end

  def draw_line(origin, goal)
    prev_distance = 0.0
    num_steps = 0
    delta = goal - origin
    dir_x = delta[0] <=> 0
    dir_y = delta[1] <=> 0
    next_crossing = Vector.new(0.0, 0.0)
    pixel = Vector.new(0, 0)
    if dir_y == 0
      return
    end
    crossing_incr_x = if dir_x != 0
      (1.0 / delta[0]).abs
    else
      1.0
    end
    crossing_incr_y = (1.0 / delta[1]).abs
    if dir_x == 0
      pixel[0] = origin[0].floor
      next_crossing[0] = 100.0
    else
      if dir_x > 0
        pixel[0] = origin[0].floor
        next_crossing[0] = crossing_incr_x - (origin[0] - pixel[0]).*(crossing_incr_x)
        num_steps += goal[0].ceil - origin[0].floor - 1
      else
        pixel[0] = origin[0].ceil - 1
        next_crossing[0] = (origin[0] - pixel[0]) * crossing_incr_x
        num_steps += origin[0].ceil - goal[0].floor - 1
      end
    end
    if dir_y > 0
      pixel[1] = origin[1].floor
      next_crossing[1] = crossing_incr_y - (origin[1] - pixel[1]).*(crossing_incr_y)
      num_steps += goal[1].ceil - origin[1].floor - 1
    else
      pixel[1] = origin[1].ceil - 1
      next_crossing[1] = (origin[1] - pixel[1]) * crossing_incr_y
      num_steps += origin[1].ceil - goal[1].floor - 1
    end
    next_distance = next_crossing.min
    half_delta_x = 0.5 * delta[0]
    setcell = ->(nd) {
      x_average = origin[0] + (prev_distance + nd).*(half_delta_x) - pixel[0]
      y_difference = (nd - prev_distance).to_f * delta[1]
      cell = @cells[pixel[1] * @width + pixel[0]]
      cell.cover += y_difference
      cell.area += (1.0 - x_average) * y_difference
    }
    num_steps.times {
      setcell.call(next_distance)
      prev_distance = next_distance
      along_x = next_crossing[0] < next_crossing[1]
      pixel += if along_x
        Vector.new(dir_x, 0)
      else
        Vector.new(0, dir_y)
      end
      next_crossing += if along_x
        Vector.new(crossing_incr_x, 0.0)
      else
        Vector.new(0.0, crossing_incr_y)
      end
      next_distance = next_crossing.min
    }
    setcell.call(1.0)
  end
end); (class Font
  FILE_MAGIC = ["\u0000\u0001\u0000\u0000", "true", "OTTO"]
  attr_reader(:memory, :units_per_em)

  def initialize(memory)
    @memory = memory
    if !FILE_MAGIC.member?(at(0, 4))
      raise("Unsupported format (magic value: #{at(0, 4).inspect})")
    end
    head = reqtable("head")
    @units_per_em = getu16(head + 18)
    @loca_format = geti16(head + 50)
    hhea = reqtable("hhea")
    @num_long_hmtx = getu16(hhea + 34)
  end

  def Font.load(filename)
    memory = File.read(filename).force_encoding("ASCII-8BIT")
    Font.new(memory)
  end

  def at(offset, len = 1)
    if offset.to_i + len.to_i >= @memory.size
      raise("Out of bounds #{offset} / len #{len} (max: #{@memory.size})")
    end
    @memory[offset..(offset + len - 1)]
  end

  def getu8(offset)
    at(offset).ord
  end

  def geti8(offset)
    at(offset).unpack1("c")
  end

  def getu16(offset)
    at(offset, 2).unpack1("S>")
  end

  def geti16(offset)
    at(offset, 2).unpack1("s>")
  end

  def getu32(offset)
    at(offset, 4).unpack1("N")
  end

  def tables
    @tables ||= Hash[*getu16(4).times.map { |t|
      [at(t * 16 + 12, 4), getu32(t * 16 + 20)]
    }.flatten]
  end

  def reqtable(tag)
    tables[tag] || raise("Unable to get table '#{tag}'")
  end

  def gettable(tag)
    tables[tag]
  end

  def glyph_bbox(outline)
    box = at(outline + 2, 8).unpack("s>*")
    if box[2] < box[0] || box[3] < box[1]
      raise("Broken bbox #{box.inspect}")
    end
    return box
  end

  def outline_offset(glyph)
    loca = reqtable("loca")
    glyf = reqtable("glyf")
    if @loca_format == 0
      base = loca + 2.*(glyph)
      this = 2 * getu16(base)
      next_ = 2 * getu16(base + 2)
    else
      (this, next_) = at(loca + 4.*(glyph), 8).unpack("NN")
    end
    return this == next_ ? nil : glyf + this
  end

  def each_cmap_entry
    cmap = reqtable("cmap")
    getu16(cmap + 2).times { |idx|
      entry = cmap + 4 + idx.*(8)
      type = getu16(entry) * 64 + getu16(entry + 2)
      table = cmap + getu32(entry + 4)
      format = getu16(table)
      yield(type, table, format)
    }
  end

  def glyph_id(char_code)
    each_cmap_entry { |type, table, format|
      if (type == 4 || type == 202)
        if format == 12
          return cmap_fmt12_13(table, char_code, 12)
        end
        return nil
      end
    }
    each_cmap_entry { |type, table, format|
      if type == 3 || type == 193
        if format == 4
          return cmap_fmt4(table + 6, char_code)
        end
        if format == 6
          return cmap_fmt6(table + 6, char_code)
        end
        return nil
      end
    }
    return nil
  end

  def hor_metrics(glyph)
    hmtx = reqtable("hmtx")
    if hmtx.nil?
      return nil
    end
    if glyph < @num_long_hmtx
      offset = hmtx + 4.*(glyph)
      return getu16(offset), geti16(offset + 2)
    end
    boundary = hmtx + 4.*(@num_long_hmtx)
    if boundary < 4
      return nil
    end
    offset = boundary - 4
    advance_width = getu16(offset)
    offset = boundary + 2.*((glyph - @num_long_hmtx))
    return advance_width, geti16(offset)
  end

  def cmap_fmt4(table, char_code)
    if char_code > 65535
      return nil
    end
    seg_count_x2 = getu16(table)
    if (seg_count_x2 & 1) != 0 || seg_count_x2 == 0
      raise("Error")
    end
    end_codes = table + 8
    start_codes = end_codes + seg_count_x2 + 2
    id_deltas = start_codes + seg_count_x2
    id_range_offsets = id_deltas + seg_count_x2
    @ecodes ||= at(end_codes, seg_count_x2 - 1).unpack("n*")
    seg_id_x_x2 = @ecodes.bsearch_index { |i|
      i > char_code
    }.to_i * 2
    start_code = getu16(start_codes + seg_id_x_x2)
    if start_code > char_code
      return 0
    end
    id_delta = getu16(id_deltas + seg_id_x_x2)
    if (id_range_offset = getu16(id_range_offsets + seg_id_x_x2)) == 0
      return (char_code + id_delta) & 65535
    end
    id = getu16(id_range_offsets + seg_id_x_x2 + id_range_offset + 2.*((char_code - start_code)))
    return id ? (id + id_delta) & 65535 : 0
  end

  def decode_outline(offset, rec_depth = 0, outl = Outline.new)
    num_contours = geti16(offset)
    if num_contours == 0
      return nil
    end
    if num_contours > 0
      return simple_outline(offset + 10, num_contours, outl)
    end
    return compound_outline(offset + 10, rec_depth, outl)
  end

  def cmap_fmt6(table, char_code)
    (first_code, entry_count) = at(table, 4).unpack("S>*")
    if !char_code.between?(first_code, 65535)
      return nil
    end
    char_code -= first_code
    if (char_code >= entry_count)
      return nil
    end
    return getu16(table + 4 + 2.*(char_code))
  end

  def cmap_fmt12_13(table, char_code, which)
    getu32(table + 12).times { |i|
      (first_code, last_code, glyph_offset) = at(table + (i * 12) + 16, 12).unpack("N*")
      if char_code < first_code || char_code > last_code
        next
      end
      if which == 12
        glyph_offset += char_code - first_code
      end
      return glyph_offset
    }
    return nil
  end
  REPEAT_FLAG = 8

  def simple_flags(off, num_pts, flags)
    value = 0
    repeat = 0
    num_pts.times { |i|
      if repeat > 0
        repeat -= 1
      else
        value = getu8(off)
        off += 1
        if value.allbits?(REPEAT_FLAG)
          repeat = getu8(off)
          off += 1
        end
      end
      flags[i] = value
    }
    return off
  end
  X_CHANGE_IS_SMALL = 2
  X_CHANGE_IS_ZERO = 16
  X_CHANGE_IS_POSITIVE = 16

  def simple_points(offset, num_pts, points, base_point)
    [].tap { |flags|
      offset = simple_flags(offset, num_pts, flags)
      accum = 0.0
      accumulate = ->(i, factor) {
        if flags[i].allbits?(X_CHANGE_IS_SMALL * factor)
          offset += 1
          bit = if flags[i].allbits?(X_CHANGE_IS_POSITIVE * factor)
            1
          else
            0
          end
          accum -= (getu8(offset - 1) ^ bit.-@) + bit
        else
          if flags[i].nobits?(X_CHANGE_IS_ZERO * factor)
            offset += 2
            accum += geti16(offset - 2)
          end
        end
        accum
      }
      num_pts.times { |i|
        points << Raster::Vector.new(accumulate.call(i, 1), 0.0)
      }
      accum = 0.0
      num_pts.times { |i|
        points[base_point + i][1] = accumulate.call(i, 2)
      }
    }
  end

  def simple_outline(offset, num_contours, outl = Outline.new)
    base_points = outl.points.length
    num_pts = getu16(offset + (num_contours - 1).*(2)) + 1
    end_pts = at(offset, num_contours * 2).unpack("S>*")
    offset += 2 * num_contours
    end_pts.each_cons(2) { |a, b|
      if b < a.+(1)
        raise
      end
    }
    offset += 2 + getu16(offset)
    flags = simple_points(offset, num_pts, outl.points, base_points)
    beg = 0
    num_contours.times { |i|
      decode_contour(outl, flags, beg, base_points + beg, end_pts[i] - beg + 1)
      beg = end_pts[i] + 1
    }
    outl
  end
  POINT_IS_ON_CURVE = 1

  def decode_contour(outl, flags, off, base_point, count)
    if count < 2
      return true
    end
    if flags[off].allbits?(POINT_IS_ON_CURVE)
      loose_end = base_point
      base_point += 1
      off += 1
      count -= 1
    else
      if flags[off + count - 1].allbits?(POINT_IS_ON_CURVE)
        count -= 1
        loose_end = base_point + count
      else
        loose_end = outl.points.length
        outl.points << midpoint(outl.points[base_point], outl.points[base_point + count - 1])
      end
    end
    beg = loose_end
    ctrl = nil
    count.times { |i|
      cur = base_point + i
      if flags[off + i].allbits?(POINT_IS_ON_CURVE)
        outl.segments << Outline::Segment.new(beg, cur, ctrl)
        beg = cur
        ctrl = nil
      else
        if ctrl
          center = outl.points.length
          outl.points << midpoint(outl.points[ctrl], outl.points[cur])
          outl.segments << Outline::Segment.new(beg, center, ctrl)
          beg = center
        end
        ctrl = cur
      end
    }
    outl.segments << Outline::Segment.new(beg, loose_end, ctrl)
    return true
  end
  OFFSETS_ARE_LARGE = 1
  ACTUAL_XY_OFFSETS = 2
  GOT_A_SINGLE_SCALE = 8
  THERE_ARE_MORE_COMPONENTS = 32
  GOT_AN_X_AND_Y_SCALE = 64
  GOT_A_SCALE_MATRIX = 128

  def compound_outline(offset, rec_depth, outl)
    if rec_depth >= 4
      return nil
    end
    flags = THERE_ARE_MORE_COMPONENTS
    while flags.allbits?(THERE_ARE_MORE_COMPONENTS)
      (flags, glyph) = at(offset, 4).unpack("S>*")
      p([flags, glyph])
      offset += 4
      if (flags & ACTUAL_XY_OFFSETS) == 0
        return nil
      end
      if (flags & OFFSETS_ARE_LARGE) != 0
        local = [[1.0, 0.0, geti16(offset)], [0.0, 1.0, geti16(offset + 2)]]
        offset += 4
      else
        local = [[1.0, 0.0, geti8(offset)], [0.0, 1.0, geti8(offset) + 1]]
        offset += 2
      end
      if flags.allbits?(GOT_A_SINGLE_SCALE)
        local[0][0] = local[1][0] = geti16(offset) / 16384.0
        offset += 2
      else
        if flags.allbits?(GOT_AN_X_AND_Y_SCALE)
          local[0][0] = geti16(offset + 0) / 16384.0
          local[1][0] = geti16(offset + 2) / 16384.0
          offset += 4
        else
          if flags.allbits?(GOT_A_SCALE_MATRIX)
            local[0][0] = geti16(offset + 0) / 16384.0
            local[0][1] = geti16(offset + 2) / 16384.0
            local[1][0] = geti16(offset + 4) / 16384.0
            local[1][1] = geti16(offset + 6) / 16384.0
            offset += 8
          end
        end
      end
      outline = outline_offset(glyph)
      if outline.nil?
        return nil
      end
      base_point = outl.points.length
      if decode_outline(outline, rec_depth + 1, outl).nil?
        return nil
      end
      transform_points(local, outl.points[base_point..-1])
    end
    return outl
  end
  HORIZONTAL_KERNING = 1
  MINIMUM_KERNING = 2
  CROSS_STREAM_KERNING = 4
  OVERRIDE_KERNING = 8

  def kerning
    if @kerning
      return @kerning
    end
    offset = gettable("kern")
    if offset.nil? || getu16(offset) != 0
      return nil
    end
    offset += 4
    @kerning = {}
    getu16(offset - 2).times {
      (length, format, flags) = at(offset + 2, 6).unpack("S>CC")
      offset += 6
      if format == 0 && flags.allbits?(HORIZONTAL_KERNING) && flags.nobits?(MINIMUM_KERNING)
        offset += 8
        getu16(offset - 8).times { |i|
          v = geti16(offset + i.*(6) + 4)
          @kerning[at(offset + i.*(6), 4)] = Kerning.new(*if flags.allbits?(CROSS_STREAM_KERNING)
            [0, v]
          else
            [v, 0]
          end)
        }
      end
      offset += length
    }
    @kerning
  end
end))); (((module Skrift
  module X11
    VERSION = "0.2.1"
  end
end); (((module Skrift
  module X11
    class Glyphs
      def empty_box_image
        img = Image.new(stride, boxh)
        img.pixels=Array.new(img.width * img.height, 0)
        img
      end

      def cache_box(ch)
        @boxcache ||= {}
        if @boxcache[ch]
          c = @boxcache[ch]
        end
        hx = (boxw + 1) / 2
        hy = (boxh + 1) / 2
        yoff = hy * stride
        img = nil
        h = 1
        lh = light_h = [-255, 0, 255, 0, 255]
        hh = heavy_h = [-255, -h, 255, h, 255]
        lv = light_v = [0, -255, 0, 255, 255]
        hv = heavy_v = [-h, -255, h, 255, 255]
        ll = light_l = [-255, 0, 0, 0, 255]
        hl = heavy_l = [-255, -h, 0, h, 255]
        lu = light_u = [0, -255, 0, 0, 255]
        hu = heavy_u = [-h, -255, h, 0, 255]
        lr = light_r = [0, 0, 255, 0, 255]
        hr = heavy_r = [0, -h, 255, h, 255]
        ld = light_d = [0, 0, 0, 255, 255]
        hd = heavy_d = [-h, 0, h, 255, 255]
        hc = [-h, -h, h, h, 255]
        d = 2
        dblc = [-d + 1, -d + 1, d - 1, d - 1, 0]
        light_vc = [0, -d, 0, d, 255]
        dh = double_h = [-255, -d, 255, -d, 255] + [-255, d, 255, d, 255]
        dv = double_v = [-d, -255, -d, 255, 255] + [d, -255, d, 255, 255]
        mask_vbar = [-d + 1, -255, d - 1, 255, 0]
        mask_hbar = [-255, -d + 1, 255, d - 1, 0]
        mt = masktop = [-255, -255, 255, -1, 0]
        maskdtop = [-255, -255, 255, -d - 1, 0]
        ml = maskleft = [-255, -255, -1, 255, 0]
        maskdleft = [-255, -255, -d - 1, 255, 0]
        mb = maskbottom = [-255, 1, 255, 255, 0]
        maskdbottom = [-255, d + 1, 255, 255, 0]
        mr = maskright = [1, -255, 255, 255, 0]
        maskdright = [d + 1, -255, 255, 255, 0]
        mask_lbar = [-255, -d + 1, d - 1, d - 1, 0]
        dlbar = double_lbar = [-255, -d, d, d, 255]
        mask_tbar = [-d + 1, -255, d - 1, d - 1, 0]
        dtbar = double_tbar = [-d, -255, d, d, 255]
        mask_rbar = [-d + 1, -d + 1, 255, d - 1, 0]
        drbar = double_rbar = [-d, -d, 255, d, 255]
        mask_dbar = [-d + 1, -d + 1, d - 1, 255, 0]
        ddbar = double_dbar = [-d, -d, d, 255, 255]
        mask_c = [0, 0, 0, 0, 0]
        hdl = heavy_dl = [heavy_d, heavy_l, hc]
        hdr = heavy_dr = [heavy_d, heavy_r, hc]
        hlu = heavy_lu = [heavy_l, heavy_u, hc]
        hru = heavy_ru = [heavy_r, heavy_u, hc]
        ldl = light_dl = [light_d, light_l]
        ldr = light_dr = [light_d, light_r]
        llu = light_lu = [light_l, light_u]
        lru = light_ru = [light_r, light_u]
        tx = hx - boxw./(3)
        mv2 = mask_v2 = [[-tx, -255, -tx, 255, 0], [tx, -255, tx, 255, 0]]
        ty = hy - boxh./(3)
        mh2 = mask_h2 = [[-255, -ty, 255, -ty, 0], [-255, ty, 255, ty, 0]]
        rects = { 9472 => lh, 9473 => hh, 9474 => lv, 9475 => hv, 9476 => lh + mv2, 9477 => hh + mv2, 9478 => lv + mh2, 9479 => hv + mv2, 9480 => lh, 9481 => hh, 9482 => lv, 9483 => hv, 9484 => ldr, 9485 => hr + ld, 9486 => hd + lr, 9487 => hdr, 9488 => ldl, 9489 => hl + ld, 9490 => [hd, ll], 9491 => hdl, 9492 => lru, 9493 => lu + hr, 9494 => lr + hu, 9495 => hru, 9496 => llu, 9497 => [hl, lu], 9498 => [ll, hu], 9499 => hlu, 9500 => lv + lr, 9501 => [lv, hr], 9502 => ldr + hu, 9503 => [lru, hd], 9504 => hv + lr, 9505 => hru + ld, 9506 => hdr + lu, 9507 => hv + hr, 9508 => ll + lv, 9509 => hl + lv, 9510 => hu + ldl, 9511 => hd + lu, 9512 => hv + ll, 9513 => hlu + ld, 9514 => hdl + lu, 9515 => hl + hv, 9516 => lh + ld, 9517 => [hl, ldr], 9518 => [hr, ldr], 9519 => [hh, ld], 9520 => [lh, hd], 9521 => [hdl, lr], 9522 => [ll, hdr], 9523 => [hh, hd], 9524 => [lh, lu], 9525 => [lru, hl], 9526 => [llu, hr], 9527 => [hh, lu], 9528 => [lh, hu], 9529 => [hlu, lr], 9530 => [hru, ll], 9531 => [hh, hu], 9532 => [lv, lh], 9533 => lv + lr + hl, 9534 => ll + lv + hr, 9535 => [lv, hh], 9536 => [lh, ld, hu], 9537 => [light_h, light_u, heavy_d], 9538 => [heavy_v, light_h], 9539 => [heavy_l, heavy_u, hc, light_d, light_r], 9540 => [ll, ld, hru], 9541 => [heavy_dl, light_ru], 9542 => [light_lu, heavy_dr], 9543 => [heavy_h, heavy_u, light_d], 9544 => [hh, hd, light_u], 9545 => [heavy_v, heavy_l, light_r], 9546 => [heavy_v, light_l, heavy_r], 9547 => [heavy_v, heavy_h], 9548 => [lh, dblc], 9549 => [heavy_h, dblc], 9550 => [light_v, dblc], 9551 => [heavy_v, dblc], 9552 => dh, 9553 => dv, 9554 => [dh, lv, ml, maskdtop], 9555 => [dv, lh, mt, maskdleft], 9556 => [ddbar, drbar, mask_dbar, mask_rbar], 9557 => [dh, mr, lv, maskdtop], 9558 => [dv, lh, maskdright, mt], 9559 => [double_dbar, double_lbar, mask_dbar, mask_lbar], 9560 => [lv, dh, ml, maskdbottom], 9561 => [lh, dv, maskdleft, mb], 9562 => [dtbar, double_rbar, mask_tbar, mask_rbar], 9563 => [dh, lv, maskdbottom, mr], 9564 => [dv, lh, mb, maskdright], 9565 => [dtbar, dlbar, mask_tbar, mask_lbar], 9566 => [lv, dh, maskleft], 9567 => [lh, dv, dblc, maskdleft], 9568 => [dv, drbar, mask_rbar, mask_vbar], 9569 => [lv, dh, maskright], 9570 => [dv, ll, dblc], 9571 => [dlbar, dv, mask_lbar, mask_vbar], 9572 => [dh, ld, dblc], 9573 => [lh, dv, mt], 9574 => [dh, ddbar, mask_hbar, mask_dbar], 9575 => [dh, light_u, dblc], 9576 => [lh, dv, mb], 9577 => [dh, double_tbar, mask_hbar, mask_tbar], 9578 => dh + lv, 9579 => dv + lh, 9580 => [dh, dv, mask_hbar, mask_vbar], 9581 => [ldr, mask_c], 9582 => [ldl, mask_c], 9583 => [llu, mask_c], 9584 => [lru, mask_c], 9585 => nil, 9586 => nil, 9587 => nil, 9588 => ll, 9589 => lu, 9590 => lr, 9591 => ld, 9592 => hl, 9593 => hu, 9594 => hr, 9595 => hd, 9596 => ll + hr, 9597 => lu + hd, 9598 => hl + lr, 9599 => hu + ld }
        r = rects[ch.ord]
        if r
          img = empty_box_image
          r.flatten.each_slice(5) { |rect|
            p(rect)
            (x1, y1, x2, y2, col) = [*rect]
            x1 = (x1 + hx).clamp(0, boxw - 1)
            x2 = (x2 + hx).clamp(0, boxw - 1)
            y1 = (y1 + hy).clamp(0, boxh - 1)
            y2 = (y2 + hy).clamp(0, boxh - 1)
            col ||= 255
            a = Array.new(x2 - x1 + 1, col)
            (y1..y2).each { |y|
              img.pixels[y * stride + x1..y * stride + x2] = a
            }
          }
          return img
        end
        if ch.ord == 9585
          img = empty_box_image
          slope = boxw.to_f / boxh
          x = boxw.to_f - 1
          (0...boxh).each { |y|
            err = x - x.to_i
            img.pixels[y * stride + x.ceil] = 255
            if x > 0
              img.pixels[y * stride + x.ceil - 1] = (255 * err).floor
            end
            x -= slope
          }
          return img
        end
        if ch.ord == 9586
          img = empty_box_image
          slope = boxw.to_f / boxh
          x = boxw.to_f - 1
          (0...boxh).each { |y|
            err = x - x.to_i
            img.pixels[y * stride + boxw - x.ceil] = 255
            if x > 0
              img.pixels[y * stride + boxw - x.ceil + 1] = (255 * err).floor
            end
            x -= slope
          }
          return img
        end
        if ch.ord == 9587
          img = empty_box_image
          slope = boxw.to_f / boxh
          x = boxw.to_f - 1
          (0...boxh).each { |y|
            err = x - x.to_i
            if x > 0
              img.pixels[y * stride + boxw - x.ceil + 1] = (255 * err).floor
            end
            if x > 0
              img.pixels[y * stride + x.ceil - 1] = (255 * err).floor
            end
            img.pixels[y * stride + boxw - x.ceil] = 255
            img.pixels[y * stride + x.ceil] = 255
            x -= slope
          }
          return img
        end
        if img
          img = img.dup
          img.pixels=img.pixels.dup
        end
        img || empty_box_image
      end
    end
  end
end); module Skrift
  module X11
    PictOpSrc = 1
    PictOpOver = 3
    CPRepeat = 1

    class Glyphs
      attr_reader(:fixed_width)
      attr_accessor(:maxheight)

      def load_font(index)
        if @fonts[index]
          return @fonts[index]
        end
        f = @fontset[index]
        if !f
          return nil
        end
        if File.exist?(f)
          return @fonts[index] = Font.load(f)
        end
        fn = File.expand_path("~/.local/share/fonts/#{f}")
        if File.exist?(fn)
          return @fonts[index] = Font.load(fn)
        end
        fn = `fc-match --format='%{file}
' #{fn}`.split("\n").first
        if File.exist?(fn)
          return @fonts[index] = Font.load(fn)
        end
        return nil
      end

      def inspect
        "<Glyphs #{object_id}"
      end

      def initialize(dpy, font = nil, fontset: nil, x_scale:, y_scale:, pic: nil, fixed: nil, maxheight: nil)
        @fonts = []
        @fontset = fontset
        @font = font || load_font(0)
        @maxheight = maxheight
        @dpy = dpy
        @sft = SFT.new(@font)
        @sft.x_scale=x_scale
        @sft.y_scale=y_scale
        @pic = pic
        @fixed = fixed
        g = @sft.gmetrics(@sft.lookup("M".ord))
        if !g
          g = @sft.gmetrics(0)
        end
        if g
          @fixed_width = g.advance_width.ceil
        else
          @fixed_width = x_scale
        end
        @nextgid = 1
        @glyphcache = {}
        @colcache = {}
        @chcache = {}
        @lm = @sft.lmetrics
        @gfmt = @dpy.render_find_standard_format(:a8).id
        @glyphset = @dpy.render_create_glyph_set(@gfmt)
      end
      attr_accessor(:lm)

      def fill_for_col(col)
        if @colcache[col]
          return @colcache[col]
        end
        r = col >> 16
        r |= r << 8
        g = (col >> 8) & 255
        g |= g << 8
        b = col & 255
        b |= b << 8
        @colcache[col] ||= @dpy.render_create_solid_fill(r, g, b, 65535)
      end
      nil

      def boxw
        @fixed_width
      end

      def stride
        (@fixed_width + 3) & 3.~
      end

      def boxh
        @boxh ||= [@maxheight, @lm.ascender.ceil - @lm.descender.ceil].compact.min
      end

      def cache_special(ch)
        if !((9472..9599) === ch.ord)
          return nil
        end
        img = cache_box(ch.ord)
        data = img.pixels.pack("C*")
        info = ::X11::Form::GlyphInfo.new(img.width, img.height, 0, 0, fixed_width, 0)
        gsgid = @nextgid
        @nextgid += 1
        @dpy.render_add_glyphs(@glyphset, gsgid, info, data)
        @glyphcache[gsgid] = fixed_width
        @chcache[ch] = { gsgid: gsgid }
      end

      def cache_glyph(gsgid, gid, baseline)
        if gid.nil?
          return
        end
        mtx = @sft.gmetrics(gid)
        if @fixed
          w = fixed_width
        else
          w = mtx.min_width || 0
        end
        h = [mtx&.min_height || 1, @maxheight].compact.min
        img = Image.new((w + 3) & 3.~, h)
        if !@sft.render(gid, img)
          data = "\u0000" * (w * h)
        else
          data = img.pixels.pack("C*")
        end
        yoff = mtx.y_offset || baseline
        info = ::X11::Form::GlyphInfo.new(img.width, img.height, -mtx.left_side_bearing, yoff - baseline, fixed_width || mtx.advance_width, 0)
        @dpy.render_add_glyphs(@glyphset, gsgid, info, data)
        @glyphcache[gsgid] = mtx.advance_width
      end
      nil
      nil

      def each_font
        @fontset.each_index { |i|
          yield(load_font(i))
        }
      end

      def cache_glyphs(str)
        gl = str.to_s.each_char.map { |ch|
          cache = @chcache[ch]
          if cache.nil?
            cache = cache_special(ch)
          end
          if cache.nil?
            each_font { |font|
              @sft.font=font
              gid = @sft.lookup(ch.ord)
              if gid
                cache = @chcache[ch] = { font: font, gid: gid, gsgid: @nextgid }
                @nextgid += 1
                break
              end
            }
          end
          if cache
            data = @glyphcache[cache[:gsgid]]
            if !data
              @sft.font=cache[:font]
              data = cache_glyph(cache[:gsgid], cache[:gid], @lm.ascender)
            end
            cache[:gsgid]
          else
            0
          end
        }
      end
      public

      def render_str(pic, col, x, y, str)
        fill = fill_for_col(col)
        gl = cache_glyphs(str)
        @dpy.render_composite_glyphs32(PictOpOver, fill, pic, @gfmt, @glyphset, 0, 0, [x, y, gl])
      end
    end
  end
end)); module Skrift
  module X11
    class Error < StandardError
    end
  end
end)); PictOpOver = 3; class Window
  attr_reader(:dpy)

  def initialize(**opts)
    @dpy = X11::Display.new
    @screen = @dpy.screens.first
    @alpha = 192 << 24
    @opaque = 255 << 24
    eventmask = X11::Form::SubstructureNotifyMask | X11::Form::ButtonReleaseMask | X11::Form::Button1MotionMask | X11::Form::ExposureMask | X11::Form::KeyPressMask | X11::Form::ButtonPressMask
    @visual = @dpy.find_visual(0, 32).visual_id
    @wid = @dpy.create_window(0, 0, 1000, 600, visual: @visual, values: { X11::Form::CWBackPixel => 0 | @alpha, X11::Form::CWBorderPixel => 0, X11::Form::CWEventMask => eventmask })
    @dpy.map_window(@wid)
    fmt = @dpy.render_find_visual_format(@visual)
    @pic = @dpy.render_create_picture(@wid, fmt)
    @scale = 16
    @fontset = opts[:fonts]
    setup_fonts
  end

  def setup_fonts
    @skr = Skrift::X11::Glyphs.new(@dpy, fontset: @fontset, x_scale: @scale, y_scale: @scale, fixed: true)
    @skr_dblheight = Skrift::X11::Glyphs.new(@dpy, fontset: @fontset, x_scale: @scale * 2, y_scale: @scale * 2, fixed: true)
    @skr_dblwidth = Skrift::X11::Glyphs.new(@dpy, fontset: @fontset, x_scale: @scale * 2, y_scale: @scale, fixed: true)
  end

  def adjust_fontsize(adj)
    @scale += adj
    @scale = @scale.clamp(5, 100)
    @char_w = nil
    @char_h = nil
    setup_fonts
  end

  def char_w
    @char_w ||= @skr.fixed_width
  end

  def char_h
    if @char_h
      return @char_h
    end
    lm = @skr.lm
    @char_h = (lm.ascender - lm.descender + lm.line_gap).floor
    @skr.maxheight=@char_h + 1
  end

  def fillrect(x, y, w, h, fg)
    @dpy.poly_fill_rectangle(@wid, gc_for_col(fg, 0), [X11::Form::Rectangle.new(x, y, w, h)])
  end

  def clear(x, y, w, h)
    @dpy.clear_area(false, @wid, x, y, w, h)
  end

  def gc_for_col(fg, bg)
    @gcs ||= {}
    key = "#{fg},#{bg}"
    if @gcs[key]
      return @gcs[key]
    end
    bg |= @alpha
    fg |= @opaque
    gc = @dpy.create_gc(@wid, foreground: fg, background: bg)
    @gcs[key] = gc
  end

  def draw_line(x, y, w, fg)
    fillrect(x, y, w, 1, fg)
  end

  def draw(x, y, c, fg, bg, lineattrs)
    case lineattrs
    when :dbl_upper
      fillrect(x, y, c.length * char_w * 2, char_h * 2, bg)
      @skr_dblheight.render_str(@pic, fg, x, y, c)
    when :dbl_lower
      fillrect(x, y, c.length * char_w * 2, char_h * 2, bg)
      @skr_dblheight.render_str(@pic, fg, x, y - char_h, c)
    when :dbl_single
      fillrect(x, y, c.length * char_w * 2, char_h, bg)
      @skr_dblwidth.render_str(@pic, fg, x, y, c)
    else
      fillrect(x, y, c.length * char_w, char_h, bg)
      c.rstrip!
      @skr.render_str(@pic, fg, x, y, c)
    end
    return
    c.each_char { |_|
      draw_line(x, y, char_w, 3080192)
      draw_line(x, y + char_h, char_w, 12032)
      fillrect(x, y, 1, char_h, 47)
      x += char_w
    }
  end

  def scroll_up(srcy, w, h, step)
    @dpy.copy_area(@wid, @wid, gc_for_col(16777215, 0), 0, srcy, 0, srcy - step, w, h)
    if @debug
      $step ||= 16
      fillrect(0, srcy + h - step, w, step, $step)
      $step += 16
    else
      clear(0, srcy + h - step, w, step + 1)
    end
  end

  def scroll_down(srcy, w, h, step)
    @dpy.copy_area(@wid, @wid, gc_for_col(16777215, 0), 0, srcy, 0, srcy + step, w, h)
    if @debug
      $step ||= 16
      fillrect(0, srcy, w, step, $step)
      $step += 16
    else
      clear(0, srcy, w, step + 1)
    end
  end
end))
((DefaultCharset = Hash.new { |_, k|
  k
}.freeze; GraphicsCharset = { 95 => " ", 96 => "◆", 97 => "▒", 98 => "␉", 99 => "␌", 100 => "␍", 101 => "␊", 102 => "°", 103 => "±", 104 => "␤", 105 => "␋", 106 => "┘", 107 => "┐", 108 => "┌", 109 => "└", 110 => "┼", 111 => "⎺", 112 => "⎻", 113 => "─", 114 => "⎼", 115 => "⎽", 116 => "├", 117 => "┤", 118 => "┴", 119 => "┬", 120 => "│", 121 => "≤", 122 => "≥", 123 => "π", 124 => "≠", 125 => "£", 126 => "·" }; GraphicsCharset.default_proc=->(_, k) {
  k
}; GraphicsCharset.freeze))
((module X11
  class X11Error < StandardError
  end
end; require("socket"); (module X11
  module Protocol
    BYTE_ORDER = case [1].pack("L")
    when "\u0000\u0000\u0000\u0001"
      "B".ord
    when "\u0001\u0000\u0000\u0000"
      "l".ord
    else
      raise(ByteOrderError.new("Cannot determine byte order"))
    end
    MAJOR = 11
    MINOR = 0
  end
end); (module X11
  class Auth
    FAILED = 0
    SUCCESS = 1
    AUTHENTICATE = 2
    ADDRESS_TYPES = { 256 => :Local, 65535 => :Wild, 254 => :Netname, 253 => :Krb5Principal, 252 => :LocalHost, 0 => :Internet, 1 => :DECnet, 2 => :Chaos }
    AuthInfo = Struct.new(:family, :address, :display, :auth_name, :auth_data)

    def initialize(path = ENV["XAUTHORITY"] || ENV["HOME"] + "/.Xauthority")
      @file = File.open(path)
    end

    def get_by_hostname(host, family, display_id)
      if host == "localhost" || host == "127.0.0.1" || host.nil?
        host = `hostname`.chomp
      end
      if family == :Internet
        address = TCPSocket.gethostbyname(host)
      end
      auth_data = nil
      until @file.eof?
        r = read
        if r.display.empty? || display_id.to_i == r.display.to_i
          auth_data = r
        end
      end
      reset
      return auth_data
    end

    def read
      auth_info = [] << ADDRESS_TYPES[@file.read(2).unpack("n").first]
      4.times {
        length = @file.read(2).unpack("n").first
        auth_info << @file.read(length)
      }
      AuthInfo[*auth_info]
    end

    def reset
      @file.seek(0, IO::SEEK_SET)
    end
  end
end); ((require("stringio"); module X11
  class DisplayError < X11Error
  end

  class ConnectionError < X11Error
  end

  class AuthorizationError < X11Error
  end

  class ProtocolError < X11Error
  end

  class Display
    attr_accessor(:socket)

    def initialize(target = ENV["DISPLAY"])
      target =~ /^([\w.-]*):(\d+)(?:.(\d+))?$/
      (host, display_id, screen_id) = [$1, $2, $3]
      family = nil
      if host.empty?
        @socket = UNIXSocket.new("/tmp/.X11-unix/X#{display_id}")
        family = :Local
        host = nil
      else
        @socket = TCPSocket.new(host, 6000 + display_id)
        family = :Internet
      end
      authorize(host, family, display_id) rescue nil
      @requestseq = 1
      @queue = []
      @extensions = {}
      @atoms = {}
    end
    nil

    def display_info
      @internal
    end

    def screens
      @internal.screens.map { |s|
        Screen.new(self, s)
      }
    end

    def new_id
      id = (@xid_next ||= 0)
      @xid_next += 1
      (id & @internal.resource_id_mask) | @internal.resource_id_base
    end

    def read_error(data)
      error = Form::Error.from_packet(StringIO.new(data))
      STDERR.puts("ERROR: #{error.inspect}")
      error
    end

    def read_reply(data)
      len = data.unpack("@4L")[0]
      extra = if len > 0
        @socket.read(len * 4)
      else
        ""
      end
      data + extra
    end

    def read_event(type, data, event_class)
      case type
      when 2
        return Form::KeyPress.from_packet(StringIO.new(data))
      when 3
        return Form::KeyRelease.from_packet(StringIO.new(data))
      when 4
        return Form::ButtonPress.from_packet(StringIO.new(data))
      when 5
        return Form::ButtonRelease.from_packet(StringIO.new(data))
      when 6
        return Form::MotionNotify.from_packet(StringIO.new(data))
      when 12
        return Form::Expose.from_packet(StringIO.new(data))
      when 14
        return Form::NoExposure.from_packet(StringIO.new(data))
      when 19
        return Form::MapNotify.from_packet(StringIO.new(data))
      when 22
        return Form::ConfigureNotify.from_packet(StringIO.new(data))
      else
        STDERR.puts("FIXME: Event: #{type}")
        STDERR.puts("EVENT: #{data.inspect}")
      end
    end

    def read_full_packet(len = 32)
      data = @socket.read_nonblock(32)
      if data.nil?
        return nil
      end
      while data.length < 32
        IO.select([@socket], nil, nil, 0.001)
        data.concat(@socket.read_nonblock(32 - data.length))
      end
      return data
    rescue IO::WaitReadable
      return nil
    end

    def read_packet(timeout = 5.0)
      IO.select([@socket], nil, nil, timeout)
      data = read_full_packet(32)
      if data.nil?
        return nil
      end
      type = data.unpack("C").first
      case type
      when 0
        read_error(data)
      when 1
        read_reply(data)
      when 2..34
        read_event(type, data, nil)
      else
        p(data)
      end
    end

    def write_request(ob)
      if ob.respond_to?(:to_packet)
        data = ob.to_packet
      end
      if ob.request_length && ob.request_length.to_i * 4 != data.size
        raise("BAD LENGTH for #{ob.inspect} (#{ob.request_length.to_i * 4} ! #{data.size} ")
      end
      @requestseq += 1
      @socket.write(data)
    end

    def write_sync(data, reply = nil)
      write_request(data)
      pkt = next_reply
      if !pkt
        return nil
      end
      if reply
        reply.from_packet(StringIO.new(pkt))
      else
        pkt
      end
    end

    def peek_packet
      !@queue.empty?
    end

    def next_packet
      @queue.shift || read_packet
    end

    def next_reply
      while pkt = read_packet
        if pkt.is_a?(String)
          return pkt
        else
          @queue.push(pkt)
        end
      end
    end

    def run
      loop {
        pkt = read_packet
        if !pkt
          return
        end
        yield(pkt)
      }
    end

    def find_visual(screen, depth, qlass = 4)
      self.display_info.screens[screen].depths.find { |d|
        d.depth == depth
      }.visuals.find { |v|
        v.qlass=qlass
      }
    end

    def create_window(x, y, w, h, values: {}, depth: 32, parent: nil, border_width: 0, wclass: X11::Form::InputOutput, visual: nil)
      wid = new_id
      parent ||= screens.first.root
      if visual.nil?
        visual = find_visual(0, depth).visual_id
      end
      values[X11::Form::CWColorMap] ||= create_colormap(0, parent, visual)
      values = values.sort_by {
        _1[0]
      }
      mask = values.inject(0) { |acc, v|
        (acc | v[0])
      }
      values = values.map {
        _1[1]
      }
      write_request(X11::Form::CreateWindow.new(depth, wid, parent, x, y, w, h, border_width, wclass, visual, mask, values))
      return wid
    end

    def atom(name)
      if !@atoms[name]
        intern_atom(false, name)
      end
      @atoms[name]
    end

    def query_extension(name)
      r = write_sync(X11::Form::QueryExtension.new(name), X11::Form::QueryExtensionReply)
      @extensions[name] = { major: r.major_opcode }
      r
    end

    def major_opcode(name)
      if !@extensions[name]
        query_extension(name)
      end
      if !@extensions[name]
        raise("No such extension '#{name}'")
      end
      @extensions[name][:major]
    end

    def intern_atom(flag, name)
      reply = write_sync(X11::Form::InternAtom.new(flag, name.to_s), X11::Form::InternAtomReply)
      if reply
        @atoms[name.to_sym] = reply.atom
      end
    end

    def get_keyboard_mapping(min_keycode = display_info.min_keycode, count = display_info.max_keycode - min_keycode)
      write_sync(X11::Form::GetKeyboardMapping.new(min_keycode, count), X11::Form::GetKeyboardMappingReply)
    end

    def create_colormap(alloc, window, visual)
      mid = new_id
      write_request(X11::Form::CreateColormap.new(alloc, mid, window, visual))
      mid
    end
    nil
    nil
    nil
    nil

    def map_window(*args)
      write_request(X11::Form::MapWindow.new(*args))
    end

    def create_gc(window, foreground: nil, background: nil)
      mask = 0
      args = []
      if foreground
        mask |= 4
        args << foreground
      end
      if background
        mask |= 8
        args << background
      end
      gc = new_id
      write_request(X11::Form::CreateGC.new(gc, window, mask, args))
      gc
    end
    nil

    def clear_area(*args)
      write_request(X11::Form::ClearArea.new(*args))
    end

    def copy_area(*args)
      write_request(X11::Form::CopyArea.new(*args))
    end
    nil
    nil

    def poly_fill_rectangle(*args)
      write_request(X11::Form::PolyFillRectangle.new(*args))
    end
    nil

    def render_opcode
      if @render_opcode
        return @render_opcode
      end
      @render_opcode = major_opcode("RENDER")
      if @render_opcode
        @render_version = write_sync(X11::Form::XRenderQueryVersion.new(@render_opcode, 0, 11), X11::Form::XRenderQueryVersionReply)
      end
      @render_opcode
    end

    def render_create_picture(drawable, format, vmask = 0, vlist = [])
      pid = new_id
      write_request(X11::Form::XRenderCreatePicture.new(render_opcode, pid, drawable, format, vmask, vlist))
      pid
    end

    def render_query_pict_formats
      @render_formats ||= write_sync(X11::Form::XRenderQueryPictFormats.new(render_opcode), X11::Form::XRenderQueryPictFormatsReply)
    end

    def render_find_visual_format(visual)
      render_query_pict_formats.screens.map { |s|
        s.depths.map { |d|
          d.visuals.map { |v|
            if v.visual == visual
              v
            else
              nil
            end
          }
        }
      }.flatten.compact.first&.format
    end

    def render_find_standard_format(sym)
      formats = render_query_pict_formats
      case sym
      when :a8
        @a8 ||= formats.formats.find { |f|
          f.type == 1 && f.depth == 8 && f.direct.alpha_mask == 255
        }
      when :rgb24
        @rgb24 ||= formats.formats.find { |f|
          f.type == 1 && f.depth == 24 && f.direct.red == 16 && f.direct.green == 8 && f.direct.blue == 0
        }
      when :argb24
        @argb24 ||= formats.formats.find { |f|
          f.type == 1 && f.depth == 32 && f.direct.alpha == 24 && f.direct.red == 16 && f.direct.green == 8 && f.direct.blue == 0
        }
      else
        raise("Unsupported format (a4/a1 by omission)")
      end
    end

    def render_create_glyph_set(format)
      glyphset = new_id
      write_request(X11::Form::XRenderCreateGlyphSet.new(major_opcode("RENDER"), glyphset, format))
      glyphset
    end

    def render_add_glyphs(glyphset, glyphids, glyphinfos, data)
      write_request(X11::Form::XRenderAddGlyphs.new(render_opcode, glyphset, Array(glyphids), Array(glyphinfos), data))
    end
    nil

    def render_composite_glyphs32(op, src, dst, fmt, glyphset, srcx, srcy, *elts)
      write_request(X11::Form::XRenderCompositeGlyphs32.new(render_opcode, op, src, dst, fmt, glyphset, srcx, srcy, elts.map { |e|
        if e.is_a?(Array)
          Form::GlyphElt32.new(*e)
        else
          e
        end
      }))
    end

    def render_create_solid_fill(*color)
      if color.length == 1 && color.is_a?(Form::XRenderColor)
        color = color[0]
      else
        color = Form::XRenderColor.new(*color)
      end
      fill = new_id
      write_request(Form::XRenderCreateSolidFill.new(render_opcode, fill, color))
      fill
    end
    nil

    def authorize(host, family, display_id)
      auth = Auth.new
      auth_info = auth.get_by_hostname(host || "localhost", family, display_id)
      if auth_info
        (auth_name, auth_data) = [auth_info.auth_name, auth_info.auth_data]
      else
        auth_name = ""
        auth_data = ""
      end
      p([auth_name, auth_data])
      handshake = Form::ClientHandshake.new(Protocol::BYTE_ORDER, Protocol::MAJOR, Protocol::MINOR, auth_name, auth_data)
      @socket.write(handshake.to_packet)
      data = @socket.read(1)
      if !data
        raise(AuthorizationError, "Failed to read response from server")
      end
      case data.unpack("w").first
      when X11::Auth::FAILED
        (len, major, minor, xlen) = @socket.read(7).unpack("CSSS")
        reason = @socket.read(xlen * 4)
        reason = reason[0..len]
        raise(AuthorizationError, "Connection to server failed -- (version #{major}.#{minor}) #{reason}")
      when X11::Auth::AUTHENTICATE
        raise(AuthorizationError, "Connection requires authentication")
      when X11::Auth::SUCCESS
        @socket.read(7)
        @internal = Form::DisplayInfo.from_packet(@socket)
      else
        raise(AuthorizationError, "Received unknown opcode #{type}")
      end
    end

    def to_s
      "#<X11::Display:0x#{object_id.to_s(16)} screens=#{@internal.screens.size}>"
    end
  end
end)); (module X11
  class Screen
    attr_reader(:display)

    def initialize(display, data)
      @display = display
      @internal = data
    end

    def root
      @internal.root
    end

    def root_depth
      @internal.root_depth
    end

    def root_visual
      @internal.root_visual
    end

    def width
      @internal.width_in_pixels
    end

    def height
      @internal.height_in_pixels
    end

    def to_s
      "#<X11::Screen(#{id}) width=#{width} height=#{height}>"
    end
  end
end); (module X11
  module Type
    def self.define(type, directive, bytesize)
      eval("\n" "        class X11::Type::#{type}
          def self.pack(x)\n            [x].pack(\"#{directive}\")\n          end\n\n          def self.unpack(x)\n            x.unpack(\"#{directive}\").first\n          end\n\n          def self.size\n            #{bytesize}
          end\n\n          def self.from_packet(sock)\n            r = sock.read(size)\n            r ? unpack(r) : nil\n          end\n        end\n      ")
    end
    define("Int8", "c", 1)
    define("Int16", "s", 2)
    define("Int32", "l", 4)
    define("Uint8", "C", 1)
    define("Uint16", "S", 2)
    define("Uint32", "L", 4)

    class String8
      def self.pack(x)
        x.force_encoding("ASCII-8BIT") + "\u0000".*((-x.length & 3))
      end

      def self.unpack(socket, size)
        val = socket.read(size)
        unused_padding = (4 - (size % 4)) % 4
        socket.read(unused_padding)
        val
      end
    end

    class String16
      def self.pack(x)
        x.encode("UTF-16BE").force_encoding("ASCII-8BIT") + "\u0000\u0000".*((-x.length & 1))
      end

      def self.unpack(socket, size)
        val = socket.read(size)
        unused_padding = (4 - (size % 4)) % 4
        socket.read(unused_padding)
        val.force_encoding("UTF-16BE")
      end
    end

    class String8Unpadded
      def self.pack(x)
        x
      end

      def self.unpack(socket, size)
        val = socket.read(size)
      end
    end

    class Bool
      def self.pack(x)
        if x
          "\u0001"
        else
          "\u0000"
        end
      end

      def self.unpack(str)
        str[0] == "\u0001"
      end

      def self.size
        1
      end
    end
    KeyCode = Uint8
    Signifigance = Uint8
    BitGravity = Uint8
    WinGravity = Uint8
    BackingStore = Uint8
    Bitmask = Uint32
    Window = Uint32
    Pixmap = Uint32
    Cursor = Uint32
    Colornum = Uint32
    Font = Uint32
    Gcontext = Uint32
    Colormap = Uint32
    Drawable = Uint32
    Fontable = Uint32
    Atom = Uint32
    VisualID = Uint32
    Mask = Uint32
    Timestamp = Uint32
    Keysym = Uint32
  end
end); (((class OpenStruct
  VERSION = "0.5.5"

  def initialize(hash = nil)
    if hash
      update_to_values!(hash)
    else
      @table = {}
    end
  end
  nil
  nil
  private(def update_to_values!(hash)
    @table = {}
    hash.each_pair { |k, v|
      set_ostruct_member_value!(k, v)
    }
  end)
  if { test: :to_h }.to_h {
    [:works, true]
  }[:works]
    def to_h(&block)
      if block
        @table.to_h(&block)
      else
        @table.dup
      end
    end
  else
    def to_h(&block)
      if block
        @table.map(&block).to_h
      else
        @table.dup
      end
    end
  end

  def each_pair
    unless defined?(yield)
      return to_enum(__method__) {
        @table.size
      }
    end
    @table.each_pair { |p|
      yield(p)
    }
    self
  end
  nil
  alias_method(:marshal_load, :update_to_values!)

  def new_ostruct_member!(name)
    unless @table.key?(name) || is_method_protected!(name)
      if defined?(::Ractor)
        getter_proc = nil.instance_eval {
          Proc.new {
            @table[name]
          }
        }
        setter_proc = nil.instance_eval {
          Proc.new { |x|
            @table[name] = x
          }
        }
        ::Ractor.make_shareable(getter_proc)
        ::Ractor.make_shareable(setter_proc)
      else
        getter_proc = Proc.new {
          @table[name]
        }
        setter_proc = Proc.new { |x|
          @table[name] = x
        }
      end
      define_singleton_method!(name, &getter_proc)
      define_singleton_method!("#{name}=", &setter_proc)
    end
  end
  private(:new_ostruct_member!)
  private(def is_method_protected!(name)
    if !respond_to?(name, true)
      false
    else
      if name.match?(/!$/)
        true
      else
        owner = method!(name).owner
        if owner.class == ::Class
          owner < ::OpenStruct
        else
          self.class!.ancestors.any? { |mod|
            if mod == ::OpenStruct
              return false
            end
            mod == owner
          }
        end
      end
    end
  end)

  def freeze
    @table.freeze
    super
  end
  nil

  def [](name)
    @table[name.to_sym]
  end

  def []=(name, value)
    name = name.to_sym
    new_ostruct_member!(name)
    @table[name] = value
  end
  alias_method(:set_ostruct_member_value!, :[]=)
  private(:set_ostruct_member_value!)

  def dig(name, *names)
    begin
      name = name.to_sym
    rescue NoMethodError
      raise!(TypeError, "#{name} is not a symbol nor a string")
    end
    @table.dig(name, *names)
  end
  nil
  InspectKey = :__inspect_key__

  def inspect
    ids = (Thread.current[InspectKey] ||= [])
    if ids.include?(object_id)
      detail = " ..."
    else
      ids << object_id

      begin
        detail = @table.map { |key, value|
          " #{key}=#{value.inspect}"
        }.join(",")
      ensure
        ids.pop
      end
    end
    ["#<", self.class!, detail, ">"].join
  end
  alias :to_s :inspect
  attr_reader(:table)
  alias :table! :table
  protected(:table!)

  def ==(other)
    unless other.kind_of?(OpenStruct)
      return false
    end
    @table == other.table!
  end

  def eql?(other)
    unless other.kind_of?(OpenStruct)
      return false
    end
    @table.eql?(other.table!)
  end

  def hash
    @table.hash
  end
  nil
  nil
  give_access = instance_methods
  if RUBY_ENGINE == "jruby"
    give_access -= [:instance_exec, :instance_eval, :eval]
  end
  give_access.each { |method|
    if method.match(/\W$/)
      next
    end
    new_name = "#{method}!"
    alias_method(new_name, method)
  }
  alias_method(:raise!, :raise)
  private(:raise!)
  if RUBY_ENGINE != "jruby"
    alias_method(:block_given!, :block_given?)
    private(:block_given!)
  end
end); module X11
  module Form
    class Form
      def self.structs
        []
      end

      def self.fields
        []
      end
    end

    class BaseForm < Form
      include(X11::Type)

      def initialize(*params)
        self.class.fields.each { |f|
          if !f.value
            param = params.shift
            instance_variable_set("@#{f.name}", param)
          end
        }
      end

      def to_packet
        structs = self.class.structs
        packet = structs.map { |s|
          value = if s.type == :unused
            nil
          else
            instance_variable_get("@#{s.name}")
          end
          case s.type
          when :field
            if s.value
              if s.value.respond_to?(:call)
                value = s.value.call(self)
              else
                value = s.value
              end
            end
            if value.is_a?(BaseForm)
              v = value.to_packet
            else
              if value.is_a?(Symbol)
                raise("FIXME")
              else
                v = s.type_klass.pack(value)
              end
            end
            v
          when :unused
            sz = if s.size.respond_to?(:call)
              s.size.call(self)
            else
              s.size
            end
            "\u0000" * sz
          when :length
            s.type_klass.pack(value.size)
          when :string
            s.type_klass.pack(value)
          when :list
            value.collect { |obj|
              if obj.is_a?(BaseForm)
                obj.to_packet
              else
                s.type_klass.pack(obj)
              end
            }
          end
        }.join
      end

      class << self
        def structs
          superclass.structs + Array(@structs)
        end

        def from_packet(socket)
          form = new
          lengths = {}
          structs.each { |s|
            case s.type
            when :field
              val = if s.type_klass.superclass == BaseForm
                s.type_klass.from_packet(socket)
              else
                s.type_klass.unpack(socket.read(s.type_klass.size))
              end
              form.instance_variable_set("@#{s.name}", val)
            when :unused
              sz = if s.size.respond_to?(:call)
                s.size.call(self)
              else
                s.size
              end
              socket.read(sz)
            when :length
              size = s.type_klass.unpack(socket.read(s.type_klass.size))
              lengths[s.name] = size
            when :string
              val = s.type_klass.unpack(socket, lengths[s.name])
              form.instance_variable_set("@#{s.name}", val)
            when :list
              len = lengths[s.name]
              if len
                val = len.times.collect {
                  s.type_klass.from_packet(socket)
                }
              else
                val = []
                while ob = s.type_klass.from_packet(socket)
                  val << ob
                end
              end
              form.instance_variable_set("@#{s.name}", val)
            end
          }
          return form
        end
        Field = Struct.new(:name, :type, :type_klass, :value, :size, keyword_init: true)

        def field(name, type_klass, type = nil, value: nil)
          class_eval {
            if value && value.respond_to?(:call)
              define_method(name.to_sym) {
                value.call(self)
              }
            else
              attr_accessor(name)
            end
          }
          s = Field.new
          s.name=name
          s.type=(if type == nil
            :field
          else
            type
          end)
          s.type_klass=type_klass
          s.value=value
          @structs ||= []
          @structs << s
        end

        def unused(size)
          @structs ||= []
          @structs << Field.new(size: size, type: :unused)
        end

        def fields
          super + Array(@structs).dup.delete_if { |s|
            s.type == :unused || s.type == :length
          }
        end
      end
    end
    CardinalAtom = 6

    class ClientHandshake < BaseForm
      field(:byte_order, Uint8)
      unused(1)
      field(:protocol_major_version, Uint16)
      field(:protocol_minor_version, Uint16)
      field(:auth_proto_name, Uint16, :length)
      field(:auth_proto_data, Uint16, :length)
      unused(2)
      field(:auth_proto_name, String8, :string)
      field(:auth_proto_data, String8, :string)
    end

    class FormatInfo < BaseForm
      field(:depth, Uint8)
      field(:bits_per_pixel, Uint8)
      field(:scanline_pad, Uint8)
      unused(5)
    end

    class VisualInfo < BaseForm
      field(:visual_id, VisualID)
      field(:qlass, Uint8)
      field(:bits_per_rgb_value, Uint8)
      field(:colormap_entries, Uint16)
      field(:red_mask, Uint32)
      field(:green_mask, Uint32)
      field(:blue_mask, Uint32)
      unused(4)
    end

    class DepthInfo < BaseForm
      field(:depth, Uint8)
      unused(1)
      field(:visuals, Uint16, :length)
      unused(4)
      field(:visuals, VisualInfo, :list)
    end

    class ScreenInfo < BaseForm
      field(:root, Window)
      field(:default_colormap, Colormap)
      field(:white_pixel, Colornum)
      field(:black_pixel, Colornum)
      field(:current_input_masks, Mask)
      field(:width_in_pixels, Uint16)
      field(:height_in_pixels, Uint16)
      field(:width_in_millimeters, Uint16)
      field(:height_in_millimeters, Uint16)
      field(:min_installed_maps, Uint16)
      field(:max_installed_maps, Uint16)
      field(:root_visual, VisualID)
      field(:backing_stores, Uint8)
      field(:save_unders, Bool)
      field(:root_depth, Uint8)
      field(:depths, Uint8, :length)
      field(:depths, DepthInfo, :list)
    end

    class DisplayInfo < BaseForm
      field(:release_number, Uint32)
      field(:resource_id_base, Uint32)
      field(:resource_id_mask, Uint32)
      field(:motion_buffer_size, Uint32)
      field(:vendor, Uint16, :length)
      field(:maximum_request_length, Uint16)
      field(:screens, Uint8, :length)
      field(:formats, Uint8, :length)
      field(:image_byte_order, Signifigance)
      field(:bitmap_bit_order, Signifigance)
      field(:bitmap_format_scanline_unit, Uint8)
      field(:bitmap_format_scanline_pad, Uint8)
      field(:min_keycode, KeyCode)
      field(:max_keycode, KeyCode)
      unused(4)
      field(:vendor, String8, :string)
      field(:formats, FormatInfo, :list)
      field(:screens, ScreenInfo, :list)
    end

    class Rectangle < BaseForm
      field(:x, Int16)
      field(:y, Int16)
      field(:width, Uint16)
      field(:height, Uint16)
    end

    class Error < BaseForm
      field(:error, Uint8)
      field(:code, Uint8)
      field(:sequence_number, Uint16)
      field(:bad_resource_id, Uint32)
      field(:minor_opcode, Uint16)
      field(:major_opcode, Uint8)
      unused(21)
    end

    class DirectFormat < BaseForm
      field(:red, Uint16)
      field(:red_mask, Uint16)
      field(:green, Uint16)
      field(:green_mask, Uint16)
      field(:blue, Uint16)
      field(:blue_mask, Uint16)
      field(:alpha, Uint16)
      field(:alpha_mask, Uint16)
    end

    class PictVisual < BaseForm
      field(:visual, Uint32)
      field(:format, Uint32)
    end

    class PictDepth < BaseForm
      field(:depth, Uint8)
      unused(1)
      field(:visuals, Uint16, :length)
      unused(4)
      field(:visuals, PictVisual, :list)
    end

    class PictScreen < BaseForm
      field(:depths, Uint32, :length)
      field(:fallback, Uint32)
      field(:depths, PictDepth, :list)
    end

    class PictFormInfo < BaseForm
      field(:id, Uint32)
      field(:type, Uint8)
      field(:depth, Uint8)
      unused(2)
      field(:direct, DirectFormat)
      field(:colormap, Colormap)
    end
    CopyFromParent = 0
    InputOutput = 1
    InputOnly = 2
    CWBackPixmap = 1
    CWBackPixel = 2
    CWBorderPixmap = 4
    CWBorderPixel = 8
    CWBitGravity = 16
    CWWinGravity = 32
    CWBackingStore = 64
    CWSaveUnder = 1024
    CWEventMask = 2048
    CWColorMap = 8192
    KeyPressMask = 1
    KeyReleaseMask = 2
    ButtonPressMask = 4
    ButtonReleaseMask = 8
    EnterWindowMask = 16
    LeaveWindowMask = 32
    PointerMotionMask = 64
    PointerMotionHintMask = 128
    Button1MotionMask = 256
    ExposureMask = 32768
    StructureNotifyMask = 131072
    SubstructureNotifyMask = 524288

    class CreateWindow < BaseForm
      field(:opcode, Uint8, value: 1)
      field(:depth, Uint8)
      field(:request_length, Uint16, value: ->(cw) {
        len = 8 + cw.value_list.length
      })
      field(:wid, Window)
      field(:parent, Window)
      field(:x, Int16)
      field(:y, Int16)
      field(:width, Uint16)
      field(:height, Uint16)
      field(:border_width, Uint16)
      field(:window_class, Uint16)
      field(:visual, VisualID)
      field(:value_mask, Bitmask)
      field(:value_list, Uint32, :list)
    end

    class MapWindow < BaseForm
      field(:opcode, Uint8, value: 8)
      unused(1)
      field(:request_length, Uint16, value: 2)
      field(:window, Window)
    end

    class InternAtom < BaseForm
      field(:opcode, Uint8, value: 16)
      field(:only_if_exists, Bool)
      field(:request_length, Uint16, value: ->(ia) {
        2 + (ia.name.length + 3)./(4)
      })
      field(:name, Uint16, value: ->(ia) {
        ia.name.length
      })
      unused(2)
      field(:name, String8, :string)
    end

    class Reply < BaseForm
      field(:reply, Uint8)
    end

    class InternAtomReply < Reply
      unused(1)
      field(:sequence_number, Uint16)
      field(:reply_length, Uint32)
      field(:atom, Atom)
      unused(20)
    end
    Replace = 0
    Prepend = 1
    Append = 2

    class ChangeProperty < BaseForm
      field(:opcode, Uint8, value: 18)
      field(:mode, Uint8)
      field(:request_length, Uint16, value: ->(cp) {
        6 + (cp.data.length + 3)./(4)
      })
      field(:window, Window)
      field(:property, Atom)
      field(:type, Atom)
      field(:format, Uint8)
      unused(3)
      field(:data, Uint32, value: ->(cp) {
        cp.data.length / 4
      })
      field(:data, Uint8, :list)
    end

    class OpenFont < BaseForm
      field(:opcode, Uint8, value: 45)
      unused(1)
      field(:request_length, Uint16, value: ->(of) {
        3 + (of.name.length + 3)./(4)
      })
      field(:fid, Font)
      field(:name, Uint16, :length)
      unused(2)
      field(:name, String8, :string)
    end

    class ListFonts < BaseForm
      field(:opcode, Uint8, value: 49)
      unused(1)
      field(:request_length, Uint16, value: ->(lf) {
        2 + (lf.pattern.length + 4)./(4)
      })
      field(:max_names, Uint16)
      field(:length_of_pattern, Uint16, value: ->(lf) {
        lf.pattern.length
      })
      field(:pattern, String8)
    end

    class CreatePixmap < BaseForm
      field(:opcode, Uint8, value: 53)
      field(:depth, Uint8)
      field(:request_length, Uint16, value: 4)
      field(:pid, Pixmap)
      field(:drawable, Uint32)
      field(:width, Uint16)
      field(:height, Uint16)
    end

    class Str < BaseForm
      field(:name, Uint8, :length, value: ->(str) {
        str.name.length
      })
      field(:name, String8Unpadded, :string)

      def to_s
        name
      end
    end

    class ListFontsReply < BaseForm
      field(:reply, Uint8, value: 1)
      unused(1)
      field(:sequence_number, Uint16)
      field(:reply_length, Uint32)
      field(:names, Uint16, :length)
      unused(22)
      field(:names, Str, :list)
    end
    FunctionMask = 1
    PlaneMask = 2
    ForegroundMask = 4
    BackgroundMask = 8
    FontMask = 16384

    class CreateGC < BaseForm
      field(:opcode, Uint8, value: 55)
      unused(1)
      field(:request_length, Uint16, value: ->(cw) {
        len = 4 + cw.value_list.length
      })
      field(:cid, Gcontext)
      field(:drawable, Drawable)
      field(:value_mask, Bitmask)
      field(:value_list, Uint32, :list)
    end

    class ChangeGC < BaseForm
      field(:opcode, Uint8, value: 56)
      unused(1)
      field(:request_length, Uint16, value: ->(ch) {
        3 + ch.value_list.length
      })
      field(:gc, Gcontext)
      field(:value_mask, Bitmask)
      field(:value_list, Uint32, :list)
    end

    class ClearArea < BaseForm
      field(:opcode, Uint8, value: 61)
      field(:exposures, Bool)
      field(:request_length, Uint16, value: 4)
      field(:window, Window)
      field(:x, Int16)
      field(:y, Int16)
      field(:width, Uint16)
      field(:height, Uint16)
    end

    class CopyArea < BaseForm
      field(:opcode, Uint8, value: 62)
      unused(1)
      field(:request_length, Uint16, value: 7)
      field(:src_drawable, Drawable)
      field(:dst_drawable, Drawable)
      field(:gc, Gcontext)
      field(:src_x, Uint16)
      field(:src_y, Uint16)
      field(:dst_x, Uint16)
      field(:dst_y, Uint16)
      field(:width, Uint16)
      field(:height, Uint16)
    end

    class PolyFillRectangle < BaseForm
      field(:opcode, Uint8, value: 70)
      unused(1)
      field(:request_length, Uint16, value: ->(ob) {
        len = 3 + 2.*((Array(ob.rectangles).length))
      })
      field(:drawable, Drawable)
      field(:gc, Uint32)
      field(:rectangles, Rectangle, :list)
    end
    Bitmap = 0
    XYPixmap = 1
    ZPixmap = 2

    class PutImage < BaseForm
      field(:opcode, Uint8, value: 72)
      field(:format, Uint8)
      field(:request_length, Uint16, value: ->(pi) {
        6 + (pi.data.length + 3)./(4)
      })
      field(:drawable, Drawable)
      field(:gc, Gcontext)
      field(:width, Uint16)
      field(:height, Uint16)
      field(:dstx, Int16)
      field(:dsty, Int16)
      field(:left_pad, Uint8)
      field(:depth, Uint8)
      unused(2)
      field(:data, String8)
    end

    class ImageText8 < BaseForm
      field(:opcode, Uint8, value: 76)
      field(:n, Uint8, :length)
      field(:request_length, Uint16, value: ->(it) {
        4 + (it.n.length + 3)./(4)
      })
      field(:drawable, Drawable)
      field(:gc, Gcontext)
      field(:x, Int16)
      field(:y, Int16)
      field(:n, String8, :string)
    end

    class ImageText16 < BaseForm
      field(:opcode, Uint8, value: 77)
      field(:n, Uint8, :length)
      field(:request_length, Uint16, value: ->(it) {
        4 + (it.n.length * 2 + 3)./(4)
      })
      field(:drawable, Drawable)
      field(:gc, Gcontext)
      field(:x, Int16)
      field(:y, Int16)
      field(:n, String16, :string)
    end

    class CreateColormap < BaseForm
      field(:opcode, Uint8, value: 78)
      field(:alloc, Uint8)
      field(:request_length, Uint16, value: 4)
      field(:mid, Colormap)
      field(:window, Window)
      field(:visual, Uint32)
    end

    class QueryExtension < BaseForm
      field(:opcode, Uint8, value: 98)
      unused(1)
      field(:request_length, Uint16, value: ->(qe) {
        2 + (qe.name.length + 3)./(4)
      })
      field(:name, Uint16, :length)
      unused(2)
      field(:name, String8)
    end

    class QueryExtensionReply < Reply
      unused(1)
      field(:sequence_number, Uint16)
      field(:reply_length, Uint32)
      field(:present, Bool)
      field(:major_opcode, Uint8)
      field(:first_event, Uint8)
      field(:first_error, Uint8)
      unused(20)
    end

    class GetKeyboardMapping < BaseForm
      field(:opcode, Uint8, value: 101)
      unused(1)
      field(:request_length, Uint16, value: 2)
      field(:first_keycode, Uint8)
      field(:count, Uint8)
      unused(2)
    end

    class GetKeyboardMappingReply < Reply
      field(:keysyms_per_keycode, Uint8)
      field(:sequence_number, Uint16)
      field(:reply_length, Uint32)
      unused(24)
      field(:keysyms, Keysym, :list)
    end
    Shift = 1
    Lock = 2
    Control = 4
    Mod1 = 8
    Mod2 = 16
    Mod3 = 32
    Mod4 = 64
    Mod5 = 128
    Button1 = 256
    Button2 = 512
    Button3 = 1024
    Button4 = 2048
    Button5 = 4096

    class Event < BaseForm
      field(:code, Uint8)
    end

    class SimpleEvent < Event
      field(:detail, Uint8)
      field(:sequence_number, Uint16)
    end

    class PressEvent < SimpleEvent
      field(:time, Uint32)
      field(:root, Window)
      field(:event, Window)
      field(:child, Window)
      field(:root_x, Int16)
      field(:root_y, Int16)
      field(:event_x, Int16)
      field(:event_y, Int16)
      field(:state, Uint16)
      field(:same_screen, Bool)
      unused(1)
    end

    class ButtonPress < PressEvent
    end

    class KeyPress < PressEvent
    end

    class KeyRelease < PressEvent
    end

    class MotionNotify < PressEvent
    end

    class ButtonRelease < PressEvent
    end

    class Expose < SimpleEvent
      field(:window, Window)
      field(:x, Uint16)
      field(:y, Uint16)
      field(:width, Uint16)
      field(:height, Uint16)
      field(:count, Uint16)
      unused(14)
    end

    class NoExposure < SimpleEvent
      field(:drawable, Drawable)
      field(:minor_opcode, Uint16)
      field(:major_opcode, Uint8)
      unused(21)
    end

    class MapNotify < Event
      unused(1)
      field(:sequence_number, Uint16)
      field(:event, Window)
      field(:override_redirect, Bool)
      unused(19)
    end

    class ConfigureNotify < Event
      unused(1)
      field(:sequence_number, Uint16)
      field(:event, Window)
      field(:above_sibling, Window)
      field(:x, Int16)
      field(:y, Int16)
      field(:width, Uint16)
      field(:height, Uint16)
      field(:border_width, Uint16)
      field(:override_redirect, Bool)
      unused(5)
    end

    class XRenderQueryVersion < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 0)
      field(:request_length, Uint16, value: 3)
      field(:major_version, Uint32)
      field(:minor_version, Uint32)
    end

    class XRenderQueryVersionReply < Reply
      unused(1)
      field(:sequence_number, Uint16)
      field(:request_length, Uint32)
      field(:major_version, Uint32)
      field(:minor_version, Uint32)
    end

    class XRenderQueryPictFormats < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 1)
      field(:request_length, Uint16, value: 1)
    end

    class XRenderQueryPictFormatsReply < Reply
      unused(1)
      field(:sequence_number, Uint16)
      field(:length, Uint32)
      field(:formats, Uint32, :length)
      field(:screens, Uint32, :length)
      field(:depths, Uint32, :length)
      field(:visuals, Uint32, :length)
      field(:subpixel, Uint32, :length)
      unused(4)
      field(:formats, PictFormInfo, :list)
      field(:screens, PictScreen, :list)
      field(:subpixels, Uint32, :list)
    end

    class XRenderCreatePicture < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 4)
      field(:request_length, Uint16, value: ->(cp) {
        5 + Array(cp.value_list).length
      })
      field(:pid, Uint32)
      field(:drawable, Uint32)
      field(:format, Uint32)
      field(:value_mask, Uint32)
      field(:value_list, Uint32, :list)
    end

    class XRenderCreateGlyphSet < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 17)
      field(:request_length, Uint16, value: 3)
      field(:gsid, Uint32)
      field(:format, Uint32)
    end

    class GlyphInfo < BaseForm
      field(:width, Uint16)
      field(:height, Uint16)
      field(:x, Int16)
      field(:y, Int16)
      field(:x_off, Int16)
      field(:y_off, Int16)
    end

    class XRenderAddGlyphs < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 20)
      field(:request_length, Uint16, value: ->(ag) {
        if ag.glyphs.length != ag.glyphids.length
          raise("Mismatch: Expected XRenderAddGlyphs glyphs and glyphids to be same length")
        end
        3 + ag.glyphs.length.*(4) + (ag.data.length + 3)./(4)
      })
      field(:glyphset, Uint32)
      field(:glyphs, Uint32, :length)
      field(:glyphids, Uint32, :list)
      field(:glyphs, GlyphInfo, :list)
      field(:data, String8)
    end

    class XRenderColor < BaseForm
      field(:red, Uint16)
      field(:green, Uint16)
      field(:blue, Uint16)
      field(:alpha, Uint16)
    end

    class GlyphElt32 < BaseForm
      field(:glyphs, Uint8, :length)
      unused(3)
      field(:delta_x, Uint16)
      field(:delta_y, Uint16)
      field(:glyphs, Uint32, :list)
    end

    class XRenderCompositeGlyphs32 < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 25)
      field(:request_length, Uint16, value: ->(ch) {
        7 + (ch.glyphcmds[0].glyphs.length + 2)
      })
      field(:op, Uint8)
      unused(3)
      field(:src, Uint32)
      field(:dst, Uint32)
      field(:mask_format, Uint32)
      field(:glyphset, Uint32)
      field(:xsrc, Uint16)
      field(:ysrc, Uint16)
      field(:glyphcmds, GlyphElt32, :list)
    end

    class XRenderFillRectangles < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 26)
      field(:request_length, Uint16, value: ->(fr) {
        5 + fr.rects.length.*(2)
      })
      field(:op, Uint8)
      unused(3)
      field(:dst, Uint32)
      field(:color, Uint32)
      field(:rects, Rectangle, :list)
    end

    class XRenderCreateSolidFill < BaseForm
      field(:req_type, Uint8)
      field(:render_req_type, Uint8, value: 33)
      field(:request_length, Uint16, value: 4)
      field(:fill, Uint32)
      field(:color, XRenderColor)
    end
  end
end)); (module X11
  KeySyms = { 439 => :XK_caron, 445 => :XK_doubleacute, 65288 => :backspace, 65289 => :tab, 65290 => :linefeed, 65291 => :clear, 65293 => :enter, 65025 => :XK_ISO_Lock, 65026 => :XK_ISO_Level2_Latch, 65027 => :XK_ISO_Level3_Shift, 65028 => :XK_ISO_Level3_Latch, 65029 => :XK_ISO_Level3_Lock, 65030 => :XK_ISO_Group_Latch, 65031 => :XK_ISO_Group_Lock, 65032 => :XK_ISO_Next_Group, 65033 => :XK_ISO_Next_Group_Lock, 65034 => :XK_ISO_Prev_Group, 65035 => :XK_ISO_Prev_Group_Lock, 65036 => :XK_ISO_First_Group, 65037 => :XK_ISO_First_Group_Lock, 65038 => :XK_ISO_Last_Group, 65039 => :XK_ISO_Last_Group_Lock, 65041 => :XK_ISO_Level5_Shift, 65042 => :XK_ISO_Level5_Latch, 65043 => :XK_ISO_Level5_Lock, 65056 => :XK_ISO_Left_Tab, 65057 => :XK_ISO_Move_Line_Up, 65058 => :XK_ISO_Move_Line_Down, 65059 => :XK_ISO_Partial_Line_Up, 65060 => :XK_ISO_Partial_Line_Down, 65061 => :XK_ISO_Partial_Space_Left, 65062 => :XK_ISO_Partial_Space_Right, 65063 => :XK_ISO_Set_Margin_Left, 65064 => :XK_ISO_Set_Margin_Right, 65065 => :XK_ISO_Release_Margin_Left, 65066 => :XK_ISO_Release_Margin_Right, 65067 => :XK_ISO_Release_Both_Margins, 65068 => :XK_ISO_Fast_Cursor_Left, 65069 => :XK_ISO_Fast_Cursor_Right, 65070 => :XK_ISO_Fast_Cursor_Up, 65071 => :XK_ISO_Fast_Cursor_Down, 65072 => :XK_ISO_Continuous_Underline, 65073 => :XK_ISO_Discontinuous_Underline, 65074 => :XK_ISO_Emphasize, 65075 => :XK_ISO_Center_Object, 65076 => :XK_ISO_Enter, 65299 => :XK_Pause, 65300 => :XK_Scroll_Lock, 65301 => :XK_Sys_Req, 65307 => :XK_Escape, 65535 => :XK_Delete, 65312 => :XK_Multi_key, 65313 => :XK_Kanji, 65314 => :XK_Muhenkan, 65315 => :XK_Henkan, 65316 => :XK_Romaji, 65317 => :XK_Hiragana, 65318 => :XK_Katakana, 65319 => :XK_Hiragana_Katakana, 65320 => :XK_Zenkaku, 65321 => :XK_Hankaku, 65322 => :XK_Zenkaku_Hankaku, 65323 => :XK_Touroku, 65324 => :XK_Massyo, 65325 => :XK_Kana_Lock, 65326 => :XK_Kana_Shift, 65327 => :XK_Eisu_Shift, 65328 => :XK_Eisu_toggle, 65329 => :Unknown_FF31, 65332 => :Unknown_FF34, 65335 => :XK_Codeinput, 65340 => :XK_SingleCandidate, 65341 => :XK_MultipleCandidate, 65342 => :XK_PreviousCandidate, 65360 => :XK_Home, 65361 => :XK_Left, 65362 => :XK_Up, 65363 => :XK_Right, 65364 => :XK_Down, 65365 => :XK_Page_Up, 65366 => :XK_Page_Down, 65367 => :XK_End, 65368 => :XK_Begin, 65376 => :XK_Select, 65377 => :XK_Print, 65378 => :XK_Execute, 65379 => :XK_Insert, 65381 => :XK_Undo, 65382 => :XK_Redo, 65383 => :XK_Menu, 65384 => :XK_Find, 65385 => :XK_Cancel, 65386 => :XK_Help, 65387 => :XK_Break, 65406 => :XK_Mode_switch, 65407 => :XK_Num_Lock, 65408 => :XK_KP_Space, 65417 => :XK_KP_Tab, 65421 => :XK_KP_Enter, 65429 => :XK_KP_Home, 65430 => :XK_KP_Left, 65431 => :XK_KP_Up, 65432 => :XK_KP_Right, 65433 => :XK_KP_Down, 65434 => :XK_KP_Page_Up, 65435 => :XK_KP_Page_Down, 65436 => :XK_KP_End, 65437 => :XK_KP_Begin, 65438 => :XK_KP_Insert, 65439 => :XK_KP_Delete, 65469 => :XK_KP_Equal, 65450 => :XK_KP_Multiply, 65451 => :XK_KP_Add, 65452 => :XK_KP_Separator, 65453 => :XK_KP_Subtract, 65454 => :XK_KP_Decimal, 65455 => :XK_KP_Divide, 65505 => :XK_Shift_L, 65506 => :XK_Shift_R, 65507 => :XK_Control_L, 65508 => :XK_Control_R, 65509 => :XK_Caps_Lock, 65510 => :XK_Shift_Lock, 65511 => :XK_Meta_L, 65512 => :XK_Meta_R, 65513 => :XK_Alt_L, 65514 => :XK_Alt_R, 65515 => :XK_Super_L, 65516 => :XK_Super_R, 65517 => :XK_Hyper_L, 65518 => :XK_Hyper_R, 268828528 => :SunProps, 268828529 => :SunFront, 269025025 => :XF86XK_ModeLock, 269025026 => :XF86XK_MonBrightnessUp, 269025027 => :XF86XK_MonBrightnessDown, 269025028 => :XF86XK_KbdLightOnOff, 269025029 => :XF86XK_KbdBrightnessUp, 269025030 => :XF86XK_KbdBrightnessDown, 269025031 => :XF86XK_MonBrightnessCycle, 269025040 => :XF86XK_Standby, 269025041 => :XF86XK_AudioLowerVolume, 269025042 => :XF86XK_AudioMute, 269025043 => :XF86XK_AudioRaiseVolume, 269025044 => :XF86XK_AudioPlay, 269025045 => :XF86XK_AudioStop, 269025046 => :XF86XK_AudioPrev, 269025047 => :XF86XK_AudioNext, 269025048 => :XF86XK_HomePage, 269025049 => :XF86XK_Mail, 269025050 => :XF86XK_Start, 269025051 => :XF86XK_Search, 269025052 => :XF86XK_AudioRecord, 269025053 => :XF86XK_Calculator, 269025054 => :XF86XK_Memo, 269025055 => :XF86XK_ToDoList, 269025056 => :XF86XK_Calendar, 269025057 => :XF86XK_PowerDown, 269025058 => :XF86XK_ContrastAdjust, 269025059 => :XF86XK_RockerUp, 269025060 => :XF86XK_RockerDown, 269025061 => :XF86XK_RockerEnter, 269025062 => :XF86XK_Back, 269025063 => :XF86XK_Forward, 269025064 => :XF86XK_Stop, 269025065 => :XF86XK_Refresh, 269025066 => :XF86XK_PowerOff, 269025067 => :XF86XK_WakeUp, 269025068 => :XF86XK_Eject, 269025069 => :XF86XK_ScreenSaver, 269025070 => :XF86XK_WWW, 269025071 => :XF86XK_Sleep, 269025072 => :XF86XK_Favorites, 269025073 => :XF86XK_AudioPause, 269025074 => :XF86XK_AudioMedia, 269025075 => :XF86XK_MyComputer, 269025076 => :XF86XK_VendorHome, 269025077 => :XF86XK_LightBulb, 269025078 => :XF86XK_Shop, 269025079 => :XF86XK_History, 269025080 => :XF86XK_OpenURL, 269025081 => :XF86XK_AddFavorite, 269025082 => :XF86XK_HotLinks, 269025083 => :XF86XK_BrightnessAdjust, 269025084 => :XF86XK_Finance, 269025085 => :XF86XK_Community, 269025086 => :XF86XK_AudioRewind, 269025087 => :XF86XK_BackForward, 269025088 => :XF86XK_Launch0, 269025089 => :XF86XK_Launch1, 269025090 => :XF86XK_Launch2, 269025091 => :XF86XK_Launch3, 269025092 => :XF86XK_Launch4, 269025093 => :XF86XK_Launch5, 269025094 => :XF86XK_Launch6, 269025095 => :XF86XK_Launch7, 269025096 => :XF86XK_Launch8, 269025097 => :XF86XK_Launch9, 269025098 => :XF86XK_LaunchA, 269025099 => :XF86XK_LaunchB, 269025100 => :XF86XK_LaunchC, 269025101 => :XF86XK_LaunchD, 269025102 => :XF86XK_LaunchE, 269025103 => :XF86XK_LaunchF, 269025104 => :XF86XK_ApplicationLeft, 269025105 => :XF86XK_ApplicationRight, 269025106 => :XF86XK_Book, 269025107 => :XF86XK_CD, 269025108 => :XF86XK_Calculater, 269025109 => :XF86XK_Clear, 269025110 => :XF86XK_Close, 269025111 => :XF86XK_Copy, 269025112 => :XF86XK_Cut, 269025113 => :XF86XK_Display, 269025114 => :XF86XK_DOS, 269025115 => :XF86XK_Documents, 269025116 => :XF86XK_Excel, 269025117 => :XF86XK_Explorer, 269025118 => :XF86XK_Game, 269025119 => :XF86XK_Go, 269025120 => :XF86XK_iTouch, 269025121 => :XF86XK_LogOff, 269025122 => :XF86XK_Market, 269025123 => :XF86XK_Meeting, 269025125 => :XF86XK_MenuKB, 269025126 => :XF86XK_MenuPB, 269025127 => :XF86XK_MySites, 269025128 => :XF86XK_New, 269025129 => :XF86XK_News, 269025130 => :XF86XK_OfficeHome, 269025131 => :XF86XK_Open, 269025132 => :XF86XK_Option, 269025133 => :XF86XK_Paste, 269025134 => :XF86XK_Phone, 269025136 => :XF86XK_Q, 269025138 => :XF86XK_Reply, 269025139 => :XF86XK_Reload, 269025140 => :XF86XK_RotateWindows, 269025141 => :XF86XK_RotationPB, 269025142 => :XF86XK_RotationKB, 269025143 => :XF86XK_Save, 269025144 => :XF86XK_ScrollUp, 269025145 => :XF86XK_ScrollDown, 269025146 => :XF86XK_ScrollClick, 269025147 => :XF86XK_Send, 269025148 => :XF86XK_Spell, 269025149 => :XF86XK_SplitScreen, 269025150 => :XF86XK_Support, 269025151 => :XF86XK_TaskPane, 269025152 => :XF86XK_Terminal, 269025153 => :XF86XK_Tools, 269025154 => :XF86XK_Travel, 269025156 => :XF86XK_UserPB, 269025157 => :XF86XK_User1KB, 269025158 => :XF86XK_User2KB, 269025159 => :XF86XK_Video, 269025160 => :XF86XK_WheelButton, 269025161 => :XF86XK_Word, 269025162 => :XF86XK_Xfer, 269025163 => :XF86XK_ZoomIn, 269025164 => :XF86XK_ZoomOut, 269025165 => :XF86XK_Away, 269025166 => :XF86XK_Messenger, 269025167 => :XF86XK_WebCam, 269025168 => :XF86XK_MailForward, 269025169 => :XF86XK_Pictures, 269025170 => :XF86XK_Music, 269025171 => :XF86XK_Battery, 269025172 => :XF86XK_Bluetooth, 269025173 => :XF86XK_WLAN, 269025174 => :XF86XK_UWB, 269025175 => :XF86XK_AudioForward, 269025176 => :XF86XK_AudioRepeat, 269025177 => :XF86XK_AudioRandomPlay, 269025178 => :XF86XK_Subtitle, 269025179 => :XF86XK_AudioCycleTrack, 269025180 => :XF86XK_CycleAngle, 269025181 => :XF86XK_FrameBack, 269025182 => :XF86XK_FrameForward, 269025183 => :XF86XK_Time, 269025184 => :XF86XK_Select, 269025185 => :XF86XK_View, 269025186 => :XF86XK_TopMenu, 269025187 => :XF86XK_Red, 269025188 => :XF86XK_Green, 269025189 => :XF86XK_Yellow, 269025190 => :XF86XK_Blue, 269025191 => :XF86XK_Suspend, 269025192 => :XF86XK_Hibernate, 269025193 => :XF86XK_TouchpadToggle, 269025200 => :XF86XK_TouchpadOn, 269025201 => :XF86XK_TouchpadOff, 269025202 => :XF86XK_AudioMicMute, 269025203 => :XF86XK_Keyboard, 269025204 => :XF86XK_WWAN, 269025205 => :XF86XK_RFKill, 269025206 => :XF86XK_AudioPreset, 269025207 => :XF86XK_RotationLockToggle, 269025208 => :XF86XK_FullScreen, 269024769 => :XF86XK_Switch_VT_1, 269024770 => :XF86XK_Switch_VT_2, 269024771 => :XF86XK_Switch_VT_3, 269024772 => :XF86XK_Switch_VT_4, 269024773 => :XF86XK_Switch_VT_5, 269024774 => :XF86XK_Switch_VT_6, 269024775 => :XF86XK_Switch_VT_7, 269024776 => :XF86XK_Switch_VT_8, 269024777 => :XF86XK_Switch_VT_9, 269024778 => :XF86XK_Switch_VT_10, 269024779 => :XF86XK_Switch_VT_11, 269024780 => :XF86XK_Switch_VT_12, 269024800 => :XF86XK_Ungrab, 269024801 => :XF86XK_ClearGrab, 269024802 => :XF86XK_Next_VMode, 269024803 => :XF86XK_Prev_VMode, 269024804 => :XF86XK_LogWindowTree, 269024805 => :XF86XK_LogGrabInfo }
end)))
"Already required '/home/vidarh/Desktop/Projects/fonts/skrift/lib/skrift.rb'"
"Already required '/home/vidarh/Desktop/Projects/skrift-x11/lib/skrift/x11.rb'"
((((require("strscan"); "Ignoring pathname"; (module Citrus
  VERSION = [3, 0, 2]

  def self.version
    VERSION.join(".")
  end
end); module Citrus
  autoload(:File, "citrus/file")
  DOT = /./mu
  Infinity = 1.0 / 0
  CLOSE = -1

  def self.cache
    @cache ||= {}
  end

  def self.eval(code, options = {})
    File.parse(code, options).value
  end

  def self.rule(expr, options = {})
    eval(expr, options.merge(root: :expression))
  end

  def self.load(file, options = {})
    unless /\.citrus$/ === file
      file += ".citrus"
    end
    force = options.delete(:force)
    if force || !cache[file]
      begin
        cache[file] = eval(::File.read(file), options)
      rescue SyntaxError => e
        e.message.replace("#{::File.expand_path(file)}: #{e.message}")
        raise(e)
      end
    end
    cache[file]
  end

  def self.require(file, options = {})
    unless /\.citrus$/ === file
      file += ".citrus"
    end
    found = nil
    paths = [""]
    unless Pathname.new(file).absolute?
      paths += $LOAD_PATH
    end
    paths.each { |path|
      found = Dir[::File.join(path, file)].first
      if found
        break
      end
    }
    if found
      Citrus.load(found, options)
    else
      raise(LoadError, "Cannot find file #{file}")
    end
    found
  end

  class Error < StandardError
  end

  class LoadError < Error
  end

  class ParseError < Error
    def initialize(input)
      @offset = input.max_offset
      @line_offset = input.line_offset(offset)
      @line_number = input.line_number(offset)
      @line = input.line(offset)
      message = "Failed to parse input on line #{line_number}"
      message << " at offset #{line_offset}
#{detail}"
      super(message)
    end
    attr_reader(:offset)
    attr_reader(:line_offset)
    attr_reader(:line_number)
    attr_reader(:line)

    def detail
      "#{line}
#{" " * line_offset}^"
    end
  end

  class SyntaxError < Error
    def initialize(error)
      message = "Malformed Citrus syntax on line #{error.line_number}"
      message << " at offset #{error.line_offset}
#{error.detail}"
      super(message)
    end
  end

  class Input < StringScanner
    def initialize(source)
      super(source_text(source))
      @source = source
      @max_offset = 0
    end
    attr_reader(:max_offset)
    attr_reader(:source)

    def reset
      @max_offset = 0
      super
    end

    def lines
      if string.respond_to?(:lines)
        string.lines.to_a
      else
        string.to_a
      end
    end

    def line_offset(pos = pos())
      p = 0
      string.each_line { |line|
        len = line.length
        if p + len >= pos
          return (pos - p)
        end
        p += len
      }
      0
    end

    def line_index(pos = pos())
      p = n = 0
      string.each_line { |line|
        p += line.length
        if p >= pos
          return n
        end
        n += 1
      }
      0
    end

    def line_number(pos = pos())
      line_index(pos) + 1
    end
    alias_method(:lineno, :line_number)

    def line(pos = pos())
      lines[line_index(pos)]
    end
    nil

    def exec(rule, events = [])
      position = pos
      index = events.size
      if apply_rule(rule, position, events).size > index
        if pos > @max_offset
          @max_offset = pos
        end
      else
        self.pos=position
      end
      events
    end

    def test(rule)
      position = pos
      events = apply_rule(rule, position, [])
      self.pos=position
      events[-1]
    end
    alias_method(:to_str, :string)
    nil

    def source_text(source)
      if source.respond_to?(:to_path)
        ::File.read(source.to_path)
      else
        if source.respond_to?(:read)
          source.read
        else
          if source.respond_to?(:to_str)
            source.to_str
          else
            raise(ArgumentError, "Unable to parse from #{source}", caller)
          end
        end
      end
    end

    def apply_rule(rule, position, events)
      rule.exec(self, events)
    end
  end

  class MemoizedInput < Input
    def initialize(string)
      super(string)
      @cache = {}
      @cache_hits = 0
    end
    attr_reader(:cache)
    attr_reader(:cache_hits)

    def reset
      @cache.clear
      @cache_hits = 0
      super
    end
    nil
    nil

    def apply_rule(rule, position, events)
      memo = @cache[rule] ||= {}
      if memo[position]
        @cache_hits += 1
        c = memo[position]
        unless c.empty?
          events.concat(c)
          self.pos += events[-1]
        end
      else
        index = events.size
        rule.exec(self, events)
        memo[position] = events.slice(index, events.size)
      end
      events
    end
  end

  module Grammar
    def self.new(&block)
      mod = Module.new {
        include(Grammar)
      }
      if block
        mod.module_eval(&block)
      end
      mod
    end

    def self.included(mod)
      mod.extend(GrammarMethods)

      class << mod
        public(:include)
      end
    end
  end

  module GrammarMethods
    def self.extend_object(obj)
      unless Module === obj
        raise(ArgumentError, "Grammars must be Modules")
      end
      super
    end

    def parse(source, options = {})
      rule_name = options.delete(:root) || root
      unless rule_name
        raise(Error, "No root rule specified")
      end
      rule = rule(rule_name)
      unless rule
        raise(Error, "No rule named \"#{rule_name}\"")
      end
      rule.parse(source, options)
    end
    nil

    def name
      super.to_s
    end

    def included_grammars
      included_modules.select { |mod|
        mod.include?(Grammar)
      }
    end

    def rule_names
      @rule_names ||= []
    end

    def rules
      @rules ||= {}
    end

    def has_rule?(name)
      rules.key?(name.to_sym)
    end

    def setup_super(rule, name)
      if Nonterminal === rule
        rule.rules.each { |r|
          setup_super(r, name)
        }
      else
        if Super === rule
          rule.rule_name=name
        end
      end
    end
    private(:setup_super)

    def super_rule(name)
      sym = name.to_sym
      included_grammars.each { |grammar|
        rule = grammar.rule(sym)
        if rule
          return rule
        end
      }
      nil
    end

    def rule(name, obj = nil, &block)
      sym = name.to_sym
      if block
        obj = block.call
      end
      if obj
        unless has_rule?(sym)
          rule_names << sym
        end
        rule = Rule.for(obj)
        rule.name=name
        setup_super(rule, name)
        rule.grammar=self
        rules[sym] = rule
      end
      rules[sym] || super_rule(sym)
    rescue => e
      e.message.replace("Cannot create rule \"#{name}\": #{e.message}")
      raise(e)
    end

    def root(name = nil)
      if name
        @root = name.to_sym
      else
        if instance_variable_defined?(:@root)
          @root
        else
          rule_names.first
        end
      end
    end
    nil
    nil
    nil

    def notp(rule, &block)
      ext(NotPredicate.new(rule), block)
    end
    nil

    def rep(rule, min = 1, max = Infinity, &block)
      ext(Repeat.new(rule, min, max), block)
    end

    def one_or_more(rule, &block)
      rep(rule, &block)
    end

    def zero_or_more(rule, &block)
      rep(rule, 0, &block)
    end

    def zero_or_one(rule, &block)
      rep(rule, 0, 1, &block)
    end

    def all(*args, &block)
      ext(Sequence.new(args), block)
    end

    def any(*args, &block)
      ext(Choice.new(args), block)
    end

    def label(rule, label, &block)
      rule = ext(rule, block)
      rule.label=label
      rule
    end

    def ext(rule, mod = nil, &block)
      rule = Rule.for(rule)
      if block
        mod = block
      end
      if mod
        rule.extension=mod
      end
      rule
    end

    def mod(rule, &block)
      rule.extension=Module.new(&block)
      rule
    end
  end

  module Rule
    def self.for(obj)
      case obj
      when Rule
        obj
      when Symbol
        Alias.new(obj)
      when String
        StringTerminal.new(obj)
      when Regexp
        Terminal.new(obj)
      when Array
        Sequence.new(obj)
      when Range
        Choice.new(obj.to_a)
      when Numeric
        StringTerminal.new(obj.to_s)
      else
        raise(ArgumentError, "Invalid rule object: #{obj.inspect}")
      end
    end
    attr_accessor(:grammar)

    def name=(name)
      @name = name.to_sym
    end
    attr_reader(:name)

    def label=(label)
      @label = label.to_sym
    end
    attr_reader(:label)

    def extension=(mod)
      if Proc === mod
        mod = Module.new {
          define_method(:value, &mod)
        }
      end
      unless Module === mod
        raise(ArgumentError, "Extension must be a Module")
      end
      @extension = mod
    end
    attr_reader(:extension)

    def default_options
      { consume: true, memoize: false, offset: 0 }
    end

    def parse(source, options = {})
      opts = default_options.merge(options)
      input = (if opts[:memoize]
        MemoizedInput
      else
        Input
      end).new(source)
      string = input.string
      if opts[:offset] > 0
        input.pos=opts[:offset]
      end
      events = input.exec(self)
      length = events[-1]
      if !length || (opts[:consume] && length < (string.length - opts[:offset]))
        raise(ParseError, input)
      end
      Match.new(input, events, opts[:offset])
    end

    def test(string, options = {})
      parse(string, options).length
    rescue ParseError
      nil
    end

    def ===(obj)
      !test(obj).nil?
    end
    nil

    def elide?
      false
    end

    def needs_paren?
      is_a?(Nonterminal) && rules.length > 1
    end

    def to_s
      if label
        "#{label}:" + (if needs_paren?
          "(#{to_citrus})"
        else
          to_citrus
        end)
      else
        to_citrus
      end
    end
    alias_method(:to_str, :to_s)

    def to_embedded_s
      if name
        name.to_s
      else
        if needs_paren? && label.nil?
          "(#{to_s})"
        else
          to_s
        end
      end
    end

    def ==(other)
      case other
      when Rule
        to_s == other.to_s
      else
        super
      end
    end
    alias_method(:eql?, :==)

    def inspect
      to_s
    end

    def extend_match(match)
      if extension
        match.extend(extension)
      end
    end
  end

  module Proxy
    include(Rule)

    def initialize(rule_name = "<proxy>")
      self.rule_name=rule_name
    end

    def rule_name=(rule_name)
      @rule_name = rule_name.to_sym
    end
    attr_reader(:rule_name)

    def rule
      @rule ||= resolve!
    end

    def exec(input, events = [])
      index = events.size
      if input.exec(rule, events).size > index
        events[index] = self
      end
      events
    end

    def elide?
      rule.elide?
    end

    def extend_match(match)
      rule.extend_match(match)
      super
    end
  end

  class Alias
    include(Proxy)

    def to_citrus
      rule_name.to_s
    end
    nil

    def resolve!
      rule = grammar.rule(rule_name)
      unless rule
        raise(Error, "No rule named \"#{rule_name}\" in grammar #{grammar}")
      end
      rule
    end
  end

  class Super
    include(Proxy)

    def to_citrus
      "super"
    end
    nil

    def resolve!
      rule = grammar.super_rule(rule_name)
      unless rule
        raise(Error, "No rule named \"#{rule_name}\" in hierarchy of grammar #{grammar}")
      end
      rule
    end
  end

  class Terminal
    include(Rule)

    def initialize(regexp = /^/)
      @regexp = regexp
    end
    attr_reader(:regexp)

    def exec(input, events = [])
      match = input.scan(@regexp)
      if match
        events << self
        events << CLOSE
        events << match.length
      end
      events
    end

    def case_sensitive?
      !@regexp.casefold?
    end

    def ==(other)
      case other
      when Regexp
        @regexp == other
      else
        super
      end
    end
    alias_method(:eql?, :==)
    nil

    def to_citrus
      @regexp.inspect
    end
  end

  class StringTerminal < Terminal
    def initialize(rule = "", flags = 0)
      super(Regexp.new(Regexp.escape(rule), flags))
      @string = rule
    end

    def ==(other)
      case other
      when String
        @string == other
      else
        super
      end
    end
    alias_method(:eql?, :==)

    def to_citrus
      if case_sensitive?
        @string.inspect
      else
        @string.inspect.gsub(/^"|"$/, "`")
      end
    end
  end

  module Nonterminal
    include(Rule)

    def initialize(rules = [])
      @rules = rules.map { |r|
        Rule.for(r)
      }
    end
    attr_reader(:rules)

    def grammar=(grammar)
      super
      @rules.each { |r|
        r.grammar=grammar
      }
    end
  end

  class AndPredicate
    include(Nonterminal)

    def initialize(rule = "")
      super([rule])
    end

    def rule
      rules[0]
    end

    def exec(input, events = [])
      if input.test(rule)
        events << self
        events << CLOSE
        events << 0
      end
      events
    end

    def to_citrus
      "&" + rule.to_embedded_s
    end
  end

  class NotPredicate
    include(Nonterminal)

    def initialize(rule = "")
      super([rule])
    end

    def rule
      rules[0]
    end

    def exec(input, events = [])
      unless input.test(rule)
        events << self
        events << CLOSE
        events << 0
      end
      events
    end

    def to_citrus
      "!" + rule.to_embedded_s
    end
  end

  class ButPredicate
    include(Nonterminal)
    DOT_RULE = Rule.for(DOT)

    def initialize(rule = "")
      super([rule])
    end

    def rule
      rules[0]
    end

    def exec(input, events = [])
      length = 0
      until input.test(rule)
        len = input.exec(DOT_RULE)[-1]
        unless len
          break
        end
        length += len
      end
      if length > 0
        events << self
        events << CLOSE
        events << length
      end
      events
    end

    def to_citrus
      "~" + rule.to_embedded_s
    end
  end

  class Repeat
    include(Nonterminal)

    def initialize(rule = "", min = 1, max = Infinity)
      if min > max
        raise(ArgumentError, "Min cannot be greater than max")
      end
      super([rule])
      @min = min
      @max = max
    end

    def rule
      rules[0]
    end

    def exec(input, events = [])
      events << self
      index = events.size
      start = index - 1
      length = n = 0
      while n < max && input.exec(rule, events).size > index
        length += events[-1]
        index = events.size
        n += 1
      end
      if n >= min
        events << CLOSE
        events << length
      else
        events.slice!(start, index)
      end
      events
    end
    attr_reader(:min)
    attr_reader(:max)

    def operator
      @operator ||= case [min, max]
      when [0, 0]
        ""
      when [0, 1]
        "?"
      when [1, Infinity]
        "+"
      else
        [min, max].map { |n|
          if n == 0 || n == Infinity
            ""
          else
            n.to_s
          end
        }.join("*")
      end
    end

    def to_citrus
      rule.to_embedded_s + operator
    end
  end

  class Sequence
    include(Nonterminal)

    def exec(input, events = [])
      events << self
      index = events.size
      start = index - 1
      length = n = 0
      m = rules.length
      while n < m && input.exec(rules[n], events).size > index
        length += events[-1]
        index = events.size
        n += 1
      end
      if n == m
        events << CLOSE
        events << length
      else
        events.slice!(start, index)
      end
      events
    end

    def to_citrus
      rules.map { |r|
        r.to_embedded_s
      }.join(" ")
    end
  end

  class Choice
    include(Nonterminal)

    def exec(input, events = [])
      events << self
      index = events.size
      n = 0
      m = rules.length
      while n < m && input.exec(rules[n], events).size == index
        n += 1
      end
      if index < events.size
        events << CLOSE
        events << events[-2]
      else
        events.pop
      end
      events
    end

    def elide?
      true
    end

    def to_citrus
      rules.map { |r|
        r.to_embedded_s
      }.join(" | ")
    end
  end

  class Match
    def initialize(input, events = [], offset = 0)
      @input = input
      @offset = offset
      @captures = nil
      @matches = nil
      if events.length > 0
        elisions = []
        while events[0].elide?
          elisions.unshift(events.shift)
          events.slice!(-2, events.length)
        end
        events[0].extend_match(self)
        elisions.each { |rule|
          rule.extend_match(self)
        }
      else
        string = input.to_str
        events = [Rule.for(string), CLOSE, string.length]
      end
      @events = events
    end
    attr_reader(:input)
    attr_reader(:offset)
    attr_reader(:events)

    def length
      events.last
    end

    def source
      (input.respond_to?(:source) && input.source) || input
    end

    def string
      @string ||= input.to_str[offset, length]
    end

    def captures(name = nil)
      unless @captures
        process_events!
      end
      if name
        @captures[name]
      else
        @captures
      end
    end

    def capture(name)
      captures[name].first
    end

    def matches
      unless @matches
        process_events!
      end
      @matches
    end

    def first
      matches.first
    end
    alias_method(:to_s, :string)
    alias_method(:to_str, :to_s)
    alias_method(:value, :to_s)

    def to_a
      [self] + matches
    end

    def [](key, *args)
      case key
      when Integer, Range
        to_a[key, *args]
      else
        captures[key]
      end
    end

    def ==(other)
      case other
      when String
        string == other
      when Match
        string == other.to_s
      else
        super
      end
    end
    alias_method(:eql?, :==)

    def inspect
      string.inspect
    end
    nil
    nil

    def process_events!
      @captures = captures_hash
      @matches = []
      capture!(@events[0], self)
      @captures[0] = self
      stack = []
      offset = 0
      close = false
      index = 0
      last_length = nil
      capture = true
      while index < @events.size
        event = @events[index]
        if close
          start = stack.pop
          if Rule === start
            rule = start
            os = stack.pop
            start = stack.pop
            match = Match.new(input, @events[start..index], @offset + os)
            capture!(rule, match)
            if stack.size == 1
              @matches << match
              @captures[@matches.size] = match
            end
            capture = true
          end
          unless last_length
            last_length = event
          end
          close = false
        else
          if event == CLOSE
            close = true
          else
            stack << index
            if last_length
              offset += last_length
              last_length = nil
            end
            if capture && stack.size != 1
              stack << offset
              stack << event
              if Proxy === event
                capture = false
              end
            end
          end
        end
        index += 1
      end
    end

    def capture!(rule, match)
      if Proxy === rule
        if @captures.key?(rule.rule_name)
          @captures[rule.rule_name] << match
        else
          @captures[rule.rule_name] = [match]
        end
      end
      if rule.label
        if @captures.key?(rule.label)
          @captures[rule.label] << match
        else
          @captures[rule.label] = [match]
        end
      end
    end

    def captures_hash
      Hash.new { |hash, key|
        case key
        when String
          hash[key.to_sym]
        when Numeric
          nil
        else
          []
        end
      }
    end
  end
end)); module Citrus
  module ModuleNameHelpers
    def module_name
      capture(:module_name)
    end

    def module_segments
      @module_segments ||= module_name.value.split("::")
    end

    def module_namespace
      module_segments[0...-1].inject(Object) { |namespace, constant|
        if constant.empty?
          namespace
        else
          namespace.const_get(constant)
        end
      }
    end

    def module_basename
      module_segments.last
    end
  end
  File = Grammar.new {
    rule(:file) {
      all(:space, zero_or_more(any(:require, :grammar))) {
        captures[:require].each { |req|
          file = req.value

          begin
            require(file)
          rescue ::LoadError => e
            begin
              Citrus.require(file)
            rescue LoadError
              raise(e)
            end
          end
        }
        captures[:grammar].map { |g|
          g.value
        }
      }
    }
    rule(:grammar) {
      mod(all(:grammar_keyword, :module_name, zero_or_more(any(:include, :root, :rule)), :end_keyword)) {
        include(ModuleNameHelpers)

        def value
          grammar = module_namespace.const_set(module_basename, Grammar.new)
          captures[:include].each { |inc|
            grammar.include(inc.value)
          }
          captures[:rule].each { |r|
            grammar.rule(r.rule_name.value, r.value)
          }
          root = capture(:root)
          if root
            grammar.root(root.value)
          end
          grammar
        end
      }
    }
    rule(:rule) {
      mod(all(:rule_keyword, :rule_name, zero_or_one(:expression), :end_keyword)) {
        def rule_name
          capture(:rule_name)
        end

        def value
          expr = capture(:expression)
          if expr
            expr.value
          else
            Rule.for("")
          end
        end
      }
    }
    rule(:expression) {
      all(:sequence, zero_or_more([["|", zero_or_one(:space)], :sequence])) {
        rules = captures[:sequence].map { |s|
          s.value
        }
        if rules.length > 1
          Choice.new(rules)
        else
          rules.first
        end
      }
    }
    rule(:sequence) {
      one_or_more(:labelled) {
        rules = captures[:labelled].map { |l|
          l.value
        }
        if rules.length > 1
          Sequence.new(rules)
        else
          rules.first
        end
      }
    }
    rule(:labelled) {
      all(zero_or_one(:label), :extended) {
        label = capture(:label)
        rule = capture(:extended).value
        if label
          rule.label=label.value
        end
        rule
      }
    }
    rule(:extended) {
      all(:prefix, zero_or_one(:extension)) {
        extension = capture(:extension)
        rule = capture(:prefix).value
        if extension
          rule.extension=extension.value
        end
        rule
      }
    }
    rule(:prefix) {
      all(zero_or_one(:predicate), :suffix) {
        predicate = capture(:predicate)
        rule = capture(:suffix).value
        if predicate
          rule = predicate.value(rule)
        end
        rule
      }
    }
    rule(:suffix) {
      all(:primary, zero_or_one(:repeat)) {
        repeat = capture(:repeat)
        rule = capture(:primary).value
        if repeat
          rule = repeat.value(rule)
        end
        rule
      }
    }
    rule(:primary) {
      any(:grouping, :proxy, :terminal)
    }
    rule(:grouping) {
      all(["(", zero_or_one(:space)], :expression, [")", zero_or_one(:space)]) {
        capture(:expression).value
      }
    }
    rule(:require) {
      all(:require_keyword, :quoted_string) {
        capture(:quoted_string).value
      }
    }
    rule(:include) {
      mod(all(:include_keyword, :module_name)) {
        include(ModuleNameHelpers)

        def value
          module_namespace.const_get(module_basename)
        end
      }
    }
    rule(:root) {
      all(:root_keyword, :rule_name) {
        capture(:rule_name).value
      }
    }
    rule(:rule_name) {
      all(/[a-zA-Z][a-zA-Z0-9_-]*/, :space) {
        first.to_s
      }
    }
    rule(:proxy) {
      any(:super, :alias)
    }
    rule(:super) {
      ext(:super_keyword) {
        Super.new
      }
    }
    rule(:alias) {
      all(notp(:end_keyword), :rule_name) {
        Alias.new(capture(:rule_name).value)
      }
    }
    rule(:terminal) {
      any(:quoted_string, :case_insensitive_string, :regular_expression, :character_class, :dot) {
        primitive = super()
        if String === primitive
          StringTerminal.new(primitive, flags)
        else
          Terminal.new(primitive)
        end
      }
    }
    rule(:quoted_string) {
      mod(all(/(["'])(?:\\?.)*?\1/, :space)) {
        def value
          eval(first.to_s)
        end

        def flags
          0
        end
      }
    }
    rule(:case_insensitive_string) {
      mod(all(/`(?:\\?.)*?`/, :space)) {
        def value
          eval(first.to_s.gsub(/^`|`$/, "\""))
        end

        def flags
          Regexp::IGNORECASE
        end
      }
    }
    rule(:regular_expression) {
      all(/\/(?:\\?.)*?\/[imxouesn]*/, :space) {
        eval(first.to_s)
      }
    }
    rule(:character_class) {
      all(/\[(?:\\?.)*?\]/, :space) {
        eval("/#{first.to_s.gsub("/", "\\/")}/")
      }
    }
    rule(:dot) {
      all(".", :space) {
        DOT
      }
    }
    rule(:label) {
      all(/[a-zA-Z0-9_]+/, :space, ":", :space) {
        first.to_str.to_sym
      }
    }
    rule(:extension) {
      any(:tag, :block)
    }
    rule(:tag) {
      mod(all(["<", zero_or_one(:space)], :module_name, [">", zero_or_one(:space)])) {
        include(ModuleNameHelpers)

        def value
          module_namespace.const_get(module_basename)
        end
      }
    }
    rule(:block) {
      all("{", zero_or_more(any(:block, /[^{}]+/)), ["}", zero_or_one(:space)]) {
        proc = eval("Proc.new #{to_s}", TOPLEVEL_BINDING)
        if to_s =~ /\b(def|include) /
          Module.new(&proc)
        else
          proc
        end
      }
    }
    rule(:predicate) {
      any(:and, :not, :but)
    }
    rule(:and) {
      all("&", :space) { |rule|
        AndPredicate.new(rule)
      }
    }
    rule(:not) {
      all("!", :space) { |rule|
        NotPredicate.new(rule)
      }
    }
    rule(:but) {
      all("~", :space) { |rule|
        ButPredicate.new(rule)
      }
    }
    rule(:repeat) {
      any(:question, :plus, :star)
    }
    rule(:question) {
      all("?", :space) { |rule|
        Repeat.new(rule, 0, 1)
      }
    }
    rule(:plus) {
      all("+", :space) { |rule|
        Repeat.new(rule, 1, Infinity)
      }
    }
    rule(:star) {
      all(/[0-9]*/, "*", /[0-9]*/, :space) { |rule|
        min = if captures[1] == ""
          0
        else
          captures[1].to_str.to_i
        end
        max = if captures[3] == ""
          Infinity
        else
          captures[3].to_str.to_i
        end
        Repeat.new(rule, min, max)
      }
    }
    rule(:module_name) {
      all(one_or_more([zero_or_one("::"), :constant]), :space) {
        first.to_s
      }
    }
    rule(:require_keyword, [/\brequire\b/, :space])
    rule(:include_keyword, [/\binclude\b/, :space])
    rule(:grammar_keyword, [/\bgrammar\b/, :space])
    rule(:root_keyword, [/\broot\b/, :space])
    rule(:rule_keyword, [/\brule\b/, :space])
    rule(:super_keyword, [/\bsuper\b/, :space])
    rule(:end_keyword, [/\bend\b/, :space])
    rule(:constant, /[A-Z][a-zA-Z0-9_]*/)
    rule(:white, /[ \t\n\r]/)
    rule(:comment, /#.*/)
    rule(:space, zero_or_more(any(:white, :comment)))
  }

  def File.parse(*)
    super
  rescue ParseError => e
    raise(SyntaxError, e)
  end
end))
(("Already required '/home/vidarh/src/personal/ruby-term/term/bundle/ruby/3.2.0/gems/citrus-3.0.2/lib/citrus.rb'"; (module TomlRB
  Error = Class.new(StandardError)
  ParseError = Class.new(Error)

  class ValueOverwriteError < Error
    attr_accessor(:key)

    def initialize(key)
      @key = key
      super("Key #{key.inspect} is defined more than once")
    end
  end
end); (module TomlRB
  module ArrayParser
    def value
      elements = captures[:array_elements].first
      if elements
        elements.value
      else
        []
      end
    end
  end
end); (module TomlRB
  module BasicString
    SPECIAL_CHARS = { "\\0" => "\u0000", "\\t" => "\t", "\\b" => "\b", "\\f" => "\f", "\\n" => "\n", "\\r" => "\r", "\\\"" => "\"", "\\\\" => "\\" }.freeze

    def value
      aux = TomlRB::BasicString.transform_escaped_chars(first.value)
      aux[1...-1]
    end

    def self.decode_unicode(str)
      [str[2..-1].to_i(16)].pack("U")
    end

    def self.transform_escaped_chars(str)
      str.gsub(/\\(u[\da-fA-F]{4}|U[\da-fA-F]{8}|.)/) { |m|
        if m.size == 2
          SPECIAL_CHARS[m] || parse_error(m)
        else
          decode_unicode(m).force_encoding("UTF-8")
        end
      }
    end

    def self.parse_error(m)
      fail(ParseError.new("Escape sequence #{m} is reserved"))
    end
  end

  module LiteralString
    def value
      first.value[1...-1]
    end
  end

  module MultilineString
    def value
      if captures[:text].empty?
        return ""
      end
      aux = captures[:text].first.value
      aux.gsub!(/\\\r?\n[\n\t\r ]*/, "")
      TomlRB::BasicString.transform_escaped_chars(aux)
    end
  end

  module MultilineLiteral
    def value
      if captures[:text].empty?
        return ""
      end
      aux = captures[:text].first.value
      aux.gsub(/\\\r?\n[\n\t\r ]*/, "")
    end
  end
end); (module TomlRB
  module OffsetDateTimeParser
    def value
      skeleton = captures[:datetime_skeleton].first
      (year, mon, day, hour, min, sec, sec_frac) = skeleton.value
      offset = captures[:date_offset].first || "+00:00"
      sec = "#{sec}.#{sec_frac}".to_f
      Time.new(year, mon, day, hour, min, sec, offset.to_s)
    end
  end

  module LocalDateTimeParser
    def value
      (year, mon, day) = captures[:date_skeleton].first.value
      (hour, min, sec, sec_frac) = captures[:time_skeleton].first.value
      usec = sec_frac.to_s.ljust(6, "0")
      Time.local(year, mon, day, hour, min, sec, usec)
    end
  end

  module LocalDateParser
    def value
      (year, mon, day) = captures[:date_skeleton].first.value
      Time.local(year, mon, day)
    end
  end

  module LocalTimeParser
    def value
      (hour, min, sec, sec_frac) = captures[:time_skeleton].first.value
      usec = sec_frac.to_s.ljust(6, "0")
      Time.at(3600 * hour.to_i + 60.*(min.to_i) + sec.to_i, usec.to_i)
    end
  end
end); (module TomlRB
  class Table
    def initialize(dotted_keys)
      @dotted_keys = dotted_keys
    end

    def navigate_keys(hash, visited_keys, symbolize_keys = false)
      ensure_key_not_defined(visited_keys)
      current = hash
      keys = if symbolize_keys
        @dotted_keys.map(&:to_sym)
      else
        @dotted_keys
      end
      keys.each { |key|
        unless current.key?(key)
          current[key] = {}
        end
        element = current[key]
        current = if element.is_a?(Array)
          element.last
        else
          element
        end
        unless current.is_a?(Hash)
          fail(ValueOverwriteError.new(key))
        end
      }
      current
    end

    def accept_visitor(parser)
      parser.visit_table(self)
    end

    def full_key
      @dotted_keys.join(".")
    end
    nil

    def ensure_key_not_defined(visited_keys)
      if visited_keys.include?(full_key)
        fail(ValueOverwriteError.new(full_key))
      end
      visited_keys << full_key
    end
  end

  module TableParser
    def value
      TomlRB::Table.new(captures[:stripped_key].map(&:value).first)
    end
  end
end); (module TomlRB
  class TableArray
    def initialize(dotted_keys)
      @dotted_keys = dotted_keys
    end

    def navigate_keys(hash, symbolize_keys = false)
      current = hash
      keys = if symbolize_keys
        @dotted_keys.map(&:to_sym)
      else
        @dotted_keys
      end
      last_key = keys.pop
      keys.each { |key|
        unless current[key]
          current[key] = {}
        end
        if current[key].is_a?(Array)
          if current[key].empty?
            current[key] << {}
          end
          current = current[key].last
        else
          current = current[key]
        end
      }
      if current[last_key].is_a?(Hash)
        fail(TomlRB::ParseError, "#{last_key} was defined as hash but is now redefined as a table!")
      end
      unless current[last_key]
        current[last_key] = []
      end
      current[last_key] << {}
      current[last_key].last
    end

    def accept_visitor(parser)
      parser.visit_table_array(self)
    end

    def full_key
      @dotted_keys.join(".")
    end
  end

  module TableArrayParser
    def value
      TomlRB::TableArray.new(captures[:stripped_key].map(&:value).first)
    end
  end
end); (module TomlRB
  class InlineTable
    def initialize(keyvalue_pairs)
      @pairs = keyvalue_pairs
    end

    def accept_visitor(keyvalue)
      value(keyvalue.symbolize_keys)
    end

    def value(symbolize_keys = false)
      result = {}
      @pairs.each { |kv|
        update = kv.assign({}, [], symbolize_keys)
        result.merge!(update) { |key, _, _|
          fail(ValueOverwriteError.new(key))
        }
      }
      result
    end
  end

  module InlineTableParser
    def value
      TomlRB::InlineTable.new(captures[:keyvalue].map(&:value))
    end
  end
end); (("Already required '/home/vidarh/src/personal/ruby-term/term/bundle/ruby/3.2.0/gems/toml-rb-2.2.0/lib/toml-rb/inline_table.rb'"; module TomlRB
  class Keyvalue
    attr_reader(:dotted_keys, :value, :symbolize_keys)

    def initialize(dotted_keys, value)
      @dotted_keys = dotted_keys
      @value = value
      @symbolize_keys = false
    end

    def assign(hash, fully_defined_keys, symbolize_keys = false)
      @symbolize_keys = symbolize_keys
      dotted_keys_str = @dotted_keys.join(".")
      keys = if symbolize_keys
        @dotted_keys.map(&:to_sym)
      else
        @dotted_keys
      end
      update = keys.reverse.inject(visit_value(@value)) { |k1, k2|
        { k2 => k1 }
      }
      if @value.is_a?(InlineTable)
        fully_defined_keys << dotted_keys_str
        hash.merge!(update) { |key, _, _|
          fail(ValueOverwriteError.new(key))
        }
      else
        if fully_defined_keys.find { |k|
          update.dig(*k)
        }
          hash.merge!(update) { |key, _, _|
            fail(ValueOverwriteError.new(key))
          }
        else
          dotted_key_merge(hash, update)
        end
      end
    end

    def dotted_key_merge(hash, update)
      hash.merge!(update) { |key, old, new|
        if old.is_a?(Hash) && new.is_a?(Hash)
          dotted_key_merge(old, new)
        else
          fail(ValueOverwriteError.new(key))
        end
      }
    end

    def accept_visitor(parser)
      parser.visit_keyvalue(self)
    end
    nil

    def visit_value(a_value)
      unless a_value.respond_to?(:accept_visitor)
        return a_value
      end
      a_value.accept_visitor(self)
    end
  end

  module KeyvalueParser
    def value
      TomlRB::Keyvalue.new(capture(:stripped_key).value, capture(:v).value)
    end
  end
end)); (module TomlRB
  class Parser
    attr_reader(:hash)

    def initialize(content, symbolize_keys: false)
      @hash = {}
      @visited_keys = []
      @fully_defined_keys = []
      @current = @hash
      @symbolize_keys = symbolize_keys

      begin
        parsed = TomlRB::Document.parse(content)
        parsed.matches.map(&:value).compact.each { |m|
          m.accept_visitor(self)
        }
      rescue Citrus::ParseError => e
        raise(TomlRB::ParseError.new(e.message))
      end
    end

    def visit_table_array(table_array)
      @fully_defined_keys = []
      table_array_key = table_array.full_key
      @visited_keys.reject! { |k|
        k.start_with?(table_array_key)
      }
      @current = table_array.navigate_keys(@hash, @symbolize_keys)
    end

    def visit_table(table)
      @fully_defined_keys = []
      @current = table.navigate_keys(@hash, @visited_keys, @symbolize_keys)
    end

    def visit_keyvalue(keyvalue)
      keyvalue.assign(@current, @fully_defined_keys, @symbolize_keys)
    end
  end
end); ((((require("date_core"); class Date
  VERSION = "3.3.3"
  nil

  class Infinity < Numeric
    def initialize(d = 1)
      @d = d <=> 0
    end

    def d
      @d
    end
    protected(:d)

    def zero?
      false
    end
    nil
    nil
    nil

    def abs
      self.class.new
    end

    def -@
      self.class.new(-d)
    end

    def +@
      self.class.new(+d)
    end

    def <=>(other)
      case other
      when Infinity
        return d <=> other.d
      when Float::INFINITY
        return d <=> 1
      when -Float::INFINITY
        return d <=> -1
      when Numeric
        return d
      else
        begin
          (l, r) = other.coerce(self)
          return l <=> r
        rescue NoMethodError
        end
      end
      nil
    end

    def coerce(other)
      case other
      when Numeric
        return -d, d
      else
        super
      end
    end

    def to_f
      if @d == 0
        return 0
      end
      if @d > 0
        Float::INFINITY
      else
        -Float::INFINITY
      end
    end
  end
end)); module TomlRB
  class Dumper
    attr_reader(:toml_str)

    def initialize(hash)
      @toml_str = ""
      visit(hash, [])
    end
    nil

    def visit(hash, prefix, extra_brackets = false)
      (simple_pairs, nested_pairs, table_array_pairs) = sort_pairs(hash)
      if prefix.any? && (simple_pairs.any? || hash.empty?)
        print_prefix(prefix, extra_brackets)
      end
      dump_pairs(simple_pairs, nested_pairs, table_array_pairs, prefix)
    end

    def sort_pairs(hash)
      nested_pairs = []
      simple_pairs = []
      table_array_pairs = []
      hash.keys.sort.each { |key|
        val = hash[key]
        element = [key, val]
        if val.is_a?(Hash)
          nested_pairs << element
        else
          if val.is_a?(Array) && val.first.is_a?(Hash)
            table_array_pairs << element
          else
            simple_pairs << element
          end
        end
      }
      [simple_pairs, nested_pairs, table_array_pairs]
    end

    def dump_pairs(simple, nested, table_array, prefix = [])
      dump_simple_pairs(simple)
      dump_nested_pairs(nested, prefix)
      dump_table_array_pairs(table_array, prefix)
    end

    def dump_simple_pairs(simple_pairs)
      simple_pairs.each { |key, val|
        unless bare_key?(key)
          key = quote_key(key)
        end
        @toml_str += <<-HEREDOC
#{key} = #{to_toml(val)}
        HEREDOC
      }
    end

    def dump_nested_pairs(nested_pairs, prefix)
      nested_pairs.each { |key, val|
        unless bare_key?(key)
          key = quote_key(key)
        end
        visit(val, prefix + [key], false)
      }
    end

    def dump_table_array_pairs(table_array_pairs, prefix)
      table_array_pairs.each { |key, val|
        unless bare_key?(key)
          key = quote_key(key)
        end
        aux_prefix = prefix + [key]
        val.each { |child|
          print_prefix(aux_prefix, true)
          args = sort_pairs(child) << aux_prefix
          dump_pairs(*args)
        }
      }
    end

    def print_prefix(prefix, extra_brackets = false)
      new_prefix = prefix.join(".")
      if extra_brackets
        new_prefix = "[" + new_prefix + "]"
      end
      @toml_str += "[" + new_prefix + "]\n"
    end

    def to_toml(obj)
      if obj.is_a?(Time) || obj.is_a?(DateTime)
        obj.strftime("%Y-%m-%dT%H:%M:%SZ")
      else
        if obj.is_a?(Date)
          obj.strftime("%Y-%m-%d")
        else
          if obj.is_a?(Regexp)
            obj.inspect.inspect
          else
            if obj.is_a?(String)
              obj.inspect.gsub(/\\(#[$@{])/, "\\1")
            else
              if obj.is_a?(Array)
                "[" + obj.map(&method(:to_toml)).join(", ") + "]"
              else
                obj.inspect
              end
            end
          end
        end
      end
    end

    def bare_key?(key)
      !!key.to_s.match(/^[a-zA-Z0-9_-]*$/)
    end

    def quote_key(key)
      "\"" + key.gsub("\"", "\\\"") + "\""
    end
  end
end)); File.dirname(File.expand_path("/home/vidarh/src/personal/ruby-term/term/bundle/ruby/3.2.0/gems/toml-rb-2.2.0/lib/toml-rb.rb")).tap { |root|
  Citrus.load("#{root}/toml-rb/grammars/helper.citrus")
  Citrus.load("#{root}/toml-rb/grammars/primitive.citrus")
  Citrus.load("#{root}/toml-rb/grammars/array.citrus")
  Citrus.load("#{root}/toml-rb/grammars/document.citrus")
}; module TomlRB
  def self.parse(content, symbolize_keys: false)
    Parser.new(content, symbolize_keys: symbolize_keys).hash
  end

  def self.load_file(path, symbolize_keys: false)
    TomlRB.parse(File.read(path), symbolize_keys: symbolize_keys)
  end

  def self.dump(hash)
    Dumper.new(hash).toml_str
  end
end))
$> = $stderr
(class WindowAdapter
  def initialize(window, term)
    @window = window
    @term = term
  end

  def char_w
    @window.char_w
  end

  def char_h
    @window.char_h
  end

  def clear
    @window.clear(0, 0, 0, 0)
  end

  def dim(col)
    [col].pack("l").each_byte.map { |b|
      b.ord * 0.4
    }.pack("C*").unpack("l")[0]
  end

  def brighten(col, bg)
    [col].pack("l").each_byte.map { |b|
      (b.ord + 128).clamp(0, 255)
    }.pack("C*").unpack("l")[0]
  end

  def clear_area(x, y, w, h)
    @window.clear(x * char_w, y * char_h, w, h)
  end

  def clear_cells(x, y, w, h)
    clear_area(x, y, w * char_w, h * char_h)
  end

  def clear_line(y, from_x, to_x = nil)
    to_x ||= @term.term_width
    clear_cells(from_x, y, to_x - from_x, 1)
  end

  def insert_lines(y, num, maxy)
    @window.scroll_down(char_h * (num - 1), @term.term_width * char_w, (maxy - num + 1) * char_h, char_h)
  end

  def delete_lines(y, num, maxy)
    @window.scroll_up(char_h * num, @term.term_width * char_w, (maxy - num + 1) * char_h, char_h)
  end

  def draw_flag_lines(flags, x, y, len, fg)
    x *= char_w
    y *= char_h
    w = len * char_w
    if flags.allbits?(OVERLINE)
      @window.draw_line(x, y, w, fg)
    end
    if flags.allbits?(CROSSED_OUT)
      @window.draw_line(x, y + char_h./(2) + 2, w, fg)
    end
    if flags.anybits?(UNDERLINE | DBL_UNDERLINE)
      @window.draw_line(x, y + char_h - 3, w, fg)
      if flags.allbits?(DBL_UNDERLINE)
        @window.draw_line(x, y + char_h - 1, w, fg)
      end
    end
  end

  def draw(x, y, c, fg, bg, flags, lineattrs)
    inverse = flags.allbits?(INVERSE)
    if inverse
      (fg, bg) = [bg, fg]
    end
    if flags.allbits?(FAINT)
      fg = dim(fg)
    end
    if flags.anybits?(BLINK) && @term.blink_state
      fg = if inverse
        brighten(fg, bg)
      else
        dim(fg)
      end
    else
      if flags.anybits?(RAPID_BLINK) && @term.rblink_state
        fg = if inverse
          brighten(fg, bg)
        else
          dim(fg)
        end
      end
    end
    @window.draw(x * char_w, y * char_h, c, fg, bg, lineattrs)
    draw_flag_lines(flags, x, y, c.length, fg)
  end
end)
(class TrackChanges
  def initialize(buffer, adapter)
    @buffer = buffer
    @adapter = adapter
    clear
  end

  def clear
    clear_changes
    @cleared = true
    @buffer.clear
    @adapter.clear
  end

  def clear_changes
    @cleared = false
    @changes = Set.new
    @scroll = []
  end
  nil

  def lineattrs(y)
    @buffer.lineattrs(y)
  end

  def get(x, y)
    @buffer.get(x, y)
  end

  def scroll_start
    @buffer.scroll_start
  end

  def scroll_end
    @buffer.scroll_end
  end

  def blinky
    @buffer.blinky
  end

  def each_character(*args, &block)
    @buffer.each_character(*args, &block)
  end

  def scroll_up
    @scroll << [:up, @buffer.scroll_start, @buffer.scroll_end]
    @buffer.scroll_up
  end

  def delete_lines(y, num, maxy)
    num.times.each { |i|
      @buffer.delete_line(y + i)
    }
    @adapter.delete_lines(y, num, @buffer.scroll_end || maxy)
  end

  def insert_lines(y, num, maxy)
    num.times.each { |i|
      @buffer.insert_line(y + i)
    }
    @adapter.insert_lines(y, num, @buffer.scroll_end || maxy)
  end

  def clear_line(*args)
    @buffer.clear_line(*args)
    @adapter.clear_line(*args)
  end

  def set(x, y, c, fg, bg, mode)
    @changes << [x, y]
    draw_buffered(x, y, [c, fg, bg, mode])
    @buffer.set(x, y, c, fg, bg, mode)
  end
  nil

  def redraw_blink
    b = @buffer.blinky
    if b.empty?
      return nil
    end
    b.each { |x, y|
      redraw(x, y)
    }
    draw_flush
  end

  def redraw(x, y)
    draw_buffered(x, y, @buffer.get(x, y), true)
  end

  def redraw_all
    @buffer.each_character { |*args|
      draw_buffered(*args, true)
    }
  end

  def redraw_with(x, y, fg: nil, bg: nil)
    cell = Array(@buffer.get(x, y)).dup
    cell[0] ||= " "
    if fg
      cell[1] = fg
    end
    if bg
      cell[2] = bg
    end
    draw_buffered(x, y, cell, true)
  end

  def draw_flush
    if @bufx && @buf && @buf[0] && !@buf[0].empty?
      c = @buf[0]
      fg = @buf[1] || PALETTE_BASIC[7]
      bg = @buf[2] || PALETTE_BASIC[0]
      unless c == " " && fg == 0 && bg == 0
        lineattrs = @buffer.lineattrs(@bufy)
        flags = @buf[3].to_i
        @adapter.draw(@bufx, @bufy, c, fg, bg, flags, lineattrs)
      end
    end
    @buf = []
    @bufx = nil
    @bufy = nil
    @last_x = -2
    @last_y = -2
  end
  $saved = 0

  def draw_buffered(x, y, cell, force = false)
    @last_x ||= -255
    @last_y ||= -255
    @buf ||= ["", PALETTE_BASIC[7], PALETTE_BASIC[0], 0]
    cell ||= [" "]
    if @buf[0] && @buf[0].length > 160
      draw_flush
    else
      if @last_y != y || @last_x + 1 != x
        draw_flush
      else
        if (@buf[1] != cell[1]) || (@buf[2] != cell[2]) || (@buf[3] != cell[3])
          draw_flush
        end
      end
    end
    @buf[0] ||= ""
    if force
      match = false
    else
      bcell = Array(@buffer.get(x, y))
      match = (cell[0] == 32 && bcell.empty? && cell[2] == BG) || cell == bcell
    end
    if @buf[0].empty?
      if match
        $saved += 1
        if $saved % 500 == 0
          p($saved)
        end
        return
      end
    else
      if match
        if @buf[0].length > 8
          draw_flush
          return
        end
      end
    end
    c = cell[0]
    @buf[1] ||= cell[1]
    @buf[2] ||= cell[2]
    @buf[3] ||= cell[3]
    @buf[0] << (c || "")
    @bufx ||= x
    @bufy ||= y
    @last_x = x
    @last_y = y
  end
end)
BG = "0"
FG = "7"

class RubyTerm
  SHELL = "/bin/bash"
  CURSOR = 16711935
  TOPMOST = 0
  LEFTMOST = 0
  attr_reader(:term_width, :term_height, :blink_state, :rblink_state)

  def charset
    @g[@gl] || DefaultCharset
  end

  def char_w
    @adapter.char_w
  end

  def char_h
    @adapter.char_h
  end

  def initconfig
    cname = File.expand_path("~/.config/rterm/config.toml")
    if File.exist?(cname)
      @config = TomlRB.load_file(cname, symbolize_keys: true)
    end
    @config ||= {}
  end

  def inspect
    "<RubyTerm #{self.object_id}>"
  end

  def initialize(args)
    initconfig
    pp(:config, @config)
    @window = Window.new(fonts: @config[:fonts])
    @adapter = WindowAdapter.new(@window, self)
    @x = 0
    @y = 0
    @gl = 0
    @g = [DefaultCharset, nil, nil, nil]
    @lnm = true
    @wraparound = true
    @tabs = 40.times.map { |i|
      i * 8
    }
    @origin_mode = false
    @mouse_mode = nil
    @mouse_reporting = nil
    ENV["TERM"] = "rxvt-256color"
    (@master, @wr, @pid) = [*PTY.spawn(SHELL, *args)]
    @term_width = (400 / char_w).to_i
    @term_height = (400 / char_h).to_i
    @buffer = TrackChanges.new(TermBuffer.new, @adapter)
    @bg = BG
    @fg = FG
    @mode = 0
    @cursor = true
  end

  def clear_cursor
    if !@cursor_pos
      return
    end
    @buffer.redraw(*@cursor_pos)
    @buffer.draw_flush
    @cursor_pos = nil
  end

  def draw_cursor
    clear_cursor
    (x, y) = [@x, @y]
    if !@cursor
      return
    end
    if x >= @term_width
      y += 1
    end
    @buffer.redraw_with(x, y, bg: CURSOR)
    @buffer.draw_flush
    @cursor_pos = [x, y]
  end

  def redraw
    @buffer.redraw_all
    draw_cursor
  end

  def each_character(&block)
    @buffer.each_character(&block)
  end

  def resize(w, h)
    @pixelw = w
    @pixelh = h
    w = w / char_w - 1
    h = h / char_h - 1
    if w <= 0 || h <= 0
      return
    end
    (ow, oh) = [@term_width, @term_height]
    (@term_width, @term_height) = [w, h]
    @master.winsize=[h + 1, w]
    @window.clear(0, 0, 0, 0)
    redraw
  end

  def parse_color(codes)
    case c = codes.shift
    when 5
      PALETTE256[codes.shift]
    when 2
      codes.shift << 16 | codes.shift.<<(8) | codes.shift
    else
      BG
    end
  end

  def fg
    if @fg.is_a?(String)
      PALETTE_BASIC[@fg.to_i + (if @mode.allbits?(BOLD)
        8
      else
        0
      end)]
    else
      @fg
    end
  end

  def bg
    if @bg.is_a?(String)
      PALETTE_BASIC[@bg.to_i]
    else
      @bg
    end
  end

  def set_modes(codes)
    while c = codes.shift
      case c
      when 0
        @mode = 0
        @fg = FG
        @bg = BG
      when 1
        @mode |= BOLD
      when 2
        @mode |= FAINT
      when 3
        @mode |= ITALICS
      when 4
        @mode |= UNDERLINE
      when 5
        @mode |= BLINK
      when 6
        @mode |= RAPID_BLINK
      when 7
        @mode |= INVERSE
      when 8
        @mode |= INVISIBLE
      when 9
        @mode |= CROSSED_OUT
      when 21
        @mode |= DBL_UNDERLINE
      when 22
        @mode &= ~BOLD & FAINT.~
      when 23
        @mode &= ~ITALICS
      when 24
        @mode &= ~UNDERLINE & DBL_UNDERLINE.~
      when 25
        @mode &= ~BLINK & RAPID_BLINK.~
      when 27
        @mode &= ~INVERSE
      when 28
        @mode &= ~INVISIBLE
      when 29
        @mode &= ~CROSSED_OUT
      when 30..37
        @fg = (c - 30).to_s
      when 38
        @fg = parse_color(codes)
      when 39
        @fg = FG
      when 40..47
        @bg = (c - 40).to_s
      when 48
        @bg = parse_color(codes)
      when 49
        @bg = BG
      when 53
        @mode |= OVERLINE
      when 55
        @mode &= ~OVERLINE
      else
        return p([:set_modes, c, codes])
      end
    end
  end

  def clear_to_end
    @buffer.clear_line(@y, @x)
  end

  def clear_to_start
    @buffer.clear_line(@y, 0, @x)
  end

  def clear_line(y = nil)
    @buffer.clear_line(y || @y, 0)
  end

  def clear_above
    (0...@y).each { |y|
      clear_line(y)
    }
    clear_to_start
  end

  def clear_below
    clear_to_end
    (@y + 1..@term_height).each { |y|
      clear_line(y)
    }
  end

  def insert_lines(num)
    @buffer.insert_lines(@y, num, @term_height)
  end

  def delete_lines(num)
    @buffer.delete_lines(@y, num, @term_height)
  end

  def decaln
    @buffer.scroll_start=nil
    @buffer.scroll_end=nil
    @term_width.times.each { |x|
      @term_height.times.each { |y|
        @buffer.set(x, y, "E", fg, bg, 0)
      }
    }
    @buffer.draw_flush
  end

  def clear_screen
    @buffer.scroll_start=nil
    @buffer.scroll_end=nil
    @buffer.clear
    @x = 0
    @y = 0
  end

  def handle_dec(s)
    args = s[2..-2].split(/[:;]/).map { |i|
      if i.empty?
        nil
      else
        i.to_i
      end
    }
    case s[-1]
    when "h", "l"
      set = s[-1] == "h"
      args.each { |code|
        case code
        when 3
          @term_width = if set
            132
          else
            80
          end
          clear_screen
        when 6
          @origin_mode = set
        when 7
          @wraparound = set
        when 9
        when 20
          @lnm = set
        when 25
          @cursor = set
          if !set
            clear_cursor
          end
        when 47
          clear_screen
        when 1000
          @mouse_mode = if set
            :vt200
          else
            nil
          end
        when 1001
          @mouse_mode = if set
            :vt200_highlight
          else
            nil
          end
        when 1002
          @mouse_mode = if set
            :btn_event
          else
            nil
          end
        when 1003
          @mouse_mode = if set
            :any_event
          else
            nil
          end
        when 1006
          @mouse_reporting = if set
            :digits
          else
            nil
          end
        end
      }
    end
  end

  def origin
    if @origin_mode
      @buffer.scroll_start || 0
    else
      0
    end
  end

  def bottom
    if @origin_mode
      @buffer.scroll_end || @term_height
    else
      @term_height
    end
  end

  def clampw(i)
    i.clamp(0, @term_width - 1)
  end

  def clamph(i)
    i.clamp(origin, bottom)
  end

  def redraw_line_from(startx)
    clear_cursor
    (startx..@term_width).each { |x|
      @buffer.redraw(x, @y)
    }
    draw_cursor
  end

  def handle_csi(s)
    if s[1] == "?"
      return handle_dec(s)
    end
    args = s[1..-2].split(/[:;]/).map { |i|
      if i.empty?
        nil
      else
        i.to_i
      end
    }
    case s[-1]
    when "@"
      @buffer.insert(@x, @y, args[0] || 1, [32, 0, 0, 0])
      redraw_line_from(@x)
    when "A"
      @y = clamph(@y - args[0].to_i.clamp(1, @term_height))
    when "B"
      @y = clamph(@y + args[0].to_i.clamp(1, @term_height))
    when "C"
      @x = clampw(@x + args[0].to_i.clamp(1, @term_width))
    when "D"
      @x = clampw(@x - args[0].to_i.clamp(1, @term_width))
    when "G"
      @x = clampw((args[0] || 1) - 1)
    when "H"
      @y = (origin + args[0].to_i.clamp(1, 99999)) - 1
      @x = (args[1] || 1) - 1
    when "J"
      case args[0] || 0
      when 0
        clear_below
      when 1
        clear_above
      when 2
        clear_screen
      when 3
        @buffer.clear
      end
    when "K"
      case args[0] || 0
      when 0
        clear_to_end
      when 1
        clear_to_start
      when 2
        clear_line
      else
        p(@esc)
      end
    when "L"
      insert_lines(args[0] || 1)
    when "M"
      delete_lines(args[0] || 1)
    when "P"
      p(@esc)
    when "c"
      @wr.write("\eP!|00000000")
    when "d"
      @y = clamph(origin + (args[0] || 1) - 1)
    when "f"
      @y = clamph(origin + (args[0] || 1) - 1)
      @x = (args[1] || 1) - 1
    when "g"
      case args[0].to_i
      when 0
        @tabs.delete(@x)
      when 3
        @tabs = []
      end
    when "m"
      set_modes(if args.empty?
        [0]
      else
        args
      end)
    when "n"
      case args[0]
      when 6
        @wr.write("\e[#{@y + 1};#{@x + 1}R")
      else
        p(@esc)
      end
    when "r"
      p([:SET_SCROLL, args])
      @buffer.scroll_start=(args[0] || 1) - 1
      @buffer.scroll_end=(args[1] || @term_height) - 1
    else
      p(@esc)
    end
  end

  def handle_escape(ch)
    @esc.put(ch)
    if @esc.complete?
      s = @esc.str
      if s[0] == "["
        handle_csi(s)
      else
        case s
        when "D"
          @y += 1
        when "E"
          @y += 1
          @x = 0
        when "H"
          @tabs = (@tabs << @x).sort.uniq
        when "M"
          @y -= 1
          if @y < 0
            @y = 0
            insert_lines(1)
          end
        when "#3"
          @buffer.set_lineattrs(@y, :dbl_upper)
        when "#4"
          @buffer.set_lineattrs(@y, :dbl_lower)
        when "#5"
          @buffer.set_lineattrs(@y, 0)
        when "#6"
          @buffer.set_lineattrs(@y, :dbl_single)
        when "#8"
          decaln
        when "(B"
          @g[0] = DefaultCharset
        when ")B"
          @g[1] = DefaultCharset
        when "(0"
          @g[0] = GraphicsCharset
        when ")0"
          @g[1] = GraphicsCharset
        when "7"
          @saved = [@x, @y, @gl, @gr, @g.dup]
        when "8"
          (@x, @y, @gl, @gr, @g) = [*Array(@saved)]
        else
          p(@esc)
        end
      end
      @esc = nil
    end
  end

  def wrap_if_needed
    if @x >= @term_width
      if @wraparound
        @x = 0
        @y += 1
      else
        @x = @term_width - 1
      end
    else
      if @x < 0
        if @wraparound
          @y -= 1
          @x = @term_width - 1
        else
          @x = 0
        end
      end
    end
  end

  def scroll_if_needed
    while @y > (@buffer.scroll_end || @term_height)
      @buffer.draw_flush
      @buffer.scroll_up
      @window.scroll_up(char_h * ((@buffer.scroll_start || 0) + 1), @term_width * char_w, ((@buffer.scroll_end || @term_height) - @buffer.scroll_start.to_i) * char_h, char_h)
      @y -= 1
    end
  end

  def handle_control(ch)
    case ch
    when 1, 2
    when 7
      p(:bell)
    when 8
      if @x >= @term_width
        @x -= 2
      else
        if @x > 0
          @x -= 1
        end
      end
    when 9
      if i = @tabs.index { |t|
        t > @x
      }
        t = @tabs[i]
        if t > @x
          @x = clampw(t)
        end
      end
    when 10, 11
      if @lnm
        @x = 0
      end
      @y = clamph(@y) + 1
      scroll_if_needed
    when 12
      @x = 0
      @y = 0
    when 13
      @x = 0
    when 14
      @gl = 1
    when 15
      @gl = 0
    when 16..26
    when 27
      @esc = EscapeParser.new
    when 28..31
    end
  end

  def putchar(ch)
    (ox, oy) = [@x, @y]
    if ch < 32
      handle_control(ch)
    else
      if @esc
        handle_escape(ch)
      else
        wrap_if_needed
        scroll_if_needed
        if ch == 127
          @x = clampw(@x - 1)
          (ox, oy) = [@x, @y]
          c = " "
        else
          (ox, oy) = [@x, @y]
          @y = clamph(@y)
          @x += 1
          c = charset[ch]
        end
        @buffer.set(ox, oy, c, fg, bg, @mode)
        scroll_if_needed
      end
    end
  end

  def write(str)
    p([:write, str])
    clear_cursor
    str.each_char { |ch|
      c = ch.ord rescue 32
      putchar(c)
    }
    draw_cursor
  end

  def adjust_fontsize(delta)
    @window.adjust_fontsize(delta)
    resize(@pixelw, @pixelh)
  end

  def key(event)
    p(event)
    (ks, str) = lookup_string(@window.dpy, event)
    case ks
    when :"ctrl_+"
      adjust_fontsize(1.0)
    when :"ctrl_-"
      adjust_fontsize(-1.0)
    when :XK_Insert
      @wr.write(`xsel -p`)
      return
    when "C"
      if str == "\u0003"
        system("xsel -o -p | xsel -i -b")
        return
      end
    when "V"
      if str == "\u0016"
        @wr.write(`xsel -b`)
        return
      end
    when :XK_Menu
      puts("FIXME: deskmenu")
    end
    @wr.write(keysym_to_vt102(ks) || str)
  end

  def blink
    t = Time.now
    doblink = false
    if ((t - @lastblink) * 10).to_i > 6
      @lastblink = t
      @blink_state = !@blink_state
      doblink = true
    end
    if ((t - @lastrblink) * 10).to_i >= 2
      @lastrblink = t
      @rblink_state = !@rblink_state
      doblink = true
    end
    if doblink
      @buffer.redraw_blink
    end
  end

  def redraw_positions(positions)
    positions.each { |pos|
      @buffer.redraw(*pos)
    }
  end

  def render_selection
    olddamage = @selection_damage || Set.new
    @selection_damage = Set.new
    @buffer.each_character_between(@select_startpos[0]..@select_startpos[1], @select_endpos[0]..@select_endpos[1]) { |x, y, cell|
      @selection_damage << [x, y]
      @buffer.redraw_with(x, y, fg: 16777215, bg: 16711935)
    }
    redraw_positions(olddamage - @selection_damage)
    @buffer.draw_flush
  end

  def get_selection
    startpos = @select_startpos
    endpos = @select_endpos
    str = ""
    ypos = nil
    @buffer.each_character_between(startpos[0]..startpos[1], endpos[0]..endpos[1]) { |x, y, cell|
      if ypos && y != ypos
        str += "\n"
      end
      ypos = y
      str << cell[0].chr rescue ""
    }
    str
  end

  def clear_selection_if_set
    if !@select_startpos
      return
    end
    redraw_positions(@selection_damage)
    @select_startpos = nil
    redraw
  end

  def handle_mouse(pkt)
    p(pkt)
    p([@mouse_mode, @mouse_reporting])
    @mouse_buttons = button = if pkt.detail > 0
      pkt.detail
    else
      @mouse_buttons
    end
    release = pkt.is_a?(X11::Form::ButtonRelease)
    p([pkt.class, pkt.is_a?(X11::Form::ButtonRelease)])
    x = pkt.event_x / char_w
    y = pkt.event_y / char_h
    case @mouse_mode
    when nil
      if @released
        clear_selection_if_set
        @released = false
      end
      @select_startpos ||= [x, y]
      if [x, y] != @select_endpos
        @select_endpos = [x, y]
        render_selection
      end
      p(:HERE, release)
      if release
        @released = true
        if @select_startpos != @select_endpos
          sel = get_selection
          io = IO.popen("xsel -i", "a+")
          io.write(sel)
          io.close
        else
          clear_selection_if_set
        end
      end
    when :vt200, :btn_event
      if release && button >= 4
        return
      end
      event = [0, 1, 2, 64, 65][button - 1]
      if pkt.is_a?(X11::Form::MotionNotify)
        event += 32
      end
      if @mouse_reporting == :digits
        p("\e[<#{event};#{x + 1};#{y + 1}#{if release
  "m"
else
  "M"
end}")
        @wr.write("\e[<#{event};#{x + 1};#{y + 1}#{if release
  "m"
else
  "M"
end}")
      else
        raise("FIXME; untested and likely broken")
        @wr.write("\e[M#{event.to_i.chr}#{x.chr}#{y.chr}")
      end
    end
  end

  def process(pkt)
    case pkt
    when X11::Form::ButtonPress, X11::Form::MotionNotify, X11::Form::ButtonRelease
      handle_mouse(pkt)
    when X11::Form::KeyPress
      key(pkt)
    when X11::Form::KeyRelease, X11::Form::NoExposure, X11::Form::ConfigureNotify
    when X11::Form::Expose
      p([:EXPOSE, pkt])
      resize(pkt.width, pkt.height)
    else
      p(pkt)
    end
  end

  def run
    puts("RUNNING")
    @lastblink ||= Time.now
    @lastrblink ||= Time.now
    loop {
      max = 10
      dpy = @window.dpy
      while dpy.peek_packet && max > 0
        process(dpy.next_packet)
        max -= 1
      end
      (rs, ws) = IO.select([@master, dpy.socket], [], [], 0.2)
      blink
      Array(rs).each { |s|
        case s.fileno
        when @master.fileno
          begin
            write(@master.read_nonblock(16384).force_encoding("UTF-8"))
          rescue Errno::EIO
            exit(Process.wait(@pid))
          end
        else
          process(dpy.next_packet)
        end
      }
    }
  end
end
RubyTerm.new(ARGV).run
