# frozen_string_literal: true

require_relative "lib/rubyterm/version"

Gem::Specification.new do |spec|
  spec.name        = "rubyterm"
  spec.version     = RubyTerm::VERSION
  spec.authors     = ["Vidar Hokstad"]
  spec.email       = ["vidar@hokstad.com"]

  spec.summary     = "A pure-Ruby X11 terminal emulator and reusable terminal engine."
  spec.description = <<~DESC
    rubyterm is a terminal emulator written entirely in Ruby. It cleanly
    separates a virtual screen buffer, an escape-sequence interpreter,
    damage-driven rendering, and swappable backends (X11, an ANSI/escape
    backend, and a headless bitmap rasteriser), so the terminal engine can be
    embedded in a Ruby application as well as run as a standalone X11
    terminal via the `rubyterm` executable.
  DESC

  spec.homepage = "https://github.com/vidarh/rubyterm"
  spec.metadata = {
    "homepage_uri"    => spec.homepage,
    "source_code_uri" => spec.homepage,
  }

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "bin/*", "README.md", "example-config.toml"]
  end
  spec.bindir        = "bin"
  spec.executables   = ["rubyterm"]
  spec.require_paths = ["lib"]

  # Runtime dependencies. skrift, its X11 adapter and the colour-emoji plugin
  # live in the skrift monorepo; until they're on RubyGems the Gemfile sources
  # them from git (skrift-boxdrawing comes in transitively via skrift-x11).
  spec.add_dependency "pure-x11", ">= 0.0.15"
  spec.add_dependency "skrift",       ">= 0.4.0"
  spec.add_dependency "skrift-x11",   ">= 0.3.0"
  spec.add_dependency "skrift-color", ">= 0.1.0"
  spec.add_dependency "toml-rb"
end
