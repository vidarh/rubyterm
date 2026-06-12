BUFTEST

# Unit Tests for ScrBuf and TermBuffer

[TESTING] Add real unit tests for the core buffer classes that currently have zero coverage.

## Goal Reference

`docs/goals/TESTABLE-testable-terminal-core.md`

## Motivation

ScrBuf and TermBuffer are the central data structures of the terminal --
every character written, every scroll operation, and every resize flows through
them. Recent commits have touched scrollback, line deletion, and resize logic,
yet the test file `test/test_termbuffer.rb` contains only a skip placeholder.
These classes have no external dependencies (`require 'set'` only), so there
is no reason they cannot be tested today.

## Scope

**Includes:**
- Load `lib/termbuffer.rb` directly in tests (no X11/Skrift needed)
- Test ScrBuf: `set`/`get`, `clear`, `delete_line`, `insert_line`,
  `resize`/`enforce_height`, `each_character`, `lineattrs`
- Test TermBuffer: `scroll_up` (including scrollback storage),
  `clear_line` (partial and full), `scroll_start`/`scroll_end` region
  handling, `on_resize`

**Does not include:**
- Tests for TrackChanges, WindowAdapter, or Term (separate future plans)
- Any changes to production code
- Integration or rendering tests

## Expected Payoff

- Catches regressions in scrollback and resize logic during active development
- Establishes a pattern for testing other core classes
- Replaces the placeholder test with real coverage of the most-modified code

## Proposed Approach

Replace the contents of `test/test_termbuffer.rb` with focused minitest cases
that instantiate ScrBuf and TermBuffer directly and exercise their public APIs.
Ensure `test_helper.rb` loads `lib/termbuffer.rb`. No mocks needed -- these
are pure data structures.

## Acceptance Criteria

- [ ] `test/test_termbuffer.rb` contains passing tests (no skips) covering
      at minimum: set/get, clear_line, scroll_up with scrollback, and resize
- [ ] `ruby -Itest test/test_termbuffer.rb` runs successfully without X11
- [ ] No production code changes required

## Open Questions

- Should scrollback buffer size be capped? Currently it grows without limit.

---
*Status: PROPOSAL - Awaiting approval*
