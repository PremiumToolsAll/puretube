import 'dart:async';

import 'package:audio_service/audio_service.dart';
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
import '../../../../core/services/watch_category_tracker.dart';
import '../../../../core/services/youtube_extractor_service.dart';
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
  final List<SponsorSegment> sponsorSegments;
  final bool skipSponsors;
  final bool pipSupported;
  final List<CaptionTrack> subtitleTracks;
  final CaptionTrack? activeSubtitle;
  final List<MuxedQuality> availableQualities;
  final MuxedQuality? currentQuality;
  final List<VideoDetails> relatedVideos;
  final bool relatedFailed;

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
    this.sponsorSegments = const [],
    this.skipSponsors = true,
    this.pipSupported = false,
    this.subtitleTracks = const [],
    this.activeSubtitle,
    this.availableQualities = const [],
    this.currentQuality,
    this.relatedVideos = const [],
    this.relatedFailed = false,
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
      sleepRemaining: sleepRemaining,
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
class PlayerController extends Notifier<PlayerUiState>
    with WidgetsBindingObserver {
  PureTubeAudioHandler get _handler =>
      ref.read(audioHandlerProvider);
  YoutubeExtractorService get _extractor =>
      ref.read(extractorProvider);
  SponsorBlockService get _sponsorBlock =>
      ref.read(sponsorBlockProvider);
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
  bool _navigatingHistory = false;

  @override
  PlayerUiState build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _pip.init();

    _pipSub = _pip.onPipChanged.listen((inPip) {
      state = state.copyWith(isInPip: inPip);
    });
    _positionSub = _handler.player.stream.position.listen((pos) {
      _maybeSkipSponsor(pos);
      _maybePersistLastVideo(pos);
    });
    _errorSub = _handler.player.stream.error.listen(_onPlayerError);

    // Wire notification skip buttons to the playback history / Up Next.
    _handler.onSkipToNext = () async {
      await playNext();
    };
    // Sync saved sponsor-skip preference (default ON).
    unawaited(_loadSavedSkipSponsors());
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
    _recoveryAttempts = 0;
    _cancelSleepTimer();
    await _handler.player.stop();

    // Record in playback history (unless this load IS a history
    // back/forward navigation — those just move the index).
    _pushHistory(videoId);

    state = PlayerUiState(
      status: PlayerStatus.loading,
      videoId: videoId,
      speed: previousSpeed,
      skipSponsors: previousSkip,
      // Restore the persisted audio-only mode on fresh app starts.
      audioOnly: previousAudioOnly || _prefAudioOnly,
    );

    try {
      final video = await _extractor.getVideoDetails(videoId);
      final streams = await _extractor.getPlaybackStreams(videoId);
      final segments = await _sponsorBlock.getSegments(videoId);

      await _handler.loadMedia(
        mediaItem: MediaItem(
          id: video.id,
          title: video.title,
          artist: video.author,
          artUri: Uri.tryParse(video.thumbnailUrl),
          duration: video.duration,
        ),
        streamUrl: streams.muxedUrl,
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
    state = const PlayerUiState();
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
      state = state.copyWith(
        relatedVideos: videos,
        relatedFailed: videos.isEmpty,
      );
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
  }

  /// Returns a video id to play for "Next", making sure Up Next is
  /// loaded first. Retries the related-videos fetch, then falls back
  /// to a direct keyword search, so Next almost always finds a video.
  /// Returns null only if every attempt fails.
  Future<String?> ensureNextVideoId() async {
    if (state.relatedVideos.isNotEmpty) {
      return state.relatedVideos.first.id;
    }
    await retryRelated();
    if (state.relatedVideos.isNotEmpty) {
      return state.relatedVideos.first.id;
    }
    // Last resort: search YouTube directly for the current title.
    final v = state.video;
    if (v == null) return null;
    try {
      final results = await _extractor.searchVideos(v.title, limit: 10);
      for (final r in results) {
        if (r.id != state.videoId) return r.id;
      }
    } catch (_) {}
    return null;
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
    if (state.currentQuality?.height == quality.height) return;
    final previous = state.currentQuality;
    final token = ++_qualitySwitchToken;
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
              target = match.first;
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
          await _rollbackQuality(previous: previous, failed: target);
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
            prevUrl = match.first.url;
            prevAudio = match.first.audioUrl;
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

  void startSleepTimer(Duration duration) {
    _cancelSleepTimer();
    _sleepEndsAt = DateTime.now().add(duration);
    state = state.copyWith(sleepRemaining: duration);
    // Persist the end time — the Dart timer keeps running while the
    // audio foreground service holds the process alive in background.
    try {
      Hive.box(HiveBoxes.playerPrefs)
          .put(_kSleepEndsAtKey, _sleepEndsAt!.millisecondsSinceEpoch);
    } catch (_) {}
    _armSleepCountdown();
  }

  /// Starts a sleep timer that fires when the current video ends.
  /// Returns false when the remaining time can't be determined.
  bool startSleepTimerUntilEndOfVideo() {
    final total = _handler.player.state.duration;
    final pos = _handler.player.state.position;
    if (total <= Duration.zero || pos >= total) return false;
    startSleepTimer(total - pos);
    return true;
  }

  void cancelSleepTimer() {
    _cancelSleepTimer();
    state = state.copyWith(sleepRemaining: null);
  }

  void _finishSleepTimer() {
    _cancelSleepTimer();
    unawaited(_handler.pause());
    state = state.copyWith(sleepRemaining: null);
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
      Hive.box(HiveBoxes.playerPrefs).delete(_kSleepEndsAtKey);
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
        return;
      }
      _sleepEndsAt = endsAt;
      state = state.copyWith(sleepRemaining: left);
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
      _prefAudioOnly =
          Hive.box(HiveBoxes.playerPrefs).get(_kAudioOnlyKey) as bool? ??
              false;
    } catch (_) {
      _prefAudioOnly = false;
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
      final fresh =
          await _extractor.getPlaybackStreams(state.videoId!);
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
          for (final q in options) {
            if (q.height == wantedHeight) {
              muxedUrl = q.url;
              muxedHeight = q.height;
              preservedQuality = q;
              break;
            }
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
