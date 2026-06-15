# frozen_string_literal: true

# rubyterm - a pure-Ruby X11 terminal emulator and reusable terminal engine.
#
# Requiring "rubyterm" loads the whole stack:
#
#   * the terminal *engine* - escape interpreter, virtual buffer, damage
#     tracking and the swappable backends (Term, TrackChanges, TermBuffer,
#     AnsiBackend, BitmapWindow); usable headlessly / embedded in a TUI; and
#   * the X11 *front end* - the Window backend, pty Controller, keymap and
#     the RubyTerm application class that bin/rubyterm runs.
#
# The engine carries no X11 dependency itself, but this entry point pulls in
# the X11/skrift libraries so a single `require "rubyterm"` gives you a
# runnable terminal. (They are pure Ruby, so requiring them needs no running
# X server - only instantiating Window does.)

require "pty"
require "io/console"
require "set"

require "X11"
require "skrift"
require "skrift/x11"
require "toml-rb"

require_relative "rubyterm/version"

# Engine
require_relative "palette"
require_relative "charsets"
require_relative "escapeparser"
require_relative "utf8decoder"
require_relative "termbuffer"
require_relative "trackchanges"
require_relative "term"

# Backends
require_relative "ansibackend"
require_relative "bitmapwindow"

# X11 front end
require_relative "keymap"
require_relative "window"
require_relative "windowadapter"
require_relative "controller"
require_relative "rubyterm/app"
