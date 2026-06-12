# Harness Quick Start: From Glitch to Bug Report

You're using the terminal, an application renders wrong. Here is how
to capture that as a debuggable artifact and hand it off. Everything
else the harness does is in [harness.md](harness.md).

## 1. Reproduce under the recorder

Re-run the application that glitched, wrapped in the recorder, inside
your terminal:

```sh
ruby harness/cli.rb record --out /tmp/bug.rec -- emacs -nw
```

(Substitute the actual command: `claude`, `htop`, ...) The app runs
normally — the recorder is a transparent pty proxy that logs every
byte the app sends to the terminal. Do whatever triggered the glitch.
When you've seen it happen, quit the app (or Ctrl-C); the recording is
complete.

Tips:

* Keep the recording short if you can — straight to the glitch and
  out. (Long recordings still work; they're just slower to chew
  through.)
* Same terminal, same window size as when you first saw the bug.
  Resizes during the session are recorded and replayed faithfully.
* The glitch doesn't need to be on screen when you quit. Transient
  garbage that later got overwritten is still caught.

## 2. Hand it off

Tell Claude (or your future self):

1. the path to the `.rec` file,
2. what looked wrong ("Emacs left stale text in the minibuffer after
   scrolling", "the status line doubled up"), and
3. roughly when in the session it happened, if you know.

That's all the harness needs. A useful first probe, which also tells
you whether the bug is automatically detectable:

```sh
ruby harness/cli.rb hunt --rec /tmp/bug.rec
```

This deterministically searches for the bug — replaying through a
headless copy of the terminal with rendering checks at intervals,
varying the feed chunk size (split escape/UTF-8 sequences only fail at
some sizes), diffing the end state against tmux — and, on a hit,
shrinks it to a minimal repro plus the exact configuration it fails
under. `"found": true` with repros = captured; the rest of the
pipeline (below) is mechanical. `"found": false` but you saw a
glitch = still report it — the trace plus your description is what a
debugging session starts from (the automated checks only cover some
bug classes).

## 3. What happens with it (the mechanical part)

The whole pipeline below is packaged as the **`debug-recording`
workflow** (`.claude/workflows/debug-recording.js`): tell Claude
"run the debug-recording workflow on /tmp/bug.rec" and it will
reproduce, minimize, diagnose, add a red regression case to
`cases/bugs/`, fix, verify against the ratchet, and clean up the fix —
leaving the changes uncommitted for review.

Step by step, the same thing by hand:

```sh
# find + shrink the bug        -> minimal repro + failing configuration
ruby harness/cli.rb hunt --rec /tmp/bug.rec
#   (hunt = replay w/ checks at offsets, chunk-size variation, extract
#    at failing offsets, minimize; each piece is also its own command)
# fix lib/*.rb, then prove it: repro passes, nothing else broke
ruby harness/cli.rb run --case /tmp/hunt-redraw-<sig>.bin --checks redraw
ruby harness/cli.rb sweep --cases cases --oracle tmux --ratchet ratchet.json
```

The minimal repro then gets committed to `cases/` and added to the
ratchet so the bug stays fixed.

## Current limitation worth knowing

Replay re-checks from byte 0; very large recordings (a long Emacs
day) replay in full rather than from checkpoints. Until save/load
checkpointing lands (see harness.md, Future work), prefer recordings
that go straight to the glitch.
