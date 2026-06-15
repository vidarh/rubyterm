# frozen_string_literal: true

# rubyterm - a pure-Ruby X11 terminal emulator and reusable terminal engine.
#
# Requiring "rubyterm" loads the whole stack:
#
#   * the terminal *engine* - escape interpreter, virtual buffer, damage
#     tracking and the ANSI backend (Term, TrackChanges, TermBuffer,
#     AnsiBackend); usable headlessly / embedded in a TUI. This is
#     "rubyterm/engine" and carries NO X11/skrift dependency; and
#   * the X11 *front end* - the Window/BitmapWindow backends, pty Controller,
#     keymap and the RubyTerm application class that bin/rubyterm runs.
#
# A TUI application that only needs the core can `require "rubyterm/engine"`
# instead and avoid pulling in X11/skrift.

require_relative "rubyterm/engine"

# X11 front end and its dependencies (pure Ruby, so requiring them needs no
# running X server - only instantiating Window does).
require "pty"
require "io/console"
require "X11"
require "skrift"
require "skrift/x11"
require "toml-rb"

require_relative "bitmapwindow"    # skrift glyph -> bitmap backend
require_relative "keymap"
require_relative "window"
require_relative "windowadapter"
require_relative "controller"
require_relative "rubyterm/app"
