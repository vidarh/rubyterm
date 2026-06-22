# frozen_string_literal: true

source "https://rubygems.org"

# Runtime + development dependencies come from rubyterm.gemspec.
gemspec

# skrift / skrift-x11 are developed alongside rubyterm and not yet on
# RubyGems, so they come from git. To work against a local checkout instead
# of the pushed branch, set a *local override* (per machine, stored in your
# global ~/.bundle/config, so it never lands in the repo):
#
#   bundle config set --global local.skrift     /path/to/skrift
#   bundle config set --global local.skrift-x11 /path/to/skrift-x11
#
# A local override requires the branch below to match the checkout's branch.
gem "skrift",     git: "https://github.com/vidarh/skrift.git",     branch: "master"
gem "skrift-x11", git: "https://github.com/vidarh/skrift-x11.git", branch: "master"

# The skrift plugins are local-only siblings (no public repo yet): skrift-x11
# now depends on skrift-boxdrawing, and skrift-color provides colour emoji.
gem "skrift-boxdrawing", path: "../skrift-boxdrawing"
gem "skrift-color",      path: "../skrift-color"
