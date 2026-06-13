# Debugging live-terminal display corruption

Notes from chasing "apps look garbled in rterm but the harness says
everything's fine." The headline lesson: some bugs live in places the
deterministic harness structurally cannot see — and there's a concrete
technique to drag them back into reproducibility.

## The problem class

Live-only display corruption in **full-screen, diff-rendering apps**
(htop, emacs, Claude Code, vim, less, tmux). These apps render to their
own virtual screen and emit only the *minimal* escape sequences needed
to morph the terminal into that screen. Consequence: any divergence
between the app's model of the screen and the terminal's actual state
becomes **permanent** — the app never repaints cells it believes are
already correct, so a momentary glitch sticks until a forced full redraw
(`C-l`, resize, etc.). This is why the corruption looks like stale/merged
content rather than a flicker.

## Why the harness doesn't catch these directly

The byte→grid oracle (tmux) and the redraw/markers checks run the core
**single-threaded and synchronously**, replaying a fixed byte stream.
That's great for parser/state bugs and incremental-render bugs, but it is
blind to three things:

1. **Concurrency** — the live terminal runs several unsynchronized
   threads (input processing, blink, 30fps flush, X events). The harness
   has none of that.
2. **Size reporting** — `winsize`/`TIOCSWINSZ` is not byte
   interpretation, so no byte→grid check can see it.
3. **Unexercised ops** — a recorded `.rec` may simply not contain the
   buggy sequences. The optimization path an app takes depends on
   `TERM`/terminfo **and the reported size**, so a recording made under
   different conditions replays perfectly clean even though the live app
   corrupts. (Our emacs `.rec` was all full repaints; htop used scroll
   regions — only htop exposed the bug.)

## The capture-replay technique (the key tool)

When a live bug won't reproduce from a `.rec`, capture what the live
terminal actually received, with the real read boundaries:

1. **Instrument `RubyTerm#write`** to log every pty chunk as it arrives
   (base64, one line per `write` call = one `read_nonblock(128)` worth,
   preserving the real boundary). A thin launcher that `require`s
   `termtest` + the debug server and prepends a write-logger is enough;
   no production changes.
2. **Run the app live** in the instrumented terminal. **htop is the
   ideal target**: it self-redraws on a timer, so you need *no*
   keypresses (avoids all xdotool/focus flakiness). `SIGSTOP` it to
   freeze the captured stream, then `render_barrier` + `dump_state` over
   the debug socket.
3. **Replay headless with the exact boundaries**:
   `session.feed(chunk, chunk: chunk.bytesize)` for each logged chunk.
4. **Three-way compare** live `dump_state` vs headless replay vs tmux:
   - live == headless, **headless != tmux** → deterministic parser/state
     bug, now reproducible headless → minimize and fix normally.
   - live == headless == **tmux** → not a byte-interpretation bug; the
     bytes are correct. Suspect **size reporting** or **concurrency**.
   - **live != headless** → concurrency/timing in the live path only.

## The size-sweep trick

If headless diverges from tmux, replay the *same bytes* at geometry ±1
row/col. If it **matches at a different size**, the byte stream was
correct for that other size — i.e. the app was **told the wrong size**.
That's a `winsize`/`report_size` bug, not a parser bug.

This is exactly how the root cause this session was found: the htop
stream was 203 cells wrong at 50×14 but **0 diffs at 50×15**, and the
live app's TTY was confirmed `15×50` while the terminal rendered 14.

## Root cause found this session

`Controller#report_size` reported `[h + 1, w]` to the child
(`TIOCSWINSZ`) — one row too many. Every full-screen app drew an extra
row, so its minimal diff-updates landed one row off and shifted/
overflowed. One-character fix (`h + 1` → `h`); fixes all full-screen
apps at once. Guarded by a unit test (`winsize == [rows, cols]`), since
the byte→grid oracle can't see size reporting.

## Concurrency hardening (related, defensive)

Separately, the live terminal mutated the shared buffer from multiple
threads with **no locking**: the input processor (`feed`), the blink
timer (`redraw_blink`), the 30fps flush, and X events
(`Expose`/`ConfigureNotify` → `resize` → buffer mutation). Routed blink,
flush, and resize through the single input queue so only the processing
thread touches the buffer. This was *not* the cause of the size bug, but
it removes genuine data races. (Caveat: one flaky resize-not-applying
was observed during testing — worth a closer look before relying on it.)

## Live-driving setup and gotchas

- **Xephyr** gives an isolated, WM-free display you can size freely and
  screenshot without touching the user's real terminals:
  `Xephyr :1 -screen 1500x900 -ac -noreset`, then run the terminal with
  `DISPLAY=:1`. It also sidesteps window-identification entirely.
- The real WM on `:0` force-sizes the window (tiling), so
  `xdotool windowsize` won't stick. Under Xephyr (no WM) it works; iterate
  size → `dump_state` until you hit the target cols/rows.
- Identify *your* window by before/after diff of
  `xdotool search --class rterm` — the user runs rterm as a daily driver
  (many windows) and the terminal doesn't export `_NET_WM_PID`.
- **`pkill -f "live.rb"` matches its own command line and kills your
  shell.** Kill by PID excluding `$$` instead.
- The shell snapshot runs with `set -e`; guard fallible commands
  (`pkill ... || true`) or the whole step aborts silently.
- `-c <instance>` (to set a unique WM_CLASS) crashes startup via a
  separate X property-length bug — don't use it for identification.
- Read PNG screenshots directly to confirm corruption; `dump_state` for
  the buffer. **Translucent windows** show the desktop/other windows
  behind — don't mistake that faint layer for corruption; the bug is in
  the solid foreground text.

## Resize: flash, freeze, and wrong size

Resize bugs live entirely in the live X layer (the harness never resizes
a real window), so they need live driving + `xwininfo`/screenshots.
Three distinct bugs, all found this way:

- **Flash (whole window blanks on resize).** The window was created with
  the default **bit gravity = ForgetGravity**, so on every resize the X
  server *discards the window contents* and fills with the background
  before we repaint. `xwininfo -id <win> -all | grep Gravity` shows it.
  Fix: create the window with `CWBitGravity => 1` (NorthWestGravity) so
  the server retains the existing pixels (anchored top-left).
- **Resize doesn't track the window / freezes.** The event mask had
  `SubstructureNotifyMask` (events about *child* windows) but **not
  `StructureNotifyMask`** (events about *this* window) -- so the window
  never received `ConfigureNotify` for its own resize. Resize had been
  limping along on Expose alone. Fix: add `StructureNotifyMask`.
- **Resize shrinks to a thin strip.** `Expose` and `ConfigureNotify`
  were handled identically (`resize(pkt.width, pkt.height)`), but
  Expose's width/height are the **damage rectangle**, not the window
  size -- a partial Expose resized the terminal to a few rows. Fix:
  `ConfigureNotify` resizes; `Expose` only repaints.

General rule: in X, **ConfigureNotify = size changed** (resize),
**Expose = pixels lost** (repaint). Never resize on Expose, and make
sure the window actually selects `StructureNotifyMask` or its own
ConfigureNotify never arrives.

- **Resize is slow / "hangs until it catches up".** A drag fires a
  *flood* of ConfigureNotify + Expose; repainting on each one builds a
  backlog the renderer then grinds through. A single redraw is cheap
  (a few ms) -- the cost is volume. Fix: **coalesce**. Keep at most one
  redraw request queued (a `@redraw_pending` flag guarded by a mutex)
  and always repaint to the *latest* pending size; further events while
  one is in flight just update the target. The event thread stays
  responsive (requesting a redraw is cheap) and the renderer does one
  repaint per slot at the current size instead of one per event, so it
  catches up within a single redraw of the drag stopping. Coalescing
  must be mutex-serialised with the apply step or the final size can be
  lost to a race.

## Triage checklist: "app looks corrupted in rterm"

1. Reproduce live; screenshot **and** `dump_state`. Clean buffer + dirty
   pixels → render layer. Dirty buffer → state/size.
2. Capture the pty stream with real boundaries; replay headless; do the
   three-way compare above.
3. headless == tmux but live differs → concurrency or size, not the
   parser.
4. Size-sweep ±1 → size-reporting bug.
5. Full-screen app + a one-row/col shift → check `report_size`/`winsize`
   first.
