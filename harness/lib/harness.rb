# Loads the terminal core headlessly (no X11, no pty, no fonts) and
# the harness components. This is the entry point for everything under
# harness/ *except* live.rb, which instead loads the full terminal via
# termtest.rb and injects on top of it.

module Harness
  ROOT = File.expand_path("../..", __dir__)
end

# BG/FG are defined by termtest.rb in the live terminal; the core
# classes reference them, so provide them when running headless.
BG = "0" unless defined?(BG)
FG = "7" unless defined?(FG)

require File.join(Harness::ROOT, 'lib/palette')
require File.join(Harness::ROOT, 'lib/charsets')
require File.join(Harness::ROOT, 'lib/escapeparser')
require File.join(Harness::ROOT, 'lib/utf8decoder')
require File.join(Harness::ROOT, 'lib/termbuffer')
require File.join(Harness::ROOT, 'lib/trackchanges')
require File.join(Harness::ROOT, 'lib/windowadapter')
require File.join(Harness::ROOT, 'lib/term')

require_relative 'patches'
require_relative 'virtualwindow'
require_relative 'statedump'
require_relative 'session'
require_relative 'tokenizer'
require_relative 'differ'
require_relative 'oracle_tmux'
require_relative 'checks'
require_relative 'ddmin'
require_relative 'minimizer'
require_relative 'sweep'
require_relative 'replay'
require_relative 'hunt'
require_relative 'autohunt'
