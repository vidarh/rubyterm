#require 'rubygems'
require 'skrift'
require 'X11'
require 'bundler'
require 'chunky_png'
require 'pp'

Bundler.setup(:default, :development)

#$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
#$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'skrift/x11'

dpy = display = X11::Display.new
screen = dpy.screens.first
visual = dpy.find_visual(0, 32).visual_id
#cmap   = dpy.create_colormap(0, screen.root, visual)

p visual
#p cmap

wid = dpy.create_window(
  0, 0,      # x,y
  1000, 600, # w,h
  visual: visual,
  values: {
    X11::Form::CWBackPixel   => 0, # ARGB background
    X11::Form::CWBorderPixel => 0, # Needed in case window depth != screen.root_depth
    X11::Form::CWEventMask   =>
      (X11::Form::SubstructureNotifyMask |
       X11::Form::StructureNotifyMask    |
       X11::Form::ExposureMask           |
       X11::Form::KeyPressMask           |
       X11::Form::ButtonPressMask)#,
#    X11::Form::CWColorMap    => cmap # Needed for same reason as borderpixel
  }
)
p wid

dpy.map_window(wid) # Window won't be visible until this

# A "picture" object for us to draw in the window with.
fmt  = dpy.render_find_visual_format(visual)
p fmt
$pic = dpy.render_create_picture(wid, fmt)

gc  = dpy.create_gc(wid, foreground: 0xffff0000)

f = Font.load("resources/FiraGO-Regular_extended_with_NotoSansEgyptianHieroglyphs-Regular.ttf")

$skrift = Skrift::X11::Glyphs.new(dpy, f, x_scale: 40, y_scale: 40)

def redraw(dpy, wid, gc)
  dpy.poly_fill_rectangle(wid, gc, [X11::Form::Rectangle.new(20,45, 400, 400)])
  $skrift.render_str($pic, 0xffffff, 50,90, 'Pure Ruby w/Skrift!')
  $skrift.render_str($pic, 0xffffff, 50,140, "And unicode:")
  $skrift.render_str($pic, 0xff00ff, 50,200, "Μπορώ να φάω σπασμένα γυαλιά χωρίς να πάθω τίποτα.")
  $skrift.render_str($pic, 0x00ffff, 50,250, "Я можу їсти шкло, й воно мені не пошкодить.")
end

loop do
  pkt = display.next_packet
  if pkt
    puts pkt.inspect[0..200]
    #raise "Error" if pkt.is_a?(X11::Form::Error)
    redraw(display, wid, gc) if pkt.is_a?(X11::Form::Expose)

    if pkt.is_a?(X11::Form::KeyPress)
#      lookup_keysym(dpy,pkt)
    end
  end
end
