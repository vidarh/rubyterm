# Terminal Test Harness

A deterministic, machine-readable test harness for the terminal
emulator. Every comparison reduces to structured pass/fail JSON — no
human (or vision model) in the loop — so it can drive fully scripted
sweep → minimize → cluster → fix pipelines, as well as ordinary
interactive debugging.

Quick start (full tour: [harness-quickstart.md](harness-quickstart.md)):

```sh
ruby harness/cli.rb run --case cases/synthetic/dch.bin --oracle tmux   # one case
ruby harness/cli.rb sweep --cases cases --oracle tmux \
    --ratchet ratchet.json                                             # regression gate
ruby harness/cli.rb minimize --case failing.bin --checks redraw        # shrink a repro
```

JSON on stdout, diagnostics on stderr, exit 0/1 = pass/fail.

## Architecture

The harness runs the *production* terminal core (`lib/`) headlessly and
in-process: `TermBuffer` + `TrackChanges` + `WindowAdapter` + `Term`,
with the X11 `Window` replaced by a `VirtualWindow` — a pure-Ruby
framebuffer that implements the same drawing interface. Feeding bytes
is synchronous and single-threaded, so when `Session#feed` returns,
everything has been interpreted and rendered: no sleeps, no sync
barriers, fully deterministic.

The production code carries **no debug facilities**. All
instrumentation is injected from `harness/` via `Module#prepend` /
class reopening (see `harness/lib/patches.rb`); the only seams in
production code are ordinary extension points (`Term#responder`,
`RubyTerm#process_chunk`, the `$0 == __FILE__` run guard).

```
harness/
  cli.rb            CLI entry point (run/sweep/minimize/tokenize/record/replay)
  live.rb           instrumented entrypoint for the live X11 terminal
  gen_cases.rb      regenerates cases/synthetic/
  lib/
    harness.rb      loads the core headlessly + all components
    patches.rb      injected instrumentation (gen tracking, adapter accessor)
    session.rb      headless terminal assembly; feed/resize/full_redraw
    virtualwindow.rb  software render sink; glyph/marker modes; trace
    statedump.rb    state -> canonical JSON schema (docs/state-schema.md)
    differ.rb       structured dump diffing + explicit normalizations
    oracle_tmux.rb  tmux-based semantic oracle
    checks.rb       state/redraw/markers/responses/trace checks + failure signatures
    tokenizer.rb    escape-safe byte-stream tokenization
    ddmin.rb        delta debugging
    minimizer.rb    signature-matched ddmin over tokens
    sweep.rb        corpus runner + ratchet
    recorder.rb     pty proxy recorder
    replay.rb       recording replayer with checkpointed checks
    debugserver.rb  Unix-socket control channel for the live terminal
cases/
  synthetic/        committed starter corpus (see gen_cases.rb)
ratchet.json        sorted case IDs known to pass on main
```

## The checks

Bugs partition into three classes, each with its own check:

### `state` — semantic bugs (parser / state machine)

Dumps the internal grid (see `docs/state-schema.md`) and diffs it
against a reference implementation interpreting the same bytes:
**tmux** (`--oracle tmux`), via a throwaway tmux server whose pane runs
`stty -echo; cat case.bin`. Screen text and cursor position are
compared; attributes are a future extension. With `--oracle none` the
check degrades to "interpreting the bytes did not crash".

Normalizations are explicit and centralized in `differ.rb` (nil cell ≡
space; cursor clamped to last column on both sides because
pending-wrap representations differ; DEC graphics translation, since
tmux's capture is undesignated). Per-case oracle divergences are
recorded in `<case>.meta.json` sidecars, e.g.
`{"skip_checks": ["state"], "reason": "tmux ignores DECCOLM"}`.

### `redraw` — incremental rendering bugs (no oracle needed)

The killer invariant: render the current buffer state through the live
incremental path *and* via a fresh full redraw into a second
`VirtualWindow`; same renderer, so any differing virtual pixel is an
incremental-update bug. This is a pure metamorphic property targeting
exactly the bug class that is otherwise hardest to catch, because
stale-content bugs are masked the moment anything forces a full
repaint. Output: differing character cells + bounding box.

### `markers` — stale content, localized and self-describing

Re-runs the case with the render sink in marker mode: instead of
glyphs, each cell is filled with a `(row, col, generation)` encoding,
where the generation is a per-cell content-write counter (injected
into `TermBuffer` by `patches.rb`). Decoding the framebuffer then
*names* the buffer cell that owns each screen cell: "cell (3,40) shows
generation 5 from cell (3,39)" is a diff a fixer can act on directly.
Scroll blits legitimately move markers around; only the generation has
to match.

### `responses` — query replies, checked host-side against tmux

The terminal answers queries (DSR, DA, ...) by writing a reply *back to
the host* (the pty), not to the screen — so a grid-only oracle never
sees it. That blind spot hides a real bug class: a host like tmux
**consumes** a reply it recognises as the answer to a query it sent, but
**forwards** a malformed or wrong-*type* reply to the foreground
program, where a cooked-mode reader (a shell at its prompt) echoes it as
visible garbage — "escape sequences on screen".

The check captures the replies our terminal generates (the headless
`Session` is `Term`'s responder, byte-identical to `Controller`) and
feeds them to the tmux oracle **as host input**, over a real pty so they
travel tmux's genuine reply-recognition path. Anything tmux leaks into
the pane is the failure, reported as the leaked lines. This is
irreducibly host-side: re-interpreting the reply in our own terminal
can't see it (we just consume our own DCS). Needs the tmux oracle;
without it the check is skipped. It is exactly how the DA2 (`\e[>c`) leak
was caught: a DA3 DCS (`\eP!|00000000\e\\`) sent in answer to DA1/DA2 is
unrecognised by tmux and printed `^[P!|00000000^[\` on screen. The fix
was to answer each Device Attributes variant with its correct reply
type (`CSI ? … c` / `CSI > … c` / `DCS ! | … ST`).

### `trace` — render-call log (informational)

Records every sink call (draw/clear/blit, with arguments) for
over/under-draw analysis. Currently reports op counts only and always
passes; the data is there for damage-tracking work on `TrackChanges`.

`class` in the output is `state` (grid wrong), `render` (grid right,
pixels wrong) or `null`; `signature` is a stable hash of *how* the
case fails, used for clustering and by the minimizer.

## Corpus, sweep and ratchet

`cases/synthetic/` is generated by `harness/gen_cases.rb` and
committed. Case files are raw bytes (`.bin`/`.txt`); the case ID is the
path relative to the swept directory, without extension.

`ratchet.json` is the regression gate: the sorted list of case IDs
known to pass. The rule is mechanical — **a patch may add IDs to the
ratchet, never remove**:

```sh
# gate: exit 1 if any previously-passing case fails
ruby harness/cli.rb sweep --cases cases --oracle tmux --ratchet ratchet.json
# after fixing bugs: fold newly-passing cases in
ruby harness/cli.rb sweep --cases cases --oracle tmux \
    --ratchet ratchet.json --update-ratchet
```

`Sweep.update_ratchet` refuses to drop regressed IDs.

## Minimization

```sh
ruby harness/cli.rb minimize --case big-failure.bin --checks redraw --out minimal.bin
```

ddmin over *tokens* (split with the terminal's own `EscapeParser`, so a
candidate never cuts an escape sequence in half), accepting a candidate
only when it fails with the **same signature** as the original —
without that, ddmin happily wanders off and minimizes into a different
bug. Avoid `--oracle tmux` here when a `redraw`/`markers` failure
suffices: oracle-free iterations are in-process and ~100× faster.

## Real applications: record and replay

Real-app streams (Emacs, Claude Code, ...) exercise patterns no
synthetic corpus will. The recorder is a pty proxy; the recording is
the test case:

```sh
ruby harness/cli.rb record --out emacs.rec -- emacs -nw   # use it until it glitches
ruby harness/cli.rb hunt --rec emacs.rec                  # find + minimize the bug(s)
```

`hunt` is the deterministic search from "recording of a glitch" to
"minimal repro + the exact configuration it fails under". It scans
feed-chunk sizes (default, then progressively smaller — escape/UTF-8
*reassembly* bugs are chunk-phase dependent and only fire when a
sequence is split across reads), replaying with redraw+markers checks
at intervals and diffing the end state against the tmux oracle per
configuration; it then cuts the stream at each failing offset and
ddmins it under that exact configuration, preferring the in-process
checks (a state minimization runs tmux on every iteration). Output:
minimal repros plus ready-to-promote `.meta.json` sidecars recording
geometry and chunk. Exit 0 = found something.

The pieces are also available individually: `replay` (checks at
`--every`-byte offsets), `extract` (cut the output stream at a byte
offset), `minimize`. Replay is record-faithful by default — each
recorded pty read is fed as one chunk; with `--chunk N` it slices
continuously across records, byte-for-byte the same as `run`/
`minimize` on an extracted stream, so failures transfer. Checks are
suppressed inside DEC 2026 synchronized-update blocks (intentionally
incomplete frames), and **all** failing offsets are reported, since
stale-rendering failures can be transient (a later clear masks them).
Input bytes are recorded too, never replayed: they tell you what query
responses the app saw when a recording behaves oddly.

## The live terminal: debug socket

```sh
ruby harness/live.rb [args...]        # instead of: ruby termtest.rb
# socket path printed on startup ($RTERM_DEBUG_SOCKET to choose it)
```

`live.rb` loads the production terminal unchanged and injects a
control channel speaking newline-delimited JSON over a Unix socket:

| command | effect |
|---|---|
| `{"cmd":"dump_state"}` | full state dump (docs/state-schema.md) |
| `{"cmd":"render_barrier"}` | flush pending damage and paint |
| `{"cmd":"feed","bytes_b64":...}` | inject bytes as if from the pty |
| `{"cmd":"tokenize","bytes_b64":...}` | chunk bytes with the real parser |

State-touching commands execute *on the input-processing thread* (a
Proc pushed through the input queue), so a dump can never observe a
half-processed chunk — a stronger barrier than the DA round-trip trick
an external driver would need.

## The debug-recording workflow

`.claude/workflows/debug-recording.js` packages the
recording-to-fixed-bug pipeline as a Claude Code workflow
(`args: {rec: "path.rec", description: "what looked wrong"}`):

1. **Hunt** — reproduction and minimization are one deterministic
   harness command (`hunt`, above); the agent only relays its JSON.
   Only if hunt finds nothing does an investigator agent probe
   interactively from the user's description (then hands any case it
   finds back to the mechanical minimizer).
2. **Diagnose** — one analyst per repro (capped by `max_bugs`,
   default 3) traces the bytes through the code and must confirm/kill
   its hypothesis by varying the repro.
3. **Red test** — the minimal repro is added as
   `cases/bugs/<name>.bin` (+ sidecar recording geometry/chunk if
   non-default) and mechanically confirmed to fail.
4. **Fix** — one fixer per bug, sequential, two attempts; every
   attempt is gated by an independent mechanical verification (case
   green, ratchet sweep clean, `rake test` green — fixers never grade
   themselves). Failed fixes are reverted; the red case stays as
   backlog.
5. **Cleanup** — a reviewer minimises the fix diff (verified state
   snapshotted first), final verification, ratchet update. Changes are
   left uncommitted for review.

## Fixer contract

For autonomous (or just disciplined) bug-fixing sessions:

* Repro: `ruby harness/cli.rb run --case <id> --oracle tmux` currently fails.
* Done when: that passes **and**
  `ruby harness/cli.rb sweep --cases cases --oracle tmux --ratchet ratchet.json`
  reports zero regressions (script-verified, not self-reported).
* Never edit: `harness/`, `cases/`, `ratchet.json`.
  The failure mode for autonomous fixers is "fixing" the test.

## Known failures (the bug backlog)

The first sweep of the synthetic corpus found 10 failing cases — all
triaged as genuine terminal bugs (oracle artifacts were fixed or
allowlisted instead):

| case | class | bug |
|---|---|---|
| `dch` | state | CSI P (delete characters) unimplemented (`term.rb` stub) |
| `dl` | state+render | `delete_lines` broken (known FIXME) |
| `scroll-lf` | state+render | scroll off by one line vs tmux; incremental blit displaces content |
| `scroll-region` | state+render | scroll-region handling diverges |
| `el-variants`, `ed-below`, `ed-all` | render | clears bypass the batched draw queue in `TrackChanges`: pending text is painted *after* the clear, leaving stale text on screen (buffer is correct). Minimal repro: `"\n\n\n4444\e[2;2H\e[0J"` |
| `deccolm-reset` | render | same batched-draw-after-clear class (state check skipped: tmux ignores DECCOLM) |
| `origin-mode` | state | DECSTBM (`CSI r`) does not home the cursor |
| `text-utf8` | state | double-width chars occupy one column |

## Deviations from the original design

This implements the design discussed in the planning conversation
(three capture layers, semantic oracle, redraw invariant, marker mode,
tokenized ddmin, corpus+ratchet, recorder/replay) with these
adaptations:

* **No Xvfb / libvterm on this machine.** The render checks run
  against `VirtualWindow` (in-process software framebuffer behind the
  same sink interface) instead of XGetImage under Xvfb, and the oracle
  is tmux (`capture-pane`) instead of a libvterm shim. The
  `VirtualWindow` model is *more* deterministic than pixel capture and
  needs no per-worker X server; real-pixmap capture can be added later
  behind the same check interface.
* **No DA-sync needed in the harness.** In-process feeding is
  synchronous. The live debug socket gets the same guarantee from
  queue-serialized barriers.
* **Virtual pixels, not real glyphs.** A glyph is modelled as an inset
  rect encoding (codepoint, fg) over the bg fill; `clear` equals a
  default-background fill (the alpha distinction between them is below
  the model's resolution); spaces paint background only, matching the
  glyph renderer. Line decorations (under/over/strike) are modelled;
  double-width/height rows are modelled in glyph mode but markers
  assume the normal grid (marker results on `#3`/`#4`/`#6` lines are
  unreliable).

## Future work

* Attribute capture in the oracle (`capture-pane -e` + SGR parser).
* esctest/vttest corpus import; fuzzer (grammar informed by
  `tokenize` histograms of real-app recordings).
* Save/load checkpoints for long replays (binary-search localization
  to `(checkpoint, byte-range)` repros) and the preamble generator to
  promote app-derived repros into self-contained cases.
* Live tripwire mode (idle-time redraw invariant in the daily-driver
  terminal, auto-capturing repros into `~/.term-bugs/`).
* Under/over-draw verdicts from the trace check once `TrackChanges`
  grows real damage tracking.
* Parallel sweep workers; input-class tests (keypress → pty bytes).
* The dynamic-workflow orchestration on top (sweep → minimize →
  cluster → parallel fixers in worktrees → ratchet-gated merge).
