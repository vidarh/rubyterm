TESTABLE

# Testable Terminal Core

A fully testable terminal core that can be exercised without X11 or PTY dependencies.

## Vision

All core terminal logic -- buffer management, escape sequence interpretation,
cursor movement, scrolling, and character rendering decisions -- can be tested
in isolation via fast, headless unit tests. Developers can confidently refactor
internals knowing that regressions will be caught immediately.

## Why This Matters

The README vision calls for decoupling the terminal buffer and escape handling
from both PTY and X11. Testability is the forcing function for that
decoupling: code that is testable in isolation is, by definition, decoupled.
Currently the only tested components are EscapeParser, UTF8Decoder, Palette,
and Charsets. The core data structures (ScrBuf, TermBuffer) and the Term class
have zero meaningful test coverage despite being the most actively modified
code.

## Potential Plans

- Add unit tests for ScrBuf and TermBuffer (no external deps required)
- Add unit tests for TrackChanges with a mock adapter
- Make Term#write functional and testable without X11
- Extract RubyTerm escape/character handling into Term so it can be tested
- Add regression tests for scrollback buffer operations

---
*Status: GOAL*
