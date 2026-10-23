import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:puretube_playback/puretube_playback.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../../core/database/hive_setup.dart';
import '../../../../core/di/providers.dart';
import '../../../../main.dart' as app_main;
import '../../../../core/error/exceptions.dart';
import '../../../../core/services/pip_service.dart';
import '../../../../core/services/sponsorblock_service.dart';
import '../../../../core/services/lyrics_service.dart';
import '../../../../core/services/watch_category_tracker.dart';
import '../../../../core/services/youtube_extractor_service.dart';

import '../../../settings/presentation/providers/quality_providers.dart';
import 'popup_visibility.dart';
import '../../data/services/audio_player_handler.dart';
import '../../domain/entities/playback_models.dart';
import '../../../library/presentation/providers/library_providers.dart';

enum PlayerStatus { idle, loading, ready, error }

class PlayerUiState {
  final PlayerStatus status;
  final String? videoId;
  final VideoDetails? video;
  final PlaybackStreams? streams;
  final String? errorMessage;
  final bool isInPip;
  final bool audioOnly;
  final double speed;
  final Duration? sleepRemaining;
  final Duration? sleepTotal;
  final bool sleepEndOfVideo;
  final List<SponsorSegment> sponsorSegments;
  final bool skipSponsors;
  final bool pipSupported;
  final List<CaptionTrack> subtitleTracks;
  final CaptionTrack? activeSubtitle;
  final List<CaptionCue> captionCues;
  final List<MuxedQuality> availableQualities;
  final MuxedQuality? currentQuality;
  final List<AudioLanguage> audioLanguages;
  final AudioLanguage? activeAudioLanguage;
  final List<VideoDetails> relatedVideos;
  final bool relatedFailed;
  final LyricsResult? lyricsResult;
  final bool lyricsLoading;

  /// Native HQ engine marker. Non-null means 1080p+ is playing through
  /// the puretube_playback plugin (NewPipeExtractor + Media3) instead of
  /// mpv — the UI renders a PureTubeVideoView and routes transport
  /// through the plugin controller. (The value itself is unused now;
  /// it used to be a texture id.)
  final int? hqTextureId;

  /// SparkTube-style quality selection: true after the user picks
  /// "Auto" in the quality menu — adaptive playback (the HQ plugin
  /// runs DASH with no height cap). An explicit height pick clears it.
  /// Survives video changes, like SparkTube's session selection.
  final bool autoQuality;

  /// HQ video aspect ratio (width/height) from the native player.
  /// 0 = unknown (UI falls back to 16:9).
  final double hqAspectRatio;

  /// Autoplay: when ON, completing a video automatically starts the
  /// next Up Next video (both video and audio mode).
  final bool autoplay;

  const PlayerUiState({
    this.status = PlayerStatus.idle,
    this.videoId,
    this.video,
    this.streams,
    this.errorMessage,
    this.isInPip = false,
    this.audioOnly = false,
    this.speed = 1.0,
    this.sleepRemaining,
    this.sleepTotal,
    this.sleepEndOfVideo = false,
    this.sponsorSegments = const [],
    this.skipSponsors = true,
    this.pipSupported = false,
    this.subtitleTracks = const [],
    this.activeSubtitle,
    this.captionCues = const [],
    this.availableQualities = const [],
    this.currentQuality,
    this.audioLanguages = const [],
    this.activeAudioLanguage,
    this.relatedVideos = const [],
    this.relatedFailed = false,
    this.lyricsResult,
    this.lyricsLoading = false,
    this.autoplay = true,
    this.hqTextureId,
    this.autoQuality = true,
    this.hqAspectRatio = 0,
  });

  PlayerUiState copyWith({
    PlayerStatus? status,
    String? videoId,
    VideoDetails? video,
    PlaybackStreams? streams,
    String? errorMessage,
    bool? isInPip,
    bool? audioOnly,
    double? speed,
    Duration? sleepRemaining,
    Duration? sleepTotal,
    bool? sleepEndOfVideo,
    bool clearSleep = false,
    List<SponsorSegment>? sponsorSegments,
    bool? skipSponsors,
    bool? pipSupported,
    List<CaptionTrack>? subtitleTracks,
    CaptionTrack? activeSubtitle,
    List<CaptionCue>? captionCues,
    bool clearSubtitle = false,
    List<MuxedQuality>? availableQualities,
    MuxedQuality? currentQuality,
    List<AudioLanguage>? audioLanguages,
    AudioLanguage? activeAudioLanguage,
    bool clearAudioLanguage = false,
    List<VideoDetails>? relatedVideos,
    bool? relatedFailed,
    LyricsResult? lyricsResult,
    bool? lyricsLoading,
    bool clearLyrics = false,
    bool? autoplay,
    int? hqTextureId,
    bool? autoQuality,
    bool clearHq = false,
    double? hqAspectRatio,
  }) {
    return PlayerUiState(
      status: status ?? this.status,
      videoId: videoId ?? this.videoId,
      video: video ?? this.video,
      streams: streams ?? this.streams,
      errorMessage: errorMessage,
      isInPip: isInPip ?? this.isInPip,
      audioOnly: audioOnly ?? this.audioOnly,
      speed: speed ?? this.speed,
      // Preserve the countdown across copyWith calls that don't touch
      // the timer (e.g. loadVideo's ready-state update) — otherwise the
      // timer badge flickers off and back on every track change.
      // clearSleep still clears it (cancel/finish paths).
      sleepRemaining:
          clearSleep ? null : (sleepRemaining ?? this.sleepRemaining),
      sleepTotal: clearSleep ? null : (sleepTotal ?? this.sleepTotal),
      sleepEndOfVideo:
          clearSleep ? false : (sleepEndOfVideo ?? this.sleepEndOfVideo),
      sponsorSegments: sponsorSegments ?? this.sponsorSegments,
      skipSponsors: skipSponsors ?? this.skipSponsors,
      pipSupported: pipSupported ?? this.pipSupported,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      captionCues: captionCues ?? this.captionCues,
      activeSubtitle:
          clearSubtitle ? null : activeSubtitle ?? this.activeSubtitle,
      availableQualities: availableQualities ?? this.availableQualities,
      currentQuality: currentQuality ?? this.currentQuality,
      audioLanguages: audioLanguages ?? this.audioLanguages,
      activeAudioLanguage: clearAudioLanguage
          ? null
          : activeAudioLanguage ?? this.activeAudioLanguage,
      relatedVideos: relatedVideos ?? this.relatedVideos,
      relatedFailed: relatedFailed ?? this.relatedFailed,
      lyricsResult: clearLyrics ? null : (lyricsResult ?? this.lyricsResult),
      lyricsLoading: lyricsLoading ?? this.lyricsLoading,
      autoplay: autoplay ?? this.autoplay,
      autoQuality: autoQuality ?? this.autoQuality,
      hqTextureId: clearHq ? null : (hqTextureId ?? this.hqTextureId),
      hqAspectRatio: clearHq ? 0 : (hqAspectRatio ?? this.hqAspectRatio),
    );
  }
}


/// Orchestrates everything about playback: extraction, the background
/// audio handler, SponsorBlock skipping, sleep timer, speed, audio-only
/// switching, stream-expiry recovery, and auto-PiP.
///
/// Pre-fetched data for one Up Next video, so tapping Next plays instantly.
class PrecachedData {
  final VideoDetails details;
  final PlaybackStreams streams;
  final List<SponsorSegment> segments;

  const PrecachedData({
    required this.details,
    required this.streams,
    this.segments = const [],
  });
}

class PlayerController extends Notifier<PlayerUiState>
    with WidgetsBindingObserver {
  PureTubeAudioHandler get _handler => ref.read(audioHandlerProvider);
  YoutubeExtractorService get _extractor => ref.read(extractorProvider);
  SponsorBlockService get _sponsorBlock => ref.read(sponsorBlockProvider);

  /// Reads the "Prefer AVC" setting (default true).
  bool _preferAvc = true;

  Future<void> _loadPreferAvc() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('prefer_avc');
      if (v != null) _preferAvc = v;
    } catch (_) {}
  }

  PipService get _pip => ref.read(pipServiceProvider);

  StreamSubscription<bool>? _pipSub;
  StreamSubscription<String>? _pipActionSub;
  bool? _lastPipPlaying;

  /// Keeps the system PiP window's play/pause action in sync with
  /// whichever engine is actually playing — one transport state
  /// shared by the main player, the popup, the notification and
  /// the PiP window.
  void _syncPipPlaying(bool playing, {bool force = false}) {
    if (!force && _lastPipPlaying == playing) return;
    _lastPipPlaying = playing;
    unawaited(_pip.setPlaying(playing));
  }

  bool? _lastAutoPip;

  /// Auto-PiP (Home button → the video shrinks into the small
  /// window and keeps playing) is armed only while the full
  /// player is open on a video that is actually playing.
  void _syncAutoPip() {
    final playing = _hqPlaying;
    final enabled = state.status == PlayerStatus.ready &&
        state.video != null &&
        !state.audioOnly &&
        playing &&
        ref.read(fullPlayerOpenProvider);
    if (_lastAutoPip == enabled) return;
    _lastAutoPip = enabled;
    unawaited(_pip.setAutoPip(enabled));
  }

  Timer? _sleepCountdown;
  DateTime? _sleepEndsAt;
  bool _skipInProgress = false;

  /// Sponsor segments already skipped for the current video
  /// ("videoId:start:end"). A segment is never skipped twice: if a
  /// seek lands a hair before the segment end (keyframe rounding),
  /// the position poll would otherwise re-trigger the skip every
  /// 500ms and the video would keep jumping a few seconds at a time.
  final Set<String> _skippedSegmentKeys = {};

  /// Bumps on every setQuality call; lets in-flight verifications detect
  /// when the user has moved on to another quality/video.
  int _qualitySwitchToken = 0;


  // ---------------- native HQ player (1080p+) ----------------
  // The puretube_playback plugin (NewPipeExtractor + Media3, SparkTube-
  // style DASH with merged/muxed fallbacks). Active only when
  // state.hqTextureId != null; everything else stays on mpv.
  // The plugin allows ONE live controller per engine, so it is created
  // lazily on first HQ use and reused for the provider's lifetime.
  PureTubeController? _pt;

  /// The plugin's engine-owned render texture id (fetched once when
  /// the controller is created). Published into
  /// [PlayerUiState.hqTextureId] while the plugin engine is active.
  int _pluginTextureId = -1;
  // Session quality memory (user rule): a fresh app start plays
  // Auto; once the user picks a quality by hand, every later video
  // in this session starts at that pick. Null = no manual pick yet.
  int? _sessionQualityHeight;
  // One-shot resume position for the next direct start (set by
  // retry() so a mid-video retry resumes HERE, not at the last
  // persisted history position).
  Duration? _pendingResumeOnce;
  bool _ptEndedHandled = false;
  String? _lastPluginError;

  /// Video id currently served by the direct-URL fallback (the
  /// plugin's NewPipe resolve was blocked). Keeps the stale resolve
  /// error from resurfacing over healthy fallback playback.
  String? _directFallbackFor;

  /// When YouTube last bot-blocked the plugin resolve. While this
  /// is fresh, fresh engages skip the doomed (and slow) NewPipe
  /// resolve and go straight to the direct fallback — Next stays
  /// instant on a blocked network.
  DateTime? _resolveBlockedAt;

  bool get _resolveBlockedRecently =>
      _resolveBlockedAt != null &&
      DateTime.now().difference(_resolveBlockedAt!) <
          const Duration(minutes: 10);
  // Video id for which the persistent-Auto hook already engaged the
  // HQ engine (prevents a fail/retry loop within one video).
  String? _autoHqEngagedFor;
  String? _pluginEngagedFor;

  /// Media3 PlayerView resize mode mirroring the screen's video fit
  /// choice (0 = contain, 3 = fill, 4 = cover). The mpv widget obeys
  /// the screen's BoxFit directly, but the plugin's native view only
  /// listens to this — without it the fit button and the landscape
  /// frame did nothing while the plugin engine was playing.
  int _pluginResizeMode = 0;

  /// Called by the player screen whenever the video fit changes
  /// (fit button cycle, entering/leaving fullscreen).
  void setVideoFitMode(int mode) {
    _pluginResizeMode = mode;
    final pt = _pt;
    if (pt != null && hqActive) {
      unawaited(pt.setResizeMode(mode).catchError((_) {}));
    }
  }

  PureTubeController get _plugin {
    var c = _pt;
    if (c == null) {
      c = PureTubeController();
      c.addListener(_onPluginChanged);
      _pt = c;
      // One connected notification: when the audio_service session
      // is healthy it carries the media notification (mirror mode),
      // so the plugin's own service notification stays off. Only
      // when AudioService failed does the plugin show its own.
      unawaited(c
          .setServiceNotificationEnabled(!app_main.audioServiceReady)
          .catchError((_) {}));
      c.textureId.then((id) {
        if (id > 0) _pluginTextureId = id;
      }).catchError((_) => -1);
    }
    return c;
  }

  /// Publishes the plugin's REAL texture id once the channel
  /// answers, replacing the -1 "engaged" placeholder. Retries a few
  /// times — the producer is created lazily natively, so the first
  /// read can race it.
  Future<void> _publishTextureId() async {
    for (final wait in const [
      Duration.zero,
      Duration(milliseconds: 800),
      Duration(milliseconds: 2500),
    ]) {
      if (_pluginTextureId > 0) break;
      if (wait > Duration.zero) await Future.delayed(wait);
      try {
        _pluginTextureId = await _plugin.textureId;
      } catch (_) {}
    }
    if (_pluginTextureId > 0 &&
        state.hqTextureId != null &&
        state.hqTextureId != _pluginTextureId) {
      state = state.copyWith(hqTextureId: _pluginTextureId);
    }
  }

  /// Connects the audio handler's media session to the plugin
  /// engine: PiP buttons, the lock screen, the notification and
  /// headset keys now describe and control THIS player — one main
  /// player, everything connected.
  void _engageMirror(VideoDetails video) {
    final h = _handler;
    h.onExternalPlay = () async {
      _hqPlaying = true;
      _hqPlayingCtrl.add(true);
      try {
        await _pt?.play();
      } catch (_) {}
    };
    h.onExternalPause = () async {
      _hqPlaying = false;
      _hqPlayingCtrl.add(false);
      try {
        await _pt?.pause();
      } catch (_) {}
    };
    h.onExternalSeek = (pos) => _seekInternal(pos);
    h.onExternalSetSpeed = (s) => setSpeed(s);
    h.onExternalStop = () => stop();
    h.externalMode = true;
    final artUri = Uri.tryParse(video.thumbnailUrl);
    h.setExternalMediaItem(MediaItem(
      id: video.id,
      title: video.title,
      artist: video.author,
      artUri: (artUri != null &&
              (artUri.scheme == 'http' || artUri.scheme == 'https'))
          ? artUri
          : null,
      duration: video.duration,
    ));
    _pushMirrorState();
  }

  void _pushMirrorState() {
    _syncPipPlaying(_hqPlaying);
    _syncAutoPip();
    if (!_handler.externalMode) return;
    final pt = _pt;
    _handler.setExternalState(
      playing: _hqPlaying,
      buffering: pt?.buffering ?? false,
      completed: pt?.ended ?? false,
      position: _hqPosition,
      buffered: pt?.bufferedPosition ?? Duration.zero,
      speed: state.speed,
    );
  }

  void _disengageMirror() {
    final h = _handler;
    if (!h.externalMode) return;
    h.externalMode = false;
    h.onExternalPlay = null;
    h.onExternalPause = null;
    h.onExternalSeek = null;
    h.onExternalSetSpeed = null;
    h.onExternalStop = null;
    h.refreshState();
  }

  /// Mirrors plugin state into the HQ display fields and forwards the
  /// ended event into the normal completion flow (Next / autoplay).
  void _onPluginChanged() {
    final c = _pt;
    if (c == null || !hqActive) return;
    // Another surface (Shorts / offline player) owns the shared
    // engine right now — its events are not this player's.
    if (PureTubeController.ownerTag != null &&
        PureTubeController.ownerTag != 'main') {
      return;
    }
    // Adopt a recreated render surface's texture id: the native
    // side replaces a dead surface (new id) and reports it in
    // state events; republishing rebuilds the Texture widget onto
    // the fresh surface — the picture comes back by itself.
    final sid = c.stateTextureId;
    if (sid > 0 && sid != _pluginTextureId) {
      _pluginTextureId = sid;
      if (state.hqTextureId != null && state.hqTextureId != sid) {
        state = state.copyWith(hqTextureId: sid);
      }
    }
    if (c.duration > Duration.zero && c.duration != _hqDuration) {
      _hqDuration = c.duration;
      _hqDurationCtrl.add(c.duration);
    }
    if (c.videoWidth > 0 && c.videoHeight > 0) {
      final ar = c.videoWidth / c.videoHeight;
      if ((ar - state.hqAspectRatio).abs() > 0.01) {
        state = state.copyWith(hqAspectRatio: ar);
      }
    }
    // Loud HQ errors (never silent): native playback/resolve failures
    // land in c.error. 'superseded' is just a raced load — ignore it.
    final err = c.error;
    if (err != null &&
        err != _lastPluginError &&
        !err.contains('superseded') &&
        !(_directFallbackFor == state.videoId && _isResolveBlock(err))) {
      _lastPluginError = err;
      state = state.copyWith(
        errorMessage: 'HQ প্লেব্যাক সমস্যা: ${_shortenError(err)}',
      );
    } else if (err == null) {
      _lastPluginError = null;
    }
    if (c.ended) {
      if (!_ptEndedHandled) {
        _ptEndedHandled = true;
        _onPlaybackCompleted();
      }
    } else {
      _ptEndedHandled = false;
    }
    _pushMirrorState();
  }

  Timer? _hqPollTimer;
  Duration _hqPosition = Duration.zero;
  Duration _hqDuration = Duration.zero;
  bool _hqPlaying = false;
  final _hqPositionCtrl = StreamController<Duration>.broadcast();
  final _hqDurationCtrl = StreamController<Duration>.broadcast();
  final _hqPlayingCtrl = StreamController<bool>.broadcast();

  /// Unified display streams for the UI: HQ engine when active, else mpv.
  /// (media_kit's streams are broadcast without replay, so the UI also
  /// needs synchronous initialData — see displayPosition/displayDuration.)
  bool get hqActive => state.hqTextureId != null;

  /// HQ display streams + synchronous snapshots for the player UI.
  /// Branch on [hqActive]: use these when true, else the media_kit player.
  Stream<Duration> get hqPositionStream => _hqPositionCtrl.stream;
  Stream<Duration> get hqDurationStream => _hqDurationCtrl.stream;
  Stream<bool> get hqPlayingStream => _hqPlayingCtrl.stream;
  Duration get hqPosition => _hqPosition;
  Duration get hqDuration => _hqDuration;
  bool get hqIsPlaying => _hqPlaying;

  /// Unified synchronous snapshots for gesture handlers: HQ engine when
  /// active, else mpv.
  Duration get displayPosition => _hqPosition;

  /// The current UI state, for readers that cannot use `ref`
  /// (e.g. a widget's dispose()).
  PlayerUiState get uiStateSnapshot => state;
  Duration get displayDuration => _hqDuration;

  /// Cached system volume (0-100). Synced with the phone's media volume —
  /// the in-app pill and the hardware buttons control the same value.
  double _systemVolume = 50;

  /// Unified volume: sets the PHONE's system media volume (0-100), so the
  /// in-app pill and the hardware volume buttons stay in sync.
  /// Player-internal volumes are kept at max; the system volume is the
  /// single source of truth.
  Future<void> setDisplayVolume(double v) async {
    final clamped = v.clamp(0.0, 100.0);
    _systemVolume = clamped;
    try {
      // Hide the system volume popup — our pill shows the level.
      VolumeController.instance.showSystemUI = false;
      await VolumeController.instance.setVolume(clamped / 100);
    } catch (_) {}
    // The plugin engine has no volume API — it always plays at
    // full volume, so the system volume set above IS the loudness
    // control (the old mpv setVolume(100) branch is gone with mpv).
  }

  double get displayVolume => _systemVolume;

  /// Starts listening for hardware volume-button changes so the pill
  /// reflects the system volume. Call once (e.g. when the player opens).
  void startSystemVolumeSync() {
    try {
      VolumeController.instance.addListener((v) {
        _systemVolume = (v * 100).clamp(0.0, 100.0);
      });
    } catch (_) {}
    // Prime the cache with the real system volume.
    try {
      VolumeController.instance.getVolume().then((v) {
        _systemVolume = (v * 100).clamp(0.0, 100.0);
      });
    } catch (_) {}
  }

  /// Stops the hardware volume listener.
  void stopSystemVolumeSync() {
    try {
      VolumeController.instance.removeListener();
    } catch (_) {}
  }

  /// Last persisted audio-only preference (Hive). Applied on the next
  /// loadVideo so a fresh app start restores the user's last mode.
  bool _prefAudioOnly = false;
  static const _kAudioOnlyKey = 'audio_only';
  static const _kSleepEndsAtKey = 'sleep_ends_at';
  static const _kSleepTotalMsKey = 'sleep_total_ms';
  static const _kSleepEndOfVideoKey = 'sleep_end_of_video';

  /// Autoplay preference (Hive, default ON). When a video/track completes
  /// and this is true, the next Up Next item starts automatically — in
  /// both video and audio mode, since both share one media_kit Player.
  bool _autoplay = true;
  static const _kAutoplayKey = 'autoplay';

  /// Completion → playNext handoff guards.
  bool _autoplayBusy = false;

  /// Ids played this session — Next/autoplay never offer them again,
  /// so tapping Next always moves forward to something new.
  final Set<String> _playedIds = {};

  /// When a sleep timer finishes (pauses playback), suppress autoplay for
  /// a short window — covers the race where media_kit's `completed`
  /// fires just after the timer paused at end-of-video.
  DateTime? _sleepFinishedAt;

  /// "Continue watching" keys (Hive player_prefs box): the last played
  /// video + position, so the home screen can offer resume after an
  /// app restart — like original YouTube.
  static const kLastVideoId = 'last_video_id';
  static const kLastVideoTitle = 'last_video_title';
  static const kLastVideoAuthor = 'last_video_author';
  static const kLastVideoThumb = 'last_video_thumb';
  static const kLastVideoDurationSecs = 'last_video_duration_secs';
  static const kLastVideoPositionSecs = 'last_video_position_secs';
  static const kLastVideoAudioOnly = 'last_video_audio_only';
  static const kLastVideoUpdatedAt = 'last_video_updated_at';

  /// Throttle for periodic last-video saves during playback.
  DateTime? _lastVideoSavedAt;
  int _lastVideoSavedSecs = -1;

  /// Playback history for Previous/Next navigation (Spotify/YouTube style).
  /// [_history] holds video IDs in play order; [_historyIndex] points at
  /// the currently playing entry. [_navigatingHistory] is true while a
  /// history back/forward load is in flight, so loadVideo() doesn't
  /// push a duplicate entry for the navigation itself.
  final List<String> _history = [];
  int _historyIndex = -1;

  /// Pre-fetched Up Next data so tapping Next plays instantly.
  /// Keyed by video id; filled by [precacheUpcoming] in the background
  /// after each successful load; consumed by [loadVideo] when the
  /// requested id matches. Pure extractor HTTP calls — never touches
  /// the player, so the currently playing video is unaffected.
  /// [_precacheToken] cancels an in-flight pass when navigation,
  /// a reorder, or a settings change makes it stale.
  final Map<String, PrecachedData> _precache = {};
  int _precacheToken = 0;

  /// Auto-generated lyrics cache, keyed by video id — shared by the
  /// AI Lyrics cards in both video and audio mode, so switching back
  /// to a track shows its lyrics instantly.
  /// [_lyricsToken] cancels an in-flight lyrics fetch when the user
  /// navigates to another video.
  final Map<String, LyricsResult> _lyricsCache = {};
  int _lyricsToken = 0;
  bool _navigatingHistory = false;

  @override
  PlayerUiState build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _pip.init();
    // Sync the in-app volume pill with the phone's system volume.
    startSystemVolumeSync();

    _pipSub = _pip.onPipChanged.listen((inPip) {
      state = state.copyWith(isInPip: inPip);
      if (inPip) {
        // Native PiP owns the window now: drop the in-app floating popup
        // so the video never renders twice.
        ref.read(popupVisibleProvider.notifier).state = false;
      }
    });
    // PiP window transport buttons (Previous / Play-Pause / Next)
    // drive the SAME controller paths as every other surface.
    _pipActionSub = _pip.onPipAction.listen((action) {
      switch (action) {
        case 'playPause':
          togglePlayPause();
          break;
        case 'next':
          unawaited(playNext());
          break;
        case 'previous':
          unawaited(playPrevious());
          break;
      }
    });
    // Auto-PiP arming follows the full player opening/closing.
    ref.listen(fullPlayerOpenProvider, (_, __) => _syncAutoPip());
    // SponsorBlock skipping, resume persistence and completion
    // (autoplay-next) are driven by the plugin: its state listener
    // (_onPluginChanged) handles completion, and the 500ms poll
    // (_startHqPoll) drives skip/persist from the plugin position.

    // Wire notification skip buttons to the playback history / Up Next.
    _handler.onSkipToNext = () async {
      await playNext();
    };
    // Sync saved sponsor-skip preference (default ON).
    unawaited(_loadSavedSkipSponsors());
    // Load the Prefer AVC setting (default ON).
    unawaited(_loadPreferAvc());
    // Restore the persisted audio-only preference (default OFF).
    unawaited(_loadPlayerPrefs());
    // Restore a persisted sleep timer (e.g. after backgrounding).
    _restoreSleepTimer();
    _handler.onSkipToPrevious = () async {
      await playPrevious();
    };

    ref.onDispose(() {
      binding.removeObserver(this);
      _pipSub?.cancel();
      _pipActionSub?.cancel();
      _cancelSleepTimer();
      _hqPollTimer?.cancel();
      final pt = _pt;
      _pt = null;
      if (pt != null) unawaited(pt.close());
      _hqPositionCtrl.close();
      _hqDurationCtrl.close();
      _hqPlayingCtrl.close();
    });

    return const PlayerUiState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.paused:
        // Home button / app switcher: persist the resume position.
        // PiP only when user explicitly taps the PiP button — auto-PiP
        // was interrupting background playback.
        // Plugin (HQ) playback now continues NATIVELY in the
        // background — the plugin's foreground service keeps it
        // alive, SparkTube-style — so there is no mpv hand-off and
        // playback never stops when the user leaves the app.
        unawaited(_persistResumePosition());
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.detached:
        // DANGER: On some devices (notably Xiaomi/MIUI), `detached`
        // fires when the app merely goes to background via the Home
        // button — stopping here would kill background playback.
        // Only persist+stop when PiP was dismissed via its X button
        // (isInPip was true). Swipe-away from recents is handled by
        // onTaskRemoved in the audio handler, and real process death
        // stops the native player on its own.
        if (state.isInPip) {
          unawaited(_persistThenStop());
        } else {
          unawaited(_persistResumePosition());
        }
        break;
      default:
        break;
    }
  }

  // ---------------- loading ----------------

  Future<void> loadVideo(String videoId) async {
    _directFallbackFor = null;
    final previousSpeed = state.speed;
    final previousSkip = state.skipSponsors;
    final previousAudioOnly = state.audioOnly;
    final keepAudioOnly = previousAudioOnly || _prefAudioOnly;
    // The sleep timer is wall-clock based and must SURVIVE track changes —
    // it is cancelled only by explicit cancel, timer finish, stop(), or
    // dispose. Never cancel it here.
    // Never replay: remember this video and drop it from Up Next, so
    // Next/autoplay always move forward to something new.
    _playedIds.add(videoId);
    if (_playedIds.length > 300) _playedIds.remove(_playedIds.first);
    final freshRelated =
        state.relatedVideos.where((v) => v.id != videoId).toList();
    // New video: clear any stale sleep-finish suppression and the
    // autoplay re-entry guard.
    _sleepFinishedAt = null;
    _autoplayBusy = false;
    // Fresh video: its sponsor segments may be skipped again.
    _skippedSegmentKeys.clear();
    // Captions belong to the previous video; tracks reload below.
    // Navigating away cancels any in-flight pre-load pass.
    _precacheToken++;
    // Navigating away also cancels any in-flight lyrics auto-fetch.
    _lyricsToken++;
    // Seamless transitions: when a video is already playing, the
    // current engine KEEPS PLAYING while the next video is fetched
    // and resolved; the plugin's load supersedes it at the switch
    // point, so Next never shows a stopped/dead player. Only a
    // fresh start (nothing playing) stops everything up front.
    final hadPlayback =
        state.status == PlayerStatus.ready && state.video != null;
    if (!hadPlayback) {
      await _stopHq();
    }

    // Record in playback history (unless this load IS a history
    // back/forward navigation — those just move the index).
    _pushHistory(videoId);

    state = PlayerUiState(
      status: PlayerStatus.loading,
      videoId: videoId,
      // Keep the current video (and its picture) on screen while the
      // next one loads — audio mode (YouTube Music style) and video
      // transitions alike; no blank spinner over a playing video.
      video: (keepAudioOnly || hadPlayback) ? state.video : null,
      hqTextureId: hadPlayback ? state.hqTextureId : null,
      hqAspectRatio: state.hqAspectRatio,
      speed: previousSpeed,
      skipSponsors: previousSkip,
      // Restore the persisted audio-only mode on fresh app starts.
      audioOnly: keepAudioOnly,
      // Keep the autoplay preference across video loads.
      autoplay: _autoplay,
      // SparkTube behavior: an explicit Auto quality pick survives
      // video changes (session-level selection).
      autoQuality: state.autoQuality,
      // The sleep timer survives track changes (wall-clock based).
      sleepRemaining: state.sleepRemaining,
      sleepTotal: state.sleepTotal,
      sleepEndOfVideo: state.sleepEndOfVideo,
      // The just-started video is out of Up Next from now on.
      relatedVideos: freshRelated,
    );

    try {
      // Resolve the user's stream-quality preferences for this network.
      // Videos always open in portrait (not fullscreen), so the
      // no-fullscreen choice applies to the initial load.
      final onWifi = await _isOnWifi();
      final targetHeight =
          _targetVideoHeight(onWifi: onWifi, fullscreen: false);
      final worstAudio = _wantWorstAudio(onWifi);

      // Use pre-fetched Up Next data when available (instant Next),
      // otherwise fetch normally. The hit is removed; other queued
      // videos stay precached for later. The fetched streams are the
      // emergency fallback + bookkeeping only — video playback
      // itself starts directly on the plugin engine (SparkTube
      // system), never from these links.
      final VideoDetails video;
      PlaybackStreams? streams;
      final List<SponsorSegment> segments;
      final PrecachedData? hit = _precache.remove(videoId);
      if (hit != null) {
        video = hit.details;
        streams = hit.streams;
        segments = hit.segments;
      } else {
        // Playback starts as soon as the DETAILS land: the Dart
        // stream chain is fallback-only data, so it no longer blocks
        // the plugin's own resolve on the critical path (SparkTube
        // starts from a single resolve — the same shape). The streams
        // patch into state when they arrive; the direct fallback
        // refetches them itself if it ever fires before that.
        final streamsFuture = _extractor.getPlaybackStreams(
          videoId,
          maxMuxedHeight: targetHeight ?? 720,
          preferBestAudio: !worstAudio,
        );
        unawaited(streamsFuture.then((s) {
          if (state.videoId == videoId && state.streams == null) {
            state = state.copyWith(streams: s);
          }
        }, onError: (_) {}));
        final results = await Future.wait([
          _extractor.getVideoDetails(videoId),
          _sponsorBlock.getSegments(videoId),
        ]);
        video = results[0] as VideoDetails;
        segments = results[1] as List<SponsorSegment>;
      }

      if (keepAudioOnly) {
        // Audio mode: the SAME plugin engine, loaded audio-only —
        // one player for everything (mpv is gone). The media
        // session mirror carries the artwork to the notification /
        // lock screen via _engageMirror.
        state = state.copyWith(
          status: PlayerStatus.ready,
          video: video,
          streams: streams,
          sponsorSegments: segments,
          pipSupported: await _pip.isPipSupported,
        );
        unawaited(_saveLastVideo());
        // Resume from the saved position if the user listened
        // before. Skip if 0 or within 10s of the end (finished).
        final savedSecs =
            ref.read(historyRepositoryProvider).getPosition(videoId);
        final totalSecs = video.duration?.inSeconds ?? 0;
        final resumeAt =
            (savedSecs > 5 && (totalSecs <= 0 || savedSecs < totalSecs - 10))
                ? Duration(seconds: savedSecs)
                : Duration.zero;
        _pluginEngagedFor = videoId;
        unawaited(_startAudioOnPlugin(video, resumeAt: resumeAt));
      } else {
        // Video mode: DIRECT plugin start (SparkTube system) — the
        // video starts from the plugin's own extracted links right
        // away; mpv is never opened for video. On a transition the
        // previous video keeps playing until the plugin installs
        // the new one (the load supersedes it natively).
        state = state.copyWith(
          status: PlayerStatus.ready,
          video: video,
          streams: streams,
          sponsorSegments: segments,
          pipSupported: await _pip.isPipSupported,
        );
        // Record this video for "Continue watching" on the home screen.
        unawaited(_saveLastVideo());
        final savedSecs =
            ref.read(historyRepositoryProvider).getPosition(videoId);
        final totalSecs = video.duration?.inSeconds ?? 0;
        final pending = _pendingResumeOnce;
        _pendingResumeOnce = null;
        final resumeAt = pending ??
            ((savedSecs > 5 && (totalSecs <= 0 || savedSecs < totalSecs - 10))
                ? Duration(seconds: savedSecs)
                : Duration.zero);
        // loadQualities must not re-engage: the direct start below
        // owns this video's engine engage.
        _pluginEngagedFor = videoId;
        if (state.autoQuality) _autoHqEngagedFor = videoId;
        unawaited(_directStart(videoId, streams: streams, resumeAt: resumeAt));
      }
      // Load captions in the background; UI updates when ready.
      unawaited(loadSubtitles());
      // Same for quality options; current quality starts at the
      // height of the initially picked stream.
      unawaited(loadQualities(initialHeight: streams?.muxedHeight));
      // Up Next suggestions load in the background; the section below
      // the player and the Next button both read them from state.
      unawaited(_loadRelated(videoId,
          titleHint: video.title, authorHint: video.author));
      // Track the watch category for personalized suggestions
      // (Up Next + home feed).
      unawaited(WatchCategoryTracker.record(video.title));
      // Auto-generate lyrics for the AI Lyrics cards (both modes) —
      // no user tap needed. Cached per video id; cancelled on
      // navigation by [_lyricsToken].
      unawaited(
          _autoFetchLyrics(videoId, title: video.title, author: video.author));
    } on PureTubeException catch (e) {
      state =
          state.copyWith(status: PlayerStatus.error, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
          status: PlayerStatus.error, errorMessage: 'Playback failed: $e');
    }
  }

  Future<void> retry() async {
    final id = state.videoId;
    if (id == null) return;
    final resumeAt = displayPosition;
    _pendingResumeOnce = resumeAt;
    await loadVideo(id);
    if (resumeAt > const Duration(seconds: 3) &&
        state.status == PlayerStatus.ready) {
      await seekTo(resumeAt);
    }
  }

  Future<void> stop() async {
    _cancelSleepTimer();
    await _stopHq();
    await _handler.stop();
    // Full reset, but keep the user's autoplay preference.
    state = PlayerUiState(autoplay: _autoplay);
    _history.clear();
    _historyIndex = -1;
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  // ---------------- playback history (Previous / Next) ----------------

  /// Pushes [videoId] onto the playback history, unless this load is
  /// itself a history back/forward navigation. Going back then loading
  /// a brand-new video truncates the forward entries (browser style).
  void _pushHistory(String videoId) {
    if (_navigatingHistory) return;
    // Drop forward entries when branching off mid-history.
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    // Avoid a duplicate when re-loading the same video (e.g. retry).
    if (_history.isEmpty || _history.last != videoId) {
      _history.add(videoId);
    }
    _historyIndex = _history.length - 1;
  }

  /// Previous button (Spotify/YouTube behavior): if the current
  /// position is past 3 seconds, restart the video; otherwise load
  /// the previously played video from history. Returns true when a
  /// previous video was loaded, false when it just restarted (or
  /// there is no previous video).
  Future<bool> playPrevious() async {
    final pos = displayPosition;
    if (pos > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
      return false;
    }
    if (_historyIndex > 0 && state.status == PlayerStatus.ready) {
      _historyIndex--;
      _navigatingHistory = true;
      try {
        await loadVideo(_history[_historyIndex]);
      } finally {
        _navigatingHistory = false;
      }
      return true;
    }
    // No previous video: just restart.
    await seekTo(Duration.zero);
    return false;
  }

  /// Next button: loads the first Up Next video (fetching it first
  /// when the list is empty), recording it in history via loadVideo.
  /// Returns the loaded video id, or null when nothing was found.
  Future<String?> playNext() async {
    if (state.status != PlayerStatus.ready) return null;
    final nextId = await ensureNextVideoId();
    if (nextId == null) return null;
    await loadVideo(nextId);
    return nextId;
  }

  /// Fired by media_kit's `stream.completed` when the current media
  /// finishes playing naturally. Starts the next Up Next item when
  /// autoplay is ON — in both video and audio mode (one shared player).
  ///
  /// Guards:
  /// - Autoplay OFF → do nothing.
  /// - "End of video" sleep timer active → stop here (timer wins).
  /// - A sleep timer just finished pausing → suppress briefly to cover
  ///   the completed-vs-timer race at end-of-video.
  /// - Re-entry guard so one completion advances exactly one item, and
  ///   the video id must still match when we act (stale events ignored).
  /// Repeat-one (set from the player's repeat button): on
  /// completion the same video restarts instead of advancing.
  bool _repeatOne = false;

  void setRepeatOne(bool value) => _repeatOne = value;

  void _onPlaybackCompleted() {
    if (_repeatOne && state.videoId != null) {
      _hqPosition = Duration.zero;
      _hqPositionCtrl.add(Duration.zero);
      unawaited(() async {
        try {
          await _pt?.seek(Duration.zero);
          await _pt?.play();
        } catch (_) {}
      }());
      return;
    }
    if (!_autoplay) return;
    if (state.status != PlayerStatus.ready) return;
    if (state.sleepEndOfVideo) return;
    final finishedAt = _sleepFinishedAt;
    if (finishedAt != null &&
        DateTime.now().difference(finishedAt) < const Duration(seconds: 10)) {
      return;
    }
    if (_autoplayBusy) return;
    if (state.videoId == null) return;
    _autoplayBusy = true;
    unawaited(playNext().whenComplete(() {
      _autoplayBusy = false;
    }));
  }

  /// Sets the autoplay preference, persists it, and updates the UI.
  Future<void> setAutoplay(bool value) async {
    if (_autoplay == value && state.autoplay == value) return;
    _autoplay = value;
    state = state.copyWith(autoplay: value);
    try {
      await Hive.box(HiveBoxes.playerPrefs).put(_kAutoplayKey, value);
    } catch (_) {}
  }

  // ---------------- transport ----------------

  /// Releases the shared engine WITHOUT forgetting the session:
  /// Shorts and the offline player take the engine over while
  /// they are open, so the main player's engagement marker is
  /// cleared (the video/queue stay; pressing play re-engages at
  /// the remembered position via [retry]).
  void invalidateEngine() {
    _disengageMirror();
    _hqPollTimer?.cancel();
    _hqPollTimer = null;
    _hqPlaying = false;
    _hqPlayingCtrl.add(false);
    if (state.hqTextureId != null) {
      state = state.copyWith(clearHq: true);
    }
  }

  Future<void> togglePlayPause() async {
    if (!hqActive && state.videoId != null && _pt != null) {
      // The engine was taken over (Shorts/offline) and released:
      // re-engage this video at the remembered position.
      unawaited(retry());
      return;
    }
    if (hqActive) {
      // Optimistic flip for a snappy icon; the poll corrects it.
      _hqPlaying = !_hqPlaying;
      _hqPlayingCtrl.add(_hqPlaying);
      final pt = _pt;
      if (pt == null) return;
      if (_hqPlaying) {
        await pt.play();
      } else {
        await pt.pause();
      }
      return;
    }
    // Not engaged: nothing to toggle.
  }

  Future<void> seekTo(Duration position) => _seekInternal(position);

  Future<void> seekBy(Duration offset) async {
    var target = _hqPosition + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (_hqDuration > Duration.zero && target > _hqDuration) {
      target = _hqDuration;
    }
    await _seekInternal(target);
  }

  Future<void> setSpeed(double speed) async {
    final s = speed.clamp(0.25, 4.0);
    // Plugin only. (The handler is NOT called back here: in mirror
    // mode its setSpeed routes to this very method — that was a
    // latent infinite loop. The session's speed is pushed to the
    // notification via _pushMirrorState instead.)
    if (hqActive) {
      try {
        await _pt?.setSpeed(s.clamp(0.25, 3.0));
      } catch (_) {}
    }
    state = state.copyWith(speed: s);
    _pushMirrorState();
  }

  /// Toggle between video and background-audio mode, preserving position.
  ///
  /// Does NOT switch streams: the current stream (muxed, or DASH video with
  /// its attached audio track) keeps playing; only the UI changes (video
  /// hidden in audio mode). This preserves position perfectly and starts
  /// audio immediately — switching to the audio-only URL was unreliable
  /// (stale/expired URLs, delayed start, position reset).
  Future<void> toggleAudioOnly() async {
    if (state.status != PlayerStatus.ready || state.videoId == null) {
      return;
    }
    final goingAudioOnly = !state.audioOnly;
    state = state.copyWith(audioOnly: goingAudioOnly);
    // Tell the engine too: audio-only disables the video track on
    // the LIVE source (no rebuild, so the sound never breaks);
    // back to video re-enables it the same way.
    // The plugin is the only engine now, so this always applies —
    // the mpv-era toggle only flipped the UI.
    try {
      await _pt?.setAudioOnly(goingAudioOnly);
    } catch (_) {}
    // Persist so a fresh app start restores the last mode.
    _prefAudioOnly = goingAudioOnly;
    unawaited(_saveAudioOnlyPref(goingAudioOnly));
  }

  /// Sets the audio/video mode directly (no-op when already in [value]).
  /// Used by the header's segmented audio/video toggle.
  Future<void> setAudioOnly(bool value) async {
    if (state.audioOnly == value) return;
    await toggleAudioOnly();
  }

  /// Starts [videoId] directly in audio-only mode (used by the audio home).
  /// Persists the preference first so [loadVideo]'s keepAudioOnly picks it
  /// up even from an idle state (unlike [toggleAudioOnly], which needs a
  /// ready player).
  Future<void> playAudioOnly(String videoId) async {
    _prefAudioOnly = true;
    unawaited(_saveAudioOnlyPref(true));
    await loadVideo(videoId);
  }

  Future<void> enterPip() async {
    if (state.pipSupported && state.status == PlayerStatus.ready) {
      // Enter PiP with the transport icon already correct.
      _syncPipPlaying(hqIsPlaying, force: true);
      await _pip.enterPip();
    }
  }

  // ---------------- Quality selection ----------------

  /// Loads the available muxed quality options in the background.
  /// Safe to call repeatedly (e.g. retry from the UI); failures are silent.
  Future<void> loadQualities({int? initialHeight}) async {
    final id = state.videoId;
    if (id == null) return;
    try {
      final options = await _extractor.getQualityOptions(id);
      if (state.videoId != id || options.isEmpty) return;
      final anchor = initialHeight ?? state.currentQuality?.height;
      // getQualityOptions sorts height desc, then fps desc, so the
      // auto default (options.first) is the top height at its highest
      // fps, and an anchor height resolves to its highest-fps variant.
      final current = anchor == null
          ? options.first
          : options.firstWhere(
              (q) => q.height == anchor,
              orElse: () => options.first,
            );
      state = state.copyWith(
        availableQualities: options,
        // The direct start already engaged the engine at the
        // session quality — don't overwrite its label with the
        // anchor (the label must show what is actually playing).
        currentQuality: hqActive ? state.currentQuality : current,
      );
      // SparkTube behavior: an explicit "Auto" pick survives video
      // changes — re-engage the adaptive plugin engine for the new
      // video (at most once per video; a failed attempt stays on mpv
      // instead of looping).
      if (state.autoQuality &&
          !state.audioOnly &&
          !hqActive &&
          _autoHqEngagedFor != id &&
          options.isNotEmpty) {
        _autoHqEngagedFor = id;
        unawaited(setQualityAuto());
      }
      // The plugin engine owns video playback at EVERY quality now —
      // mpv's DASH path kept failing (720p "Failed to open" on the
      // user's test video). Engage it once per video at the user's
      // DEFAULT target quality for this context — NOT the anchor
      // height, which is whatever mpv happened to open with (often
      // the 360p muxed instant-start stream, so the title showed
      // "360p" first and playback stayed low). A failure stays
      // quietly on mpv (same stream, no scary error for an invisible
      // engine swap). Explicit picks still report failures loudly
      // via setQuality.
      if (!state.autoQuality &&
          !state.audioOnly &&
          !hqActive &&
          _pluginEngagedFor != id &&
          options.isNotEmpty) {
        _pluginEngagedFor = id;
        final engageToken = ++_qualitySwitchToken;
        final onWifi = await _isOnWifi();
        if (state.videoId != id) return;
        final targetH = _targetVideoHeight(onWifi: onWifi, fullscreen: false);
        if (targetH == null) {
          // Settings say "auto": engage adaptively, no cap.
          unawaited(
              _playHq(options.first, engageToken, cap: null, loud: false));
        } else {
          final pick = _pickClosestOption(options, targetH) ?? options.first;
          unawaited(_playHq(pick, engageToken, cap: pick.height, loud: false));
        }
      }
      // Dubbed audio languages (YouTube "Audio Track"). Loaded alongside
      // qualities; empty for single-language videos.
      _loadAudioLanguages(id);
    } catch (_) {}
  }

  /// Loads dubbed audio languages for the "Audio Track" menu.
  Future<void> _loadAudioLanguages(String videoId) async {
    try {
      final langs = await _extractor.session.getAudioLanguages(videoId);
      if (state.videoId != videoId) return;
      state = state.copyWith(
        audioLanguages: langs,
        activeAudioLanguage: langs.isEmpty
            ? null
            : langs.firstWhere(
                (l) => l.isDefault,
                orElse: () => langs.first,
              ),
        clearAudioLanguage: langs.isEmpty,
      );
    } catch (_) {}
  }

  /// Switches the dubbed audio language, keeping the same video.
  /// Works like YouTube: if the current stream is muxed (360p, embedded
  /// audio), switches to the DASH video-only stream at the same height
  /// plus the selected language's audio track.
  Future<void> setAudioLanguage(AudioLanguage lang) async {
    final q = state.currentQuality;
    if (q == null) return;
    if (state.activeAudioLanguage?.id == lang.id) return;

    // HQ engine active: switch the track natively — the plugin
    // rebuilds from its cached catalog with the chosen dub, position
    // preserved, no mpv detour and no full reload.
    if (hqActive) {
      state = state.copyWith(activeAudioLanguage: lang);
      final pt = _plugin;
    PureTubeController.ownerTag = 'main';
      try {
        final catalog = pt.catalog ??
            await pt
                .resolve('https://www.youtube.com/watch?v=${state.videoId}');
        final trackId = _matchPluginTrack(catalog, lang);
        if (trackId != null) await pt.setAudioTrack(trackId);
      } catch (_) {}
      return;
    }

    MuxedQuality updated;
    if (q.audioUrl != null) {
      // DASH: same video stream, new language's audio URL.
      updated = MuxedQuality(
        label: q.label,
        height: q.height,
        url: q.url,
        audioUrl: lang.audioUrl,
        bitrateKbps: q.bitrateKbps,
        fps: q.fps,
        codec: q.codec,
        fullCodec: q.fullCodec,
        audioFullCodec: q.audioFullCodec,
        audioBitrateBps: lang.bitrateBps,
        audioSampleRate: q.audioSampleRate,
        isHdr: q.isHdr,
      );
    } else {
      // Muxed (embedded audio): find the DASH video-only stream at the
      // same height, pair it with the selected language's audio.
      final dash = state.availableQualities
          .where((o) => o.audioUrl != null && o.height == q.height)
          .toList();
      if (dash.isEmpty) return;
      // Prefer AVC, then highest bitrate.
      dash.sort((a, b) {
        final aAvc = a.codec.toLowerCase().contains('avc') ? 0 : 1;
        final bAvc = b.codec.toLowerCase().contains('avc') ? 0 : 1;
        if (aAvc != bAvc) return aAvc.compareTo(bAvc);
        return b.bitrateKbps.compareTo(a.bitrateKbps);
      });
      final v = dash.first;
      updated = MuxedQuality(
        label: v.label,
        height: v.height,
        url: v.url,
        audioUrl: lang.audioUrl,
        bitrateKbps: v.bitrateKbps,
        fps: v.fps,
        codec: v.codec,
        fullCodec: v.fullCodec,
        audioFullCodec: v.audioFullCodec,
        audioBitrateBps: lang.bitrateBps,
        audioSampleRate: v.audioSampleRate,
        isHdr: v.isHdr,
      );
    }
    state = state.copyWith(activeAudioLanguage: lang);
    await setQuality(updated);
  }

  /// Loads Up Next suggestions in the background. The section below the
  /// player and the Next (⏭️) button both read them from state, so no
  /// extra API call is needed when the user taps Next.
  Future<void> _loadRelated(String videoId,
      {String? titleHint, String? authorHint}) async {
    try {
      // Boost: current video's category first, then the user's
      // most-watched categories — so waz suggests waz, songs suggest
      // songs, etc.
      final currentCat = WatchCategoryTracker.detect(titleHint ?? '');
      final historyTop = await WatchCategoryTracker.top(2);
      final boost = <String>[
        if (currentCat != null) currentCat,
        ...historyTop.where((c) => c != currentCat),
      ];
      final videos = await _extractor.getRelatedVideos(videoId,
          titleHint: titleHint, authorHint: authorHint, boostCategories: boost);
      if (state.videoId != videoId) return;
      // Never offer already-played videos (or the current one) again —
      // this keeps Next/autoplay moving forward forever.
      final fresh = videos
          .where((v) => v.id != videoId && !_playedIds.contains(v.id))
          .toList();
      state = state.copyWith(
        relatedVideos: fresh,
        relatedFailed: fresh.isEmpty,
      );
      // Up Next is known now — pre-fetch upcoming videos' streams so
      // tapping Next plays instantly.
      unawaited(precacheUpcoming());
    } catch (_) {
      if (state.videoId != videoId) return;
      state = state.copyWith(relatedFailed: true);
    }
  }

  /// Retry loading Up Next suggestions (retry button in the section).
  Future<void> retryRelated() async {
    final id = state.videoId;
    if (id == null) return;
    state = state.copyWith(relatedFailed: false);
    final v = state.video;
    await _loadRelated(id, titleHint: v?.title, authorHint: v?.author);
  }

  /// Reorders the Up Next queue (drag-to-reorder in the queue sheet).
  /// Playback order follows the queue, so "Next" plays the new first item.
  /// Note: the sheet uses onReorderItem, which already adjusts newIndex
  /// for the removed item — no manual index shifting needed here.
  void reorderQueue(int oldIndex, int newIndex) {
    final videos = List<VideoDetails>.from(state.relatedVideos);
    if (oldIndex < 0 ||
        oldIndex >= videos.length ||
        newIndex < 0 ||
        newIndex > videos.length) {
      return;
    }
    final item = videos.removeAt(oldIndex);
    videos.insert(newIndex, item);
    state = state.copyWith(relatedVideos: videos);
    // The "next" videos may have changed — refresh the precache so
    // tapping Next stays instant.
    refreshPrecache();
  }

  /// Returns a video id to play for "Next", making sure Up Next is
  /// loaded first. Retries the related-videos fetch, then falls back
  /// to a direct keyword search, so Next almost always finds a video.
  /// Returns null only if every attempt fails. Has an overall timeout
  /// so the UI never hangs on a slow network.
  Future<String?> ensureNextVideoId() async {
    try {
      return await _ensureNextVideoIdInner()
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _ensureNextVideoIdInner() async {
    // First unplayed, non-current video — never the one already playing
    // or anything played earlier this session.
    String? pickNext() {
      for (final v in state.relatedVideos) {
        if (v.id != state.videoId && !_playedIds.contains(v.id)) {
          return v.id;
        }
      }
      return null;
    }

    final first = pickNext();
    if (first != null) return first;
    await retryRelated();
    final second = pickNext();
    if (second != null) return second;
    // Last resort: search YouTube directly for the current title.
    final v = state.video;
    if (v == null) return null;
    try {
      final results = await _extractor
          .searchVideos(v.title, limit: 10)
          .timeout(const Duration(seconds: 15));
      for (final r in results) {
        if (r.id != state.videoId && !_playedIds.contains(r.id)) {
          return r.id;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Pre-fetches the next N Up Next videos' details + streams in the
  /// background so tapping Next (⏭️) plays instantly instead of waiting
  /// on network calls. N comes from the Pre-loading setting
  /// ('preload_count', 0 = off, default 3, max 100).
  /// Best-effort: per-video failures are swallowed and Next simply does
  /// a normal load. Only does extractor HTTP calls — the player and
  /// current playback are never touched. A newer pass, a reorder, a
  /// settings change, or navigation cancels an in-flight pass via
  /// [_precacheToken].
  Future<void> precacheUpcoming() async {
    if (state.status != PlayerStatus.ready) return;
    final count = await _readPreloadCount();
    if (count <= 0) return;
    final currentId = state.videoId;
    if (currentId == null || state.relatedVideos.isEmpty) return;
    // Honor the user's quality preference for pre-cached videos too
    // (muxed range only — DASH targets are fetched fresh on load).
    final onWifi = await _isOnWifi();
    final targetHeight = _targetVideoHeight(onWifi: onWifi, fullscreen: false);
    final worstAudio = _wantWorstAudio(onWifi);
    final ids = <String>[];
    for (final v in state.relatedVideos) {
      if (ids.length >= count) break;
      if (v.id == currentId) continue;
      if (_precache.containsKey(v.id)) continue;
      ids.add(v.id);
    }
    if (ids.isEmpty) return;
    final token = ++_precacheToken;
    for (final id in ids) {
      try {
        final results = await Future.wait([
          _extractor.getVideoDetails(id),
          _extractor.getPlaybackStreams(
            id,
            maxMuxedHeight: targetHeight ?? 720,
            preferBestAudio: !worstAudio,
          ),
          _sponsorBlock.getSegments(id),
        ]);
        if (token != _precacheToken || state.videoId != currentId) return;
        _precache[id] = PrecachedData(
          details: results[0] as VideoDetails,
          streams: results[1] as PlaybackStreams,
          segments: results[2] as List<SponsorSegment>,
        );
      } catch (_) {
        // Best effort per video — Next falls back to a normal load.
      }
    }
  }

  /// Clears the pre-load cache and starts a fresh pass — used after the
  /// Pre-loading setting changes or the queue is reordered.
  void refreshPrecache() {
    _precacheToken++; // cancel any in-flight pass
    _precache.clear();
    unawaited(precacheUpcoming());
  }

  // ---------------- Auto-generated lyrics ----------------

  /// Fetches lyrics for the just-loaded video in the background so the
  /// AI Lyrics cards (video + audio mode) show a loading state first and
  /// the lyrics when ready — no user tap needed.
  ///
  /// Source order (user requirement):
  /// 1. YouTube's own captions/transcript (free, YouTube's own AI) —
  ///    for music videos the transcript IS essentially the lyrics.
  /// 2. lyrics.ovh (free API)
  /// 3. Pollinations AI (free, no key)
  /// 4. Gemini (advanced — only when the user set an API key in Settings)
  ///
  /// Results are cached per video id (max 50 entries) and shared between
  /// both modes. In-flight fetches are cancelled by [_lyricsToken] on
  /// navigation.
  Future<void> _autoFetchLyrics(String videoId,
      {required String title, required String author}) async {
    final token = ++_lyricsToken;
    final cached = _lyricsCache[videoId];
    if (cached != null) {
      if (state.videoId == videoId) {
        state = state.copyWith(lyricsResult: cached, lyricsLoading: false);
      }
      return;
    }
    if (state.videoId == videoId) {
      state = state.copyWith(clearLyrics: true, lyricsLoading: true);
    }
    try {
      LyricsResult result;
      // 1. YouTube's own captions (free AI transcript) — primary source.
      final transcript = await _extractor.getCaptionTranscript(videoId);
      if (token != _lyricsToken) return; // user moved on
      if (transcript != null && transcript.trim().isNotEmpty) {
        result = LyricsResult(
          lyrics: transcript.trim(),
          artist: author,
          title: title,
          found: true,
        );
      } else {
        // 2-4. lyrics.ovh -> Pollinations -> Gemini (key from Settings).
        final prefs = await SharedPreferences.getInstance();
        if (token != _lyricsToken) return;
        final apiKey = prefs.getString('gemini_api_key');
        final service = LyricsService(geminiApiKey: apiKey);
        try {
          result = await service.getLyricsAuto(
              videoTitle: title, channelName: author);
        } finally {
          service.dispose();
        }
      }
      if (token != _lyricsToken) return;
      if (_lyricsCache.length >= 50) {
        _lyricsCache.remove(_lyricsCache.keys.first);
      }
      _lyricsCache[videoId] = result;
      if (state.videoId == videoId) {
        state = state.copyWith(lyricsResult: result, lyricsLoading: false);
      }
    } catch (_) {
      if (token != _lyricsToken) return;
      if (state.videoId == videoId) {
        state = state.copyWith(lyricsLoading: false);
      }
    }
  }

  /// Manual retry from the AI Lyrics card (clears the cache entry so
  /// the fetch runs again).
  void retryLyrics() {
    final v = state.video;
    final id = state.videoId;
    if (v == null || id == null) return;
    _lyricsCache.remove(id);
    unawaited(_autoFetchLyrics(id, title: v.title, author: v.author));
  }

  // ---------------- Stream quality preferences ----------------

  /// True when the active network is Wi-Fi/Ethernet; anything else
  /// (mobile, unknown) counts as mobile data. Defaults to Wi-Fi when
  /// the check itself fails.
  Future<bool> _isOnWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true;
    }
  }

  /// Desired initial video height for the current network, or null for
  /// "auto" (current behavior). When not fullscreen, the no-fullscreen
  /// choice wins unless it is 'same' (mirror fullscreen).
  int? _targetVideoHeight({required bool onWifi, required bool fullscreen}) {
    final nofs = ref.read(onWifi
        ? wifiNoFullscreenQualityProvider
        : mobileNoFullscreenQualityProvider);
    final full = ref
        .read(onWifi ? wifiVideoQualityProvider : mobileVideoQualityProvider);
    final value = (!fullscreen && nofs != 'same') ? nofs : full;
    return qualityValueToHeight(value);
  }

  /// True when the user picked the data-saver audio tier.
  bool _wantWorstAudio(bool onWifi) =>
      ref.read(
          onWifi ? wifiAudioQualityProvider : mobileAudioQualityProvider) ==
      'worst';

  /// Codec preference rank for DASH: AVC (H.264) is the most compatible
  /// (proven to play), then VP9, then AV1.
  int _dashCodecRank(String codec) {
    final c = codec.toLowerCase();
    if (c.contains('avc')) return 3;
    if (c.contains('vp9')) return 2;
    if (c.contains('av01') || c == 'av1') return 1;
    return 0;
  }

  bool _isAvc(String codec) => codec.toLowerCase().contains('avc');

  /// Best DASH option at-or-below [targetHeight].
  ///
  /// When "Prefer AVC" is ON (default): AVC (H.264) is strongly
  /// preferred — it's the most compatible codec. First pass picks the
  /// highest AVC at-or-below target; only if no AVC exists at all does
  /// it fall back to best-height VP9/AV1.
  /// When OFF: picks by height first, then codec rank, then fps.
  MuxedQuality? _pickDashOption(List<MuxedQuality> options, int targetHeight) {
    if (_preferAvc) {
      MuxedQuality? bestAvc;
      for (final q in options) {
        if (!q.isDash || q.height > targetHeight) continue;
        if (!_isAvc(q.codec)) continue;
        if (bestAvc == null ||
            q.height > bestAvc.height ||
            (q.height == bestAvc.height && q.fps > bestAvc.fps)) {
          bestAvc = q;
        }
      }
      if (bestAvc != null) return bestAvc;
    }

    MuxedQuality? best;
    for (final q in options) {
      if (!q.isDash || q.height > targetHeight) continue;
      if (best == null ||
          q.height > best.height ||
          (q.height == best.height &&
              _dashCodecRank(q.codec) > _dashCodecRank(best.codec)) ||
          (q.height == best.height &&
              _dashCodecRank(q.codec) == _dashCodecRank(best.codec) &&
              q.fps > best.fps)) {
        best = q;
      }
    }
    return best;
  }

  /// Closest option at-or-below [targetHeight], preferring muxed over
  /// DASH on ties and the higher fps variant within the same kind.
  /// Falls back to the lowest available option.
  MuxedQuality? _pickClosestOption(
      List<MuxedQuality> options, int targetHeight) {
    if (options.isEmpty) return null;
    MuxedQuality? best;
    for (final q in options) {
      if (q.height > targetHeight) continue;
      if (best == null ||
          q.height > best.height ||
          (q.height == best.height &&
              ((best.isDash && !q.isDash) ||
                  (best.isDash == q.isDash && q.fps > best.fps)))) {
        best = q;
      }
    }
    return best ?? options.last;
  }

  /// Re-applies the quality preference when the user enters/exits
  /// fullscreen: fullscreen uses the "Video" choice, portrait uses the
  /// "When not fullscreen" choice ('same' = keep the current stream).
  /// 'auto' never forces a switch.
  Future<void> applyFullscreenQuality(bool isFullscreen) async {
    if (state.status != PlayerStatus.ready || state.audioOnly) return;
    // SparkTube rule: an explicit "Auto" pick beats the settings
    // defaults for this session — fullscreen changes don't override it.
    if (state.autoQuality) return;
    // The user's own session pick beats the settings defaults too.
    if (_sessionQualityHeight != null) return;
    final videoId = state.videoId;
    if (videoId == null) return;
    final onWifi = await _isOnWifi();
    final target = _targetVideoHeight(onWifi: onWifi, fullscreen: isFullscreen);
    if (target == null) return; // 'auto' — leave the stream alone.
    if (state.currentQuality?.height == target) return;
    var options = state.availableQualities;
    if (options.isEmpty) {
      try {
        options = await _extractor.getQualityOptions(videoId);
      } catch (_) {
        return;
      }
      if (state.videoId != videoId) return;
    }
    final match = _pickClosestOption(options, target);
    if (match == null) return;
    await setQuality(match);
  }

  /// Reads the Pre-loading setting directly from SharedPreferences
  /// (avoids importing the settings UI layer into the controller).
  Future<int> _readPreloadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('preload_count');
      if (v == null) return 3;
      return v.clamp(0, 100);
    } catch (_) {
      return 3;
    }
  }

  /// SparkTube-style "Auto" quality: adaptive playback.
  ///
  /// SparkTube "Auto": the plugin runs an adaptive DASH session with
  /// NO height cap — it opens high (optimistic bandwidth estimate)
  /// and adapts per segment, like the official player. If the plugin
  /// cannot start, mpv takes the best stream at or below the 720p
  /// settings default. The pick survives video changes (see
  /// loadQualities).
  Future<void> setQualityAuto() async {
    if (state.status != PlayerStatus.ready || state.videoId == null) {
      return;
    }
    if (state.audioOnly) return;
    final token = ++_qualitySwitchToken;
    state = state.copyWith(autoQuality: true);
    // Back to Auto: the session pick no longer rules later videos.
    _sessionQualityHeight = null;
    final options = state.availableQualities;
    if (options.isEmpty) return;
    final top = options.first; // sorted height desc — bookkeeping only
    if (hqActive) {
      // Already on the plugin: just lift the cap — the cached
      // catalog rebuilds adaptively, position preserved.
      try {
        await _plugin.setQuality(null);
      } catch (_) {}
      state = state.copyWith(currentQuality: top);
      return;
    }
    final ok = await _playHq(top, token, cap: null, loud: false);
    if (ok) return;
    if (token != _qualitySwitchToken) return;
    // Plugin could not start: best stream at or below the 720p default.
    final match = _pickClosestOption(options, 720);
    if (match == null) return;
    await setQuality(match, keepAuto: true);
  }

  /// Switches to a different quality, preserving the current position
  /// and play state (via handler.switchStream).
  ///
  /// DASH (video-only) streams are fragile: YouTube may reject them
  /// (PO token / throttling / "Failed to open"). The new stream is
  /// verified after switching; on failure the previous quality is
  /// restored and the REAL failure reason is shown loudly (user
  /// directive 2026-10-17: never silently fall back to 360p).
  Future<void> setQuality(MuxedQuality quality, {bool keepAuto = false}) async {
    final videoId = state.videoId;
    if (state.status != PlayerStatus.ready || videoId == null) {
      return;
    }
    if (state.audioOnly) return; // quality applies to video mode only
    // Full-struct equality (height + fps + urls): picking the exact
    // stream already playing is a no-op, but switching between fps
    // variants of the same height (720p30 -> 720p60) must NOT be
    // skipped — the old height-only check blocked that.
    if (state.currentQuality == quality) return;
    final previous = state.currentQuality;
    final token = ++_qualitySwitchToken;
    // Explicit menu choice is respected as-is (the menu now lists every
    // codec variant separately). Automatic selection uses _pickDashOption
    // which prefers AVC.
    var target = quality;
    // An explicit height pick ends Auto mode (SparkTube semantics);
    // internal re-applications (Auto's own mpv pick) keep it.
    if (!keepAuto && state.autoQuality) {
      state = state.copyWith(autoQuality: false);
    }
    // A manual pick rules the rest of the session: later videos
    // start at this height too (see _directStart).
    if (!keepAuto) {
      _sessionQualityHeight = target.height;
    }
    // Already on the plugin with another target: SparkTube-style
    // rebuild from the plugin's cached catalog at the new cap —
    // position preserved, no re-extraction, no mpv detour.
    if (hqActive) {
      var rebuilt = false;
      try {
        await _plugin.setQuality(target.height);
        rebuilt = true;
      } catch (_) {}
      if (rebuilt) {
        state = state.copyWith(currentQuality: target);
        return;
      }
      // Rebuild failed — fall through to the full _playHq reload.
    }
    // Every quality goes through the plugin engine first now: it
    // plays any height reliably (exact stream for an explicit pick),
    // where mpv's DASH path kept failing ("Failed to open"). A plugin
    // failure falls through to the mpv path below instead of giving
    // up — and the mpv path reports its own failures loudly.
    final pluginOk =
        await _playHq(target, token, cap: target.height, loud: false);
    if (pluginOk) return;
    if (token != _qualitySwitchToken || state.videoId != videoId) {
      return;
    }
    // The plugin is the only engine now: a failed pick restores
    // the previous quality ON THE PLUGIN and reports loudly —
    // never a silent drop (user directive 2026-10-17).
    if (previous != null) {
      final restored =
          await _playHq(previous, token, cap: previous.height, loud: false);
      if (token != _qualitySwitchToken || state.videoId != videoId) {
        return;
      }
      if (restored) {
        state = state.copyWith(
          errorMessage:
              '${target.resolutionLabel} চালানো যায়নি — আগের কোয়ালিটিতে ফিরে গেছে',
        );
        return;
      }
    }
    state = state.copyWith(
      errorMessage: '${target.resolutionLabel} চালানো যায়নি',
    );
  }

  /// Shortens a raw playback error for display: long stream URLs carry
  /// no information for the user, so they are collapsed to a placeholder.
  String _shortenError(String e) {
    var s = e.replaceAll(
        RegExp(r'https?://[^\s]*googlevideo\.com[^\s]*'), '[googlevideo-url]');
    s = s.replaceAll(RegExp(r'https?://\S+'), '[url]');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  /// Audio mode start on the plugin engine: an audio-only load
  /// (no video track decoded), the session mirror engaged, the
  /// poll running — the exact same machinery as video mode.
  Future<void> _startAudioOnPlugin(VideoDetails video,
      {required Duration resumeAt}) async {
    final pt = _plugin;
    PureTubeController.ownerTag = 'main';
    try {
      await pt.load(
        'https://www.youtube.com/watch?v=${video.id}',
        audioOnly: true,
        position: resumeAt,
        autoplay: true,
      );
    } catch (e) {
      // Bot-blocked resolve? Same direct-URL fallback as video mode.
      if (state.videoId == video.id &&
          state.audioOnly &&
          _isResolveBlock(e.toString()) &&
          await _playDirectFallback(video.id, _qualitySwitchToken,
              resumeAt,
              audioOnly: true)) {
        return;
      }
      if (state.videoId == video.id && state.audioOnly) {
        state = state.copyWith(
          status: PlayerStatus.error,
          errorMessage:
              'গান চালু করা যায়নি: ${_shortenError(e.toString())}',
        );
      }
      return;
    }
    if (state.videoId != video.id) return;
    if (_pluginTextureId <= 0) {
      try {
        _pluginTextureId = await pt.textureId;
      } catch (_) {}
    }
    // hqTextureId doubles as the "plugin engaged" marker the whole
    // UI keys on; audio mode simply never renders the texture. When
    // the real id is momentarily unknown publish -1 (engaged, renders
    // nothing) — never a guessed id like 1, which can be a REAL
    // texture owned by something else. _publishTextureId heals it.
    state = state.copyWith(
        hqTextureId: _pluginTextureId > 0 ? _pluginTextureId : -1);
    unawaited(_publishTextureId());
    if (pt.duration > Duration.zero) {
      _hqDuration = pt.duration;
      _hqDurationCtrl.add(pt.duration);
    }
    _hqPosition = resumeAt;
    _hqPositionCtrl.add(resumeAt);
    _hqPlaying = true;
    _hqPlayingCtrl.add(true);
    if (state.speed != 1.0) {
      try {
        await pt.setSpeed(state.speed.clamp(0.25, 3.0));
      } catch (_) {}
    }
    _startHqPoll();
    _engageMirror(video);
  }

  Future<void> _directStart(String videoId,
      {PlaybackStreams? streams, required Duration resumeAt}) async {
    final token = ++_qualitySwitchToken;
    final onWifi = await _isOnWifi();
    if (state.videoId != videoId) return;
    final targetH = _targetVideoHeight(onWifi: onWifi, fullscreen: false);
    // Quality rule: Auto (fresh start or user-chosen) = adaptive;
    // a manual pick from earlier in this session beats the
    // settings default for every new video.
    final int? cap;
    if (state.autoQuality) {
      cap = null;
    } else if (_sessionQualityHeight != null) {
      cap = _sessionQualityHeight;
    } else {
      cap = targetH;
    }
    final target = MuxedQuality(
      label: cap == null ? 'Auto' : '${cap}p',
      height: cap ?? targetH ?? 720,
      // Placeholder only: the plugin resolves and plays its own
      // streams; this URL is never what reaches the player.
      url: streams?.muxedUrl ?? '',
    );
    final ok =
        await _playHq(target, token, cap: cap, loud: false, startAt: resumeAt);
    if (ok) return;
    if (token != _qualitySwitchToken ||
        state.videoId != videoId ||
        state.audioOnly) {
      return;
    }
    // No second engine to fall back to anymore (mpv is gone):
    // the plugin already retried internally (expiry re-resolve +
    // muxed fallback stages), so a failure here is real — say so
    // loudly instead of leaving a silent black player.
    if (state.videoId == videoId && !state.audioOnly) {
      state = state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'ভিডিও চালু করা যায়নি — আবার চেষ্টা করুন',
      );
    }
  }

  bool _isResolveBlock(String raw) =>
      raw.contains('resolve_failed') ||
      raw.contains('LOGIN_REQUIRED') ||
      raw.contains('not a bot') ||
      raw.contains('blocked anonymous');

  /// Fallback for when YouTube blocks the plugin's NewPipe resolve
  /// (LOGIN_REQUIRED bot wall on a flagged IP): the app's own
  /// extraction chain usually still returns direct stream URLs
  /// (session engine), so play those through the same plugin
  /// engine — playback survives the block instead of erroring out.
  Future<bool> _playDirectFallback(String videoId, int token,
      Duration resumeAt, {required bool audioOnly}) async {
    try {
      var streams = state.streams;
      if (streams == null ||
          streams.videoId != videoId ||
          streams.isExpired) {
        streams = await _extractor.getPlaybackStreams(videoId);
      }
      if (token != _qualitySwitchToken || state.videoId != videoId) {
        return false;
      }
      final pt = _plugin;
      if (_pluginTextureId <= 0) {
        try {
          _pluginTextureId = await pt.textureId;
        } catch (_) {}
      }
      state = state.copyWith(
          hqTextureId: _pluginTextureId > 0 ? _pluginTextureId : -1);
      unawaited(_publishTextureId());
      if (audioOnly) {
        await pt.loadDirect(streams.audioOnlyUrl,
            audioOnly: true, position: resumeAt, autoplay: true);
      } else {
        await pt.loadDirect(streams.muxedUrl,
            position: resumeAt, autoplay: true);
      }
      if (token != _qualitySwitchToken || state.videoId != videoId) {
        return false;
      }
      _directFallbackFor = videoId;
      if (state.speed != 1.0) {
        try {
          await pt.setSpeed(state.speed.clamp(0.25, 3.0));
        } catch (_) {}
      }
      if (!audioOnly) {
        try {
          await pt.setResizeMode(_pluginResizeMode);
        } catch (_) {}
      }
      if (pt.duration > Duration.zero) {
        _hqDuration = pt.duration;
        _hqDurationCtrl.add(pt.duration);
      }
      _hqPosition = resumeAt;
      _hqPositionCtrl.add(resumeAt);
      _hqPlaying = true;
      _hqPlayingCtrl.add(true);
      _startHqPoll();
      final playingVideo = state.video;
      if (playingVideo != null) _engageMirror(playingVideo);
      state = state.copyWith(
        streams: streams,
        // Honest label: the fallback serves the app-chain muxed
        // stream (<=720p), not the requested HQ target.
        currentQuality: audioOnly
            ? state.currentQuality
            : MuxedQuality(
                label: '${streams.muxedHeight}p',
                height: streams.muxedHeight,
                url: streams.muxedUrl,
              ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playHq(MuxedQuality target, int token,
      {required int? cap, bool loud = true, Duration? startAt}) async {
    final videoId = state.videoId;
    if (videoId == null) return false;
    // Resume where the plugin currently is (a quality switch or
    // a re-engage keeps the position; a fresh video passes 0).
    final resumeAt = startAt ?? _hqPosition;
    final url = 'https://www.youtube.com/watch?v=$videoId';
        // On a bot-blocked network the NewPipe resolve is doomed and
    // slow; once it has failed that way, go straight to the direct
    // fallback so video switches stay instant.
    if (_resolveBlockedRecently) {
      final okFb = await _playDirectFallback(videoId, token, resumeAt,
          audioOnly: false);
      if (okFb) return true;
    }
final pt = _plugin;

    // If a dubbed audio language is selected, find the matching plugin
    // track first (the plugin groups tracks by NewPipe's track id /
    // name; the app's AudioLanguage only carries a display name).
    String? audioTrackId;
    final lang = state.activeAudioLanguage;
    if (lang != null) {
      try {
        final catalog = await pt.resolve(url);
        audioTrackId = _matchPluginTrack(catalog, lang);
      } catch (_) {}
      if (token != _qualitySwitchToken || state.videoId != videoId) {
        return false;
      }
    }

    // The plugin renders into a permanent engine-owned texture, so
    // there is no view to mount first; publish the real texture id
    // and the player/popup Texture widgets show the picture. They
    // are pure render targets — mounting/unmounting them (popup,
    // PiP, fullscreen) never touches playback.
    if (_pluginTextureId <= 0) {
      try {
        _pluginTextureId = await pt.textureId;
      } catch (_) {}
    }
    state = state.copyWith(
        hqTextureId: _pluginTextureId > 0 ? _pluginTextureId : -1);
    unawaited(_publishTextureId());
    try {
      await pt.load(
        url,
        height: cap,
        audioTrackId: audioTrackId,
        position: resumeAt,
        autoplay: true,
      );
      if (token != _qualitySwitchToken || state.videoId != videoId) {
        // Superseded by a newer load: the NEW load owns the shared
        // engine now. Never stop it here — stopping the engine from
        // a stale load kills the video the user just switched to
        // (this is what made Next-from-notification/popup hang).
        return false;
      }
      if (state.speed != 1.0) {
        try {
          await pt.setSpeed(state.speed.clamp(0.25, 3.0));
        } catch (_) {}
      }
      // Re-apply the screen's fit choice to the fresh native view.
      try {
        await pt.setResizeMode(_pluginResizeMode);
      } catch (_) {}
      if (pt.duration > Duration.zero) {
        _hqDuration = pt.duration;
        _hqDurationCtrl.add(pt.duration);
      }
      _hqPosition = resumeAt;
      _hqPositionCtrl.add(resumeAt);
      _hqPlaying = true;
      _hqPlayingCtrl.add(true);
      _startHqPoll();
      // The media session (PiP, lock screen, notification) now
      // mirrors this engine — everything controls the main player.
      final playingVideo = state.video;
      if (playingVideo != null) {
        _engageMirror(playingVideo);
      }
      _resolveBlockedAt = null;
      final s = state.streams;
      state = state.copyWith(
        currentQuality: target,
        streams: s == null
            ? null
            : PlaybackStreams(
                videoId: s.videoId,
                muxedUrl: target.url,
                muxedHeight: target.height,
                audioOnlyUrl: s.audioOnlyUrl,
                audioBitrate: s.audioBitrate,
                fetchedAt: s.fetchedAt,
              ),
      );
      return true;
    } catch (e) {
      if (token != _qualitySwitchToken || state.videoId != videoId) {
        return false;
      }
      // YouTube bot-blocked the plugin's resolve (LOGIN_REQUIRED on
      // a flagged IP)? Fall back to the app's own extraction chain
      // and play its direct URLs through the same engine.
      final rawErr = pt.error ?? e.toString();
      if (_isResolveBlock(rawErr)) {
        _resolveBlockedAt = DateTime.now();
      }
      if (_isResolveBlock(rawErr) &&
          await _playDirectFallback(videoId, token, resumeAt,
              audioOnly: false)) {
        return true;
      }
      await _stopHq();
      if (!loud) return false;
      final raw = pt.error ?? e.toString();
      state = state.copyWith(
        errorMessage:
            '${target.resolutionLabel} চালানো যায়নি: ${_shortenError(raw)}',
      );
      return false;
    }
  }

  /// Best-effort match between the app's [AudioLanguage] (display name
  /// only) and the plugin's track list (NewPipe ids / names).
  String? _matchPluginTrack(PureTubeCatalog catalog, AudioLanguage lang) {
    if (catalog.audioTracks.isEmpty) return null;
    if (lang.isDefault) {
      for (final t in catalog.audioTracks) {
        if (t.isOriginal) return t.id;
      }
      return catalog.audioTracks.first.id;
    }
    final wanted = lang.displayName.toLowerCase().split(' ').first;
    for (final t in catalog.audioTracks) {
      if (t.label.toLowerCase().contains(wanted) ||
          t.id.toLowerCase().startsWith(wanted)) {
        return t.id;
      }
    }
    return null;
  }

  /// Stops the HQ engine and clears its state. Does not touch mpv.
  /// The plugin controller itself is kept alive for reuse (it allows
  /// only one live controller per engine); stop() halts its player.
  Future<void> _stopHq() async {
    _disengageMirror();
    _hqPollTimer?.cancel();
    _hqPollTimer = null;
    _hqPosition = Duration.zero;
    _hqDuration = Duration.zero;
    _hqPlaying = false;
    _ptEndedHandled = false;
    _lastPluginError = null;
    try {
      await _pt?.stop();
    } catch (_) {}
    if (state.hqTextureId != null) {
      state = state.copyWith(clearHq: true);
    }
  }

  /// Polls HQ position/playing state for the UI + SponsorBlock.
  /// The plugin controller already holds fresh values (its native side
  /// ticks at 500ms), so this just mirrors them into the display
  /// streams the UI listens to.
  void _startHqPoll() {
    _hqPollTimer?.cancel();
    _hqPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (PureTubeController.ownerTag != null &&
          PureTubeController.ownerTag != 'main') {
        return;
      }
      if (state.hqTextureId == null) return;
      final pt = _pt;
      if (pt == null) return;
      final pos = pt.position;
      _hqPosition = pos;
      _hqPositionCtrl.add(pos);
      if (pt.duration > Duration.zero && pt.duration != _hqDuration) {
        _hqDuration = pt.duration;
        _hqDurationCtrl.add(pt.duration);
      }
      final playing = pt.isPlaying;
      if (playing != _hqPlaying) {
        _hqPlaying = playing;
        _hqPlayingCtrl.add(playing);
      }
      _maybeSkipSponsor(pos);
      _maybePersistLastVideo(pos);
      _pushMirrorState();
    });
  }

  /// Unified seek — the plugin is the only engine.
  Future<void> _seekInternal(Duration target) {
    if (!hqActive) return Future.value();
    _hqPosition = target;
    _hqPositionCtrl.add(target);
    final pt = _pt;
    if (pt == null) return Future.value();
    return pt.seek(target);
  }

  /// Starts a wall-clock sleep timer: playback pauses when it
  /// fires, whatever track is playing by then. The timer is
  /// persisted (ends-at + total) so it survives app restarts and
  /// NEVER shifts with track changes.
  void startSleepTimer(Duration duration) {
    _cancelSleepTimer();
    final endsAt = DateTime.now().add(duration);
    _sleepEndsAt = endsAt;
    try {
      final box = Hive.box(HiveBoxes.playerPrefs);
      box.put(_kSleepEndsAtKey, endsAt.millisecondsSinceEpoch);
      box.put(_kSleepTotalMsKey, duration.inMilliseconds);
      box.put(_kSleepEndOfVideoKey, false);
    } catch (_) {}
    state = state.copyWith(
      sleepRemaining: duration,
      sleepTotal: duration,
      sleepEndOfVideo: false,
    );
    _armSleepCountdown();
  }

  /// Sleep at the end of the current video: a wall-clock timer
  /// set to the video's remaining time (so the timer itself never
  /// moves), flagged so completion does not autoplay the next.
  /// Returns false when the remaining time is unknown.
  bool startSleepTimerUntilEndOfVideo() {
    final total = displayDuration;
    final pos = displayPosition;
    if (total <= Duration.zero || total - pos <= Duration.zero) {
      return false;
    }
    final remaining = total - pos;
    _cancelSleepTimer();
    final endsAt = DateTime.now().add(remaining);
    _sleepEndsAt = endsAt;
    try {
      final box = Hive.box(HiveBoxes.playerPrefs);
      box.put(_kSleepEndsAtKey, endsAt.millisecondsSinceEpoch);
      box.put(_kSleepTotalMsKey, remaining.inMilliseconds);
      box.put(_kSleepEndOfVideoKey, true);
    } catch (_) {}
    state = state.copyWith(
      sleepRemaining: remaining,
      sleepTotal: remaining,
      sleepEndOfVideo: true,
    );
    _armSleepCountdown();
    return true;
  }

  /// Cancels an active sleep timer (sheet's "Off").
  void cancelSleepTimer() {
    _cancelSleepTimer();
    state = state.copyWith(sleepRemaining: null, clearSleep: true);
  }

  void _finishSleepTimer() {
    _cancelSleepTimer();
    // Mark the finish time so a `completed` event racing the timer at
    // end-of-video doesn't trigger autoplay right after the timer
    // deliberately stopped playback.
    _sleepFinishedAt = DateTime.now();
    unawaited(_handler.pause());
    state = state.copyWith(sleepRemaining: null, clearSleep: true);
  }

  void _armSleepCountdown() {
    _sleepCountdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final endsAt = _sleepEndsAt;
      if (endsAt == null) return;
      final left = endsAt.difference(DateTime.now());
      if (left <= Duration.zero) {
        _finishSleepTimer();
      } else {
        state = state.copyWith(sleepRemaining: left);
      }
    });
  }

  void _cancelSleepTimer() {
    _sleepCountdown?.cancel();
    _sleepCountdown = null;
    _sleepEndsAt = null;
    try {
      final box = Hive.box(HiveBoxes.playerPrefs);
      box.delete(_kSleepEndsAtKey);
      box.delete(_kSleepTotalMsKey);
      box.delete(_kSleepEndOfVideoKey);
    } catch (_) {}
  }

  /// Restores a persisted sleep timer (e.g. the app was backgrounded
  /// and the controller was rebuilt). Called once from [build].
  void _restoreSleepTimer() {
    try {
      final box = Hive.box(HiveBoxes.playerPrefs);
      final ms = box.get(_kSleepEndsAtKey) as int?;
      if (ms == null) return;
      final endsAt = DateTime.fromMillisecondsSinceEpoch(ms);
      final left = endsAt.difference(DateTime.now());
      if (left <= Duration.zero) {
        box.delete(_kSleepEndsAtKey);
        box.delete(_kSleepTotalMsKey);
        box.delete(_kSleepEndOfVideoKey);
        return;
      }
      final totalMs = box.get(_kSleepTotalMsKey) as int?;
      final endOfVideo = box.get(_kSleepEndOfVideoKey) as bool? ?? false;
      _sleepEndsAt = endsAt;
      state = state.copyWith(
        sleepRemaining: left,
        sleepTotal: totalMs != null ? Duration(milliseconds: totalMs) : left,
        sleepEndOfVideo: endOfVideo,
      );
      _armSleepCountdown();
    } catch (_) {}
  }

  // ---------------- SponsorBlock ----------------

  void toggleSkipSponsors(bool value) {
    state = state.copyWith(skipSponsors: value);
  }

  /// Loads the saved sponsor-skip preference (default ON).
  Future<void> _loadSavedSkipSponsors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('skip_sponsors');
      if (v != null && v != state.skipSponsors) {
        state = state.copyWith(skipSponsors: v);
      }
    } catch (_) {}
  }

  /// Loads the persisted audio-only preference from Hive (default OFF).
  /// Applied on the next loadVideo so a fresh app start restores the
  /// user's last mode.
  Future<void> _loadPlayerPrefs() async {
    try {
      // Dynamic box: stores plain values (bool), unlike the Map boxes.
      final box = Hive.box(HiveBoxes.playerPrefs);
      _prefAudioOnly = box.get(_kAudioOnlyKey) as bool? ?? false;
      // Autoplay (default ON) — pushed to state so the Up Next toggle
      // reflects the persisted value.
      _autoplay = box.get(_kAutoplayKey) as bool? ?? true;
      state = state.copyWith(autoplay: _autoplay);
    } catch (_) {
      _prefAudioOnly = false;
      _autoplay = true;
    }
  }

  Future<void> _saveAudioOnlyPref(bool value) async {
    try {
      await Hive.box(HiveBoxes.playerPrefs).put(_kAudioOnlyKey, value);
    } catch (_) {}
  }

  /// Persists the current resume position to history. Called when the
  /// app is backgrounded or torn down so playback position survives
  /// even if the player screen's dispose() never runs.
  Future<void> _persistResumePosition() async {
    final id = state.videoId;
    if (id == null || state.status != PlayerStatus.ready) return;
    final v = state.video;
    try {
      await ref.read(historyRepositoryProvider).saveResumePosition(
            videoId: id,
            positionSecs: displayPosition.inSeconds,
            title: v?.title ?? '',
            author: v?.author ?? '',
            thumbnailUrl: v?.thumbnailUrl ?? '',
            durationSecs: v?.duration?.inSeconds,
          );
    } catch (_) {}
    // Also refresh the "Continue watching" entry.
    await _saveLastVideo();
  }

  /// Saves the current video + position + mode to the player_prefs box
  /// for the home screen's "Continue watching" card. Safe to call
  /// often; failures are silent.
  Future<void> _saveLastVideo() async {
    final id = state.videoId;
    final v = state.video;
    if (id == null || v == null || state.status != PlayerStatus.ready) {
      return;
    }
    try {
      final posSecs = displayPosition.inSeconds;
      await Hive.box(HiveBoxes.playerPrefs).putAll({
        kLastVideoId: id,
        kLastVideoTitle: v.title,
        kLastVideoAuthor: v.author,
        kLastVideoThumb: v.thumbnailUrl,
        kLastVideoDurationSecs: v.duration?.inSeconds ?? 0,
        kLastVideoPositionSecs: posSecs,
        kLastVideoAudioOnly: state.audioOnly,
        kLastVideoUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      });
      _lastVideoSavedAt = DateTime.now();
      _lastVideoSavedSecs = posSecs;
    } catch (_) {}
  }

  /// Throttled last-video saver: at most once every 10s and only when
  /// the position actually advanced (avoids Hive churn on pause).
  void _maybePersistLastVideo(Duration pos) {
    if (state.status != PlayerStatus.ready || state.videoId == null) {
      return;
    }
    final secs = pos.inSeconds;
    if (secs < 3 || secs == _lastVideoSavedSecs) return;
    final last = _lastVideoSavedAt;
    if (last != null && DateTime.now().difference(last).inSeconds < 10) {
      return;
    }
    unawaited(_saveLastVideo());
  }

  Future<void> _persistThenStop() async {
    await _persistResumePosition();
    await stop();
  }

  // ---------------- Subtitles / CC ----------------

  /// Loads available caption tracks (fire-and-forget; empty on failure).
  Future<void> loadSubtitles() async {
    final id = state.videoId;
    if (id == null) return;
    try {
      final tracks = await _extractor.getCaptionTracks(id);
      if (state.videoId != id) return; // video changed meanwhile
      state = state.copyWith(subtitleTracks: tracks);
    } catch (_) {}
  }

  /// Selects a caption track (null = off). Applies via media_kit.
  /// Selects a caption track (null = off). The cues are downloaded
  /// and drawn by the player's own overlay, synced to the plugin
  /// position (mpv used to render tracks natively; it is gone).
  Future<void> selectSubtitle(CaptionTrack? track) async {
    if (track == null) {
      state = state.copyWith(clearSubtitle: true, captionCues: const []);
      return;
    }
    state = state.copyWith(activeSubtitle: track, captionCues: const []);
    final videoId = state.videoId;
    if (videoId == null) return;
    final cues =
        await _extractor.getCaptionCues(videoId, track.languageCode);
    // Bail if the user switched video/track while downloading.
    if (state.videoId != videoId ||
        state.activeSubtitle?.languageCode != track.languageCode) {
      return;
    }
    if (cues.isNotEmpty) {
      state = state.copyWith(captionCues: cues);
    }
  }

  void _maybeSkipSponsor(Duration position) {
    if (!state.skipSponsors || _skipInProgress) return;
    if (state.status != PlayerStatus.ready) return;
    for (final seg in state.sponsorSegments) {
      if (seg.contains(position)) {
        final key = '${state.videoId}:${seg.start}:${seg.end}';
        if (!_skippedSegmentKeys.add(key)) break; // already skipped once
        _skipInProgress = true;
        _seekInternal(Duration(milliseconds: (seg.end * 1000).toInt() + 250))
            .whenComplete(() => _skipInProgress = false);
        break;
      }
    }
  }

}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerUiState>(PlayerController.new);
