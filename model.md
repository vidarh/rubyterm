
G1..G4  Holds a character set
GL      Holds the number of G1..G4 used for characters 0x00..0x7f
GR      Holds the number of G1..G4 used for characters 0x80..0xff
  NOTE: conflicts w/UTF8
Cursor  Visible/invisible
Mouse, button tracking modes
Bracketed paste mode
Alternate screen mode

Sixxel, Regis, Tektronix 4014
  
Cell attributes:
 * FG color
 * BG color
 * Mode(Bold, Inverse, Italics, Underline, Blink, other?)

Line attributes (I *think*)
 * Double-Width (does this affect the whole line?
 * Double-Height(Upper)
 * Double-Height(Lower)


Operations that result in cursor moves have "attributes":
 * Flag: Cursor should be clamped within width/height or not.
 * Flag: Cursor should continue onto next line or not
 * Flag(? or is this inherent in the previous one): Cursor might trigger
   scroll.

vttest on real VT220/320 hardware:
https://www.youtube.com/watch?v=03Pz5AmxbE4

Note how blink in particular changes intensity rather than turn off
entirely.
