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

### `-x11` keystroke latency (investigated, mostly fixed)

Reported symptom: ~1s/keystroke, "janky", unpredictable. Root causes found
and fixed (all in `re/lib/re/x11.rb`):

1. **Per-byte render storm.** `handle_input` processed one byte per call, so
   the bytes of an arrow's escape (`\e[B`) were spread across calls with a
   full render between each. That both rendered 3x per arrow *and* let
   KeyboardMap's escape timeout fire mid-sequence, splitting the arrow into
   stray characters in the status line. Fix: drain the whole input buffer in
   one call (commit `83effce`).
2. **Spurious second render.** `handle_input` returned `[]` when idle;
   `Editor#handle_input` guards with `if c = @ctrl.handle_input` and `[]` is
   truthy, so every keystroke forced a second full render. Fix: return `nil`
   when nothing was dispatched (commit `795a6a5`).
3. **Expose → full re-render.** The Expose handler ran a full `re.render`;
   under a compositor each render's flush emits another Expose → storm.
   Fix: Expose just re-blits the back buffer (`window.flush`); only key
   input and resize trigger a real render (commit `faba1fe`).

**Measured on the real X server (`:0`), clean system, ~37-row window:**
`view.render` median **7.6ms**, p90 11.5ms, with exactly **1 render per
keystroke**. Breakdown: rubyterm core (TermBuffer→damage→WindowAdapter
draw + flush) is only **2-6ms**; re's own `View#render` row-build is
~3ms; Rouge highlighting is cached (`moderender≈0ms`). First (cold) paint
is ~65ms - glyph rasterization for every cell - then damage tracking drops
it to near-zero.

**Caution for future profiling:** an early reading of ~31ms/render was
*contaminated by ~20 leaked `re --x11` test processes* (several spinning in
`binding.pry`) hammering the CPU and X server. Always reap spawned test
processes before trusting a perf number; the clean figure was ~6x lower.

Residual: a ~46ms tail on occasional frames (GC from re rebuilding every
visible row's `AnsiTerm::String` each frame). Median is smooth; the tail
would need a re-side change to skip rebuilding unchanged rows (re's own
FIXMEs). Not yet done.

Debug harness `RE_X11_TIME=1` (EV/RENDER/TIME lines to stderr) is still
present in `editor.rb`/`x11.rb`/`rubyterm_screen.rb` - env-gated; strip
before merging the migration back to the canonical `re`.

### `-x11` redraw-after-resize (fixed)

Reported: the window occasionally didn't repaint after a resize (^L fixed
it). Cause: `resize_window`/`zoom` blank the whole back buffer
(`@window.clear`), but the following render only rebuilds the screen
backend when the *char grid* (cols x rows) changes. A sub-cell pixel
resize - common while dragging - leaves the grid unchanged, so the damage
tracker sees no changed cells and draws nothing over the cleared buffer ->
blank until ^L (which calls `@out.reset`). Fix: `View#invalidate`
(delegates to `@out.reset`, rebuilding the backend so all content is
treated as new) is called after the resize/zoom clear (commit `60455e6`).
Verified: an unchanged-content repaint emits 0 bytes, but the full content
again after `invalidate`.

### `-x11` per-frame allocation / GC tail (partly addressed)

The occasional ~46-65ms render spikes are GC: re rebuilds every visible row
each frame, allocating ~73k objects/frame on a large (4K) window. Minor GC
fires ~once/frame; the worst spikes coincide with major GC. Breakdown by
phase: rowbuild ~60k, flush ~12k, overlays/moderender/setup negligible.

Transient-allocation trace (GC disabled during one render): ~44k Strings +
16k Hashes, concentrated in `AnsiTerm::String#parse` and `Attr#to_h`/`merge`
- i.e. re-parsing escape-laden strings and per-cell Attr churn.

Fixed so far: the **line-number gutter** was re-parsed
(`AnsiTerm::String.new(lf % n)`) for every row every frame; now memoised by
(current-line?, n). ~73k -> ~54k allocations/frame (-26%), median render
20ms -> 17ms, screenshot-verified (commit `7c82723`).

Then the content-row build itself was memoised (commit `6fdbf72`). The
expensive per-row assembly downstream of ModeRender (tab expansion,
search/match marks, `line[range]` truncation, padding) is extracted
unchanged into `build_content_line` and cached by `content_line`, keyed on
the row's full appearance (`line.to_str` = text + syntax incl. multiline
state) plus `@xoff`, text width, `max_line_length`, the search string, and
the mark/cursor column when on that row. Reuse is safe: `print` only reads
the line (splices a copy into `@out`) and the overlay passes replace attrs
rather than mutating them. The render structure (cls, row loop, overlay
passes, status, flush) is untouched - only the build is cached - so the
"rebuild from scratch" reading is preserved. Cache dropped on theme/mode
change (`reset!`), capped at 2000 rows.

Result on a real X server (4K window): **~73k -> ~13k allocations/frame
(-82%), median render 20ms -> 5.5ms, worst-case 65ms -> 11ms - the GC tail
is gone.** Screenshot-verified across vertical/horizontal cursor moves,
in-line edits and scrolling (cursor, current-line highlight, syntax,
line numbers all correct).

The remaining ~13k/frame is the unavoidable per-frame work: `cls`, printing
every row (cheap - `[]=` shares attr refs), the overlay passes
(`render_background`/curline/cursor), and the screen's own `to_str` diff in
`flush`. No longer GC-bound for in-view cursor moves.

### `-x11` large-window scroll stall + region scroll (fixed)

Reported: on a big window, holding a cursor key **stalled** - the window
froze (no re-render) for ~1s at a time. Instrumented: each *scroll* line
redrew the whole screen, so `draw_flush` (glyph drawing) hit **71-104ms** and
re blocked pushing ~13k X requests while the server throttled keypress
delivery (`handle_input` blocked ~1s between single renders). In-view cursor
moves were fine (2 rows, ~7ms); only viewport scrolling was affected.

Fix (commit `de924fd`): **region scroll.** `View#render` computes the scroll
delta; when the viewport shifts a few lines and is full of content it calls
`RubytermX11Screen#scroll`, which shifts the TermBuffer and blits the window
pixmap in one CopyArea (`delete_lines`/`insert_lines` inside a temporary
scroll region) and shifts the screen row cache in lockstep. The normal render
then redraws only the newly-exposed rows + the old/new cursor rows + the
status line; the rest hit the row cache. Big jumps and the ansiterm/terminal
backends (no `#scroll`) fall back to the existing full redraw, so only the
x11 path changes. Measured (1863x2054 window, holding Down): `draw_flush`
**71-104ms -> 0.2ms**, no more freezes. Screenshot-verified scroll down,
scroll up and in-view moves (content, cursor, highlight, syntax all correct).

Also capped the content/gutter memos at 400 entries (was 2000/4000): with
region scroll they only need the on-screen rows, and the smaller old-gen
footprint cut the worst major-GC pause **~250ms -> ~150ms** (commit
`5b5e229`). Residual: an occasional ~150ms major-GC stutter during sustained
scrolling, mostly from ModeRender caching every line visited - out of scope.
