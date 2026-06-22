# frozen_string_literal: true

source "https://rubygems.org"

# Runtime + development dependencies come from rubyterm.gemspec.
gemspec

# skrift and its plugins/adapter live in the skrift monorepo and are not yet
# on RubyGems, so they come from git. To work against a local checkout, set
# *local overrides* pointing at the monorepo subdirs (per machine, in your
# global ~/.bundle/config, so they never land in the repo):
#
#   bundle config set --global disable_local_branch_check true
#   bundle config set --global local.skrift            /path/to/skrift/skrift
#   bundle config set --global local.skrift-x11        /path/to/skrift/skrift-x11
#   bundle config set --global local.skrift-boxdrawing /path/to/skrift/skrift-boxdrawing
#   bundle config set --global local.skrift-color      /path/to/skrift/skrift-color
gem "skrift",     git: "https://github.com/vidarh/skrift.git",     branch: "master"
gem "skrift-x11", git: "https://github.com/vidarh/skrift-x11.git", branch: "master"

# skrift-x11 depends on skrift-boxdrawing; skrift-color provides colour emoji.
# These now live in the skrift monorepo too; resolve them the same way (git +
# local override to the monorepo subdir).
gem "skrift-boxdrawing", git: "https://github.com/vidarh/skrift-boxdrawing.git", branch: "master"
gem "skrift-color",      git: "https://github.com/vidarh/skrift-color.git",      branch: "master"
