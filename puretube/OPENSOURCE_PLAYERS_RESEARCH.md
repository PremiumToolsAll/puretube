# Open Source Android Media Players — Research for PureTube

Research date: 2026-10-12
Goal: Find the best open-source players to learn UI/UX, gestures, and design from — especially MX Player-style premium dark UIs.

---

## 1. Video Players

### 1.1 VLC for Android
- **URL:** https://code.videolan.org/videolan/vlc-android/ (GitLab, not GitHub)
- **License:** GPL-2.0-or-later
- **Stars:** N/A (VideoLAN's own GitLab)
- **Key features:**
  - Plays everything (huge codec support via libVLC)
  - Audio equalizer with presets
  - Subtitle/audio track selection
  - Background audio mode, Chromecast
  - Media library with folder browsing
- **Learn for PureTube:**
  - Equalizer UI (5-band with presets) — PureTube has no EQ
  - Their "audio mode" keeps the queue + playlist visible — good reference for our audio screen
  - Resume-playback per video with progress bars on thumbnails

### 1.2 mpv-android
- **URL:** https://github.com/mpv-android/mpv-android
- **License:** MIT
- **Stars:** ~3,600
- **Key features:**
  - Built on libmpv (same engine family as PureTube's media_kit!)
  - **Gesture-based seeking, volume/brightness control** — the reference implementation
  - Secondary/dual subtitle support (libass styled subs)
  - High-quality rendering (scalers, debanding, interpolation)
  - Background playback, PiP, keyboard input
- **Learn for PureTube:**
  - ⭐ **Gesture handling code** (`MPVView` touch handling) — swipe zones, velocity-based seek, volume/brightness HUD timing
  - Since PureTube also uses mpv under the hood (via media_kit), their mpv property usage (`setProperty` patterns) is directly applicable
  - Dual-subtitle rendering approach

### 1.3 mpvEx (mpvExtended)
- **URL:** https://github.com/marlboro-advance/mpvEx
- **License:** Apache-2.0
- **Stars:** ~2,600
- **Key features:**
  - mpv-android fork with **easier, more polished interface**
  - File browsing, network shares (SMB), PiP
  - Customizable gesture actions
- **Learn for PureTube:**
  - How they simplified mpv-android's bare UI into something consumer-friendly
  - Settings organization for a powerful engine (good IA reference)

### 1.4 mpvRex (→ REX Player)
- **URL:** https://github.com/sfsakhawat999/mpvRex
- **License:** Apache-2.0
- **Stars:** active community
- **Key features:**
  - Fork of mpvEx with Jetpack Compose UI
  - ⭐ **Seek cancellation** — cancel an in-progress seek by dragging finger back (unique!)
  - A-B loop, frame-by-frame stepping
  - **Persistent mini player** with background audio, swipe-up morphing to fullscreen
  - Swipe-to-skip gestures on mini player bar
  - Subtitle seek gesture (swipe near bottom edge to jump between subtitles)
  - Single-tap left/right to seek, relative seeking
  - Player always-dark mode, bottom-controls layout toggle
- **Learn for PureTube:**
  - ⭐ **Seek cancellation** — genuinely novel, YouTube/MX don't have it
  - Mini-player morphing animation (swipe up to expand) — matches our mini bar → fullscreen flow
  - Subtitle-skip gesture — nice power-user feature for our subtitle support
  - Design credits list Next Player + Gramophone as inspirations — same taste as ours

### 1.5 Next Player
- **URL:** https://github.com/anilbeesetti/nextplayer
- **License:** GPL-3.0-only
- **Stars:** ~4,500
- **Key features:**
  - Native Kotlin + Jetpack Compose, Material 3 (Material You dynamic color)
  - Vertical swipe brightness (left) / volume (right)
  - Horizontal swipe to seek
  - Pinch to zoom, resize modes (fit/stretch/crop/100%)
  - Volume boost, external subtitles, controls lock, PiP
  - DASH/HLS/RTSP streaming support
- **Learn for PureTube:**
  - ⭐ **Cleanest gesture implementation** of the MX-style trio (left=brightness, right=volume, horizontal=seek)
  - Controls-lock pattern (prevent accidental touches)
  - Volume boost UI — PureTube could add this (mpv `volume` > 100)

### 1.6 Nova Video Player
- **URL:** https://github.com/nova-video-player/aos-AVP
- **License:** Apache-2.0
- **Stars:** long-running project (Archos fork)
- **Key features:**
  - Network protocols: SMB, SFTP, WebDAV, FTP(S), UPnP
  - Auto movie/TV metadata with posters and backdrops
  - Audio boost, night mode (dynamic volume leveling)
  - Subtitle/audio sync adjustment, private mode
  - Android TV leanback UI
- **Learn for PureTube:**
  - Night mode (dialogue volume leveling) — premium audio feature
  - Metadata-rich library design (posters/backdrops) — our Library tab could borrow this

### 1.7 NexusPlayer
- **URL:** https://github.com/calfo903/nexusplayer
- **License:** GPL-3.0
- **Key features (self-described):** "combining the raw playback power & advanced codec control of VLC with the ultra-smooth, premium gesture interactions of MX Player Pro"
  - ExoPlayer/Media3 engine, Jetpack Compose Material 3 UI
  - ⭐ MX-style gestures: double-tap seek, vertical swipe brightness/volume, horizontal scrubbing, **pinch-to-zoom, two-finger speed control**
  - VLC-style 5-band equalizer + bass boost + up to 200% loudness
  - Whisper AI subtitle auto-generation
  - Auto-next episode detection, Chromecast/DLNA
- **Learn for PureTube:**
  - ⭐ **Two-finger vertical swipe for speed control** — novel gesture we don't have
  - Their explicit "VLC power + MX Player gestures" positioning is exactly PureTube's ambition
  - AI subtitle generation concept (long-term)

### 1.8 Ryzix Player
- **URL:** https://github.com/RD7890/Ryzix-Player
- **License:** MIT
- **Key features:**
  - Kotlin + Media3/ExoPlayer, **Material You** design
  - Gesture controls (swipe brightness/volume, double-tap ±10s)
  - Screen lock, subtitles (SRT/ASS/SSA), audio track selector
  - Speed 0.25×–4×, aspect ratio modes (Fit/Fill/Stretch/Zoom/16:9/4:3)
  - PiP, background playback with media-session notification, watch history
- **Learn for PureTube:**
  - Aspect-ratio mode list is the most complete seen — our fit-cycle could adopt the same set
  - Material You dynamic theming done well

### 1.9 Android Offline Video Player (kaushik-jagani)
- **URL:** https://github.com/kaushik-jagani/android-offline-video-player
- **License:** (not verified via API; repo visible)
- **Key features:**
  - Kotlin + Media3 + Material Design 3, **dark UI inspired by MX Player**
  - Horizontal swipe seek **with frame thumbnail preview**
  - Double-tap = play/pause (configurable)
  - Scrollable toolbar: A-B repeat, equalizer, speed, screenshot, rotation, night mode, loop, mute, sleep timer
  - Screen lock, auto-rotate by video dimensions, remaining-time display
- **Learn for PureTube:**
  - ⭐ **Seek preview with frame thumbnail** — premium touch our seekbar lacks
  - Toolbar overflow pattern for many player actions (we have ⋮ sheet; their horizontal toolbar is faster)
  - Screenshot button — easy win

---

## 2. YouTube Clients

### 2.1 NewPipe
- **URL:** https://github.com/TeamNewPipe/NewPipe
- **License:** GPL-3.0-or-later
- **Stars:** ~40,000
- **Key features:**
  - No Google account / no Play Services needed
  - ⭐ **Popup player** (resizable floating window) — the original inspiration for ours
  - Background audio (audio-only stream to save data)
  - 4K, subtitles, downloads (video/audio/subtitles), local playlists
  - Channel subscriptions with groups, watch history, comments
  - Kodi integration
- **Learn for PureTube:**
  - ⭐ **Popup player implementation** — resizable, draggable, remember position
  - Their background-audio mode loads **audio-only streams** (data saver) — we already do `toggleAudioOnly`
  - Download dialog with format/quality selection — compare with ours
  - Note: codebase is in maintenance mode (bugfixes only)

### 2.2 LibreTube
- **URL:** https://github.com/libre-tube/LibreTube
- **License:** GPL-3.0-or-later
- **Stars:** ~12,800
- **Key features:**
  - YouTube client with subscriptions, playlists, downloads, no Google account
  - Modern Material You UI, sponsorblock + DeArrow integration
  - Piped backend (optional now; direct YouTube default in v32+)
- **Learn for PureTube:**
  - SponsorBlock UI (skip button + colored segments on seekbar) — **directly applicable**, we have the segments API already
  - DeArrow (crowdsourced titles/thumbnails) concept
  - Their player UI is the closest open-source analog to YouTube's own

---

## 3. Downloaders

### 3.1 Seal
- **URL:** https://github.com/JunkFood02/Seal
- **License:** GPL-3.0
- **Stars:** ~29,600
- **Key features:**
  - yt-dlp backend (1000+ sites), aria2c external downloader
  - Audio extraction with metadata + thumbnail embedding (mutagen)
  - Playlist download, subtitle embedding, custom yt-dlp command templates
  - **Material Design 3, dynamic color, pure Kotlin, single-activity Compose**
- **Learn for PureTube:**
  - ⭐ **Download UX gold standard**: quality list → format → audio/video toggle → progress with speed
  - Custom command templates — power-user feature
  - Their share-sheet integration ("Share → Seal") — PureTube could register as share target
  - Note: native Android (Kotlin); ours is Flutter, so borrow UX patterns not code

---

## 4. Music Players (for PureTube's Audio Mode)

### 4.1 Metrolist
- **URL:** https://github.com/MetrolistGroup/Metrolist (org)
- **License:** GPL-3.0
- **Stars:** ~13,400
- **Key features:**
  - YouTube Music client, Material 3, downloads, synced lyrics, equalizer, listen-together sessions, Android Auto
- **Learn for PureTube:**
  - ⭐ **Audio-mode UI reference** — this is what a premium YT-Music-style player looks like
  - Synced lyrics UI pattern, queue management

### 4.2 Kreate (RiMusic fork)
- **URL:** https://github.com/knighthat/Kreate
- **License:** GPL-3.0
- **Stars:** ~1,150
- **Key features:** Built-in downloader, offline music, Material You
- **Learn for PureTube:** Offline-first audio architecture

### 4.3 Gramophone
- **URL:** https://github.com/Akanetan/Gramophone (also FoedusProgramme/Gramophone fork)
- **License:** (UI-focused player)
- **Key features:** Design-first offline music player
- **Learn for PureTube:** Cited by mpvRex as design inspiration — worth a look for audio-mode aesthetics

---

## 5. What PureTube Should Steal (Prioritized)

### Immediate (small, high impact)
1. **Seek preview thumbnail** (kaushik-jagani player) — show frame preview while scrubbing
2. **A-B repeat + loop single** (multiple players) — easy, users love it
3. **Screenshot button** in ⋮ sheet — trivial via mpv `screenshot` command
4. **Volume boost >100%** (Next Player / NexusPlayer) — mpv `volume-max` property
5. **Screen lock** (Next Player / Ryzix) — one tap disables gestures
6. **Aspect-ratio mode list** (Ryzix: Fit/Fill/Stretch/Zoom/16:9/4:3) — expand our fit-cycle

### Medium (bigger wins)
7. **SponsorBlock skip UI** (LibreTube) — colored segments on seekbar + auto-skip toast; we already fetch segments
8. **Seek cancellation** (mpvRex) — drag back to cancel a seek; unique differentiator
9. **Two-finger speed gesture** (NexusPlayer) — novel, fits our 0.25x–4x range
10. **Equalizer** (VLC / NexusPlayer 5-band) — mpv `af` audio filters can do this
11. **Subtitle-skip gesture** (mpvRex) — swipe near bottom to jump between subtitle lines
12. **Share-target registration** (Seal) — "Share → PureTube" from YouTube app

### Long-term (concepts)
13. **AI subtitle generation** (NexusPlayer/Whisper) — on-device, premium feel
14. **Night mode audio leveling** (Nova) — dialogue clarity
15. **DeArrow integration** (LibreTube) — crowdsourced titles/thumbnails

### Gesture reference card (MX-style standard)
| Gesture | Action | Source |
|---|---|---|
| Left vertical swipe | Brightness | Next Player, MX |
| Right vertical swipe | Volume | Next Player, MX |
| Horizontal swipe | Seek | Next Player, MX |
| Double-tap left/right | ±10s (configurable) | MX, PureTube ✓ |
| Pinch | Zoom (fit/fill/crop) | Next Player, MX |
| Two-finger vertical | Playback speed | NexusPlayer ⭐ |
| Single tap | Toggle controls | all |
| Swipe near bottom | Subtitle skip | mpvRex ⭐ |
| Drag back mid-seek | Cancel seek | mpvRex ⭐ |

---

## 6. License Notes for PureTube

- **MIT / Apache-2.0** (mpv-android, mpvEx, mpvRex, Nova, Ryzix): permissive — can borrow code with attribution
- **GPL-3.0** (NewPipe, LibreTube, Seal, Next Player, Metrolist, Kreate, NexusPlayer): copyleft — **do not copy code** into PureTube; use only for UX ideas/patterns
- **GPL-2.0** (VLC): copyleft — same restriction

**Rule of thumb:** Study GPL apps for *what* to build, never *copy* their code. MIT/Apache apps can be referenced more freely, but PureTube is Flutter/Dart while most are native Kotlin — in practice we're porting concepts anyway.
