# Layer seams — current surfaces & coupling map

*Phase 1 of the refactor (see `architecture-review.md`). This documents
the **current** de-facto interfaces between the layers and the places
they leak, so later phases have a concrete target. It describes what IS,
annotated with where it's going. No behaviour is changed by writing it
down. Regenerate the greps if the code moves.*

The eventual layering is: `Screen` (virtual buffer + op API + damage) →
`Backend` protocol → optional `Term` interpreter / TUI facade → Host.
Today three of those four boundaries exist only implicitly, and each
leaks. The three interfaces below are the implicit ones made explicit.

---

## 1. The Screen operation API (what `Term` calls on the buffer)

`Term` holds the buffer as `@buffer` (a `TrackChanges` wrapping a
`TermBuffer`). This is the set of methods it calls — i.e. the surface a
future `Screen` must provide to the interpreter. Pixel-free already;
this is the cleanest of the three seams.

**Mutation (content):**
- `set(x, y, ch, fg, bg, flags)` — write a cell
- `insert(x, y, n, cell)` — ICH / IRM open a gap
- `delete_chars(x, y, n)` — DCH
- `clear_line(y, from_x = 0, to_x = nil)` — EL / ED helpers
- `clear` — erase whole buffer

**Mutation (lines / scrolling):**
- `insert_lines(y, n, maxy)` — IL
- `delete_lines(y, n, maxy)` — DL
- `scroll_up` — region scroll (pushes to scrollback)
- `set_lineattrs(y, attr)` — DECDWL/DECDHL/DECSWL

**Region / geometry state:**
- `scroll_start`, `scroll_end` (getters) + `scroll_start=`, `scroll_end=`
  (setters) — DECSTBM margins
- `on_resize(w, h)`

**Query / read-only:**
- `lineattrs(y)`, `get(x, y)`, `scrollback_size`
- `each_character`, `each_character_between(spos, epos)`

**Render-side (today these live on the buffer; in the target they move to
the damage→backend path):**
- `redraw(x, y)`, `redraw_with(x, y, fg:, bg:)`,
  `redraw_cell_at(sx, sy, cell, fg:, bg:)`, `redraw_display(x, y, sb)`
- `redraw_all(scrollback_offset)`, `redraw_blink`, `draw_flush`

> **Target:** the first three groups become the `Screen` op API
> (§6.1 of the review). The "render-side" group dissolves: `Screen`
> records damage and a `Backend` realises it; `draw_flush` becomes
> `flush(backend)`, `redraw_all` becomes `mark_all_dirty`.

`TrackChanges`'s own surface is now explicit (Phase 0/1): it defines the
above (delegating model mutations to `TermBuffer`, forwarding draws to
`@adapter`), plus the seven explicit delegators that replaced
`method_missing` (`insert`, `delete_chars`, `set_lineattrs`,
`scroll_start=`, `scroll_end=`, `scrollback_size`,
`each_character_between`).

---

## 2. The Backend protocol (de-facto, from `WindowAdapter`)

`WindowAdapter` and the harness's `VirtualWindow`+adapter both implement
the same pixel sink. This is the *implicit* backend protocol — the thing
to formalise so `AnsiBackend`/`BitmapBackend` can be alternatives.

**Cell metrics (capability query):**
- `char_w`, `char_h`

**Content:**
- `draw(x, y, c, fg, bg, flags, lineattrs)` — paint a run of cells
- `draw_flag_lines(flags, x, y, len, fg)` — under/over/strike lines
- `clear`, `clear_area(x, y, w, h)`, `clear_cells(x, y, w, h)`,
  `clear_line(y, from_x, to_x = nil)`

**Scrolling (cell-region → medium-specific blit):**
- `scroll_up(scroll_start, scroll_end)`
- `insert_lines(y, n, maxy)`, `delete_lines(y, n, maxy)`

**DECCOLM / sizing:**
- `set_columns(cols)` — delegates to the Host (`RubyTerm#set_columns`)

**Scrollback coupling (does NOT belong in a backend — see leaks below):**
- `scrollback_mode`, `scrollback_anchor`

**Colour helpers (X11-specific; do not belong in the protocol):**
- `dim(col)`, `brighten(col, bg)` — should be backend-internal

> **Target:** §6.2 of the review. The protocol is `begin_frame /
> draw_run / clear_cells / scroll / set_cursor / end_frame` +
> `cell_metrics` / `size`. Note today's protocol is stated in **pixel/
> char units and X11 idioms** (colour helpers, `scrollback_mode`); the
> target is stated in **cell-space damage** so an Ansi or Bitmap backend
> can satisfy it. The scroll geometry currently computed in pixels inside
> `WindowAdapter#insert_lines`/`delete_lines` moves up into `Screen` as a
> cell-space op; the backend only receives "rows a..b moved by n".

---

## 3. Coupling map — where the layers leak

These are the exact cross-layer reaches the later phases remove. Counts
are call sites as of this writing.

### 3a. `Term` → `@adapter` — the interpreter's pixel coupling (Phase 4 removes)

`Term`'s own header says it *"should know nothing about X11 … and should
ideally not use the `@adapter`."* It does, here:

| `lib/term.rb` | call | why it leaks | target |
|---|---|---|---|
| 29–30 | `@adapter.char_w/char_h` | interpreter asking pixel metrics | Host/backend owns metrics |
| 133 | `@adapter.clear` (+ `scrollback_mode`) | erase routed to pixels | `Screen#erase` + damage |
| 220, 312, 319 | `@adapter.scrollback_mode` | interpreter gating on UI state | Screen/Host concern |
| 223 | `@adapter.scrollback_anchor` | UI viewport poke | Host |
| 227 | `@adapter.scroll_up(...)` | pixel scroll from interpreter | `Screen#scroll` damage |
| 366 | `@adapter.set_columns(w)` | DECCOLM → window policy | Host policy |
| 27 | `CURSOR = 0xff00ff` | a **pixel colour** in the interpreter | cursor overlay in `Screen` |

### 3b. `TrackChanges` → `@adapter` — buffer knows the backend + scrollback (Phases 2–3)

| `lib/trackchanges.rb` | call |
|---|---|
| 21, 57, 63, 69, 79, 106 | `@adapter.scrollback_mode` (policy gate inside the buffer) |
| 21 | `@adapter.clear` |
| 57 | `@adapter.delete_lines` |
| 63 | `@adapter.insert_lines` |
| 69 | `@adapter.clear_line` |
| 145/157 | `@adapter.draw` (the run-batched paint) |

> The buffer should not consult `scrollback_mode` at all, and should emit
> damage rather than call `@adapter.draw`/`delete_lines`/… directly. The
> `draw`-batching (`draw_buffered`) is a *backend* optimisation that
> Phase 2 moves into `X11Backend`.

### 3c. `RubyTerm` → `@window` — Host reaching past the backend (Phase 6 formalises)

`WindowAdapter`'s header claims *"nothing should talk to the window
directly"*; `RubyTerm` does, at ~30 sites. By concern:

- **Scrollback UI:** `scrollback_count` (5), `scrollback_mode` (2),
  `scrollback_reset`, `scrollback_page_up`, `scrollback_page_down`
- **X11 internals:** `dpy` (4), `wid`, `map_window`
- **Frame / size:** `flush` (3), `clear` (2), `width`, `height`,
  `on_resize`, `request_pixel_size`, `fit_columns`, `adjust_fontsize`
- **Wiring:** `set_buffer`

> Much of this is legitimately the **Host** talking to the **X11
> backend** — but it should go through the backend protocol (frame/size/
> metrics) or be Host-internal (scrollback UI state), not reach into
> `Window` X11 details (`dpy`, `wid`). Phase 6 draws the Host/Backend
> line here.

---

## 4. Reading order for the phases

- **Phase 2** (collapse buffer): targets §1 (make it the `Screen` op API)
  and §3b (move `draw_buffered` to the backend; drop `scrollback_mode`
  from the buffer).
- **Phase 3** (damage first-class): replaces the §1 "render-side" group
  and the §3b `@adapter.draw`/`*_lines` calls with damage emission.
- **Phase 4** (cut `Term` coupling): removes every row of §3a.
- **Phase 6** (Host/App): formalises §3c and §2's DECCOLM/scrollback
  edges into the Host↔Backend boundary.
