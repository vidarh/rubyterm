# frozen_string_literal: true

source "https://rubygems.org"

# Runtime + development dependencies come from rubyterm.gemspec.
gemspec

# skrift, its X11 adapter and the plugins all live in one monorepo, each in its
# own subdirectory (skrift/, skrift-x11/, …), and are not yet on RubyGems — so
# pull all four from that single repo. A `git do … end` block lets Bundler find
# each gem's gemspec in its subdir; a per-gem `git:` would look at the repo root
# and miss them.
#
# To develop against a local checkout, set ONE Bundler local override at the
# monorepo root (in your global ~/.bundle/config). It redirects the whole
# skrift.git source, so every gem in the block resolves to your checkout:
#
#   bundle config set --global disable_local_branch_check true
#   bundle config set --global local.skrift /path/to/skrift
git "https://github.com/vidarh/skrift.git", branch: "master" do
  gem "skrift"
  gem "skrift-x11"
  gem "skrift-boxdrawing"
  gem "skrift-color"
end

group :development do
  gem "rake", "~> 13.0"
end
