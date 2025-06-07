require 'minitest/autorun'
require 'minitest/pride'

# Load only the core library components that don't require external dependencies
begin
  require_relative '../lib/escapeparser'
rescue LoadError => e
  puts "Warning: Could not load escapeparser: #{e.message}"
end

begin
  require_relative '../lib/palette'
rescue LoadError => e
  puts "Warning: Could not load palette: #{e.message}"
end

begin
  require_relative '../lib/utf8decoder'
rescue LoadError => e
  puts "Warning: Could not load utf8decoder: #{e.message}"
end

begin
  require_relative '../lib/charsets'
rescue LoadError => e
  puts "Warning: Could not load charsets: #{e.message}"
end

# Test helper methods
module TestHelpers
  def create_escape_parser
    return nil unless defined?(EscapeParser)
    EscapeParser.new
  end
  
  def create_utf8_decoder
    return nil unless defined?(UTF8Decoder)
    UTF8Decoder.new
  end
end

# Include helper methods in all test classes
class Minitest::Test
  include TestHelpers
end