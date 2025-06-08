

# #Design change:
#
# Terminal writes to the buffer.
# Buffer batches up updates to an output adapter (the window, but could be a terminal...)
#
# But for now, the now stupidly misnamed TrackChanges class just bifurcates buffer changes
# and passes them to both the buffer *and* the screen, and "nothing" should talk to
# the window directly. Once all window updates are moved to TrackChanges/WindowAdapter
# We want to make it smarter.
#
class WindowAdapter
  def initialize window, term
    @window = window
    @term = term
  end

  def char_w = @window.char_w
  def char_h = @window.char_h
  def clear  = @window.clear(0,0,@window.width,@window.height)

  def dim(col) #FIXME
    [col].pack("l").each_byte.map{|b| b.ord*0.4 }.pack("C*").unpack("l")[0]
  end

  def brighten(col, bg)
    # FIXME. Should bring it towards bg
    [col].pack("l").each_byte.map{|b| (b.ord+128).clamp(0,255) }.pack("C*").unpack("l")[0]
  end
  
  def clear_area(x,y,w,h)  = @window.clear(x*char_w,y*char_h,w,h)
  def clear_cells(x,y,w,h) = clear_area(x,y, w * char_w, h * char_h)

  def clear_line y, from_x, to_x = nil
    to_x ||= @term.term_width
    clear_cells(from_x, y, to_x-from_x, 1)
  end

  def insert_lines(y, num, maxy)
    @window.scroll_down(char_h*(num-1),
      @term.term_width * char_w,
      (maxy-num+1)*char_h,
      char_h*num)
  end

  def delete_lines(y, num, maxy)
    @window.scroll_up(char_h*(y+num+1), @term.term_width * char_w,
      (maxy-num-y)*char_h, char_h*(num-1))
  end


  # # Migrating draw_flush

  def draw_flag_lines(flags, x,y, len, fg)
    x *= char_w
    y *= char_h
    w = len * char_w
    if flags.allbits?(OVERLINE)
      @window.draw_line(x,y,w,fg)
    end
    if flags.allbits?(CROSSED_OUT)
      @window.draw_line(x,y+char_h/2+2, w, fg)
    end
    if flags.anybits?(UNDERLINE | DBL_UNDERLINE)
      @window.draw_line(x,y+char_h-3, w, fg)
      if flags.allbits?(DBL_UNDERLINE)
        @window.draw_line(x,y+char_h-1, w, fg)
      end
    end
  end

  def draw(x,y,c,fg,bg,flags,lineattrs)
    inverse = flags.allbits?(INVERSE)
    if inverse
      fg,bg=bg,fg
    end

    if flags.allbits?(FAINT)
      fg = dim(fg)
    end

    if flags.anybits?(BLINK) && @term.blink_state
      fg = inverse ? brighten(fg,bg) : dim(fg)
    elsif flags.anybits?(RAPID_BLINK) && @term.rblink_state
      fg = inverse ? brighten(fg,bg) : dim(fg)
    end

    if x.nil?
      # @BUG
      STDERR.puts "\e[35m@BUG\[0m: x.nil? @windowadapter#draw"
      return
    end
    
    @window.draw(x*char_w, y*char_h, c, fg, bg, lineattrs)
    # FIXME: Take into account lineattrs
    draw_flag_lines(flags, x, y, c.length, fg)
  end
  
  # Force a complete redraw of the window contents
  def redraw_all
    # First clear the entire window
    @window.clear(0, 0, @window.width, @window.height)
    
    # Force the window to flush and update its display
    @window.dirty!
    @window.flush
  end


  def scroll_up(scroll_start, scroll_end)
    @window.scroll_up(
      char_h*((scroll_start||0)+1),
      @window.width,
      (scroll_end-scroll_start)*char_h,
      char_h
    )
  end
end
