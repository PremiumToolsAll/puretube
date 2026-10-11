import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/services/pip_service.dart';
import '../../../../core/services/sponsorblock_service.dart';
import '../../../../core/services/youtube_extractor_service.dart';
import '../../data/services/audio_player_handler.dart';
import '../../domain/entities/playback_models.dart';

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
    );
  }
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

  @override
  PlayerUiState build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _pip.init();

    _pipSub = _pip.onPipChanged.listen((inPip) {
      state = state.copyWith(isInPip: inPip);
    });
    _positionSub =
        _handler.player.stream.position.listen(_maybeSkipSponsor);
    _errorSub = _handler.player.stream.error.listen(_onPlayerError);

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
        // Home button / app switcher while video is playing: shrink to PiP.
        if (state.status == PlayerStatus.ready &&
            !state.audioOnly &&
            !state.isInPip &&
            _handler.player.state.playing) {
          unawaited(_pip.enterPip());
        }
        break;
      case AppLifecycleState.detached:
        // PiP window dismissed with X, or process teardown: stop playback.
        unawaited(stop());
        break;
      default:
        break;
    }
  }

  // ---------------- loading ----------------

  Future<void> loadVideo(String videoId) async {
    final previousSpeed = state.speed;
    final previousSkip = state.skipSponsors;
    _recoveryAttempts = 0;
    _cancelSleepTimer();
    await _handler.player.stop();

    state = PlayerUiState(
      status: PlayerStatus.loading,
      videoId: videoId,
      speed: previousSpeed,
      skipSponsors: previousSkip,
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
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
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
    final s = speed.clamp(0.5, 2.0);
    await _handler.setSpeed(s);
    state = state.copyWith(speed: s);
  }

  /// Toggle between video and background-audio mode, preserving position.
  Future<void> toggleAudioOnly() async {
    if (state.status != PlayerStatus.ready ||
        state.videoId == null) {
      return;
    }
    final goingAudioOnly = !state.audioOnly;
    try {
      final streams = await _ensureFreshStreams();
      final url =
          goingAudioOnly ? streams.audioOnlyUrl : streams.muxedUrl;
      await _handler.switchStream(url);
      state = state.copyWith(audioOnly: goingAudioOnly);
    } on PureTubeException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    }
  }

  Future<void> enterPip() async {
    if (state.pipSupported && state.status == PlayerStatus.ready) {
      await _pip.enterPip();
    }
  }

  // ---------------- sleep timer ----------------

  void startSleepTimer(Duration duration) {
    _cancelSleepTimer();
    _sleepEndsAt = DateTime.now().add(duration);
    state = state.copyWith(sleepRemaining: duration);
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

  void cancelSleepTimer() {
    _cancelSleepTimer();
    state = state.copyWith(sleepRemaining: null);
  }

  void _finishSleepTimer() {
    _cancelSleepTimer();
    unawaited(_handler.pause());
    state = state.copyWith(sleepRemaining: null);
  }

  void _cancelSleepTimer() {
    _sleepCountdown?.cancel();
    _sleepCountdown = null;
    _sleepEndsAt = null;
  }

  // ---------------- SponsorBlock ----------------

  void toggleSkipSponsors(bool value) {
    state = state.copyWith(skipSponsors: value);
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

  Future<PlaybackStreams> _ensureFreshStreams() async {
    final current = state.streams;
    if (current != null && !current.isExpired) return current;
    final fresh =
        await _extractor.getPlaybackStreams(state.videoId!);
    state = state.copyWith(streams: fresh);
    return fresh;
  }

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
      state = state.copyWith(streams: fresh);
      final url =
          state.audioOnly ? fresh.audioOnlyUrl : fresh.muxedUrl;
      await _handler.switchStream(url, resumeAt: resumeAt);
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
