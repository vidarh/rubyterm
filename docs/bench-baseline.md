# Performance baseline (pre-refactor)

*Captured Phase 1, before any data-model changes, as the regression
baseline for the architecture refactor (see `architecture-review.md` §8).
Raw data: `harness/bench-baseline.json`. Reproduce:*

```
ruby harness/bench.rb --mb 1 --virtual-kb 16 --json
```

Ruby 3.2.2, 80×24, 128-byte chunks. **Same-machine** comparison only —
absolute timing is machine/load dependent; the **deterministic** metrics
(`alloc/KB`, `live(+)`, `GC runs`) are the robust regression signal and
do not depend on machine speed or concurrent load.

## Numbers

| sink | load | MB/s | alloc/KB | GC runs | GC ms | live(+) |
|---|---|--:|--:|--:|--:|--:|
| null (core)    | plain | 0.22 | **6484** | 210 | 911 | 1,171,804 |
| null (core)    | ansi  | 0.25 | **6537** | 206 | 885 |   866,747 |
| null (core)    | wrap  | 0.22 | **6401** | 200 | 950 | 1,122,192 |
| virtual (full) | plain | —    | **73009**| 46  | 69  | 39,234 |
| virtual (full) | ansi  | —    | **55509**| 52  | 51  | 27,881 |
| virtual (full) | wrap  | —    | **50353**| 48  | 46  | 31,282 |

- **null** = `Term` + `TrackChanges` + `TermBuffer` against a no-op sink:
  the interpreter + buffer + draw-batch cost Phase 2 changes.
- **virtual** = the full pipeline through `WindowAdapter` →
  `VirtualWindow`. Runs a small input (16 KB) because VirtualWindow's
  pure-Ruby `copy_area` is ~120× slower than the core; **its MB/s is not
  an X11 proxy** — read its `alloc/KB`/`live(+)`, not its timing. (live(+)
  is small only because the input is small; per-KB it tracks the core.)

## What the baseline says (the Phase-2/3 targets)

1. **~6,500 allocations per KB in the core**, almost all from
   `TermBuffer#set` allocating a fresh `[ch,fg,bg,flags]` Array per glyph
   (plus the `@changes` `[x,y]` pair and the draw-batch match probe). A
   columnar store of packed immediates (review §8.3) should cut this by
   roughly an order of magnitude. **This is the headline number.**
2. **~0.9 s of GC per MB and ~1.1M live objects retained per MB** in the
   core — the retention is object-per-cell scrollback (each scrolled-off
   line keeps ~80 cell Arrays). At ~0.2 MB/s, a "cat a multi-MB file"
   genuinely stalls, and GC is a large slice of it. Columnar rows +
   packed scrollback should collapse both.
3. **The render path allocates ~10× the core** (`alloc/KB` ~50k–73k vs
   ~6.5k). So Phase 3 (damage-driven backends, run batching at the
   backend) has at least as much allocation headroom as the buffer
   rewrite. The full-pipeline allocation profile is where the
   `cat`-a-file cost actually concentrates.

## How to use it

Re-run the same command after each refactor phase and diff against
`bench-baseline.json`. Treat **`alloc/KB` and `live(+)` as gated
regression metrics** (deterministic); treat MB/s as indicative. Phase 2's
explicit bar is *no major regression*; Phase 8 is where these numbers are
actively driven down. (X11-inclusive end-to-end timing — real X server +
skrift rasterisation — is a separate future benchmark; see `TODO.md`.)
