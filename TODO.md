
# Bugs

 * Bright SGR colours unhandled: `Term#set_modes` (lib/term.rb) handles
   30-37/40-47 but not the bright variants 90-97 (fg) and 100-107 (bg),
   so they fall through to the diagnostic logger and render with no
   colour change. Map 90-97 -> bright foreground (palette 8-15) and
   100-107 -> bright background. (Surfaced by harness/bench.rb's ansi
   workload.)
 * Font re-scales on `reset`. The DECCOLM (80/132 column) support
   rescales the font to fit the column count, but `reset` (and any
   `\e[?3l` to the column count we're already at) triggers a rescale even
   though nothing changed - a visible, unintended side-effect. Reconsider
   whether DECCOLM should rescale at all when the width doesn't actually
   change (skip the rescale if cols == current), and whether RIS/`reset`
   should touch the font/column scaling at all. (Window#fit_columns /
   RubyTerm#set_columns, lib/term.rb set_width_and_clear.)

# Design improvement

 * Keep track of spans of identical attributes so we don't need to
   make things as complicated/expensive when rendering
 * Keep track of presence/absence of blink attributes
 * Extract out and share the underlying buffer between @re and @rterm
   and gradually migrate more of the screen buffer code into it
   but separate the ANSI rendering and X rendering into backends.
   (See docs/architecture-review.md + docs/seams.md for the plan.)
 * Benchmark the full chain INCLUDING X11 (real X server + skrift glyph
   rasterisation) under Xvfb. harness/bench.rb currently covers the core
   (null sink) and the full headless pipeline (virtual window) for
   regression-testing the refactor; an X11-inclusive benchmark is more
   relevant for future *rendering* optimisation than for regression
   tracking, so it's deferred.
 
# Longer term

 * Scrollbar
 * Test if much effort to make work with mruby
 * Package up either w/mruby or libruby by collating all binaries.
   * First test: Script to crudely replace require/require_relative's
     with files in question. -> See rubypkg
 * Kerning and basic ligatures (e.g. -> to ⟶ or similar (but: needs to
   be scaled up?)
 * Forcing non-monospaced fonts into grids w/scaling?
 * Non-standard: Handling non-monospaced fonts

# Fun stuff

 * Sixxel
 * ReGIS
 * "Glow" effect via Gaussian filter; maybe as separate Gem for Skrift.
 * Emoji font support (means OTF support + SVG support)
 * Fraktur support per ECMA.
