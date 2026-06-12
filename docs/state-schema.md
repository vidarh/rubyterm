# Terminal State Dump Schema

The canonical JSON shape produced by `Harness::StateDump.dump` (and by
the live terminal's `dump_state` debug-socket command). Everything
that diffs terminal state — the oracle differ, save/load round-trip
checks, failure signatures — works against this schema. Oracles may
emit a *partial* dump (only the fields they can know); the differ
compares the intersection.

```json
{
  "cols": 80,
  "rows": 24,
  "cursor": {
    "row": 0,
    "col": 5,
    "visible": true,
    "pending_wrap": false
  },
  "scroll_region": [0, 23],
  "modes": {
    "origin": false,
    "autowrap": true,
    "lnm": true
  },
  "tabstops": [0, 8, 16, 24],
  "charsets": {"g0": "B", "g1": "0", "active": 0},
  "cells": [
    [ {"ch": "A", "fg": 13421772, "bg": 0, "attrs": ["bold"], "gen": 12},
      null,
      ...
    ],
    ...
  ],
  "scrollback_len": 140
}
```

Field notes:

* **cursor.col / pending_wrap** — `col` is the raw internal x and may
  equal `cols` when a wrap is pending (this implementation defers the
  wrap to the next printed character). `pending_wrap` makes that state
  explicit because it is the single most common differential-testing
  discrepancy between terminal implementations; the differ clamps the
  column on both sides.
* **scroll_region** — 0-based inclusive `[top, bottom]`; defaults to
  the full screen when no DECSTBM is active.
* **tabstops** — sorted 0-based columns.
* **charsets** — `"B"` = US-ASCII (default), `"0"` = DEC special
  graphics; `active` is the GL slot (0 = G0, 1 = G1).
* **cells** — `rows` arrays of `cols` entries. `null` means the cell
  was never written (rendered identically to a space with default
  background). `ch` is the *translated* character (charset mapping
  applied at write time). `fg`/`bg` are resolved 24-bit RGB integers
  (palette already applied). `attrs` is the decoded attribute list:
  `bold`, `faint`, `italics`, `underline`, `blink`, `rapid_blink`,
  `inverse`, `invisible`, `crossed_out`, `dbl_underline`, `overline`.
* **cells[][].gen** — per-cell content-generation counter (only
  present when the harness's gen tracking is loaded; `null` for cells
  created by paths that bypass `TermBuffer#set`). Bumped only when
  content actually changes; the marker render mode paints it into the
  framebuffer so stale screen content can be detected and attributed.
* **scrollback_len** — number of lines in the scrollback buffer
  (scrollback content itself is not part of the dump yet).
