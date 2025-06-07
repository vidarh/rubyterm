#require 'rubygems'
require 'skrift'
require 'X11'
require 'bundler'
require 'chunky_png'
require 'pp'

Bundler.setup(:default, :development)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'skrift/x11'

$dpy = dpy = display = X11::Display.new
screen = dpy.screens.first

# Transparency: Check
# https://stackoverflow.com/questions/13395179/empty-or-transparent-window-with-xlib-showing-border-lines-only/13397150#13397150

# FIXME: Hack; see XFindVisualMatch
visual = 123

cmap = $dpy.create_colormap(0, screen.root, visual)

wid = display.new_id
$dpy.create_window(
  32, 
  wid, screen.root,
  0, 0, # x,y
  1000, 600, # w,h
  0,
  X11::Form::InputOutput,
  visual, #X11::Form::CopyFromParent -- Must be provided if e.g. depth is different than root.
  X11::Form::CWBackPixel | X11::Form::CWBorderPixel |
    X11::Form::CWEventMask | X11::Form::CWColorMap,
  [0x00000000, # ARGB background
   0x0, # Border pixel; Necessary when depth != screen.root_depth
   X11::Form::SubstructureNotifyMask |
   X11::Form::StructureNotifyMask    | ## Move
   X11::Form::ExposureMask           |
   X11::Form::KeyPressMask           |
   X11::Form::ButtonPressMask,
   cmap # Colormap. Necessary when depth != screen.root_depth
  ]
)

dpy.map_window(wid) # Window won't be visible until this

# A "picture" object for us to draw in the window with.
fmt  = dpy.render_find_visual_format(visual)
$pic = dpy.render_create_picture(wid, fmt)

# The easy way
#$fgpic = dpy.render_create_solid_fill(0xffff,0xffff,0,0)


$gc  = dpy.create_gc(wid, foreground: 0xffff0000)

puts "Main loop"

$f = Font.load("resources/FiraGO-Regular_extended_with_NotoSansEgyptianHieroglyphs-Regular.ttf")

$skrift = Skrift::X11::Glyphs.new($dpy, $f, x_scale: 40, y_scale: 40)

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
    #puts pkt.inspect[0..200]
    #raise "Error" if pkt.is_a?(X11::Form::Error)
    redraw(display, wid, $gc) if pkt.is_a?(X11::Form::Expose)

    if pkt.is_a?(X11::Form::KeyPress)
#      lookup_keysym(dpy,pkt)
    end
  end
end
