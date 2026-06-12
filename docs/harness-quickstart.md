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
ruby harness/cli.rb replay --rec /tmp/bug.rec --checks redraw,markers
```

This replays the byte stream through a headless copy of the terminal
and re-checks rendering at intervals. `"pass": false` with a list of
byte offsets = the bug is captured and machine-checkable; the rest of
the pipeline (below) is mechanical. `"pass": true` but you saw a
glitch = still report it — the trace plus your description is what a
debugging session starts from (the checks only cover some bug
classes, and the state oracle, screen dumps at offsets, etc. can be
brought to bear interactively).

## 3. What happens with it (the mechanical part)

The whole pipeline below is packaged as the **`debug-recording`
workflow** (`.claude/workflows/debug-recording.js`): tell Claude
"run the debug-recording workflow on /tmp/bug.rec" and it will
reproduce, minimize, diagnose, add a red regression case to
`cases/bugs/`, fix, verify against the ratchet, and clean up the fix —
leaving the changes uncommitted for review.

Step by step, the same thing by hand:

```sh
# locate failures              -> failing byte offsets
ruby harness/cli.rb replay --rec /tmp/bug.rec --checks redraw,markers
# cut the stream at a failure  -> a standalone case file
ruby harness/cli.rb extract --rec /tmp/bug.rec --to 196608 --out bug.bin
# shrink to a minimal repro    -> usually a few hundred bytes or less
ruby harness/cli.rb minimize --case bug.bin --checks redraw --out minimal.bin
# fix lib/*.rb, then prove it: repro passes, nothing else broke
ruby harness/cli.rb run --case minimal.bin
ruby harness/cli.rb sweep --cases cases --oracle tmux --ratchet ratchet.json
```

The minimal repro then gets committed to `cases/` and added to the
ratchet so the bug stays fixed.

## Current limitation worth knowing

Replay re-checks from byte 0; very large recordings (a long Emacs
day) replay in full rather than from checkpoints. Until save/load
checkpointing lands (see harness.md, Future work), prefer recordings
that go straight to the glitch.
