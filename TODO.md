
# Bugs

 * Bright SGR colours unhandled: `Term#set_modes` (lib/term.rb) handles
   30-37/40-47 but not the bright variants 90-97 (fg) and 100-107 (bg),
   so they fall through to the diagnostic logger and render with no
   colour change. Map 90-97 -> bright foreground (palette 8-15) and
   100-107 -> bright background. (Surfaced by harness/bench.rb's ansi
   workload.)

# Essentials


 * (B) Double-buffering to remove the last bit of flicker.
 * (B) Scrollback buffer
 * (C) Better keyboard handling.
 * Background fill - fill full line

# Design improvement

 * Term buffer should track damage precisely
 * This includes "scrolling" the damage buffer, so that a "scroll up"
   etc. gets recorded with any other damaged scrolled so we can
   replay as "scroll then render".
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
 * Double-height/width text rendering, just because
 * Fraktur support per ECMA.
