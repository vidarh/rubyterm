# cases/bugs/

Regression cases promoted from real failures (recordings, fuzzing,
manual repros): one minimized `.bin` per bug, named after the bug, with
an optional `.meta.json` sidecar (`geometry`, `skip_checks`, `reason` —
see docs/harness.md). Added red, then fixed, then folded into
`ratchet.json` so the bug stays fixed.
