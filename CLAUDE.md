# Ruby Term - Development Guide

## Build/Run Commands
- Run terminal: `ruby termtest.rb`
- Build executable (requires unreleased tool 'rubypkg'): `make build` (creates standalone executable in file `t`)
- Install to ~/bin: `make promote`
- Debug mode: `DEBUG=1 ruby termtest.rb`

## Code Organization

### Scrollback Buffer
- Primary implementation: `lib/termbuffer.rb` - handles line storage and management
- Scroll handling: `lib/window.rb` - contains viewport and scroll position logic
- User input processing: `lib/keymap.rb` - mappings for Page Up/Down and scrolling keys

## Code Style Guidelines

### Formatting & Syntax
- Use 2-space indentation
- Prefer Ruby's modern syntax: method definitions with `=` for one-liners
- Use concise, readable variable names
- Liberal use of symbols (`:symbol`) for keys and identifiers
- Use snake_case for methods and variables

### Design Patterns
- Terminal is decoupled into components (buffer, controller, window adapter)
- Use classes with clear responsibilities
- Employ thread-based event handling
- Prefer standard library over external dependencies when possible

### Error Handling
- Use exceptions for genuine errors, with rescue blocks to handle gracefully
- Debug information with `p` calls (preferable to puts for inspection)
- In production mode, trap and log exceptions where possible

### Documentation
- Document escape sequences and control codes with comments
- Include references to terminal specifications when implementing features
- Use inline documentation for complex logic

## Test Harness

A deterministic test harness lives in `harness/` (full guide:
`docs/harness.md`, state schema: `docs/state-schema.md`). JSON on
stdout, exit 0/1. Key commands:

- Run one case: `ruby harness/cli.rb run --case cases/synthetic/dch.bin --oracle tmux`
- Regression gate: `ruby harness/cli.rb sweep --cases cases --oracle tmux --ratchet ratchet.json`
- Shrink a repro: `ruby harness/cli.rb minimize --case FILE --checks redraw`
- Record/replay real apps: `ruby harness/cli.rb record --out F.rec -- cmd` / `replay --rec F.rec`
- Instrumented live terminal: `ruby harness/live.rb` (debug socket; see docs)

Rules when fixing terminal bugs:
- A fix is done when the failing case passes AND the ratchet sweep
  shows zero regressions. Never edit `harness/`, `cases/` or
  `ratchet.json` to make a fix "pass".
- After real fixes, fold newly-passing cases in with `--update-ratchet`.
- Production code (`lib/`, `termtest.rb`) must stay free of debug
  hooks; harness instrumentation is injected from `harness/lib/patches.rb`
  and `harness/live.rb` via prepend/reopen.
