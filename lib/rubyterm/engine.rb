# frozen_string_literal: true

# rubyterm engine — the reusable terminal core WITHOUT the X11 front end.
#
# Loads the escape interpreter (Term), the screen buffer (TermBuffer), the
# damage tracker (TrackChanges), the escape/UTF-8 parsers, and the ANSI
# backend (AnsiBackend). None of these depend on X11 or skrift, so a TUI
# application (e.g. an editor) can drive the buffer and emit minimal escape
# sequences without being an X client.
#
# `require "rubyterm"` loads this and then adds the X11 front end on top.

require "set"

require_relative "version"
require_relative "../palette"      # PALETTE_BASIC, PALETTE256, FG, BG
require_relative "../charsets"
require_relative "../escapeparser"
require_relative "../utf8decoder"
require_relative "../termbuffer"
require_relative "../trackchanges"
require_relative "../term"
require_relative "../ansibackend"
