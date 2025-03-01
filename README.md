
# Ruby Term

This is a *very early*, *very rough* Ruby terminal application that uses
a pure-Ruby X11 client to talk to an X server. The entire terminal is
pure Ruby.

It will change a lot when I get time...

It will currently fail to run most full-screen applications, as only a very
small subset of escape codes are handled properly (enough to run my own
personal editor, barely). Localisation is a mess. Font-handling is near
non-existent. Keymap handling is very limited.

In general: **You probably don't want to use this.**

If you insist on playing with it anyway, I do welcome thoughtful modifications,
but I have very specific ideas for the direction I want to take it, so
either talk to me first (e-mail: vidar@hokstad.com) or fork it. Or both. I
will not guarantee I'll merge in changes unless we've spoken about it first.

Some thoughts on where I want to take this:

* Decouple the interpretation of escape sequences and updates of the terminal
  buffer entirely from both the pty handling and the X11 interface, and make
  it a separate gem.
* Allow Ruby applications to instantiate a "terminal window" with an IO object
  as the interface without actually running in a terminal (I want to use it to
  run my own editor in), while being able to do **basic** other X stuff.
* Make the terminal itself complete enough to run most Linux/Unix command line
  tools - so that means a fairly complete unicode enabled xterm/vt100 terminal.
* KEEP THE CODE SMALL, but understandable. You might spot hints at golfing in
  the current code. I will value terseness, but only as long as it helps
  preserve readability.

## Done
* Moved to a pure-Ruby direct implementation of a small subset of the
  X Protocol.

## To test it:

`bundle install`, then run `ruby termtest.rb` and with some luck you'll
get a terminal window.

## Resources

https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Definitions
https://www.xfree86.org/current/ctlseqs.html
