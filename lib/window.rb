
# Encapsulate the X backend and
# operations on the window

require 'skrift'
require 'skrift/x11'
#require 'pry'

class Window
  attr_reader :dpy, :wid, :scrollback_count # FIXME
  attr_accessor :width, :height
  
  # Get scrollback status
  def scrollback_mode
    @scrollback_count > 0
  end
  
  # Set buffer reference to access scrollback size
  def set_buffer(buffer)
    @buffer = buffer
  end
  
  # Get scrollback buffer size
  def scrollback_buffer_size
    return 0 unless @buffer
    @buffer.scrollback_size
  end
  
  # Increase scrollback counter
  def scrollback_page_up
    # Get current scrollback buffer size
    max_scrollback = scrollback_buffer_size
    return if max_scrollback == 0
    
    # Store previous count for calculating how many new lines to clear
    previous_count = @scrollback_count
    
    # Limit scrollback count to available lines
    @scrollback_count += 10
    if @scrollback_count > max_scrollback
      @scrollback_count = max_scrollback
    end
    
    # Calculate how many new lines we've scrolled and clear them
    new_lines = @scrollback_count - previous_count
    if new_lines > 0
      # Clear the area where new scrollback lines will appear
      clear(0, 0, @width, new_lines * char_h)
    end
    
    draw_scrollback_indicator if @scrollback_count <= 10
  end
  
  # Decrease scrollback counter
  def scrollback_page_down
    return false if @scrollback_count <= 0
    
    # Remember previous count
    previous_count = @scrollback_count
    
    @scrollback_count -= 10
    if @scrollback_count <= 0
      # Exiting scrollback mode
      @scrollback_count = 0
      @dirty = true
      
      # Clear entire scrollback area that was showing
      clear(0, 0, @width, previous_count * char_h)
      return true
    else
      # Clear area that was occupied by lines no longer in scrollback
      lines_removed = previous_count - @scrollback_count
      if lines_removed > 0
        clear(0, 0, @width, lines_removed * char_h)
      end
    end
    false
  end

  def initialize(**opts)
    @scrollback_count = 0
    
    @dpy = X11::Display.new
    @screen = @dpy.screens.first

    @alpha  = 0x80 << 24
    @opaque = 0xff << 24

    eventmask = X11::Form::SubstructureNotifyMask |
          X11::Form::ButtonReleaseMask      |
          X11::Form::Button1MotionMask      |
          X11::Form::ExposureMask           |
          X11::Form::KeyPressMask           |
          X11::Form::ButtonPressMask

    @visual = @dpy.find_visual(0, 32).visual_id

    @width, @height = 1000, 600

    @wid = @dpy.create_window(
      0, 0, @width, @height,
      visual: @visual,
      values: {
        X11::Form::CWBackPixel   => 0x00 | @alpha, # ARGB background; transparency
        X11::Form::CWBorderPixel => 0,
        X11::Form::CWEventMask   => eventmask,
      }
    )

    #@gc2 = @dpy.create_gc(@wid, foreground: 0xffffff, background: 0x80000000)

    # Create pixmap buffer with enough space for the window
    create_buffer

    #@buf = @wid
    
    @scale = opts[:fontsize] || 16
    @fontset = opts[:fonts]
    setup_fonts

    @dirty = false
  end

  def map_window = @dpy.map_window(@wid)

  def dirty! = (@dirty = true)
    
  # Create a buffer to back the terminal window
  def create_buffer
    # Free the old resources if they exist
    if defined?(@pic) && @pic
      @dpy.render_free_picture(@pic)
      @pic = nil
    end
    
    if defined?(@buf) && @buf
      @dpy.free_pixmap(@buf)
      @buf = nil
    end
    
    # Create new buffer with dimensions matching the window
    # Add extra space for possible future window growth
    buffer_width = [@width * 2, 1920].max
    buffer_height = [@height * 2, 1080].max
    
    @buf = @dpy.create_pixmap(32, @wid, buffer_width, buffer_height)
    @buf_width = buffer_width
    @buf_height = buffer_height
    
    # Clear the entire buffer
    clear(0, 0, buffer_width, buffer_height)
    
    # Create the picture
    fmt = @dpy.render_find_visual_format(@visual)
    @pic = @dpy.render_create_picture(@buf, fmt)
  end

  def on_resize(w,h)
    ow,oh=@width,@height
    @width, @height = w,h
    
    # If the window dimensions exceed the buffer size, recreate the buffer
    if w > @buf_width || h > @buf_height
      # Free old resources and create new buffer
      create_buffer
      
      # Signal that a full redraw is needed
      @dirty = true
    else
      # Clear newly visible areas
      clear(ow, 0, w-ow, [oh,h].min) if w > ow
      clear(0, oh, w, h-oh) if h > oh
    end

    copy_buffer
  end

  def setup_fonts
    @skr = Skrift::X11::Glyphs.new(@dpy, fontset: @fontset, x_scale: @scale, y_scale: @scale, fixed: true)
    # FIXME: Maybe instantiate these as needed.
    @skr_dblheight = Skrift::X11::Glyphs.new(@dpy, fontset: @fontset, x_scale: @scale*2, y_scale: @scale*2, fixed: true)
    @skr_dblwidth  = Skrift::X11::Glyphs.new(@dpy, fontset: @fontset, x_scale: @scale*2, y_scale: @scale, fixed: true)
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
    return @char_h if @char_h
    lm = @skr.lm
    @char_h = (lm.ascender - lm.descender + lm.line_gap).floor
    @skr.maxheight = @char_h + 1
  end

  def fillrect(x,y,w,h,fg)
    # FIXME: Consider if I want this opaque (as gc_for_col does currently) or
    # not, or maybe *less* transparent but not fully opaque
    @dpy.poly_fill_rectangle(@buf, gc_for_col(fg,0x0), [x, y, w, h])
    @dirty = true
  end

  def clear(x,y,w,h)
    # gc_for_col makes the foreground opaque
    @cleargc ||= @dpy.create_gc(@buf, foreground: 0x0|@alpha, background: 0)
    @dpy.poly_fill_rectangle(@buf, @cleargc, [x, y, w, h])
    @dirty = true
  end

  def gc_for_col(fg,bg)
    @gcs ||= {}
    key = "#{fg},#{bg}"
    return @gcs[key] if @gcs[key]
    bg |= @alpha
    fg |= @opaque
    gc = @dpy.create_gc(@buf, foreground: fg, background: bg)
    @gcs[key]=gc
  end

  # FIXME: Line draw, not rect
  def draw_line(x,y,w,fg) = fillrect(x,y,w,1,fg)
  
  def draw(x,y, c, fg, bg, lineattrs)
    case lineattrs
    when :dbl_upper
      # FIXME: Clipping
      fillrect(x,y,c.length*char_w*2,char_h*2,bg)
      @skr_dblheight.render_str(@pic, fg, x, y, c)
    when :dbl_lower
      # FIXME: Clipping
      fillrect(x,y,c.length*char_w*2,char_h*2,bg)
      @skr_dblheight.render_str(@pic, fg, x, y-char_h, c)
    when :dbl_single
      fillrect(x,y,c.length*char_w*2,char_h,bg)
      @skr_dblwidth.render_str(@pic, fg, x, y, c)
    else
      fillrect(x,y,c.length*char_w,char_h,bg)
      c.rstrip!
      @skr.render_str(@pic,fg, x, y, c)
    end
    return
    #DEBUG
    #p c
    c.each_char do |_|
      draw_line(x,y,char_w, 0x2f0000)
      draw_line(x,y+char_h,char_w, 0x002f00)
      fillrect(x,y,1, char_h, 0x00002f)
      x+=char_w
    end
    @dirty = true
  end

  def draw_scrollback_indicator
    if @scrollback_count > 0
      # First clear the top line to avoid overlapping text
      clear(0, 0, @width, char_h)
      
      indicator = "---scrollback---"
      x = (@width - indicator.length * char_w) / 2
      @skr.render_str(@pic, 0xff0000, x, 0, indicator)
      @dirty = true
    end
  end

  def copy_buffer
    @dirty = false
    @flushgc ||= @dpy.create_gc(@buf, foreground: @alpha, background: @alpha,
      graphics_exposures: false
    )
    @dpy.copy_area(@buf, @wid, @flushgc, 0, 0, 0,0,@width, @height)
    
    # Draw scrollback indicator after copying buffer if in scrollback mode
    draw_scrollback_indicator if @scrollback_count > 0
  end
  
  def flush
    if @dirty
      # FIXME: Keep track of dirty region
      @dirty = false
      p :flush
      copy_buffer
    end
  end
  
  def scroll_up(srcy, w, h, step)
    @dpy.copy_area(@buf,@buf,gc_for_col(0xffffff,0), 0, srcy, 0, srcy-step, w, h)
    @dirty = true

    if @debug
      $step||= 16
      fillrect(0,srcy+h-step, w, step, $step)
      $step += 16
    else
      # Use the full window width to ensure we clear the entire line width,
      # not just the content width that was passed in
      clear(0, srcy+h-step, @width, step+1)
    end
    
    # Redraw the scrollback indicator if needed
    draw_scrollback_indicator if @scrollback_count > 0
  end

  def scroll_down(srcy, w, h, step)
#    if srcy+h > 
    @dpy.copy_area(@buf,@buf,gc_for_col(0xffffff,0), 0, srcy, 0, srcy+step, w, h)
    @dirty = true
    if @debug
      $step||= 16
      fillrect(0,srcy, w, step, $step)
      $step += 16
    else
      clear(0,srcy, w, step)
    end
    
    # Redraw the scrollback indicator if needed
    draw_scrollback_indicator if @scrollback_count > 0
  end
end
