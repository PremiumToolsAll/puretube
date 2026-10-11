# PureTube Overnight Research — YouTube Feature Parity Deep Dive

**Date:** 2026-10-12 (overnight session)
**Scope:** Player features, background playback, downloads, UI/UX, performance
**Method:** Web research (9to5Google, Android Police, Android Authority, official Android docs, pub.dev) + PureTube source audit (`~/workspace/puretube/lib/`)

---

## 1. EXECUTIVE SUMMARY

PureTube already covers YouTube's **core** player surface (play/pause, seek, quality, speed, subtitles, PiP, mini player, downloads, sleep timer). The gaps are in **advanced/power-user features**: video chapters, ambient mode, pinch-to-zoom, stats overlay, seek-interval customization, 4x speed, smart downloads, and gesture polish. None of these are architectural rewrites — all can be built on the existing `PureTubeAudioHandler` + `PlayerController` + media_kit stack.

**Biggest user-facing wins (effort vs impact):**
1. Video chapters (highly visible, differentiator)
2. Double-tap seek customization (settings, 5/10/15/20/30/60s)
3. Playback speed up to 4x (one-line clamp change)
4. Pinch-to-zoom in fullscreen
5. "Stats for nerds" debug overlay (helps diagnose the DASH/background issues too)

---

## 2. FEATURE INVENTORY

### 2.1 Player Features

| Feature | YouTube | PureTube | Gap |
|---|---|---|---|
| Play/Pause (72px, animated) | ✅ | ✅ | — |
| Next/Previous | ✅ | ✅ | — |
| Seekbar (drag + tap, tooltip) | ✅ | ✅ | — |
| Double-tap ±10s seek | ✅ | ✅ (hardcoded 10s) | **No duration setting** |
| Double-tap interval setting (5/10/15/20/30/60s) | ✅ Settings → General | ❌ | **MISSING** |
| Long-press 2x speed | ✅ | ✅ | — |
| Speed control | 0.25x–4x (0.05 steps mobile) | 0.5x–2.0x | **Capped at 2x** |
| Quality selection (incl. DASH 1440p/2160p) | ✅ | ✅ | — |
| Subtitles/CC | ✅ | ✅ | — |
| **Video chapters** | ✅ (description timestamps → segmented seekbar, haptic on change, chapter list, chapter loop) | ❌ | **MISSING** |
| Chapter loop (repeat one chapter) | ✅ | ❌ | **MISSING** |
| **Ambient mode** (video-color glow around player, dark mode) | ✅ (Settings → Additional settings) | ❌ | **MISSING** |
| **Pinch-to-zoom** (up to 8x, portrait + landscape) | ✅ | ❌ (fit-cycle button only) | **MISSING** |
| **Stats for nerds** (resolution, codec, bandwidth, buffer health, dropped frames overlay) | ✅ | ❌ | **MISSING** |
| Sleep timer | ✅ | ✅ | — |
| "Jump ahead" (AI skip to highlights) | ✅ (Premium) | ❌ | **MISSING** (needs ML — defer) |
| Swipe up = fullscreen, swipe down = exit | ✅ | ❌ | **MISSING** |
| Volume/brightness swipe gestures | N/A (system) | ✅ (PureTube extra) | — (keep) |
| Audio-only mode | ✅ (Premium bg play) | ✅ (PureTube extra) | — (keep) |
| Like/Dislike | ✅ | ✅ (just added) | — |
| Share | ✅ | ✅ | — |
| Playback queue ("Play next in queue") | ✅ (Premium) | ⚠️ (Up Next list only) | Partial |
| Continue watching across devices | ✅ | ⚠️ (local history only) | Partial (no account sync — by design, local-first) |

### 2.2 Background Playback

| Feature | YouTube (Premium) | PureTube | Gap |
|---|---|---|---|
| Audio continues on Home/minimize | ✅ | ✅ (audio_service) | — (verify on device) |
| Media notification (play/pause/next/prev/seek) | ✅ | ✅ (audio_service) | — (verify on device) |
| Lock screen media card (art + controls) | ✅ | ✅ (audio_service) | — (verify on device) |
| Bluetooth/headset button controls | ✅ | ✅ (audio_service) | — |
| Headphone unplug → auto-pause | ✅ | ✅ (audio_service) | — |
| Phone call → auto-pause (audio focus) | ✅ | ✅ (OS-level) | — |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (API 34+) | ✅ | ✅ (manifest) | — |
| WAKE_LOCK permission | ✅ | ⚠️ **check manifest** | Verify |
| Notification while paused (`androidStopForegroundOnPause: false`) | ✅ | ✅ | — |
| 10-min idle → service leaves foreground (Media3 guidance) | ✅ | ⚠️ | Consider: stop service after long pause to save battery |

**Android best-practice notes (from developer.android.com/media3 + community):**
- Start the foreground service **while the activity is visible** (on play press) — Android 12+ blocks FGS starts from background.
- Keep `Player` + `MediaSession` in the service; notification updates are automatic from player state.
- `onTaskRemoved()`: keep service running if playing, stop if paused (PureTube currently stops on `detached` — matches this).
- Media-style notifications are **exempt** from the `POST_NOTIFICATIONS` runtime permission on Android 13+ (still request it for other notifications).
- Xiaomi/MIUI + Samsung One UI kill background apps aggressively even with "No restrictions" — in-app guidance (Settings → Battery → No restrictions, Autostart) is the standard mitigation; PureTube already tells the user this.
- Low-priority foreground notification reduces OEM battery-killer targeting (Samsung Device Care flags DEFAULT priority as "battery intensive").

### 2.3 Downloads

| Feature | YouTube (Premium) | PureTube | Gap |
|---|---|---|---|
| Manual download (quality picker 144p–1080p + audio-only) | ✅ | ✅ | — |
| Download management screen | ✅ | ✅ | — |
| Offline playback | ✅ | ✅ | — |
| **Smart Downloads** (auto-download recommended over WiFi, default 360p up to 1080p, ~4GB budget, user-adjustable) | ✅ | ❌ | **MISSING** |
| Download only on WiFi toggle | ✅ | ⚠️ | Verify |
| Download expiration (30-day refresh) | ✅ | ❌ | **MISSING** |
| Storage usage indicator / per-download size | ✅ | ⚠️ (partial — speed shown) | Partial |
| Background download with progress notification | ✅ | ✅ | — |
| Shorts downloads | ✅ (separate) | ❌ | **MISSING** |
| Download queue (multiple concurrent) | ✅ | ⚠️ | Verify |

### 2.4 UI/UX — Latest YouTube Patterns (2024–2026)

| Pattern | YouTube | PureTube | Gap |
|---|---|---|---|
| Rounded "expressive" buttons (thumbs, share, comments) | ✅ (2024 redesign) | ⚠️ (gold theme instead — intentional) | Design choice, keep |
| Mini player: play/pause flanked by ±10s | ✅ (2024) | ✅ (just added) | — |
| Mini player draggable to screen corners | ✅ | ❌ (fixed bottom bar) | **MISSING** |
| Seekbar chapter segments | ✅ | ❌ (needs chapters) | **MISSING** |
| Haptic on chapter change while scrubbing | ✅ | ❌ | **MISSING** |
| Scrub preview thumbnails (storyboard) | ✅ | ❌ | **MISSING** (needs storyboard data — youtube_explode may not expose; defer) |
| Press ripple + scale | ✅ | ✅ (PressScale) | — |
| Play/pause icon morph | ✅ | ✅ (AnimatedSwitcher) | — |
| Seekbar thumb grows on drag | ✅ | ✅ (just added) | — |
| Glassmorphism / blurred album art | ✅ (ambient) | ✅ (audio mode) | — |
| Edge-to-edge + gesture nav | ✅ | ✅ | — |

### 2.5 Performance

| Strategy | Status in PureTube | Notes |
|---|---|---|
| Thumbnail caching (cached_network_image) | ✅ | Already used |
| HTTP disk cache for streams (ExoPlayer SimpleCache / mpv cache) | ❌ | media_kit/mpv: `cache` mpv property exists; YouTube URLs are signed+expiring so stream caching has limited value — **thumbnail + metadata caching matters more** |
| Feed pagination | ✅ (SearchSession paging) | — |
| Preload next video's metadata while watching | ❌ | **Opportunity:** prefetch Up Next thumbnails/details |
| Adaptive bitrate (DASH) | ✅ (manual quality select) | Auto-ABR not implemented — manual is fine for now |
| Image downscaling for notification art (`artDownscaleHeight`) | ⚠️ | audio_service supports `artDownscaleWidth/Height` — set to reduce memory |
| Startup: defer non-critical init | ✅ (try/catch fallbacks in main) | — |
| Watchdog for stuck streams | ⚠️ | media_kit article pattern: 5s timer, reopen if position frozen — consider adding |

---

## 3. PRIORITY RANKING

### P0 — Fix first (correctness)
1. **Background/notification device verification** — code is correct; needs the Settings diagnostic result from the user's phone (green vs red). If red, `AudioService.init` is throwing on Xiaomi — capture the exception.
2. **WAKE_LOCK permission check** — verify `android.permission.WAKE_LOCK` is in the manifest (needed for uninterrupted audio with screen off on some OEMs).

### P1 — High-impact user features
3. **Video chapters** — parse `00:00` timestamps from description → segmented seekbar + chapter list sheet + haptic on chapter cross + "current chapter" label. PureTube already fetches full description; parsing is a regex.
4. **Double-tap seek duration setting** — 5/10/15/20/30/60s in Settings; replace hardcoded 10s in `_onDoubleTap` and mini player buttons.
5. **Playback speed to 4x** — change `setSpeed` clamp from 2.0 to 4.0; add 2.5x/3x/4x chips to speed sheet.

### P2 — Polish / differentiation
6. **Pinch-to-zoom in fullscreen** — `InteractiveViewer` (maxScale 8.0) around the video in fullscreen; double-tap-drag pan while zoomed. Conflicts with existing double-tap seek — resolve via gesture arena (pinch = 2 pointers wins).
7. **Ambient mode** — sample dominant color from video thumbnail (already cached via cached_network_image) → animated gradient glow behind player in dark UI; toggle in player settings. Cheap version: use thumbnail's dominant color; expensive version: per-frame sampling (defer).
8. **"Stats for nerds" overlay** — toggle in player ⋮ menu → overlay showing: current quality label, codec, container, player position/buffer/duration, network state. Data available from `PlayerController` state + media_kit streams. Also helps future debugging.
9. **Swipe up/down for fullscreen** — vertical swipe on video toggles fullscreen (YouTube pattern); must not conflict with volume/brightness swipes (use swipe on center region or require fast fling).

### P3 — Downloads depth
10. **Smart Downloads** — overnight job: pick N unwatched videos from home feed, download at 360p over WiFi+charging, 2GB default budget, toggle in Settings → Downloads. Reuse existing `DownloadService`.
11. **Download expiration refresh** — 30-day TTL on download records; "Refresh" button re-downloads expired items.
12. **Shorts downloads** — route Shorts through the same download pipeline.

### P4 — Defer
- "Jump ahead" AI highlights (needs ML model — out of scope)
- Scrub preview storyboards (youtube_explode_dart may not expose storyboard spec — verify before attempting)
- Cross-device continue watching (no account system — local-first by design)
- Mini player drag-to-corner (nice-to-have; bottom bar works)

---

## 4. IMPLEMENTATION NOTES — TOP 5 MISSING FEATURES

### #1 Video Chapters

**What YouTube does:** Creators put `00:00 Intro` / `02:31 Demo` lines in the description (first stamp must be 0:00, ≥3 stamps, each ≥10s). Player draws segmented seekbar, shows chapter title while scrubbing, haptic "thump" on chapter cross, chapter list in description sheet, per-chapter loop.

**PureTube implementation plan:**
1. **Parser** (`lib/features/player/domain/chapters.dart`): regex `^(?:(\d+):)?(\d{1,2}):(\d{2})\s+(.+)$` over `video.description` (multiline). Validate: first at 0s, ascending, ≥3 chapters, each ≥10s. Return `List<VideoChapter(title, start)>`.
2. **State:** add `List<VideoChapter> chapters` to `PlayerUiState`; parse in `loadVideo()` after `getVideoDetails` (description is already fetched).
3. **Seekbar:** extend `_SeekBarPainter` to draw segment dividers at `chapter.start / duration` fractions (2px gaps, white24). Cheap — no layout change.
4. **Current chapter label:** `position → chapter` lookup in the time-label row; show under the title or as a chip above the seekbar.
5. **Haptic:** in the position listener, detect chapter-index change → `HapticFeedback.selectionClick()`.
6. **Chapter list UI:** section in the description bottom sheet (already exists) listing chapters; tap → `seekTo(chapter.start)`.
7. **Chapter loop (optional P2):** long-press a chapter row → repeat icon; position listener seeks back to chapter start when passing chapter end.

**Files to touch:** new `lib/features/player/domain/chapters.dart`; `player_controller.dart` (state + parse); `player_screen.dart` (painter + label + sheet section). Estimated: ~250 lines.

### #2 Double-Tap Seek Duration Setting

**What YouTube does:** Settings → General → "Double-tap to seek" → 5/10/15/20/30/60s. Applies to double-tap gestures everywhere.

**PureTube implementation plan:**
1. **Preference:** `SharedPreferences` int `double_tap_seconds`, default 10. Add getter/setter in the existing settings/prefs helper.
2. **Settings UI:** new ListTile in `settings_screen.dart` → bottom-sheet radio list (5/10/15/20/30/60).
3. **Player wiring:** replace hardcoded `Duration(seconds: 10)` in `_onDoubleTap` (player_screen.dart ~L351/354) and mini-player `seekBy` calls with the pref value. Read once per gesture (cheap) or cache in controller state.
4. **Ripple label:** the "−10s"/"+10s" flash text should show the configured value.

**Files to touch:** `settings_screen.dart`, `player_screen.dart`, `mini_player_bar.dart`, prefs helper. Estimated: ~60 lines.

### #3 Playback Speed to 4x

**What YouTube does:** 0.25x–4x in fine steps on mobile (Premium "4x" highlighted as a perk).

**PureTube implementation plan:**
1. `player_controller.dart` `setSpeed`: change `s.clamp(0.5, 2.0)` → `s.clamp(0.25, 4.0)`.
2. Speed sheet: add chips 2.5x, 3x, 4x (keep existing 0.5/0.75/1/1.25/1.5/2).
3. media_kit `setRate(4.0)` — mpv handles high rates; audio becomes chipmunky (expected, same as YouTube).

**Files to touch:** `player_controller.dart`, speed sheet in `player_screen.dart`. Estimated: ~15 lines. **Easiest win on this list.**

### #4 Pinch-to-Zoom in Fullscreen

**What YouTube does:** Pinch in fullscreen zooms up to 8x; drag to pan while zoomed; pinch-in returns to "Original".

**PureTube implementation plan:**
1. Wrap the fullscreen `Video` widget in `InteractiveViewer(maxScale: 8.0, minScale: 1.0, panEnabled: true)` — but **only** in fullscreen landscape (YouTube enables it in fullscreen; portrait has it too but landscape is the primary case).
2. **Gesture conflict:** PureTube uses double-tap for ±10s seek and vertical swipes for volume/brightness. `InteractiveViewer` uses scale (2-pointer) — the gesture arena resolves pinch (2 pointers) vs double-tap (1 pointer, 2 taps) cleanly. Vertical 1-finger swipe stays with volume/brightness.
3. Zoom indicator: small "2.4x" pill top-center while `scale > 1.0` (listen via `TransformationController`); "Reset" on tap.
4. Reset zoom on video change (`loadVideo` → `transformationController.value = Matrix4.identity()`).

**Files to touch:** `player_screen.dart` (fullscreen video stack). Estimated: ~80 lines. **Test on device:** pinch vs double-tap arena behavior.

### #5 "Stats for Nerds" Overlay

**What YouTube does:** Player ⋮ → "Stats for nerds" → overlay with video ID, current/optimal resolution, codecs, connection speed, buffer health, dropped frames, viewport.

**PureTube implementation plan:**
1. **Toggle:** add "Stats for nerds" row in the player ⋮ More sheet; persist per-session bool in screen state.
2. **Overlay widget:** `Positioned(top: 8, left: 8)` monospace 11px text on black54, non-interactive (`IgnorePointer`).
3. **Data sources (all already available):**
   - Video ID / title: `uiState.video`
   - Current quality: `uiState.currentQuality?.label` (e.g. "1080p", "1440p (1.5K)")
   - Codec/FPS/bitrate: `MuxedQuality` already carries codec/fps/bitrate fields
   - Position / duration / buffer: `player.stream.position/duration/buffer`
   - Connection: `ConnectivityResult` (existing connectivity handling) — show "WiFi"/"mobile"
   - Dropped frames: not exposed by media_kit — omit or show "n/a"
4. **Why it matters beyond nerds:** gives the user a way to screenshot real playback state when reporting "DASH not working" — replaces guesswork.

**Files to touch:** `player_screen.dart` (sheet row + overlay widget). Estimated: ~70 lines.

---

## 5. SOURCES

- Video chapters: techwatchph.com (2026-10-05), versely.studio blog, androidcentral.com (chapter loop), beebom.com
- Ambient mode: makeuseof.com, digitaltrends.com, techyorker.com, screenapp.io (2026), androidpolice.com
- Pinch-to-zoom: makeuseof.com, gbtimes.com, phonearena.com (Zoom to fill screen setting)
- Stats for nerds: alanspicer.com (guide), minitool.com, newsbytesapp.com
- Double-tap customization: phonearena.com (48 days ago), technipages.com, androidauthority.com, croma.com (swipe fullscreen, long-press 2x)
- Smart downloads: digitalmusicnews.com, webpronews.com, androidinfotech.com, rsoblog.com
- Background best practices: developer.android.com/media/media3/session/background-playback (via GitHub mirrors), capgo.app, ghostify solution.md (device checklist), emircanoz2020-stack (OEM quirks)
- Caching: medium.com (ExoPlayer CacheDataSource, SimpleCache + LRU), better_native_video_player_plus (pub.dev — Media3 cache + precache pattern), moldstud.com

---

## 6. NOTES FOR IMPLEMENTATION ORDER

Suggested build sequence (each is independently shippable, smallest first):
1. **Speed 4x** (15 lines) → immediate
2. **Double-tap setting** (60 lines) → settings + player
3. **Stats for nerds** (70 lines) → debugging aid for everything else
4. **Video chapters** (250 lines) → biggest visible win
5. **Pinch-to-zoom** (80 lines) → needs device testing for gesture conflicts
6. **Ambient mode** (thumbnail-color glow, ~100 lines) → visual delight
7. **Smart downloads** (new service + scheduler, ~400 lines) → largest, do last

All features build on the existing `PureTubeAudioHandler` + `PlayerController` architecture. No new player singletons. No Isar. Hive stays.
