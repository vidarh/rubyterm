# Harness Quick Start

Five-minute tour of the test harness. Full reference:
[harness.md](harness.md); dump format: [state-schema.md](state-schema.md).

Everything prints JSON on stdout (diagnostics on stderr) and exits
0 on pass, 1 on fail. No X server needed for anything except
`harness/live.rb`; the only external dependency is `tmux` for
`--oracle tmux`.

## 1. Run one case

```sh
ruby harness/cli.rb run --case cases/synthetic/text-basic.bin --oracle tmux
```

Key fields in the output:

```json
{
  "pass": false,
  "class": "render",            // "state" = wrong grid, "render" = right grid, wrong pixels
  "signature": "8b67c093...",   // stable id of *how* it fails (clusters duplicates)
  "checks": {
    "state":  {"pass": true,  "oracle": "tmux", "diff": []},
    "redraw": {"pass": false, "cells": [[0,3],[1,3]], "bbox": [1,49,30,14]},
    "markers": {"pass": true, "cells": []}
  },
  "screen": ["what the terminal", "displays as text", ...]
}
```

Reading a failure:

- `state.diff` — cells/cursor where we disagree with tmux interpreting
  the same bytes: `{"row": 1, "col": 0, "expected": "f", "got": "t"}`.
  A parser / state-machine bug.
- `redraw.cells` — character cells where the incrementally maintained
  screen differs from a from-scratch redraw of the same buffer. An
  incremental-rendering bug (stale content the user would see).
- `markers.cells` — like redraw, but each entry *names the cell the
  wrong pixels came from*:
  `{"row": 19, "col": 0, "problem": "stale_gen", "expected_gen": 160, "got": [{"row": 23, "col": 0, "gen": 153}]}`
  means cell (19,0) shows content that was written for cell (23,0).

Useful flags: `--geometry 40x10`, `--dump` (include the full state
dump), `--checks state,redraw` (subset; `markers` re-runs the case in
marker render mode, `state` without `--oracle tmux` only checks that
interpreting the bytes doesn't crash).

## 2. Sweep the corpus / check for regressions

```sh
# What's broken right now?
ruby harness/cli.rb sweep --cases cases/synthetic --oracle tmux

# The gate (use this before/after any terminal change):
ruby harness/cli.rb sweep --cases cases/synthetic --oracle tmux --ratchet ratchet.json
```

The ratchet sweep passes as long as no *previously-passing* case
breaks — the known-failing backlog doesn't block you. Takes ~1 minute
(tmux oracle dominates; drop `--oracle tmux` for a fast render-only
pass).

## 3. Fix a bug

```sh
ruby harness/cli.rb run --case cases/synthetic/dch.bin --oracle tmux   # fails
# ... edit lib/term.rb ...
ruby harness/cli.rb run --case cases/synthetic/dch.bin --oracle tmux   # passes?
ruby harness/cli.rb sweep --cases cases/synthetic --oracle tmux --ratchet ratchet.json  # no regressions?
ruby harness/cli.rb sweep --cases cases/synthetic --oracle tmux --ratchet ratchet.json --update-ratchet  # protect it
rake test
```

Rules: a fix is done when the case passes *and* the ratchet sweep is
clean. Never edit `harness/`, `cases/` or `ratchet.json` to make a fix
pass (`--update-ratchet` is the only sanctioned ratchet change — it
refuses to drop regressed IDs).

## 4. Shrink a failing input

```sh
ruby harness/cli.rb minimize --case big-failure.bin --checks redraw --out minimal.bin
```

ddmin over escape-sequence-safe tokens; only accepts candidates that
fail with the same `signature`. Prefer `--checks redraw` or `markers`
over the tmux oracle here — oracle-free iterations are in-process and
~100× faster. `minimal_inspect` in the output shows the repro
human-readably.

## 5. Capture a bug from a real application

```sh
ruby harness/cli.rb record --out emacs.rec -- emacs -nw
# use it until it glitches, then quit
ruby harness/cli.rb replay --rec emacs.rec --checks redraw,markers
```

Replay reports every failing byte offset. New small cases go in
`cases/synthetic/` as raw byte files (add via `harness/gen_cases.rb`
if synthetic, or save minimized bytes directly); the case ID is the
filename without extension.

## 6. Poke the live terminal

```sh
ruby harness/live.rb            # instead of: ruby termtest.rb
# prints: rterm debug socket: /tmp/rterm-debug-<pid>.sock
```

```sh
# From another shell — inject bytes and dump coherent state as JSON:
printf '%s\n' '{"cmd":"feed","bytes_b64":"'$(printf 'hello' | base64)'"}' \
              '{"cmd":"dump_state"}' | nc -U /tmp/rterm-debug-*.sock
```

Commands: `dump_state`, `render_barrier`, `feed`, `tokenize`
(see harness.md for details).

## Where things live

| | |
|---|---|
| `harness/cli.rb` | all commands above |
| `harness/lib/` | implementation (loaded headlessly; no X11) |
| `cases/synthetic/` | committed corpus (`harness/gen_cases.rb` regenerates) |
| `*.meta.json` sidecars | documented oracle divergences (`skip_checks`) |
| `ratchet.json` | sorted IDs of cases known to pass |
| `test/test_harness.rb` | unit tests for the harness itself (`rake test`) |
| `docs/harness.md` | full guide, fixer contract, known-bug backlog |
