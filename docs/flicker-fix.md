# Anti-Flicker Implementation

## Problem Statement

The terminal exhibited severe flickering when running applications like Claude Code, particularly visible when:
- Status lines updated (harmonizing animation, token counters)
- User typed input (flicker on every keypress when typing fast)
- Multiple lines at the bottom of the screen would flash/flicker

## Root Cause Analysis

### Diagnosis Process

Log analysis (using `LOG_TERM=1 ruby termtest.rb`) revealed the core issue:

1. **Escape Sequence Pattern**: Applications like Claude Code send patterns like:
   ```
   \e[2K\e[1A (clear line, cursor up) repeated 10+ times
   ```
   followed by redrawing the same lines with updated content.

2. **Frequency**: This pattern occurred ~2,870 times during normal usage

3. **Timing Issue**: The operations were split across multiple queue items:
   - Queue item 1: Multiple `\e[2K\e[1A` sequences (clears)
   - Queue item 2: Content redraws

4. **The Flush Race**:
   - Each `clear()` operation set `@dirty = true` immediately
   - The 30 FPS flush thread runs independently: `@window.flush` every ~33ms
   - The flush thread could copy the cleared-but-not-yet-redrawn state to the visible window
   - Result: User sees blank lines briefly before content redraws = **flicker**

### Additional Issues Found

- `fillrect()` (used to draw character backgrounds) also set `@dirty = true` immediately
- This caused partial character renders (background filled, text not yet drawn) to be visible
- Each individual rendering operation triggered potential flushes instead of batching

## Solution Implementation

The fix involves three coordinated mechanisms:

### 1. Deferred Dirty Flag on Clear Operations

**File**: `lib/window.rb` - `clear()` method

**Change**: Instead of setting `@dirty = true` immediately, set `@pending_clear = true`

**Rationale**:
- Clear operations are almost always followed by redraws
- Deferring the dirty flag prevents showing the cleared state
- The flag is cleared when content is drawn (see mechanism #2)

**Code**:
```ruby
def clear(x,y,w,h)
  @render_mutex.synchronize do
    @cleargc ||= @dpy.create_gc(@buf, foreground: 0x0|@alpha, background: 0)
    @dpy.poly_fill_rectangle(@buf, @cleargc, [x, y, w, h])
    @pending_clear = true  # Deferred, not @dirty = true
  end
end
```

### 2. Atomic Character Rendering

**File**: `lib/window.rb` - `fillrect()` and `draw()` methods

**Change**:
- `fillrect()` no longer sets `@dirty`
- `draw()` sets `@dirty` only after complete character is rendered (background + text)
- `draw()` clears any `@pending_clear` flag

**Rationale**:
- Character rendering involves multiple operations (fillrect for background, then text)
- Only mark dirty when the complete character is in the buffer
- Clear pending flag since we've now drawn content

**Code**:
```ruby
def fillrect(x,y,w,h,fg)
  @dpy.poly_fill_rectangle(@buf, gc_for_col(fg,0x0), [x, y, w, h])
  # Don't set dirty - let draw() handle it after complete render
end

def draw(x,y, c, fg, bg, lineattrs)
  @render_mutex.synchronize do
    case lineattrs
    when :dbl_upper
      fillrect(x,y,c.length*char_w*2,char_h*2,bg)
      @skr_dblheight.render_str(@pic, fg, x, y, c)
    # ... other cases ...
    else
      fillrect(x,y,c.length*char_w,char_h,bg)
      c.rstrip!
      @skr.render_str(@pic,fg, x, y, c)
    end
    @pending_clear = false  # Clear pending since we've drawn
    @dirty = true           # Now mark dirty
  end
end
```

### 3. Queue-Aware Flushing

**File**: `lib/window.rb` - `flush()` method
**File**: `termtest.rb` - flush thread

**Change**:
- `flush()` now accepts optional `queue` parameter
- Don't flush if queue is not empty (operations still pending)
- Only flush complete frames when queue is drained

**Rationale**:
- Prevents flushing between related operations split across queue items
- Ensures clear+redraw sequences are atomic from viewer's perspective

**Code**:
```ruby
def flush(queue = nil)
  return unless @render_mutex.try_lock

  begin
    # Don't flush if queue not empty - ensures complete frames
    if queue && !queue.empty?
      return
    end

    # Timeout safety: promote pending clears after 50ms
    if @pending_clear
      @pending_clear_time ||= Time.now
      if (Time.now - @pending_clear_time) > 0.05
        @dirty = true
        @pending_clear = false
        @pending_clear_time = nil
      end
    else
      @pending_clear_time = nil
    end

    if @dirty
      @dirty = false
      copy_buffer
    end
  ensure
    @render_mutex.unlock
  end
end
```

**Flush thread**:
```ruby
threads << Thread.new do
  loop do
    @window.flush(@queue)  # Pass queue reference
    sleep(1/30.0)
  end
end
```

### 4. Thread Synchronization

**File**: `lib/window.rb` - initialization and rendering methods

**Changes**:
- Added `@render_mutex` initialized early in constructor (before `create_buffer`)
- Both `clear()` and `draw()` use `@render_mutex.synchronize`
- `flush()` uses `@render_mutex.try_lock` to avoid blocking

**Rationale**:
- Prevents flush thread from copying buffer mid-operation
- `try_lock` ensures flush thread doesn't block if rendering in progress
- Protects the `@pending_clear` flag from race conditions

## Safety Mechanisms

### Timeout for Standalone Clears

Not all clears are followed by redraws. The 50ms timeout in `flush()` ensures:
- If a clear has no subsequent draw within 50ms, it's promoted to `@dirty`
- Standalone clears still become visible (just delayed slightly)
- No visual corruption or stuck states

### Mutex Error Handling

- Mutex always unlocked via `ensure` clause
- Early returns properly handled
- No deadlock scenarios

## Results

**Before**: Severe flickering, especially with Claude Code status line updates and fast typing

**After**: Far less flickering - clear+redraw sequences now appear atomic to the user

## Known Limitations / Future Work

This is a **workaround**, not the proper solution. The proper fix requires implementing the full TrackChanges architecture (see `lib/trackchanges.rb`):

### Proper Solution: Complete TrackChanges Implementation

TrackChanges should:

1. **Buffer ALL operations** before rendering to graphical layer
   - Clears, draws, cursor moves, scrolls
   - Accumulate in logical frame boundary

2. **Compute net changes**
   - If a line is cleared then rewritten, only perform final write
   - Eliminate redundant operations entirely
   - No workarounds needed for deferred dirty flags

3. **Batch dirty regions**
   - Track which regions actually changed
   - Mark `@window.dirty` once per logical frame
   - Not once per operation

4. **Frame-based rendering**
   - Define clear frame boundaries (e.g., when queue drains)
   - Render all accumulated changes atomically
   - Natural flicker elimination

### Why Not Implement Proper Solution Now?

- TrackChanges partial implementation exists but needs major refactoring
- Would require touching escape sequence handling, buffer management, and rendering
- Current workaround achieves "far less flickering" with minimal changes
- Proper solution is a larger architectural project

## Testing

To reproduce the original issue and verify the fix:

1. Run with logging: `LOG_TERM=1 ruby termtest.rb`
2. Launch Claude Code inside the terminal
3. Observe status line during "harmonizing" animation
4. Type rapidly and observe during keypress processing
5. Check logs for patterns:
   - `/tmp/term_output.log` - escape sequences sent by application
   - `/tmp/term_flush.log` - flush timing and skipped flushes
   - `/tmp/term_draw.log` - draw operations

Expected log patterns:
- Many "FLUSH SKIPPED (queue not empty)" entries during updates
- `\e[2K\e[1A` sequences grouped before content in output log
- Flushes only when queue drains

## Files Modified

- `lib/window.rb`: Main anti-flicker implementation
- `lib/trackchanges.rb`: Documentation of proper long-term solution
- `termtest.rb`: Pass queue to flush thread, add logging infrastructure
- `docs/flicker-fix.md`: This document
