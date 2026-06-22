require 'rake/testtask'

# Default task
task default: :test

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

# Individual test tasks for each component
namespace :test do
  desc "Run TermBuffer tests"
  Rake::TestTask.new(:termbuffer) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList['test/test_termbuffer.rb']
    t.verbose = true
  end

  desc "Run EscapeParser tests"
  Rake::TestTask.new(:escapeparser) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList['test/test_escapeparser.rb']
    t.verbose = true
  end

  desc "Run UTF8Decoder tests"
  Rake::TestTask.new(:utf8decoder) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList['test/test_utf8decoder.rb']
    t.verbose = true
  end

  desc "Run Palette tests"
  Rake::TestTask.new(:palette) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList['test/test_palette.rb']
    t.verbose = true
  end

  desc "Run Charsets tests"
  Rake::TestTask.new(:charsets) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList['test/test_charsets.rb']
    t.verbose = true
  end
end

# Run the terminal application
desc "Run the terminal emulator"
task :run do
  sh "bundle exec ruby bin/rubyterm"
end

# Debug mode
desc "Run the terminal emulator in debug mode"
task :debug do
  sh "DEBUG=1 bundle exec ruby bin/rubyterm"
end

# Build executable (requires rubypkg tool)
desc "Build standalone executable"
task :build do
  sh "make build"
end

# Install to ~/bin
desc "Install to ~/bin"
task :promote do
  sh "make promote"
end

# Gem packaging — distinct from `rake build`, which builds the standalone
# executable. Note: until skrift and its plugins are on RubyGems, a published
# rubyterm gem can't resolve them, so publish those first.
require_relative "lib/rubyterm/version"
GEM_PKG = File.expand_path("pkg", __dir__)

desc "Build the rubyterm gem into pkg/"
task :gem do
  require "fileutils"
  FileUtils.mkdir_p(GEM_PKG)
  sh "gem build rubyterm.gemspec -o #{GEM_PKG}/rubyterm-#{RubyTerm::VERSION}.gem"
end

desc "Build + push the rubyterm gem to RubyGems"
task publish: :gem do
  sh "gem push #{GEM_PKG}/rubyterm-#{RubyTerm::VERSION}.gem"
end

# Show available tasks
desc "Show all available tasks"
task :help do
  puts "Available tasks:"
  puts "  rake test          - Run all tests"
  puts "  rake test:COMPONENT - Run tests for specific component"
  puts "  rake run           - Run the terminal emulator"
  puts "  rake debug         - Run in debug mode"
  puts "  rake build         - Build standalone executable"
  puts "  rake promote       - Install to ~/bin"
  puts "  rake gem           - Build the rubyterm gem into pkg/"
  puts "  rake publish       - Build + push the rubyterm gem to RubyGems"
  puts ""
  puts "Test components available:"
  puts "  - termbuffer"
  puts "  - escapeparser" 
  puts "  - utf8decoder"
  puts "  - palette"
  puts "  - charsets"
end