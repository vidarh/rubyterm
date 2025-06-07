# -*- encoding: utf-8 -*-
# stub: skrift-x11 0.2.1 ruby lib

Gem::Specification.new do |s|
  s.name = "skrift-x11".freeze
  s.version = "0.2.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Vidar Hokstad".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-11-12"
  s.email = ["vidar@hokstad.com".freeze]
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0".freeze)
  s.rubygems_version = "3.4.10".freeze
  s.summary = "Helpers to use the pure-Ruvy TrueType engine Skrift with pure Pure-X11 X bindings".freeze

  s.installed_by_version = "3.4.10" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<skrift>.freeze, [">= 0"])
  s.add_runtime_dependency(%q<pure-x11>.freeze, [">= 0"])
end
