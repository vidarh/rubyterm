
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
