import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/hive_setup.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/services/pip_service.dart';
import '../../../../core/services/sponsorblock_service.dart';
import '../../../../core/services/lyrics_service.dart';
import '../../../../core/services/watch_category_tracker.dart';
import '../../../../core/services/youtube_extractor_service.dart';
import '../../../../core/services/sabr/sabr_http_server.dart';
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
  final List<MuxedQuality> availableQualities;
  final MuxedQuality? currentQuality;
  final List<VideoDetails> relatedVideos;
  final bool relatedFailed;
  final LyricsResult? lyricsResult;
  final bool lyricsLoading;

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
    this.availableQualities = const [],
    this.currentQuality,
    this.relatedVideos = const [],
    this.relatedFailed = false,
    this.lyricsResult,
    this.lyricsLoading = false,
    this.autoplay = true,
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
    bool clearSubtitle = false,
    List<MuxedQuality>? availableQualities,
    MuxedQuality? currentQuality,
    List<VideoDetails>? relatedVideos,
    bool? relatedFailed,
    LyricsResult? lyricsResult,
    bool? lyricsLoading,
    bool clearLyrics = false,
    bool? autoplay,
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
      sleepTotal:
          clearSleep ? null : (sleepTotal ?? this.sleepTotal),
      sleepEndOfVideo: clearSleep
          ? false
          : (sleepEndOfVideo ?? this.sleepEndOfVideo),
      sponsorSegments: sponsorSegments ?? this.sponsorSegments,
      skipSponsors: skipSponsors ?? this.skipSponsors,
      pipSupported: pipSupported ?? this.pipSupported,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      activeSubtitle:
          clearSubtitle ? null : activeSubtitle ?? this.activeSubtitle,
      availableQualities:
          availableQualities ?? this.availableQualities,
      currentQuality: currentQuality ?? this.currentQuality,
      relatedVideos: relatedVideos ?? this.relatedVideos,
      relatedFailed: relatedFailed ?? this.relatedFailed,
      lyricsResult:
          clearLyrics ? null : (lyricsResult ?? this.lyricsResult),
      lyricsLoading: lyricsLoading ?? this.lyricsLoading,
      autoplay: autoplay ?? this.autoplay,
    );
  }
}

/// Outcome of _verifyDashLoad.
enum _DashLoadOutcome {
  /// mpv produced a duration — the stream is loading/playing.
  loaded,

  /// mpv reported an error ("Failed to open ...") — the URL is dead
  /// (expired, 403'd, or revoked). A manifest refresh may fix it.
  error,

  /// No duration and no error within the timeout — the network is too
  /// slow or the stream stalled. Retrying the same way won't help.
  timeout,
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
  PureTubeAudioHandler get _handler =>
      ref.read(audioHandlerProvider);
  YoutubeExtractorService get _extractor =>
      ref.read(extractorProvider);
  SponsorBlockService get _sponsorBlock =>
      ref.read(sponsorBlockProvider);

  /// Reads the "Prefer AVC" setting (default true).
  bool _preferAvc = true;

  /// Local HTTP server for serving SABR media to the player.
  final SabrHttpServer _sabrServer = SabrHttpServer();
  bool _sabrServerStarted = false;

  Future<void> _ensureSabrServer() async {
    if (!_sabrServerStarted) {
      await _sabrServer.start();
      _sabrServerStarted = true;
    }
  }

  Future<void> _loadPreferAvc() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('prefer_avc');
      if (v != null) _preferAvc = v;
    } catch (_) {}
  }
  PipService get _pip => ref.read(pipServiceProvider);

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _pipSub;

  Timer? _sleepCountdown;
  DateTime? _sleepEndsAt;
  bool _skipInProgress = false;
  int _recoveryAttempts = 0;

  /// Bumps on every setQuality call; lets in-flight verifications detect
  /// when the user has moved on to another quality/video.
  int _qualitySwitchToken = 0;

  /// True while a DASH quality switch is being verified (or rolled back).
  /// The global [_onPlayerError] recovery must stay out during this window —
  /// the switch owns error handling until verification completes.
  bool _dashVerifyInFlight = false;

  /// Last persisted audio-only preference (Hive). Applied on the next
  /// loadVideo so a fresh app start restores the user's last mode.
  bool _prefAudioOnly = false;
  static const _kAudioOnlyKey = 'audio_only';

  /// Autoplay preference (Hive, default ON). When a video/track completes
  /// and this is true, the next Up Next item starts automatically — in
  /// both video and audio mode, since both share one media_kit Player.
  bool _autoplay = true;
  static const _kAutoplayKey = 'autoplay';

  /// Completion → playNext handoff guards.
  StreamSubscription<bool>? _completedSub;
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

    _pipSub = _pip.onPipChanged.listen((inPip) {
      state = state.copyWith(isInPip: inPip);
      if (inPip) {
        // Native PiP owns the window now: drop the in-app floating popup
        // so the video never renders twice.
        ref.read(popupVisibleProvider.notifier).state = false;
      }
    });
    _positionSub = _handler.player.stream.position.listen((pos) {
      _maybeSkipSponsor(pos);
      _maybePersistLastVideo(pos);
    });
    _errorSub = _handler.player.stream.error.listen(_onPlayerError);
    // Natural playback completion → autoplay the next Up Next item.
    // Both video and audio mode share this one media_kit Player, so a
    // single listener covers both.
    try {
      _completedSub =
          _handler.player.stream.completed.listen((_) {
        _onPlaybackCompleted();
      });
    } catch (_) {}

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
      _positionSub?.cancel();
      _errorSub?.cancel();
      _completedSub?.cancel();
      _cancelSleepTimer();
    });

    return const PlayerUiState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.paused:
        // Home button / app switcher: let audio continue in background,
        // but persist the resume position first.
        // PiP only when user explicitly taps the PiP button — auto-PiP
        // was interrupting background playback.
        unawaited(_persistResumePosition());
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
    final previousSpeed = state.speed;
    final previousSkip = state.skipSponsors;
    final previousAudioOnly = state.audioOnly;
    final keepAudioOnly = previousAudioOnly || _prefAudioOnly;
    _recoveryAttempts = 0;
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
    // Navigating away cancels any in-flight pre-load pass.
    _precacheToken++;
    // Navigating away also cancels any in-flight lyrics auto-fetch.
    _lyricsToken++;
    await _handler.player.stop();

    // Record in playback history (unless this load IS a history
    // back/forward navigation — those just move the index).
    _pushHistory(videoId);

    state = PlayerUiState(
      status: PlayerStatus.loading,
      videoId: videoId,
      // Audio mode: keep the previous track's artwork/title visible while
      // the new track loads (YouTube Music style — no full-screen spinner).
      video: keepAudioOnly ? state.video : null,
      speed: previousSpeed,
      skipSponsors: previousSkip,
      // Restore the persisted audio-only mode on fresh app starts.
      audioOnly: keepAudioOnly,
      // Keep the autoplay preference across video loads.
      autoplay: _autoplay,
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
      // DASH (video-only + separate audio) is how high quality plays:
      // 'auto' aims for 720p DASH by default, explicit 720p+ choices
      // use DASH too. The pre-cache only holds muxed streams, so it
      // can't serve DASH targets.
      final wantDash = !keepAudioOnly &&
          (targetHeight == null || targetHeight >= 720);

      // Use pre-fetched Up Next data when available (instant Next),
      // otherwise fetch normally. The hit is removed; other queued
      // videos stay precached for later.
      final VideoDetails video;
      final PlaybackStreams streams;
      final List<SponsorSegment> segments;
      String? dashAudioUrl;
      final PrecachedData? hit = _precache.remove(videoId);
      if (hit != null && !wantDash) {
        video = hit.details;
        streams = hit.streams;
        segments = hit.segments;
      } else {
        // Fast path: fetch details, streams, and sponsor segments in
        // parallel instead of sequentially — cuts load time significantly.
        if (wantDash) {
          // Fetch the DASH option list and the audio track in parallel,
          // then build a DASH-backed PlaybackStreams.
          final results = await Future.wait([
            _extractor.getVideoDetails(videoId),
            // Quality list failure must not kill the load — empty
            // options simply fall back to the muxed stream below.
            _extractor
                .getQualityOptions(videoId)
                .catchError((_) => const <MuxedQuality>[]),
            _extractor.getPlaybackStreams(videoId,
                preferBestAudio: !worstAudio),
            _sponsorBlock.getSegments(videoId),
          ]);
          video = results[0] as VideoDetails;
          final options = results[1] as List<MuxedQuality>;
          final base = results[2] as PlaybackStreams;
          segments = results[3] as List<SponsorSegment>;
          final dash =
              _pickDashOption(options, targetHeight ?? 720);
          if (dash != null) {
            streams = PlaybackStreams(
              videoId: videoId,
              muxedUrl: dash.url,
              muxedHeight: dash.height,
              audioOnlyUrl: base.audioOnlyUrl,
              audioBitrate: base.audioBitrate,
              fetchedAt: DateTime.now(),
            );
            dashAudioUrl = dash.audioUrl;
          } else {
            // No DASH stream at that height — fall back to muxed.
            streams = base;
          }
        } else {
          final results = await Future.wait([
            _extractor.getVideoDetails(videoId),
            _extractor.getPlaybackStreams(
              videoId,
              maxMuxedHeight: targetHeight ?? 720,
              preferBestAudio: !worstAudio,
            ),
            _sponsorBlock.getSegments(videoId),
          ]);
          video = results[0] as VideoDetails;
          streams = results[1] as PlaybackStreams;
          segments = results[2] as List<SponsorSegment>;
        }
      }

      // audio_service fetches artUri natively for the notification/lockscreen
      // artwork. Only hand it a real http(s) URL — an empty or malformed
      // Uri makes the notification's artwork loader fail and can leave
      // the notification art-less or stale.
      final artUri = Uri.tryParse(video.thumbnailUrl);
      await _handler.loadMedia(
        mediaItem: MediaItem(
          id: video.id,
          title: video.title,
          artist: video.author,
          artUri: (artUri != null &&
                  (artUri.scheme == 'http' || artUri.scheme == 'https'))
              ? artUri
              : null,
          duration: video.duration,
        ),
        streamUrl: streams.muxedUrl,
        audioUrl: dashAudioUrl,
        speed: previousSpeed,
      );

      state = state.copyWith(
        status: PlayerStatus.ready,
        video: video,
        streams: streams,
        sponsorSegments: segments,
        pipSupported: await _pip.isPipSupported,
      );
      // Record this video for "Continue watching" on the home screen.
      unawaited(_saveLastVideo());
      // Resume from saved position if the user watched this before.
      // Skip if position is 0 or within 10s of the end (likely finished).
      final savedSecs =
          ref.read(historyRepositoryProvider).getPosition(videoId);
      final totalSecs = video.duration?.inSeconds ?? 0;
      if (savedSecs > 5 &&
          (totalSecs <= 0 || savedSecs < totalSecs - 10)) {
        await _handler.player
            .seek(Duration(seconds: savedSecs));
      }
      // Load captions in the background; UI updates when ready.
      unawaited(loadSubtitles());
      // Same for quality options; current quality starts at the
      // height of the initially picked stream.
      unawaited(loadQualities(initialHeight: streams.muxedHeight));
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
      unawaited(_autoFetchLyrics(videoId,
          title: video.title, author: video.author));
    } on PureTubeException catch (e) {
      state = state.copyWith(
          status: PlayerStatus.error, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
          status: PlayerStatus.error,
          errorMessage: 'Playback failed: $e');
    }
  }

  Future<void> retry() async {
    final id = state.videoId;
    if (id == null) return;
    final resumeAt = _handler.player.state.position;
    await loadVideo(id);
    if (resumeAt > const Duration(seconds: 3) &&
        state.status == PlayerStatus.ready) {
      await _handler.seek(resumeAt);
    }
  }

  Future<void> stop() async {
    _cancelSleepTimer();
    _recoveryAttempts = 0;
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
    final pos = _handler.player.state.position;
    if (pos > const Duration(seconds: 3)) {
      await _handler.seek(Duration.zero);
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
    await _handler.seek(Duration.zero);
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
  void _onPlaybackCompleted() {
    if (!_autoplay) return;
    if (state.status != PlayerStatus.ready) return;
    if (state.sleepEndOfVideo) return;
    final finishedAt = _sleepFinishedAt;
    if (finishedAt != null &&
        DateTime.now().difference(finishedAt) <
            const Duration(seconds: 10)) {
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

  Future<void> togglePlayPause() async {
    if (_handler.player.state.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> seekTo(Duration position) => _handler.seek(position);

  Future<void> seekBy(Duration offset) async {
    final player = _handler.player;
    var target = player.state.position + offset;
    final duration = player.state.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    await _handler.seek(target);
  }

  Future<void> setSpeed(double speed) async {
    final s = speed.clamp(0.25, 4.0);
    await _handler.setSpeed(s);
    state = state.copyWith(speed: s);
  }

  /// Toggle between video and background-audio mode, preserving position.
  ///
  /// Does NOT switch streams: the current stream (muxed, or DASH video with
  /// its attached audio track) keeps playing; only the UI changes (video
  /// hidden in audio mode). This preserves position perfectly and starts
  /// audio immediately — switching to the audio-only URL was unreliable
  /// (stale/expired URLs, delayed start, position reset).
  Future<void> toggleAudioOnly() async {
    if (state.status != PlayerStatus.ready ||
        state.videoId == null) {
      return;
    }
    final goingAudioOnly = !state.audioOnly;
    state = state.copyWith(audioOnly: goingAudioOnly);
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
      final anchor =
          initialHeight ?? state.currentQuality?.height;
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
        currentQuality: current,
      );
    } catch (_) {}
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
          titleHint: titleHint,
          authorHint: authorHint,
          boostCategories: boost);
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
    await _loadRelated(id,
        titleHint: v?.title, authorHint: v?.author);
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
    final targetHeight =
        _targetVideoHeight(onWifi: onWifi, fullscreen: false);
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
        state = state.copyWith(
            lyricsResult: cached, lyricsLoading: false);
      }
      return;
    }
    if (state.videoId == videoId) {
      state = state.copyWith(clearLyrics: true, lyricsLoading: true);
    }
    try {
      LyricsResult result;
      // 1. YouTube's own captions (free AI transcript) — primary source.
      final transcript =
          await _extractor.getCaptionTranscript(videoId);
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
        state = state.copyWith(
            lyricsResult: result, lyricsLoading: false);
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
  int? _targetVideoHeight(
      {required bool onWifi, required bool fullscreen}) {
    final nofs = ref.read(onWifi
        ? wifiNoFullscreenQualityProvider
        : mobileNoFullscreenQualityProvider);
    final full = ref.read(onWifi
        ? wifiVideoQualityProvider
        : mobileVideoQualityProvider);
    final value = (!fullscreen && nofs != 'same') ? nofs : full;
    return qualityValueToHeight(value);
  }

  /// True when the user picked the data-saver audio tier.
  bool _wantWorstAudio(bool onWifi) =>
      ref
          .read(onWifi
              ? wifiAudioQualityProvider
              : mobileAudioQualityProvider) ==
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

  bool _isAvc(String codec) =>
      codec.toLowerCase().contains('avc');

  /// Best DASH option at-or-below [targetHeight].
  ///
  /// When "Prefer AVC" is ON (default): AVC (H.264) is strongly
  /// preferred — it's the most compatible codec. First pass picks the
  /// highest AVC at-or-below target; only if no AVC exists at all does
  /// it fall back to best-height VP9/AV1.
  /// When OFF: picks by height first, then codec rank, then fps.
  MuxedQuality? _pickDashOption(
      List<MuxedQuality> options, int targetHeight) {
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
              _dashCodecRank(q.codec) >
                  _dashCodecRank(best.codec)) ||
          (q.height == best.height &&
              _dashCodecRank(q.codec) ==
                  _dashCodecRank(best.codec) &&
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
    final videoId = state.videoId;
    if (videoId == null) return;
    final onWifi = await _isOnWifi();
    final target =
        _targetVideoHeight(onWifi: onWifi, fullscreen: isFullscreen);
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

  /// Switches to a different quality, preserving the current position
  /// and play state (via handler.switchStream).
  ///
  /// DASH (video-only) streams are fragile: YouTube may reject them
  /// (PO token / throttling / "Failed to open"). The new stream is
  /// verified after switching; on failure the PREVIOUS quality is
  /// restored and a clear error is shown — the app never silently
  /// drops to an arbitrary lower quality.
  Future<void> setQuality(MuxedQuality quality) async {
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
    // NOTE: no manifest refresh before switching (an earlier version
    // refreshed here for DASH). YouTube's android client limits stream
    // URL reuse — the extractor itself warns it "often prevents
    // downloading the same stream multiple times or more than one
    // stream from the same manifest" — and every manifest fetch HEADs
    // each URL, burning the budget mpv needs for real playback. DASH
    // needs 2 URLs (video + audio), so a pre-switch refresh made DASH
    // 403 while single-URL muxed survived. The cached URLs from
    // loadQualities() are minutes old (signed URLs live ~6h). If they
    // did expire, verification below fails and we refresh+retry once.
    try {
      await _handler.switchStream(target.url,
          audioUrl: target.audioUrl);
    } catch (_) {
      // Switch itself threw (e.g. invalid URL): roll back.
      if (token != _qualitySwitchToken || state.videoId != videoId) {
        return;
      }
      await _rollbackQuality(previous: previous, failed: target);
      return;
    }
    // Verify DASH actually loads; muxed streams are trusted.
    if (target.isDash) {
      _dashVerifyInFlight = true;
      try {
        var outcome = await _verifyDashLoad(target, token);
        if (token != _qualitySwitchToken || state.videoId != videoId) {
          return;
        }
        // Hard mpv error (e.g. 403 "Failed to open"): the cached URLs
        // are likely dead/expired — refresh once and retry with fresh
        // URLs (a new manifest = new URLs with a full use budget). A
        // timeout means the network is just slow; retrying won't help.
        if (outcome == _DashLoadOutcome.error) {
          try {
            final fresh = await _extractor.getQualityOptions(videoId);
            // Bail if the user moved on while the manifest was loading.
            if (token != _qualitySwitchToken || state.videoId != videoId) {
              return;
            }
            final match = fresh
                .where((q) => q.height == quality.height && q.isDash);
            if (match.isNotEmpty) {
              // Retry the same fps variant when it still exists (the
              // list is sorted fps-desc, so first is the best
              // fallback).
              target = match.firstWhere((q) => q.fps == quality.fps,
                  orElse: () => match.first);
              // Keep the quality menu in sync with the fresh URLs.
              state = state.copyWith(availableQualities: fresh);
              await _handler.switchStream(target.url,
                  audioUrl: target.audioUrl);
              outcome = await _verifyDashLoad(target, token);
              if (token != _qualitySwitchToken ||
                  state.videoId != videoId) {
                return;
              }
            }
          } catch (_) {
            // Refresh/retry failed; fall through to rollback.
          }
        }
        if (outcome != _DashLoadOutcome.loaded) {
          // DASH failed — try SABR (YouTube's native protocol) before
          // rolling back. SABR streams directly from YouTube's CDN.
          final sabrOk = await _trySabrFallback(
              videoId, target, token);
          if (!sabrOk) {
            await _rollbackQuality(
                previous: previous, failed: target);
          }
          return;
        }
      } finally {
        _dashVerifyInFlight = false;
      }
    }
    if (token != _qualitySwitchToken || state.videoId != videoId) {
      return;
    }
    // Success: adopt the new quality.
    final s = state.streams;
    state = state.copyWith(
      currentQuality: target,
      // Keep the cached streams record in sync so expiry recovery
      // and audio<->video toggling reuse the chosen quality.
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
  }

  /// Waits for a DASH stream to actually start producing a duration.
  ///
  /// [token] must match [_qualitySwitchToken]; a mismatch means the user
  /// picked another quality (or video) meanwhile and the caller must
  /// treat the result as stale.
  Future<_DashLoadOutcome> _verifyDashLoad(
      MuxedQuality target, int token) async {
    const timeout = Duration(seconds: 8);
    const pollInterval = Duration(milliseconds: 500);
    final deadline = DateTime.now().add(timeout);
    var hadError = false;
    final errorSub =
        _handler.player.stream.error.listen((_) => hadError = true);
    try {
      while (DateTime.now().isBefore(deadline)) {
        // Bail early if superseded or an error fired. (Do NOT compare
        // state.currentQuality here: it still holds the OLD quality
        // until verification succeeds.)
        if (token != _qualitySwitchToken) return _DashLoadOutcome.timeout;
        if (hadError) return _DashLoadOutcome.error;
        final duration = _handler.player.state.duration;
        if (duration > Duration.zero) return _DashLoadOutcome.loaded;
        await Future.delayed(pollInterval);
      }
      return _DashLoadOutcome.timeout;
    } finally {
      await errorSub.cancel();
    }
  }

  /// Tries SABR (YouTube's native streaming protocol) when DASH fails.
  /// Downloads video+audio via SABR and plays the local files.
  /// Returns true if SABR playback started.
  Future<bool> _trySabrFallback(
      String videoId, MuxedQuality target, int token) async {
    try {
      state = state.copyWith(
          errorMessage: 'Trying SABR for ${target.resolutionLabel}...');
      // Get SABR info to find matching itags.
      final sabrInfo =
          await _extractor.session.getSabrInfo(videoId);
      final formats =
          sabrInfo['formats'] as List<Map<String, dynamic>>;

      // Find video format matching target height (prefer same codec).
      Map<String, dynamic>? videoFormat;
      for (final f in formats) {
        if (f['isAudio'] as bool) continue;
        if ((f['height'] as int) != target.height) continue;
        if (videoFormat == null) {
          videoFormat = f;
        } else {
          // Prefer AVC if target is AVC.
          final targetIsAvc = target.codec.toLowerCase().contains('avc');
          final fIsAvc = (f['mimeType'] as String)
              .toLowerCase()
              .contains('avc');
          if (targetIsAvc == fIsAvc) {
            if ((f['bitrate'] as int) >
                (videoFormat['bitrate'] as int)) {
              videoFormat = f;
            }
          }
        }
      }
      // Fallback: highest bitrate at target height.
      videoFormat ??= formats
          .where((f) =>
              !(f['isAudio'] as bool) &&
              (f['height'] as int) == target.height)
          .fold<Map<String, dynamic>?>(null, (best, f) {
        if (best == null ||
            (f['bitrate'] as int) > (best['bitrate'] as int)) {
          return f;
        }
        return best;
      });
      if (videoFormat == null) return false;

      // Best audio format.
      final audioFormat = formats
          .where((f) => f['isAudio'] as bool)
          .fold<Map<String, dynamic>?>(null, (best, f) {
        if (best == null ||
            (f['bitrate'] as int) > (best['bitrate'] as int)) {
          return f;
        }
        return best;
      });
      if (audioFormat == null) return false;

      if (token != _qualitySwitchToken ||
          state.videoId != videoId) {
        return false;
      }

      // True streaming via SABR: start mpv as soon as enough data
      // is buffered, while the download continues in the background.
      var started = false;
      final paths =
          await _extractor.session.downloadViaSabr(
        videoId: videoId,
        videoItag: videoFormat['itag'] as int,
        audioItag: audioFormat['itag'] as int,
        onProgress: (d, _) {
          if (token == _qualitySwitchToken && !started) {
            state = state.copyWith(
                errorMessage:
                    'SABR: ${d ~/ 1024} KB buffered...');
          }
        },
        onReadyToPlay: (videoPath, audioPath) async {
          if (token != _qualitySwitchToken ||
              state.videoId != videoId ||
              started) {
            return;
          }
          started = true;
          try {
            // Serve via local HTTP for better streaming.
            await _ensureSabrServer();
            final urls = _sabrServer.registerFiles(
              videoId: videoId,
              videoPath: videoPath,
              audioPath: audioPath,
              videoMime:
                  videoFormat?['mimeType'] as String? ?? 'video/mp4',
              audioMime:
                  audioFormat?['mimeType'] as String? ?? 'audio/mp4',
            );
            await _handler.switchStream(
              urls['videoUrl']!,
              audioUrl: urls['audioUrl']!,
            );
            if (token == _qualitySwitchToken) {
              state = state.copyWith(
                currentQuality: target,
                errorMessage: null,
              );
            }
          } catch (_) {
            // mpv failed; the download continues, caller handles.
          }
        },
      );

      if (token != _qualitySwitchToken ||
          state.videoId != videoId) {
        return false;
      }

      // If onReadyToPlay already started playback, we're done.
      // Otherwise (download completed without early start), play now
      // via the local HTTP server (better range-request handling).
      if (!started) {
        await _ensureSabrServer();
        final urls = _sabrServer.registerFiles(
          videoId: videoId,
          videoPath: paths['videoPath']!,
          audioPath: paths['audioPath']!,
          videoMime:
              videoFormat['mimeType'] as String? ?? 'video/mp4',
          audioMime:
              audioFormat['mimeType'] as String? ?? 'audio/mp4',
        );
        await _handler.switchStream(
          urls['videoUrl']!,
          audioUrl: urls['audioUrl'],
        );
        state = state.copyWith(
          currentQuality: target,
          errorMessage: null,
        );
      }
      return true;
    } catch (e) {
      // SABR failed; caller will roll back.
      return false;
    }
  }

  /// Restores the previous quality after a failed switch and surfaces a
  /// clear error (e.g. "1080p failed to load, back to 720p"). The app
  /// never silently drops to an arbitrary lower quality.
  Future<void> _rollbackQuality({
    required MuxedQuality? previous,
    required MuxedQuality failed,
  }) async {
    final failedName = failed.resolutionLabel;
    if (previous == null) {
      state = state.copyWith(
          errorMessage: '$failedName failed to load');
      return;
    }
    final prevName = previous.resolutionLabel;
    try {
      // Refresh the previous stream URL too — it may have expired while
      // the failed attempt was in flight.
      var prevUrl = previous.url;
      String? prevAudio = previous.audioUrl;
      final vid = state.videoId;
      if (previous.isDash && vid != null) {
        try {
          final fresh = await _extractor.getQualityOptions(vid);
          final match = fresh
              .where((q) => q.height == previous.height && q.isDash);
          if (match.isNotEmpty) {
            // Restore the same fps variant when it still exists;
            // the list is sorted fps-desc so the first entry is the
            // best fallback otherwise.
            final same = match.firstWhere(
              (q) => q.fps == previous.fps,
              orElse: () => match.first,
            );
            prevUrl = same.url;
            prevAudio = same.audioUrl;
          }
        } catch (_) {}
      }
      await _handler.switchStream(prevUrl, audioUrl: prevAudio);
      final restored = MuxedQuality(
        label: previous.label,
        height: previous.height,
        url: prevUrl,
        audioUrl: prevAudio,
        bitrateKbps: previous.bitrateKbps,
        fps: previous.fps,
        codec: previous.codec,
        isHdr: previous.isHdr,
      );
      final s = state.streams;
      state = state.copyWith(
        currentQuality: restored,
        errorMessage: '$failedName failed to load, back to $prevName',
        streams: s == null
            ? null
            : PlaybackStreams(
                videoId: s.videoId,
                muxedUrl: prevUrl,
                muxedHeight: previous.height,
                audioOnlyUrl: s.audioOnlyUrl,
                audioBitrate: s.audioBitrate,
                fetchedAt: s.fetchedAt,
              ),
      );
    } catch (e) {
      state = state.copyWith(
          errorMessage:
              '$failedName failed to load, could not restore $prevName: $e');
    }
  }

  // ---------------- sleep timer ----------------

  /// Hive key for the persisted sleep-timer end time (epoch millis),
  /// so the timer survives app backgrounding.
  static const _kSleepEndsAtKey = 'sleep_ends_at_ms';
  static const _kSleepTotalMsKey = 'sleep_total_ms';
  static const _kSleepEndOfVideoKey = 'sleep_end_of_video';

  void startSleepTimer(Duration duration, {bool endOfVideo = false}) {
    _cancelSleepTimer();
    _sleepEndsAt = DateTime.now().add(duration);
    state = state.copyWith(
      sleepRemaining: duration,
      sleepTotal: duration,
      sleepEndOfVideo: endOfVideo,
    );
    // Persist the end time — the Dart timer keeps running while the
    // audio foreground service holds the process alive in background.
    // The original total + end-of-video flag are persisted too so the
    // sleep timer sheet can show the right option as selected.
    try {
      final box = Hive.box(HiveBoxes.playerPrefs);
      box.put(_kSleepEndsAtKey, _sleepEndsAt!.millisecondsSinceEpoch);
      box.put(_kSleepTotalMsKey, duration.inMilliseconds);
      box.put(_kSleepEndOfVideoKey, endOfVideo);
    } catch (_) {}
    _armSleepCountdown();
  }

  /// Starts a sleep timer that fires when the current video ends.
  /// Returns false when the remaining time can't be determined.
  bool startSleepTimerUntilEndOfVideo() {
    final total = _handler.player.state.duration;
    final pos = _handler.player.state.position;
    if (total <= Duration.zero || pos >= total) return false;
    startSleepTimer(total - pos, endOfVideo: true);
    return true;
  }

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
    _sleepCountdown =
        Timer.periodic(const Duration(seconds: 1), (_) {
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
        sleepTotal: totalMs != null
            ? Duration(milliseconds: totalMs)
            : left,
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
      _prefAudioOnly =
          box.get(_kAudioOnlyKey) as bool? ?? false;
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
      await Hive.box(HiveBoxes.playerPrefs)
          .put(_kAudioOnlyKey, value);
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
            positionSecs:
                _handler.player.state.position.inSeconds,
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
      final posSecs = _handler.player.state.position.inSeconds;
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
    if (state.status != PlayerStatus.ready ||
        state.videoId == null) {
      return;
    }
    final secs = pos.inSeconds;
    if (secs < 3 || secs == _lastVideoSavedSecs) return;
    final last = _lastVideoSavedAt;
    if (last != null &&
        DateTime.now().difference(last).inSeconds < 10) {
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
  Future<void> selectSubtitle(CaptionTrack? track) async {
    try {
      if (track == null) {
        await _handler.player
            .setSubtitleTrack(SubtitleTrack.no());
        state = state.copyWith(clearSubtitle: true);
      } else {
        await _handler.player.setSubtitleTrack(
            SubtitleTrack.uri(track.url,
                title: track.language));
        state = state.copyWith(activeSubtitle: track);
      }
    } catch (_) {}
  }

  void _maybeSkipSponsor(Duration position) {
    if (!state.skipSponsors || _skipInProgress) return;
    if (state.status != PlayerStatus.ready) return;
    for (final seg in state.sponsorSegments) {
      if (seg.contains(position)) {
        _skipInProgress = true;
        _handler
            .seek(
                Duration(milliseconds: (seg.end * 1000).toInt() + 250))
            .whenComplete(() => _skipInProgress = false);
        break;
      }
    }
  }

  // ---------------- stream expiry & error recovery ----------------

  /// media_kit reports fatal errors (expired/403'd URL, lost connection)
  /// on player.stream.error. Recover by re-extracting fresh URLs and
  /// resuming at the last position. Bounded to 2 attempts, then the
  /// error is surfaced to the UI instead of looping forever.
  Future<void> _onPlayerError(String error) async {
    if (state.status != PlayerStatus.ready ||
        state.videoId == null) {
      return;
    }
    if (error.trim().isEmpty) return;
    // A DASH quality switch is mid-verification/rollback — it owns error
    // handling until done. Recovering here would fight the switch and
    // leave the player in an inconsistent state.
    if (_dashVerifyInFlight) return;

    if (_recoveryAttempts >= 2) {
      state = state.copyWith(
        status: PlayerStatus.error,
        errorMessage:
            'Playback failed and could not recover: $error',
      );
      return;
    }
    _recoveryAttempts++;

    try {
      final resumeAt = _handler.player.state.position;
      final onWifi = await _isOnWifi();
      final fresh = await _extractor.getPlaybackStreams(state.videoId!,
          preferBestAudio: !_wantWorstAudio(onWifi));
      if (state.status != PlayerStatus.ready) return;
      // Preserve the user's chosen quality across recovery when possible.
      // Exception: DASH (video-only) qualities are fragile — if the player
      // errored while on DASH ("Failed to open ...googlevideo.com..."),
      // retrying the same DASH URL just fails again. Fall back to the
      // reliable muxed stream instead so the video keeps playing.
      var muxedUrl = fresh.muxedUrl;
      var muxedHeight = fresh.muxedHeight;
      MuxedQuality? preservedQuality;
      final wantedHeight = state.currentQuality?.height;
      final wantedIsDash = state.currentQuality?.isDash ?? false;
      if (!state.audioOnly &&
          !wantedIsDash &&
          wantedHeight != null &&
          wantedHeight != fresh.muxedHeight) {
        try {
          final options =
              await _extractor.getQualityOptions(state.videoId!);
          // Preserve the user's exact (height, fps) variant when it
          // still exists; muxed-only (a DASH match would lose audio).
          // The list is sorted fps-desc, so the first height match is
          // the best fallback.
          final wantedFps = state.currentQuality?.fps;
          final atHeight = options
              .where((q) => q.height == wantedHeight && !q.isDash)
              .toList();
          if (atHeight.isNotEmpty) {
            final q = atHeight.firstWhere((e) => e.fps == wantedFps,
                orElse: () => atHeight.first);
            muxedUrl = q.url;
            muxedHeight = q.height;
            preservedQuality = q;
          }
        } catch (_) {}
      }
      state = state.copyWith(
        streams: PlaybackStreams(
          videoId: fresh.videoId,
          muxedUrl: muxedUrl,
          muxedHeight: muxedHeight,
          audioOnlyUrl: fresh.audioOnlyUrl,
          audioBitrate: fresh.audioBitrate,
          fetchedAt: fresh.fetchedAt,
        ),
        // Keep the quality label in sync with the stream actually playing.
        currentQuality: preservedQuality ??
            MuxedQuality(
              label: 'MPEG-4 ${muxedHeight}p',
              height: muxedHeight,
              url: muxedUrl,
            ),
      );
      final url = state.audioOnly ? fresh.audioOnlyUrl : muxedUrl;
      await _handler.switchStream(url,
          audioUrl:
              state.audioOnly ? null : preservedQuality?.audioUrl,
          resumeAt: resumeAt);
    } on PureTubeException catch (e) {
      // Most likely NetworkException: user lost internet mid-playback.
      state = state.copyWith(
          status: PlayerStatus.error, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
          status: PlayerStatus.error,
          errorMessage: 'Playback error: $e');
    }
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerUiState>(
        PlayerController.new);
