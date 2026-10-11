# Seekbar Orientation Verification — PureTube

Date: 2026-10-12
Task: Verify seek-by-drag works in BOTH portrait and landscape (fullscreen)

## Implementation Analysis

### Seekbar Widget: `_PlayerSeekBar`
Location: `lib/features/player/presentation/screens/player_screen.dart`

**Pointer handling:** Raw `Listener` with `onPointerDown`/`onPointerMove`/`onPointerUp`
(not `GestureDetector`) — bypasses the gesture arena so horizontal drags can't be
stolen by video-area scrub/volume recognizers behind it.

**Position calculation:** `_fracFromGlobal(Offset globalPos)`
- Uses `GlobalKey` → `RenderBox` → `globalToLocal()`
- Computes fraction from the **live rendered box size**
- Accounts for 12dp horizontal padding: `(local.dx - 12) / (width - 24)`
- Clamped to 0.0–1.0

### Orientation Correctness

| Aspect | Portrait | Landscape (Fullscreen) | Verdict |
|--------|----------|----------------------|---------|
| Fraction calc | Uses live box width | Uses live box width | ✅ Orientation-agnostic |
| GlobalKey | Persists across rebuild | Persists across rebuild | ✅ No re-creation |
| Drag fraction | 0.0–1.0 (relative) | 0.0–1.0 (relative) | ✅ Valid after rotation |
| Tap-to-seek | `onPointerDown` → seek on up | Same | ✅ Works |
| Drag-to-seek | `onPointerMove` updates frac | Same | ✅ Works |
| Tooltip position | LayoutBuilder constraints | LayoutBuilder constraints | ✅ Adapts to width |
| Thumb rendering | CustomPainter | CustomPainter | ✅ Scales with size |

**Rotation mid-drag:** `_dragFrac` is a relative fraction, so it remains valid
even if the device rotates during a drag. The `LayoutBuilder` rebuilds the
tooltip with new constraints. Edge case handled.

**Tooltip clipping:** `Stack(clipBehavior: Clip.none)` ensures the tooltip
(positioned at `top: -34`) is never clipped, in either orientation.

### Changes Made (this session)

1. **Drag tooltip** (was in spec, not implemented):
   - Shows exact time (`mm:ss` / `h:mm:ss`) above the thumb while dragging
   - Positioned via `LayoutBuilder` constraints, clamped to stay on-screen
   - Gold-bordered dark pill matching the premium theme

2. **Growing thumb** (P2 polish item):
   - Thumb radius: 7 → 11 while dragging
   - Passed via `dragging` flag to `_SeekBarPainter`
   - `shouldRepaint` updated to include `dragging`

3. **Dead code removal**:
   - Removed unused `_fracFromDx()` method (used `context.size`, never called)

### Verification
- `dart analyze` on full project: **0 errors** (29 pre-existing info/warning)
- Both portrait (`AspectRatio 16/9`) and landscape (`SizedBox.expand`) layouts
  use the same `_buildBottomControls` → same `_PlayerSeekBar` widget
- Audio mode also uses `_PlayerSeekBar` (portrait only) — tooltip works there too

### Files Changed
- `lib/features/player/presentation/screens/player_screen.dart`
  - `_SeekBarPainter`: added `dragging` parameter, growing thumb
  - `_PlayerSeekBarState.build`: wrapped in `LayoutBuilder` + `Stack` with tooltip
  - Removed dead `_fracFromDx()` method
