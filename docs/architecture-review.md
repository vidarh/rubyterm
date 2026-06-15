# rterm Architecture Review & Refactoring Plan

*Written 2026-06. Scope: the layering of `rterm` (this repo), assessed
against the stated goal of cleanly separable layers — virtual buffer,
escape interpreter, operation API, and swappable rendering backends —
and against `~/src/personal/re` + the `ansiterm` gem as the other
candidate foundation.*

---

## 1. Executive summary

The goal is sound and you are closer than the mess suggests. There is
already an *outline* of the right layering in the code, and the two
genuinely hard, high-value assets needed for it already exist — they're
just in two different repos and pointed at each other:

- **rterm has a strong escape interpreter** (`Term`, ~680 lines,
  VT100/VT102-correct, guarded by the harness) but **no rendering
  backend abstraction at all** — its "adapter" speaks *pixels*, and the
  interpreter, the buffer, and the app all reach around it to the X11
  window anyway.
- **`re`/`ansiterm` has a working economic text-mode renderer** (the
  `Buffer#to_s` line-diff + `Attr#transition_to` minimal-SGR kernel —
  exactly the "Emacs-like" backend you want) but **almost no escape
  interpretation** and an immature, editor-shaped buffer.

So the two repos are mirror images: each has the half the other is
missing. The pragmatic move is **not** "adopt the gem" (it isn't a
foundation — see §5) and **not** "keep muddling rterm forward". It is:

> Converge on a single, properly-designed **`Screen`** (virtual buffer +
> operation API + first-class damage), keep rterm's `Term` as the
> optional escape-interpreter layer, define a real **`Backend`
> protocol**, and lift `ansiterm`'s diff kernel into an **`AnsiBackend`**
> that renders a `Screen` to economic escape sequences. Then migrate
> `re` onto that `Screen` + `AnsiBackend`.

That single decision serves all three constituencies: rterm gets a
backend seam and a free text backend; `re` gets a stronger shared buffer
and optional full escape handling while *keeping* its economic renderer;
future TUI clients get a "build a Screen, pick a backend" API that
renders to a terminal **or** an X11 window from the same app code.

The keystones are two interfaces — the **Screen operation API** and the
**Backend protocol**. Get those right and every other box slots in. The
rest of this document is the harsh critique that justifies that, the
target architecture, and a phased, harness-guarded migration that has
value even if you stop halfway.

---

## 2. The current architecture (as-is)

### 2.1 Object graph

```
RubyTerm (termtest.rb, 586 lines) ───────────────────────────── the "Host" + god object
  owns: X11 event loop, pty Controller, 4 threads + @queue, selection,
        scrollback UI, mouse, DECCOLM policy, blink, font zoom, config
  │
  ├── Window (lib/window.rb)            X11 + skrift; pixmap double-buffer; copy_area scroll
  ├── WindowAdapter (lib/windowadapter) cell→pixel: char_w/h, scroll-blit geometry, glyph draw,
  │                                     colour dim/brighten, DECCOLM delegation
  ├── TrackChanges (lib/trackchanges)   "stupidly misnamed" — buffer mutation + damage set +
  │     │                               draw batching/coalescing, all in one
  │     └── TermBuffer / ScrBuf         cell grid [ch,fg,bg,flags]; scrollback; line attrs
  ├── Term (lib/term.rb)                escape/control interpreter; cursor; modes; regions
  │     ├── EscapeParser                byte-level escape state machine
  │     ├── UTF8Decoder
  │     └── charsets / palette
  └── Controller (lib/controller.rb)    pty spawn, read thread, key/mouse/DA replies → pty

harness/ swaps Window → VirtualWindow, reuses WindowAdapter/TrackChanges/TermBuffer/Term.
```

### 2.2 What each layer *should* own vs what it *does* own

| Concern | Should live in | Actually lives in |
|---|---|---|
| Byte → operation interpretation | Interpreter | `Term` ✓ (but coupled to adapter) |
| Styled-cell grid + cursor + regions + scrollback | Virtual buffer | split across `TermBuffer`, `ScrBuf`, **and** `TrackChanges` |
| Damage tracking | Virtual buffer | `TrackChanges.@changes` (barely used) + eager pixel draw |
| Realising damage as pixels / escapes / bitmap | Backend | only a *pixel* path exists (`WindowAdapter`→`Window`); bypassed by 3 callers |
| Cursor/selection overlays | Virtual buffer | hand-rolled in `RubyTerm` as pixel re-stamping |
| Threading / input / pty / window | Host | `RubyTerm` (fused with everything) |
| Terminal capabilities / cell metrics | Backend | `Term.char_w` asks the adapter; `re`'s `View` reaches for `IO.console.winsize` |

The diagonal is the problem: almost every concern leaks one or two
layers away from where it belongs.

---

## 3. Harsh critique (with evidence)

### A. The seams are misdrawn and leaky

**A1 — `TrackChanges` is three classes wearing a trenchcoat.** Its own
header (`trackchanges.rb:1-11`) calls it *"the now stupidly misnamed
TrackChanges class [that] just bifurcates buffer changes and passes them
to both the buffer *and* the screen"* with a `FIXME: Roll this into the
actual buffer`. It conflates (a) model mutation (delegates to
`TermBuffer`), (b) damage tracking (`@changes`), and (c) a run-length
draw batcher (`draw_buffered`/`draw_flush`, `trackchanges.rb:136-237`).
Those are three different jobs at three different layers. Worse, it
makes *policy* decisions by reaching into the backend:
`unless @adapter.scrollback_mode` appears in `set`, `clear`,
`insert_lines`, `delete_lines`, `clear_line`, `redraw_blink`
(`trackchanges.rb:21,57,63,69,79,95`). A buffer should not know what
"scrollback mode" is.

**A2 — `method_missing` makes the buffer API unknowable.**
`trackchanges.rb:89-92` forwards any unknown method to `@buffer` *and
prints a debug line* (`p [:TRACK, sym, ...]`). So the real surface of
the central object is implicit, and exercising an un-wrapped path spews
to stderr in production.

**A3 — `Term` is coupled to a pixel backend, by its own admission.**
`term.rb:5-24` says *"This class should know **nothing** about X11 or
windows, and should ideally not use the `@adapter`"* — then takes
`@adapter` in the ctor with `# FIXME: Untangle` (`term.rb:44`), and uses
it for `char_w`/`char_h` (`:29-30`), `@adapter.clear` (`:133`),
`@adapter.scrollback_mode` (`:220,312,319`), `@adapter.scroll_up`
(`:227`), and `@adapter.set_columns` (`:363`). It even defines a *pixel
colour*, `CURSOR = 0xff00ff` (`term.rb:27`), inside the escape
interpreter. The interpreter cannot currently be instantiated without a
rendering adapter.

**A4 — there is no backend abstraction, only a pixel adapter.**
`WindowAdapter` and the harness's `VirtualWindow` both target the *same*
pixel interface (`fillrect`, `copy_area`, glyph `draw`,
`char_w`/`char_h`). There is **no** "render this buffer as escape
sequences" seam anywhere — the single thing you most want (a text
backend) has nothing to plug into. And the adapter that *is* there isn't
even the sole renderer: `RubyTerm#redraw` clears the window directly
(`termtest.rb:119`), and `TrackChanges` paints directly. `WindowAdapter`'s
header claims *"nothing should talk to the window directly"*
(`windowadapter.rb:8-11`) — three things do.

**A5 — `WindowAdapter` mixes geometry, rendering, and colour policy.**
Cell↔pixel scaling, scroll-blit geometry, glyph drawing, *and* colour
`dim`/`brighten` (`windowadapter.rb:41-48`) live together. The scroll
*math* (the IL/DL geometry I just fixed) lives here in **pixel units** —
that's backend-specific knowledge that belongs either in the Screen (as
a cell-space operation) or in each backend, not in a shared adapter.

### B. The damage / render model is muddled and pixel-biased

**B1 — damage is consumed eagerly by the pixel path.** `TrackChanges#set`
(`:72-81`) mutates the buffer **and** immediately paints **and** records
`@changes`, all at once. There is no clean "compute damage, then let a
backend decide how to realise it" step. An economic text backend needs
exactly that damage list to emit minimal escapes; here it's spent on the
spot by the X11 path and `@changes` is nearly vestigial.

**B2 — two redraw philosophies that can disagree.** Incremental
(`draw_buffered` per cell) vs. full (`redraw_all`,
`trackchanges.rb:104-107`; `RubyTerm#redraw` clears the whole window and
repaints, `termtest.rb:116-133`). They can and do diverge — the harness
has a dedicated `redraw` check *because* of this, and the IL/DL bug I
just fixed was exactly an incremental-vs-full split. That class of bug is
structural: it exists because "what changed" is not single-sourced.

**B3 — cursor and selection are pixel overlays bolted onto the Host.**
`RubyTerm#reapply_selection`/`render_selection` (`termtest.rb:388-440`)
re-stamp the highlight in pixels after every draw, and the cursor is
drawn by `Term#draw_cursor` poking the buffer with the `CURSOR` colour.
The code's own `FIXME` (`termtest.rb:399-400`) has the right idea —
*"Cursor, selection etc. are 'special' overlays on top of attributes.
Allow the terminal to set a set of positions + fg/bg, and a set of
ranges."* — but it isn't built, so only the X11 path renders them.

### C. Orchestration & threading are in the wrong place

**C1 — `RubyTerm` is a god object** (586 lines): X11 windowing + pty +
four threads + queue serialisation + selection + scrollback UI + mouse +
DECCOLM policy + blink + font zoom + config. "Frontend", "platform", and
"app glue" are fused. *Chopping off the frontend* currently means
disentangling all of this by hand.

**C2 — the core is thread-unsafe by design, and the discipline leaks.**
`termtest.rb:210-217` documents that the buffer is not thread-safe and
that everything must funnel through `@queue`. That's a reasonable Host
choice — but it's baked into the core's usage, so no other app can use
the buffer without adopting rterm's exact threading model. A reusable
core must be synchronous (feed → mutate → flush), with threading left to
the Host.

### D. Data-model issues

**D1 — the cell is a bare 4-element `Array` `[ch, fg, bg, flags]`** with
the char as an ordinal `Integer`, and colours stored *inconsistently* —
sometimes a `String` palette index (`"7"`), sometimes a packed `Int`,
resolved only at draw time by `Term#fg`/`#bg` (`term.rb:253-254`). There
is no `Cell` type, so there's nowhere to hang per-cell width
(double-width is currently a whole-*line* attribute), no invariants, and
a persistent `nil` vs `[]` vs `[32,…]` ambiguity for "empty cell" that
several `draw_buffered` `FIXME`s dance around
(`trackchanges.rb:186-224`).

**D2 — three near-duplicate scrollback index mappings.**
`ScrBuf#line_at` (`termbuffer.rb:48-54`), `TermBuffer#get`
(`:186-193`), and `TermBuffer#getline` (`:194-201`) each re-implement
"negative row → scrollback" slightly differently. One belongs on one
object.

**D3 — debug prints in production code, against your own rule.**
`ScrBuf#enforce_height` does `p [:enforce_height, …]` /
`p [:enforce_height_no_h]` (`termbuffer.rb:151,155`), and
`TrackChanges#method_missing` does `p [:TRACK, …]`. `CLAUDE.md` says
*"Production code (`lib/`) must stay free of debug hooks."* These are
live violations.

### E. Smaller smells

- Stale `~` editor-backup files litter `lib/` (`term.rb~`,
  `trackchanges.rb~`, …) — untracked (already `.gitignore`d) but noise on
  disk and a source of "which is real?" confusion when grepping.
- `erase_in_display`'s `when 3` has `FIXME: Not in VT100. Where is this
  from?` (`term.rb:162`) — interpreter behaviour nobody is sure of.
- `RubyTerm#redraw` unconditionally clears the entire window every
  repaint (`termtest.rb:117-119`) — fine for X11 double-buffer, fatal
  for an economic text backend (it'd repaint the world). Another symptom
  of "full redraw" not being a damage concept.

None of this is unusual for code mid-untangle. But it means the layer
boundaries you want are currently *aspirational comments*, not
interfaces.

---

## 4. What the layering is trying to become

Read charitably, the existing `FIXME`s already sketch the target:

- `Term`'s header wants the interpreter to *"function with just a buffer
  with damage tracking so that it is possible to use it to render either
  to a terminal … or to an X11 window"* and to eventually be assignable
  to `$stdout`/`$stdin`.
- `TrackChanges`'s header wants the buffer to *"batch up updates to an
  output adapter (the window, but could be a terminal…)"*.
- `RubyTerm`'s `FIXME` wants cursor/selection to be **overlay** concepts,
  not pixel hacks.

So the intended shape is already in your head and half-written in the
comments. The job is to *make the seams real* and pick one buffer.

---

## 5. `ansiterm` / `re` as the alternative foundation

`re` renders to an `AnsiTerm::Buffer` and computes minimal escape
sequences to update the terminal, à la Emacs. That economic renderer is
the prize. But as a **foundation** for both projects, the gem is not
ready, and shouldn't be adopted wholesale:

**The genuinely valuable kernel (keep this):**
- `AnsiTerm::String#to_str` (`string.rb:18-32`) — serialise a styled row
  emitting an SGR only when the attribute changes.
- `AnsiTerm::Attr#transition_to` (`attr.rb:80-104`) — minimal SGR delta
  between two attributes, collapsing to `\e[0m` on reset.
- `AnsiTerm::Buffer#to_s` (`buffer.rb:81-117`) — per-row diff against a
  cache; emit `CUP` + row + `EL` only for changed rows.

This trio *is* an economic text backend. It's small, and it's the right
idea.

**Why it is not a foundation as-is:**
- **Immature buffer.** `Buffer#print` doesn't wrap; there's no
  cursor/scroll-region semantics; `scroll_up` ignores regions
  (`buffer.rb:73-79`). `@cache = Array.new { AnsiTerm::String.new }`
  (`buffer.rb:24`) is an outright **bug** — `Array.new` with a block
  needs a size; this yields an empty array and the block is never called
  (it "works" only because `@cache[y]` is `nil` anyway).
- **Bug in the diff kernel.** `Attr#transition_to` compares
  `other.bgcol != self.fgcol` (`attr.rb:83`) — background against
  *foreground*. It happens not to bite `re`'s usage.
- **Editor-shaped data model.** A row is a `String` + a parallel
  `@attrs` array of `Attr` flyweights, and construction *parses ANSI*
  (`string.rb:parse`). That's memory-efficient for sparsely-styled text
  and serialises naturally — but it's the wrong shape for a terminal's
  hot path: single-cell random writes, mid-line insert/delete, per-cell
  double-width, and high-frequency mutation all fight the
  string+parallel-array representation, and re-parsing ANSI on
  construction is pure overhead for a terminal.
- **No escape interpretation.** The thing rterm is best at, `ansiterm`
  explicitly punts on.
- **Never profiled, never used outside `re`** (your own note). So it
  carries no battle-tested guarantee either.

**Verdict.** A terminal *is* a 2-D grid with random column access, per-
cell width, insert/delete, scroll regions and scrollback; the **cell
grid is the correct canonical model**, and rterm already has it (plus
the interpreter and the harness that guards it). `ansiterm`'s
string+attrs is best understood as a *serialisation view*, not the
store. Therefore: **converge on rterm's grid + `Term`, and port
`ansiterm`'s diff kernel into a backend that consumes that grid's
damage.** Direction of travel: *`re` migrates onto rterm's core; the one
great part of `ansiterm` survives as `AnsiBackend`.*

The counter-option — adopt `AnsiTerm::Buffer` and rebuild the
interpreter and grid semantics on top — throws away the largest, best-
tested asset (the `Term` interpreter and its ratcheted test suite) to
keep the *smaller*, *less* mature one. Not worth it.

---

## 6. Target architecture

Five layers, each a real interface. Bottom to top:

```
L0  storage + Attr        canonical store = columnar parallel arrays of packed
                          immediates per row (codepoints + style words), NOT an
                          array of cell objects — see §8. Attr/Style = an immutable
                          flyweight materialised from a style word only at the render
                          boundary. A transient `Cell` value is an inspection view,
                          never the backing store. No behaviour, no pixels.

L1  Screen  (the keystone)  the virtual buffer:
                          grid of Cells + cursor + scroll region + scrollback +
                          line attrs + overlays (cursor, selection) + DAMAGE log.
                          Exposes the OPERATION API (§6.1). Knows nothing about
                          pixels, escape bytes, X11, or threads.

L2  Backend (the other keystone)  a protocol (§6.2). Consumes Screen damage
                          (or a full snapshot) and realises it:
                            • X11Backend     cells → pixels (today's Window+adapter, slimmed)
                            • AnsiBackend    cells → minimal escapes (ansiterm kernel, ported)
                            • BitmapBackend  cells → RGBA buffer (new; headless visual tests)
                            • VirtualBackend harness (today's VirtualWindow, re-cast)

L3a Interpreter (Term)    bytes → L1 operations. OPTIONAL. Emulators & multiplexers use it;
                          a TUI app does not. No backend dependency.

L3b TUI API               thin facade over L1 (op API) + input events. The "chop off the
                          frontend" deliverable that `re` and other apps consume.

L4  Host / App            wires {input source} + {backend} + {interpreter | app logic} +
                          threading.
                            • rterm emulator: X11 input + pty + Term + X11Backend
                            • re            : keyboard + app logic + AnsiBackend(→ terminal)
                            • harness       : input bytes + Term + VirtualBackend
```

The two interfaces that matter are L1's op API and the L2 protocol.

### 6.1 The `Screen` operation API (sketch)

This is just the set of methods `Term` already calls on `@buffer`, made
explicit and pixel-free, plus the overlay/damage additions:

```ruby
class Screen
  # construction / sizing
  def initialize(cols, rows); end
  def resize(cols, rows); end
  attr_reader :cols, :rows, :cursor   # cursor = [x, y]

  # cursor / regions / line attrs (cell-space, no pixels)
  def move_cursor(x, y); end
  def scroll_region=(top..bottom); end
  def line_attr=(attr);  end          # DECDWL/DECDHL etc. for cursor row

  # content
  def put(ch, attr);     end          # write at cursor, advance (handles wrap if asked)
  def insert(n, attr);   end          # ICH / IRM
  def delete_chars(n);   end          # DCH
  def erase(:to_eol | :to_bol | :line | :below | :above | :screen); end

  # line ops, in CELL space (the IL/DL geometry lives here, once)
  def insert_lines(n);   end          # IL
  def delete_lines(n);   end          # DL
  def scroll(n);         end          # +n up / -n down, within region; pushes to scrollback

  # overlays (every backend renders these — kills the pixel hacks)
  def cursor_overlay(visible:, style:); end
  def set_selection(ranges, fg:, bg:); end

  # damage & inspection (what backends consume)
  def damage;   end                   # since last flush: dirty cells, scroll ops, resize
  def snapshot; end                   # full styled grid (for full repaint / oracle)
  def mark_all_dirty; end             # "full redraw" == this, not a special path
end
```

`Term` becomes a pure function of bytes → these calls. Note
`insert_lines`/`delete_lines`/`scroll` are **cell-space** here; the
pixel/escape geometry moves into the backends.

### 6.2 The `Backend` protocol (sketch)

```ruby
module Backend
  # Realise one flush worth of damage. The Screen drives this.
  def begin_frame(screen); end
  def draw_run(x, y, cells, attr); end       # a run of same-attr cells
  def clear_cells(x, y, w, h); end
  def scroll(region, n);       end           # rows region scrolled by n; backend picks how
  def set_cursor(x, y, style); end
  def end_frame; end                          # X11: copy_area; Ansi: return the byte string

  # capabilities the Host/Screen may query
  def cell_metrics; end                       # pixel backends: {char_w:, char_h:}; text: nil
  def size;         end                       # text backends: terminal winsize
end
```

Three concrete backends prove the protocol is real:

- **`X11Backend`** = today's `Window` + the *rendering* half of
  `WindowAdapter`, slimmed to the protocol. `scroll` → `copy_area`;
  `draw_run` → `fillrect` + glyph; `end_frame` → buffer copy.
- **`AnsiBackend`** = `ansiterm`'s kernel, re-homed to consume `Screen`
  damage instead of rebuilding/diffing whole rows. `draw_run` →
  `CUP` + `Attr#transition_to` + chars; `scroll` → `\e[r` + `IND`/`RI`
  or `IL`/`DL`; `end_frame` → the accumulated byte string. This is the
  Emacs-style backend, now damage-driven (faster than `ansiterm`'s
  full-row recompare — see §8).
- **`BitmapBackend`** = `draw_run`/`scroll`/`clear` into an RGBA array.
  Gives headless visual testing with no X11/Xvfb, and proves the
  protocol isn't secretly X11-shaped.

### 6.3 Design decisions worth stating explicitly

1. **Damage is first-class and single-sourced.** `Screen` records dirty
   cells + scroll ops; backends *pull* and realise them; "full redraw" is
   `mark_all_dirty`. This deletes the incremental-vs-full divergence bug
   *class*, not just the instances.
2. **Backends are sinks, not the model.** Only `Screen` talks to a
   backend, only via the protocol (+ capability queries). No more
   `Term`/`Host` reaching past the adapter to the window.
3. **Scroll/IL/DL are semantic cell ops.** The geometry math (today's
   pixel `scroll_up`/`insert_lines`) lives once in `Screen` in cell
   space; each backend translates `scroll(region, n)` to its medium
   (`copy_area` / region-scroll escapes / `memmove`).
4. **Cursor & selection are overlays in `Screen`.** Every backend renders
   them; the `RubyTerm` re-stamping hackery disappears.
5. **Threading is the Host's job.** The core is synchronous: feed →
   mutate → `flush(backend)`. rterm keeps its queue/threads in L4; `re`
   keeps its loop; neither leaks into L1–L3.
6. **Capabilities flow from the backend up.** Pixel backends expose
   `cell_metrics`; text backends expose `size`. The Host asks the
   *backend*, fixing both the `Term.char_w`-asks-the-adapter leak and
   `re`'s `View`-reaches-for-`winsize` leak symmetrically.

### 6.4 How this delivers the stated dreams

- *"Replace the X11 backend without touching other code"* → swap the L2
  implementation; L1/L3 untouched.
- *"A text backend that renders economically like Emacs"* → `AnsiBackend`.
- *"A bitmap backend"* → `BitmapBackend`.
- *"Chop off the terminal frontend; let Ruby TUI apps render to a
  terminal **or** an X11 window via escapes **or** a high-level API"* →
  the app builds a `Screen` through the L3b op API and picks
  `AnsiBackend` (→ terminal) or `X11Backend` (→ window). **Same app
  code.** `re` becomes the first such app.

---

## 7. Migration plan (incremental, harness-guarded)

The ratchet sweep is the safety net: **every step keeps it green.** This
is a sequence of independently-valuable refactors, not a big-bang
rewrite. Stop points are marked — partial adoption still pays off.

### Phase 0 — Hygiene (hours, ~zero risk)
- Delete the stale untracked `~` editor backups from `lib/`.
- Remove the always-firing `p` debug prints from `lib/`
  (`enforce_height`, `method_missing`, `$saved`, `p :flush`, the keymap
  and mouse-report prints) — your own `CLAUDE.md` forbids debug hooks in
  `lib/`. Leave the diagnostic `p @esc` "unhandled sequence" logs for now;
  fold them into an injected logger later (they don't fire on the hot
  path).
- *(Deferred to Phase 1)* Replace `TrackChanges#method_missing` with an
  explicit delegation list once the call inventory (the coupling map)
  makes the forwarded surface known — doing it blind risks missing a
  load-bearing forward (e.g. `scroll_start=`, `insert`, `delete_chars`,
  `set_lineattrs` all currently route through it).

### Phase 1 — Name the seams + stand up the benchmark (low risk)
- **Add the performance benchmark to the testing tools** (§8), measuring
  *both* axes: (a) throughput — bytes/sec, allocations-per-byte, live
  object count draining a large file through `Term`; (b) input latency —
  time-from-Ctrl-C-to-quiescence under a sustained flood. This is
  additive tooling (no behaviour change) and **must exist before Phase 2**
  so the rewrite has a regression baseline. Record a baseline snapshot.
- Write down the **Backend protocol** (§6.2) as a module/duck-type doc;
  have `WindowAdapter` and `VirtualWindow` declare they implement it.
- Write down the **Screen op API** (§6.1) as the methods `Term` calls.
- Produce the coupling map: every `Term`→`@adapter` call and every
  `RubyTerm`/`TrackChanges`→`@window` call. (No behaviour change.)
> **Value if you stop here:** the boundaries are documented and testable,
> and performance is measured (a prerequisite for everything after).

### Phase 2 — Collapse the buffer trio into one `Screen` (the big step)

> **Sequencing note (discovered during execution).** The harness's
> markers check tracks per-cell generations by **cell-array object
> identity** (`patches.rb` `compare_by_identity`), relying on cells being
> persistent objects that physically move through the buffer. Columnar
> storage of the **live grid** removes those objects, so it *forces a
> redesign of the harness gen-tracking* — which is really the damage-model
> work of Phase 3. The gen-tracking only ever covers the live screen,
> never scrollback. So Phase 2 splits:
>
> - **2a — scrollback compaction (done).** Scrollback (unbounded, the
>   dominant *retained-object* cost) now stores packed parallel arrays
>   instead of object-per-cell. Safe: it never touches the live grid or
>   gen-tracking. Result vs baseline: live objects retained −83% (5.8×),
>   GC time −50%, alloc/KB flat. Ratchet + tests green.
> - **2b — live-grid columnar + native damage generation (done).** The
>   live grid is now columnar parallel arrays of immediates, and
>   `TermBuffer#generation_at` is a native per-cell generation (the damage
>   primitive). The harness markers check reads it instead of the old
>   identity hash (`patches.rb`). Cumulative result vs baseline: alloc/KB
>   −15% (6484→5477, with the draw path still reconstructing cells via
>   `get` — see below), GC time −57%, live retained −86%. Ratchet + tests
>   green.
> - **Draw-batch made columnar-aware (done).** `TrackChanges#draw_buffered`
>   now skips identical repaints via `TermBuffer#cell_eq?`/`#unset?`
>   instead of reconstructing a cell Array per char, and the dead
>   write-only `@changes`/`@scroll` damage sets were removed. Cumulative
>   Phase 2 result vs baseline: **throughput +59%**, alloc/KB −47%
>   (6484→3433), GC time −84%, live retained −90%. Ratchet + tests green.
> - **Per-char cell-arg Array dropped (done).** `TrackChanges#set` reuses
>   a per-instance scratch cell instead of allocating `[c,fg,bg,mode]` per
>   character (draw_buffered reads it synchronously and never retains it).
>   Cumulative alloc/KB now **−63%** vs baseline (6484 → 2426).
> - **Damage-driven flush (done).** Mutation is decoupled from rendering:
>   in `defer` mode `TrackChanges#set` only mutates, and `draw_flush` walks
>   the buffer's damage (`TermBuffer#each_damaged`, gated by row-level
>   dirty tracking) and draws the changed cells. This is now the live
>   default in both the terminal (termtest.rb) and the harness. Built and
>   proven equivalent first (`test_damage.rb` compares eager vs deferred
>   via the AnsiBackend round-trip), then flipped; the markers/redraw/state
>   ratchet passes on the deferred path, perf is neutral (dirty-row
>   tracking keeps `each_damaged` from walking the whole grid), and a live
>   Xvfb render confirms the X11 path. The run-batcher stays shared in
>   `TrackChanges` (its same-attr runs suit both the X11 and Ansi backends),
>   rather than being pushed into each backend.
> - **Still open:** interpreter-side per-char allocs (UTF8Decoder/
>   EscapeParser) — Phase 8.

- Merge `TermBuffer` + `ScrBuf` + the *model-mutation* half of
  `TrackChanges` into a single `Screen` backed by columnar parallel
  arrays of packed immediates (§8) — not an array-of-cell-objects, and
  *not* a naïve "make `Cell` a class" refactor (that worsens the GC
  profile). Resolve palette colours to the packed style word at SGR-parse
  time (§8.5). Unify the three scrollback mappings (D2) into one.
- Move the run-batching `draw_buffered`/`draw_flush` *out* of the buffer
  and into the `X11Backend` — it's a pixel-draw optimisation, not a model
  concern.
- Keep the op API identical so `Term` doesn't change. Do it behind the
  harness; the ratchet stays green throughout.
- **Performance goal for this phase is *no major regression* vs the
  Phase 1 baseline on both axes — not improvement.** The columnar store
  (§8.3) should already help allocations-per-byte and object count, but
  don't chase it here; if the benchmark shows the rewrite held the line
  (or improved incidentally), that's success. Real optimisation is
  Phase 8. Run the benchmark as a gate alongside the ratchet.

### Phase 3 — Make damage first-class; backends pull it
- `Screen` records damage; `flush(backend)` walks it → protocol calls.
  Remove eager draw-on-set. "Full redraw" = `mark_all_dirty`.
- Re-express scroll/IL/DL as cell-space damage ops; move the pixel
  geometry into `X11Backend` (this is where my recent `WindowAdapter`
  fix migrates). The harness `redraw`/`markers` checks now guard the new
  damage path directly.
> **Value if you stop here:** rterm is cleanly Screen + Backend; the
> divergence bug class is gone; the adapter is a real backend.

### Phase 4 — Cut `Term`'s adapter coupling (done, minus the cursor overlay)
- **Done.** `Term` no longer references `@adapter` at all and constructs
  with **only a buffer** (`Term.new(buffer)`). The scroll blit +
  scrolled-back handling moved into `TrackChanges#scroll_up`;
  `set_columns`/`scrollback_mode` now route through the buffer
  (`@buffer.set_columns`/`@buffer.scrollback_mode`); the redundant
  `@adapter.clear` and the `char_w`/`char_h` delegation (only used for an
  initial size guess) were removed. Ratchet + tests green.
- **Cursor overlay (done).** The `CURSOR` pixel constant and the cursor
  drawing moved out of `Term` into `TrackChanges` (`#draw_cursor`/
  `#clear_cursor`): the interpreter now just *reports* the cursor position
  and visibility, and the buffer renders the overlay. Harness-safe because
  the framebuffer output is byte-identical (the cursor is still a
  CURSOR-background cell, just painted from the buffer) - ratchet + tests
  green. `Term` now carries no pixel/colour constants and no rendering at
  all. (The AnsiBackend still recognises the CURSOR-background cell; making
  the cursor style a per-backend choice is a possible later refinement.)
  DECCOLM policy (font rescale on `reset`) remains a separate TODO.

### Phase 5 — Write `AnsiBackend` (done, ahead of Phase 3)
**Done** (`lib/ansibackend.rb`), and deliberately landed *before* the
damage-driven flush: the existing run-batcher already emits a usable
damage stream (changed runs + scroll/clear ops), so `AnsiBackend` is a
drop-in for `WindowAdapter` that turns those same calls into minimal
escapes (CUP + SGR-delta + text, scroll-region escapes, EL). The same
`Term` core now renders to a terminal or an X11 window depending only on
the backend.
- Validated by the metamorphic round-trip oracle (`test_ansibackend.rb`):
  `Term → AnsiBackend → escapes → Term' → identical screen`, no external
  oracle. Plus a terminal-in-a-terminal demo
  (`examples/terminal_in_terminal.rb`) confirmed live in tmux, and
  **`re` (a full TUI editor) runs correctly inside it**.
- This round-trip oracle is now the second deterministic check the
  *damage-driven flush* (remaining Phase 3) can be built against: assert
  the damage-driven escapes stay identical to the eager ones before
  flipping the live `set` path.
> **The backend seam is proven real.** The Emacs-style economic text
> backend the project set out to build exists and renders real apps.

### Phase 6 — Extract Host/App seam; migrate `re`
- Pull X11 + pty + threads + selection/scrollback UI out of the core into
  an `RubyTerm` Host that wires {X11 input, pty, `Term`, `X11Backend`}.
- Define the **L3b TUI API** facade (op API + input events).
- Migrate `re` onto `Screen` + `AnsiBackend` via that facade; keep
  `ansiterm` until `re` is happy. This validates "chop off the frontend"
  and gives `re` the (optional) full interpreter and a profiled buffer.

### Phase 7 — Third backend + cleanup
- **`BitmapWindow` (done).** A third implementation of the Window drawing
  interface (after the X11 `Window` and the harness `VirtualWindow`):
  it rasterises real glyphs with skrift and composites them into an
  in-memory RGB buffer. Wrapped by `WindowAdapter` it is a full bitmap
  backend — the same `Term` core rendered to a pixel buffer with no X
  server. Reuses all of `WindowAdapter`'s cell→pixel + scroll geometry, so
  only the pixel ops + glyph blend are new (~150 lines). Proves the seam
  is backend-agnostic and gives **X11-free visual testing** (`#save_png`).
  Tested (`test_bitmapwindow.rb`): glyphs land in the right cells, fg
  colour, clear, and scroll all verified against the pixel buffer.
- Still: delete remaining dead code / leftover names as they surface.

### Phase 8 — Performance (optimise against the baseline, now that it's safe)
Deferred to the end on purpose: by here the data model is columnar, the
backend seam is clean, and the Phase 1 benchmark + ratchet can prove each
change helps without breaking correctness. Now go after the numbers on
both axes:
- **Throughput / the "accidental `cat` of a multi-MB file".** Profile the
  hot path (`stackprof`/`memory_profiler`); confirm the columnar store
  eliminated the per-cell allocation; cache SGR transitions (§8.6). Then,
  if needed, the *acceptable cheats*: **jump-scrolling** (coalesce/skip
  rendering intermediate frames the user never sees), batch larger input
  chunks, drop redundant intra-frame redraws. These are legitimate here
  because they're measured and bounded — not guessed at earlier.
- **Input latency / Ctrl-C responsiveness.** Tune the
  read→interpret→flush granularity so a flood can't starve input: bound
  the work committed between input checks, and don't let an unflushed
  backlog build (which both delays the screen and delays noticing the
  interrupt). Watch the tension with jump-scrolling — skipping frames is
  good for axis (a) only if it *shrinks* the backlog, not if it lets it
  grow.
- Re-run the benchmark; record the delta against the Phase 1 baseline.
> **Value:** the user-visible wins (fast `cat`, instant Ctrl-C) land on a
> codebase that can prove they didn't cost correctness.

> **Progress — jump-scrolling (DONE, throughput axis).** The damage model
> made the "acceptable cheat" clean: `TrackChanges#suspend` suppresses all
> rendering (the buffer + scrollback still mutate) so a flood is interpreted
> across many chunks and then painted with ONE full redraw of the final
> screen. Wired into `RubyTerm#process_chunk`: when the input queue backs up
> past `JUMP_BACKLOG`, suspend per-chunk rendering and let the screen catch
> up at the 30fps flush tick or when the queue drains; every exit from a
> suspended run is a *full* redraw (suspended scrolls skip their blits, so
> only `redraw_all` can reconstruct the screen).
>   - Correctness validated three ways: byte-identical framebuffer on a real
>     backend (`test_bitmapwindow` jump vs incremental); a deterministic
>     replay of the exact `process_chunk` control flow matching a
>     pure-incremental reference; and a live `cat` flood under a headless X
>     server converging to the exact final screen via `dump_state`.
>   - **Throughput: ~1100× on a glyph-rasterising backend** (150 KB scrolling
>     flood through `BitmapWindow`: 760 s incremental → 0.69 s jump-scrolled
>     — it renders the final 24 rows once instead of rasterising thousands of
>     scrolled-off lines). On X11 (cheap CopyArea blits) the win is smaller;
>     the larger lever there is the **time-to-stop** axis below.
>   - Opt-in (suspend defaults off): ratchet clean (55, 0 regressions),
>     `rake test` green (95).
>
> **Measured — Ctrl-C / time-to-stop axis (live pty + threads, headless X).**
> Traced the input backlog and flood consume-rate on the real terminal (via
> a `queue_size` probe on the debug socket and flood-progress sampling).
> Findings:
>   - **The input queue does NOT grow unboundedly.** During a 1.6 MB `cat`
>     flood `@queue` stayed at 0–2 (peak 9). The kernel pty buffer flow-
>     controls the source: `cat` blocks once the ~64 KB pty buffer fills, so
>     the post-Ctrl-C backlog is bounded (~64 KB) by the OS, not by us.
>     **Explicit Ruby-side backpressure is therefore unnecessary** — the
>     earlier "bound `@queue`" idea was solving a non-problem.
>   - **On X11, jump-scrolling is ~neutral for a `cat` flood.** Flood
>     duration was ~18 s for 1.6 MB whether jump-scroll was off, default
>     (JB=8, which barely engages since the queue never backs up), or
>     forced aggressive (JB=1: 18.6 s). Because the slow consumer paces the
>     producer, the queue never backs up, and — more fundamentally —
>     rendering is not the X11 bottleneck.
>   - **Interpretation is the throughput ceiling, not rendering.** The
>     `null` benchmark sink (interpret + buffer + draw-batch, *zero*
>     rendering) tops out at ~0.2 MB/s — the same order as the live X11
>     flood. So X11 time-to-stop ≈ bounded_backlog / interpret_rate ≈
>     64 KB / 0.2 MB/s ≈ 0.3 s, and is governed by the **interpreter**
>     (`Term#feed`, the escape/UTF-8 parsers, `TermBuffer#set`), not the
>     renderer.
>
> **Conclusion / next lever.** Jump-scrolling's payoff is real but specific:
> backends where *rendering* dominates (the glyph rasteriser: ~1100×). For
> X11 throughput AND time-to-stop the remaining lever is the **interpreter
> hot path** — profile it (`stackprof`) and attack the ~0.2 MB/s ceiling
> (per-byte parser dispatch, UTF-8 decode, `set` packing). That is the
> natural continuation of this axis.

**Sequencing note.** Phases 2–4 deliver rterm value without touching
`re`. Phase 5 delivers the text backend. Phase 6 is the `re` payoff.
Phase 8's optimisations apply whether or not `re` migrated. The benchmark
(Phase 1) and the no-regression bar (Phase 2) mean performance is watched
from the start even though it's *improved* only at the end. You can pause
at any phase boundary with a coherent, green codebase.

---

## 8. Performance — Ruby's object model *is* the design constraint

Neither buffer is profiled, so everything here is a hypothesis to verify,
not a justification to skip benchmarking. But Ruby's representation rules
are predictable enough that they should *shape* the data model up front —
getting the storage layout wrong is expensive to undo after `Term`, the
backends, and `re` all depend on it.

**First, add the benchmark to the testing tools (before Phase 2 — see
§7).** It must measure two distinct axes, because they trade off against
each other and the data model affects both:

- **(a) Throughput — raw bytes → screen.** Drain a large `cat`/build-log
  through `Term`; record bytes/sec, and via `GC.stat` /
  `ObjectSpace.count_objects` / `allocation_tracer`/`memory_profiler`,
  **allocations-per-byte** and **live object count**. The user-facing
  proxy is *"how long until the `cat` finishes."*
- **(b) Input latency — reaction time under load.** While a flood is
  draining, how quickly does the terminal react to the user? The acid
  test is **Ctrl-C: when the user interrupts, how immediately does output
  stop?** That depends on how big a chunk the processing loop commits to
  between checks for new input, and on not having a deep unflushed
  backlog — i.e. it's a *scheduling/granularity* property, separate from
  raw throughput. Measure time-from-signal-to-quiescence under a
  sustained flood.

Note these can be improved by *cheating*: for the `cat` case,
jump-scrolling (skip rendering intermediate frames the user will never
see) and similar shortcuts are an acceptable hack — but that is a
**post-benchmark** optimisation (Phase 8), never a premature one, and it
trades against axis (b) if it lets the backlog grow. Establish the
baseline first; optimise against numbers, not intuition.

Then design the storage to the following Ruby facts.

### 8.1 The facts that matter

- **Tagged immediates allocate nothing and compare by identity.**
  `Integer` in the fixnum range (62-bit magnitude on 64-bit CRuby),
  `Symbol`, `nil`/`true`/`false`, and (large-range) `Float` are stored
  *in* the `VALUE` word — no heap object, never GC-marked, `==` is a
  pointer compare. Codepoints, packed style words, and `:dbl_single`-style
  line attrs are all immediates.
- **Strings are one object over a raw byte buffer.** An N-char String is
  *one* allocation; in-place mutation (`<<`, `[]=`, `setbyte`) doesn't
  allocate per char. But indexing the i-th *character* of a UTF-8 String
  is O(i) (codepoint walk over bytes), so a String is a poor random-access
  grid row.
- **Every Array/Hash/object is a heap allocation** (~40 B header + buffer)
  that GC must mark while live and collect when dead. Object *count*
  drives mark time; allocation *rate* drives collection frequency.

### 8.2 The single biggest issue: a heap object per cell write

rterm's hot path allocates. `TermBuffer#set` does
`@scrbuf[y][x] = [ch.ord, fg, bg, flags]` (`termbuffer.rb:285`) — a fresh
4-element Array **per glyph printed**. Draining a megabyte ≈ ~10⁶ Array
allocations, each becoming garbage as the cell is overwritten. The
*contents* are already optimal (codepoint and flags are immediates — the
existing codepoint-as-`ord` choice is correct); it's the per-cell Array
*wrapper* that is pure waste. Scrollback turns this from churn into a
standing cost: object-per-cell means an N-line history holds ~`80·N`
live Array objects (a 100k-line scrollback ≈ 8M objects GC must mark on
every cycle).

### 8.3 Recommended storage: columnar, packed, allocation-free on write

Store each row as **two parallel Arrays of immediates**, not an array of
cell objects:

```
row.chars  = [Integer codepoint, …]   # 1 Array object; elements are immediates
row.style  = [Integer style_word, …]  # 1 Array object; elements are immediates
```

Pack `fg(24) + bg(24) + flags + a few palette/default sentinel bits`
into one **style word** that fits the 62-bit fixnum range (24+24+~12 = 60
< 62). Consequences, all favourable:

- **Per-cell write allocates nothing:** `chars[x] = cp; style[x] = sw`
  stores two immediates into existing Array slots. The ~10⁶-allocations-
  per-MB cost disappears.
- **Live object count collapses:** a row is ~2 objects regardless of
  width; an 80×24 screen ≈ 48 objects vs ~1944 today; a 100k-line
  scrollback ≈ 200k objects vs ~8M. GC mark time drops by orders of
  magnitude.
- **Damage detection gets cheaper:** "did this cell change?" is two
  fixnum `==` (pointer compares), not `Array#==` element-iteration (which
  is what `draw_buffered` does today, `trackchanges.rb:197`).
- **A packed style word *is* the flyweight.** Equal styles are
  automatically identity-equal as fixnums — you get `ansiterm`'s
  "identity comparison instead of field comparison" goal for free, with
  no pool and no custom `==`.

Prefer Array-of-fixnums over a `pack`ed binary `String` for the live
grid: both are zero-alloc on write, but the Array keeps O(1) integer
slots and avoids `unpack` arithmetic. (A `pack`ed/escape-encoded String
*per line* is, however, an excellent **scrollback** representation —
read-mostly, ~1 object/line, re-materialised only when scrolled into
view. A tiered model — columnar arrays for the live screen, packed
strings for history — is worth considering once the basics land.)

**If the common attributes don't fit 60 bits, tier the style word — do
not widen to a Bignum.** Reserve the style word for truecolor fg+bg +
the *common* flags (bold, inverse, the default-fg/bg sentinels), plus one
**`HAS_EXTRAS` bit**. Rare attributes — underline (and underline colour),
strikethrough, blink, hyperlink/OSC-8 IDs, anything else that needs more
bits — live in a **third, sparse array** consulted *only* when
`HAS_EXTRAS` is set. The payoff matches the actual frequency
distribution: the overwhelming majority of cells in real output carry
none of these, so the common path stays two arrays of immediates and
zero-alloc on write; the third array holds entries for the handful of
cells that need them (and can itself be a `Hash{col => extras}` per row,
or a parallel sparse array, so an unstyled row allocates nothing for it).
A cell's full attribute is then "style word, plus — iff `HAS_EXTRAS` —
the extras record." This keeps the hot path immediate-only while leaving
unlimited headroom for the long tail, and it cleanly answers the
"style-word budget" question: the budget is *only* the common case;
everything rare is out-of-band and pay-as-you-go.

### 8.4 The flyweight belongs at the render boundary, not in storage

This refines my earlier note (and *reverses* the "introduce a `Cell`
value type" idea): **do not make the stored cell an object.** Storage is
columnar immediates. Materialise a rich `Attr`/`Style` object — with
`bold?`, `transition_to`, resolved RGB — **lazily, only where the rich
API is needed**: the `AnsiBackend`'s SGR-transition computation and the
`X11Backend`'s colour/GC lookup. Pool those by style-word key so a frame
reuses one `Attr` per distinct style (a row has a handful of distinct
styles, not 80). This is exactly `ansiterm`'s flyweight win — kept,
but applied where it pays (the renderer touches O(styles) objects, not
O(cells)) instead of imposing an object per stored cell.

Inspection APIs (`Screen#snapshot`, selection extraction) may return
transient `Cell` value objects for ergonomics — but those are *views*
built on demand, never the backing store, and never created on the write
path.

### 8.5 Resolve once, at attribute-set time

rterm stores palette colours as **Strings** (`@fg = (c-30).to_s`,
`term.rb:277`) and resolves them to ints at *draw* time
(`Term#fg`/`#bg`, `:253-254`) — a per-draw allocation + branch, and a
type inconsistency (fg is sometimes a String, sometimes a packed Int).
Resolve to the packed style word **once**, when SGR is parsed, so the hot
write and the hot draw paths see only immediates. Keep the
default-fg/default-bg distinction as sentinel bits in the style word so
`AnsiBackend` can still emit `39`/`49` rather than an explicit colour.

### 8.6 Other allocation hot spots to watch

- **`AnsiBackend` must be damage-driven, not `ansiterm`'s
  rebuild-and-compare.** `Buffer#to_s` (`buffer.rb:81-117`) rebuilds every
  row's String and String-compares it to a cache *every flush* — fine at
  editor (per-keypress) frequency, pathological for a terminal draining
  megabytes. Consume `Screen` damage (changed runs only).
- **Precompute/cache SGR transitions.** `Attr#transition_to`
  (`attr.rb:80-104`) builds intermediate arrays and `flatten.join`s per
  transition. At terminal frequency, memoise the emitted SGR string keyed
  by `(from_style_word, to_style_word)` (or per style word from a
  normalised base) so a transition is a hash hit, not array surgery.
- **Batch runs at the backend, not the model.** The run-coalescing in
  `TrackChanges#draw_buffered` is sound; it belongs in `X11Backend`, and
  `AnsiBackend` wants the same shape (one SGR + a run of chars, not
  per-cell escapes). Run batching also amortises method-dispatch, which is
  not free in Ruby.
- **Symbols for line attrs are already optimal** (`:dbl_single` etc. are
  interned immediates) — keep them, or fold into style-word bits if you
  later want per-cell (not per-line) double-width.

### 8.7 Net effect on the assessment

None of this changes the layering in §6 — `Screen` (op API + damage),
`Backend` protocol, `Term`, host. It sharpens **L0/L1's representation**:
the canonical store is *columnar parallel arrays of packed immediates*,
not an array of `Cell`/`Attr` objects; the flyweight is a render-time
view keyed on the packed style word. That keeps the design Ruby-GC-
friendly on the two axes that hurt most — allocation rate on the write
path and live-object count under deep scrollback — both of which the
current array-per-cell model gets wrong, and which a naïve "make `Cell`
a class" refactor would make *worse*. Confirm with the §8 benchmark
before and after; treat allocations-per-byte and live-object-count as
first-class regression metrics alongside the ratchet.

---

## 9. Risks & honest caveats

- **Phase 2 is genuinely large** — it's the rewrite of the core data
  structure. The harness makes it *safe*, not *small*. Budget for it and
  do it in one focused sweep rather than dribbling.
- **`re` migration (Phase 6) may surface op-API gaps.** `re` does things
  a terminal doesn't (gutters, syntax spans, horizontal scroll). Expect
  to grow the `Screen`/`String`-style span API (`set_attr(range, attr)`,
  `merge_attr_below`) to satisfy it. Treat `re` as the acceptance test
  for the TUI API.
- **Scroll-region escape generation in `AnsiBackend` is fiddly** across
  real terminals; lean on the round-trip oracle (Phase 5) and a
  capability flag to fall back to full-line repaints where unsure (which
  is all `ansiterm` does today anyway).
- **Don't over-abstract L0/L2 up front.** Define the protocol from the
  three concrete backends you actually build; a protocol designed in the
  abstract will be subtly X11-shaped or subtly Ansi-shaped.

---

## 10. One-paragraph recommendation

Keep rterm's `Term` interpreter and its cell-grid as the spine; collapse
`TermBuffer`/`ScrBuf`/`TrackChanges` into one damage-tracking `Screen`
whose store is columnar parallel arrays of packed immediates (codepoints
+ style words — Ruby-GC-friendly, allocation-free on write, with the
flyweight kept as a render-time view, §8), behind a small, explicit
operation API; define a `Backend` protocol and slim the X11 path into one
implementation of it; port `ansiterm`'s minimal-SGR diff kernel into an
`AnsiBackend` so the same `Screen` can render economically to a terminal;
then lift X11/pty/threads/selection into a `RubyTerm` Host and migrate
`re` onto the `Screen` + `AnsiBackend` through a thin TUI facade.
`ansiterm` is the reference for the text backend, not the foundation; the
foundation is rterm's grid + interpreter, cleaned up. Do it in
harness-guarded phases, each green and each independently useful.
```
