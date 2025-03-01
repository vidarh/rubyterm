
# FIXME:
# This is the start of defining character sets as per
# the vt102/vt200 specs
#
# They should be wrapped in modules and split out with other relevant
# data in a separate gem.
#
# These objects are expected to act as a Hash, and provide a value
# for anything passed in, translating only those keys that are different
#

  DefaultCharset  = Hash.new{|_,k| k }.freeze # Identity

  # Line drawings.
  # http://fileformats.archiveteam.org/wiki/DEC_Special_Graphics_Character_Set
  GraphicsCharset = {
    0x5f => "\u00A0",
    0x60 => "\u25c6",
    0x61 => "\u2592",
    0x62 => "\u2409",
    0x63 => "\u240C",
    0x64 => "\u240d",
    0x65 => "\u240A",
    0x66 => "\u00B0",
    0x67 => "\u00B1",
    0x68 => "\u2424",
    0x69 => "\u240B",
    0x6A => "\u2518",
    0x6B => "\u2510",
    0x6C => "\u250C",
    0x6D => "\u2514",
    0x6E => "\u253C",
    0x6f => "\u23BA",
    0x70 => "\u23BB",
    0x71 => "\u2500",
    0x72 => "\u23BC",
    0x73 => "\u23BD",
    0x74 => "\u251c",
    0x75 => "\u2524",
    0x76 => "\u2534",
    0x77 => "\u252c",
    0x78 => "\u2502",
    0x79 => "\u2264",
    0x7A => "\u2265",
    0x7B => "\u03C0",
    0x7C => "\u2260",
    0x7D => "\u00A3",
    0x7E => "\u00b7",
  }
  GraphicsCharset.default_proc = ->(_,k) {k}
  GraphicsCharset.freeze
