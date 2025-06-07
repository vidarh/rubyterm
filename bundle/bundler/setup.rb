require 'rbconfig'
unless defined?(Gem)
  module Gem
    def self.ruby_api_version
      RbConfig::CONFIG["ruby_version"]
    end

    def self.extension_api_version
      if 'no' == RbConfig::CONFIG['ENABLE_SHARED']
        "#{ruby_api_version}-static"
      else
        ruby_api_version
      end
    end
  end
end
if Gem.respond_to?(:discover_gems_on_require=)
  Gem.discover_gems_on_require = false
else
  kernel = (class << ::Kernel; self; end)
  [kernel, ::Kernel].each do |k|
    if k.private_method_defined?(:gem_original_require)
      private_require = k.private_method_defined?(:require)
      k.send(:remove_method, :require)
      k.send(:define_method, :require, k.instance_method(:gem_original_require))
      k.send(:private, :require) if private_require
    end
  end
end
$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/citrus-3.0.2/lib")
$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/coderay-1.1.3/lib")
$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/method_source-1.0.0/lib")
$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/pry-0.14.2/lib")
$:.unshift "/home/vidarh/src/repos/ruby-x11/lib"
$:.unshift "/home/vidarh/Desktop/Projects/skrift/lib"
$:.unshift "/home/vidarh/Desktop/Projects/skrift-x11/lib"
$:.unshift File.expand_path("#{__dir__}/../#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/toml-rb-2.2.0/lib")
