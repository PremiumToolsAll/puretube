# YouTube Feature Parity Research — PureTube

Research date: 2026-10-12
Sources: 9to5Google, Android Police, YouTube app behavior

## 1. YouTube Player Buttons

### Fullscreen Player
| Button | PureTube Status |
|--------|----------------|
| Play/Pause (center, large) | ✅ Present |
| Next/Previous | ✅ Present |
| Seek bar with time labels | ✅ Present |
| Fullscreen toggle | ✅ Present |
| Settings (quality/speed/subtitles) | ✅ Present |
| PiP button | ✅ Present |
| Audio mode toggle | ✅ Present (PureTube extra) |
| Like/Dislike | ⚠️ Like only, no Dislike |
| Share | ✅ Present |
| Comments button | ✅ Present (via UI) |
| Sleep timer | ✅ Present |
| Double-tap ±10s seek | ✅ Present |
| Volume/brightness swipe | ✅ Present |

### Mini Player (YouTube's new 2024 design)
| Button | PureTube Status |
|--------|----------------|
| Play/Pause | ✅ Present |
| 10s rewind | ❌ MISSING |
| 10s forward | ❌ MISSING |
| Close (X) | ✅ Present |
| Draggable to corners | ❌ MISSING (fixed bottom bar) |
| Expand on tap | ✅ Present |

### Notification / Lock Screen
| Button | PureTube Status |
|--------|----------------|
| Play/Pause | ✅ via audio_service |
| Next/Previous | ✅ via audio_service |
| Seek bar | ✅ via audio_service |
| 10s rewind/forward | ✅ via MediaControl.rewind/fastForward |

## 2. YouTube Button Animations
- Press: ripple effect + slight scale
- Play/Pause: icon morph with rotation
- Seek bar: thumb grows while dragging
- PureTube: PressScale (0.88x scale, 200ms) ✅ applied

## 3. YouTube Background Playback
- Audio continues when app minimized
- Notification with media controls
- Lock screen controls
- PureTube: implemented via audio_service, diagnostic added to Settings

## 4. YouTube Downloads
- Quality selection (144p–1080p, audio only)
- Download management screen
- Offline playback
- PureTube: ✅ all present (download sheet, downloads screen, offline player)

## Gap Analysis — Priority Order

### P0 (Critical)
1. Background/notification fix verification (diagnostic in Settings)

### P1 (High — YouTube parity)
2. Mini player: add 10s rewind/forward buttons (YouTube's new miniplayer has these)
3. Add Dislike button next to Like (YouTube has both)

### P2 (Medium — Polish)
4. Play/pause icon morph animation (AnimatedSwitcher with rotation)
5. Seek bar thumb grows while dragging

### Already Complete
- Press animations (PressScale on all buttons)
- State accuracy (all toggles reflect real state)
- Popup player (7 buttons matching design)
- Download system
- Sleep timer, speed, quality, subtitles
