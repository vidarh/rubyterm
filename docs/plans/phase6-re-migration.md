# Phase 6 — migrate `re` onto rubyterm's shared core

Status: PLAN (no code yet). Work happens in a **copy** of `re` at
`Desktop/Projects/re` (the user runs the real editor from
`~/src/personal/re`; the copy is isolated so we can't break it).

## Goal

`re` (the editor) renders through the vendored **`ansiterm`** gem today.
Migrate it to render through rubyterm's shared core — `TermBuffer` (screen
model) + `TrackChanges` (damage) + `AnsiBackend` (minimal-escape output) —
so the buffer is shared, profiled and tested, and rubyterm's core is proven
against a real TUI app. This is the "chop off the frontend / expose a TUI
API" validation from the architecture review.

## Current state (survey)

`re`'s view layer is built on three `ansiterm` classes:

- **`AnsiTerm::Buffer`** — `re`'s `@out`. Cell-grid screen + line-level
  diff cache; `to_s` emits CUP/SGR/EL only for changed rows. Methods `re`
  uses: `new(w,h)`, `move_cursor(x,y)`, `print(*strings)`, `lines`,
  `to_s`, `resize(w,h)`, `reset`, `cls`, `scroll_up`.
- **`AnsiTerm::String`** — a styled row (text + per-char attributes).
  `re` builds these and `@out.print`s them; it also reaches into
  `@out.lines[i]` and mutates the row directly via `set_attr(range, attr)`,
  `merge_attr_below(range, attr)`, and `[](x)`.
- **`AnsiTerm::Attr`** — `fgcol` / `bgcol` (SGR params, e.g. `[38,2,r,g,b]`
  or `39`) + `flags` (BOLD/UNDERLINE/CROSSED_OUT).

Render flow: `Editor#run` → `View#render` (builds `@out`) → `View#flush`
(`$stdout.print(@out.to_s)`). Syntax colour comes from Rouge via a custom
`ReFormatter`; the view overlays line numbers, search marks, current-line
highlight and a fake cursor by mutating `@out.lines[i]`.

rubyterm already absorbed `ansiterm`'s **diff kernel** into `AnsiBackend`
(Phase 5). So the missing piece is the **buffer + styled-row API** that
`re` drives.

## Key insight

`re`'s row overlays map cleanly onto cell operations:

| `re` does (on an `AnsiTerm::String` row) | on a `TermBuffer` row |
|---|---|
| `print(styled_str)` at cursor | `set(x,y,cp,fg,bg,flags)` per char |
| `set_attr(range, attr)` (overwrite) | per cell in range: rewrite style |
| `merge_attr_below(range, attr)` (paint-below) | per cell: set style only where unset |
| `line[x]` (cell present?) | `get(x,y)` / `unset?(x,y)` |

`re`'s own code already says *"Might be better to simply set this directly
on the TermBuffer"* — the direction is welcome.

## Strategy: a compatibility shim first, simplify later

Do **not** rewrite `re`'s view layer up front. Instead provide a drop-in
class with the `AnsiTerm::Buffer` API, backed by rubyterm's core, and swap
`re`'s `@out` to it. `re`'s view code stays unchanged; we validate the core
against `re`'s real usage with minimal risk. Once solid, optionally
simplify `re`'s view to call the cell API directly (deleting the
styled-string overlays — the author's FIXMEs).

### Prerequisite (rubyterm side): an engine-only require

`require "rubyterm"` currently pulls in X11/skrift/toml — `re` (a terminal
*app*, not an X server) must not need those. Add **`lib/rubyterm/engine.rb`**
that loads only palette/charsets/parsers + `TermBuffer`/`TrackChanges`/
`Term`/`AnsiBackend` (none of which depend on X11 or skrift), and have
`lib/rubyterm.rb` require it then add the X11 front end. This is the "TUI
API facade" foundation and is independently useful. Low risk, additive.

### The shim (`Re::Screen`, backed by rubyterm core)

Implements the `AnsiTerm::Buffer` surface `re` uses:

- construction/`resize`/`reset`/`cls`/`move_cursor`/`scroll_up` → drive a
  `TermBuffer` (+ `TrackChanges`) directly (no `Term` interpreter, so no
  wrap/scroll surprises — `re` clips lines itself).
- `print(*styled)` → for each `AnsiTerm::String`, walk its chars + attrs,
  map `Attr → (fg,bg,flags)`, `TermBuffer#set` per cell, advance cursor.
- `lines` → array of lightweight **row proxies** over `TermBuffer` rows,
  each implementing `set_attr` / `merge_attr_below` / `[]` as
  read-modify-write loops over cells.
- `to_s` → flush damage through `AnsiBackend` and return `AnsiBackend#take`
  (the shared diff kernel replaces `AnsiTerm::Buffer`'s `@cache`).

### Attr mapping (the fiddly bit to get exactly right)

`AnsiTerm::Attr` uses SGR params; rubyterm uses 24-bit fg/bg ints + flag
bits. Translate: `[38,2,r,g,b]`/`[48,2,r,g,b]` → `0xRRGGBB`; `39`/`49` →
default FG/BG; 30-37/40-47 (+90-97/100-107) → palette; BOLD/UNDERLINE/
CROSSED_OUT → rubyterm flag bits. Build this as a small, unit-tested
function — it's the highest-risk correctness surface.

## Incremental steps

1. **rubyterm:** add `lib/rubyterm/engine.rb` (engine-only require);
   `lib/rubyterm.rb` builds on it. Verify `require "rubyterm/engine"`
   pulls in no X11/skrift. (rubyterm repo; safe, additive.)
2. **re copy:** depend on rubyterm (path/git) in `re/Gemfile`; confirm the
   engine loads inside `re`.
3. **shim + tests:** build `Re::Screen` + the Attr mapping; metamorphic
   test vs `AnsiTerm::Buffer` (same op sequence ⇒ equivalent final screen /
   escape output) so we can trust the swap before touching `re`'s runtime.
4. **swap behind a flag:** `@out = ENV["RE_RUBYTERM"] ? Re::Screen.new(...)
   : AnsiTerm::Buffer.new(...)`. Run `re` (in the copy) both ways; diff the
   rendered screen on real files (syntax highlight, current-line, cursor,
   search marks, scroll, resize).
5. **iterate** on gaps the live run surfaces (attr edge cases, cursor,
   wide/zero-width chars, padding).
6. **default + keep `ansiterm`** vendored as a fallback until confident.
7. **later (optional):** simplify `re`'s view to call the cell API
   directly, retiring the styled-string overlays.

## Risks / open questions

- **Attr fidelity** (truecolor, defaults, palette, flags) — unit-test hard.
- **Overlay semantics**: `merge_attr_below` (paint-below) vs `set_attr`
  (overwrite) must be replicated exactly or highlights/cursor differ.
- **Cursor**: `re` draws a *fake* cursor via `set_attr` and also calls
  `move_cursor`; map onto `AnsiBackend`'s cursor handling (or keep `re`'s
  approach and just render the cell).
- **`AnsiBackend` was written to emit a terminal emulator's screen**; `re`'s
  usage is close but validate the diff output on `re`'s patterns.
- **Performance**: `re` is interactive; the shim must not regress redraw
  latency vs `ansiterm`'s line cache. Measure.

## First action

Step 1 (engine-only require) is a safe, additive rubyterm change and the
prerequisite for everything else. Do that, then build the shim + tests
(steps 2–3) before any change to `re`'s runtime behaviour.

## Status / results (AnsiBackend path)

Steps 1–4 done; `re` renders through rubyterm's core behind a flag.

- **Step 1 (rubyterm):** `lib/rubyterm/engine.rb` — engine-only require, no
  X11/skrift. Done.
- **Step 2 (re copy):** `rubyterm` added to `re`'s Gemfile (path gem;
  skrift/skrift-x11 git + global local-overrides). Done.
- **Step 3 (shim + test):** `re/lib/re/rubyterm_screen.rb` —
  `RubytermScreen < AnsiTerm::Buffer`, overriding only `#to_s` (render the
  rows into a persistent `TermBuffer`, emit via `AnsiBackend`). The only
  new logic is the Attr→(fg,bg,flags) map (Integer/String/Array SGR forms,
  palette-256, truecolor, BOLD brightens basic/default fg by +8).
  Metamorphic test (`re/tmp/shim_metamorphic.rb`) — colours, bold, palette,
  truecolor, `set_attr`, `merge_attr_below`, scroll all match AnsiTerm; the
  shim additionally **fixes** an AnsiTerm `to_str` bug (fg not reset after
  `\e[0m` when a bg is set → colour bleed).
- **Step 4 (wire behind flag):** `View#@out` uses `RubytermScreen` when
  `RE_RUBYTERM=1`, else `AnsiTerm::Buffer` (default unchanged). Live test
  (`re/tmp/live_compare.rb`: runs `re` both ways in a pty, interprets each
  output through `Term`, compares full cells) — runs without crashing and
  renders **identically** (char+fg+bg+flags) for `re.rb`, `view.rb`,
  `ansi.rb`. `help.md` differs in **one** right-edge highlight cell (a
  `set_attr`-boundary bg edge case).

### Open follow-ups

1. **The 1-cell `set_attr`-boundary bg diff** on markdown — minor cosmetic,
   in the intricate boundary handling; track down or accept.
2. **Output size / latency:** the shim emits ~70 % more bytes on a *full*
   redraw (AnsiBackend writes truecolor everywhere + CUP per run vs
   AnsiTerm's per-row minimal-SGR diff). Incremental (typing) updates are
   damage-based and may be competitive; **measure interactive redraw**
   before defaulting it on.
3. **Default on / retire ansiterm** once 1–2 are comfortable; keep
   `ansiterm` vendored as a fallback.
4. **Later:** simplify `re`'s view to the cell API directly (the author's
   own FIXMEs).

## `-x11` backend (DONE)

`re --x11` runs as a standalone X11 application via rubyterm's pure-Ruby
`Window` backend - no host terminal, cells drawn straight to the window:

- **Output:** `RubytermX11Screen` (a `RubytermScreen` whose backend is
  `WindowAdapter`+`Window`; `#to_s` draws + `window.flush`, returns `""`).
- **Input:** `RubytermX11Controller` (a `Termcontroller` subclass) reads X11
  `KeyPress` events and reuses rubyterm's `lookup_string` +
  `keysym_to_vt102` to produce the terminal escape bytes a real terminal
  would send, fed to Termcontroller's `KeyboardMap` + keybinding dispatch
  unchanged. Single-threaded: `handle_input` blocks on the next X event;
  Expose/ConfigureNotify trigger a redraw; raw/pause/suspend are no-ops.
- **Wiring:** `View`/`Editor` branch on `x11?` for `@out`, `winsize`
  (window grid), `@ctrl`, and `render`/`reset_screen`/`quit` (skip
  `IO.console`, nil with no tty). `re.rb` gains a `--x11` flag (loads the
  X11 stack, runs as one local process).

Verified under Xvfb: re renders a file with full syntax highlighting, line
numbers, status bar, current-line highlight and a block cursor; arrow keys,
End and typing dispatch correctly. The default (ansiterm) and `RE_RUBYTERM`
(AnsiBackend) paths are untouched.

Remaining polish: window focus (bare-X has none - a WM handles it normally);
live window-resize → grid; the AnsiBackend-path follow-ups above (byte
size, the 1-cell markdown diff) before defaulting either path on.
