import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rxdart/rxdart.dart';

/// PureTube foreground audio service.
///
/// Architecture:
/// - `media_kit` [Player] does the actual decoding (video or audio-only).
/// - [AudioService] wraps it in a `MediaSession` + Android foreground
///   service (`FOREGROUND_SERVICE_MEDIA_PLAYBACK`), so playback survives
///   app close, Doze, and battery optimization.
/// - Lock-screen + notification controls: previous, rewind, play/pause,
///   fast-forward, next.
///
/// Callbacks [onSkipNext]/[onSkipPrevious] are wired by the playback
/// controller (which owns the queue).
class PureTubeAudioHandler extends BaseAudioHandler
    with SeekHandler {
  PureTubeAudioHandler() {
    _initSession();
    _playingSub =
        _player.stream.playing.listen((_) => _broadcast());
    _positionSub = _player.stream.position
        .listen((_) => _broadcast());
    _bufferingSub = _player.stream.buffering
        .listen((_) => _broadcast());
    _durationSub =
        _player.stream.duration.listen((duration) {
      final item = mediaItem.value;
      if (item != null && item.duration != duration) {
        mediaItem.add(item.copyWith(duration: duration));
      }
      _broadcast();
    });
    _completedSub = _player.stream.completed
        .listen((completed) {
      if (completed) {
        // Auto-advance the queue.
        skipToNext();
      } else {
        _broadcast();
      }
    });
  }

  final Player _player = Player(
    configuration:
        const PlayerConfiguration(title: 'PureTube'),
  );

  /// The single player the video UI attaches its VideoController to.
  Player get player => _player;

  /// Wired by the playback controller.
  Future<void> Function()? onSkipNext;
  Future<void> Function()? onSkipPrevious;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;

  Future<void> _initSession() async {
    final session = await AudioSession.instance;
    await session.configure(
        const AudioSessionConfiguration.music());
    // Handle headset plug / bluetooth disconnect.
    session.becomingNoisyEventStream.listen((_) => pause());
  }

  // ── Loading ─────────────────────────────────────────────────

  /// Open [streamUrl] (optionally a DASH video+audio pair) and play.
  Future<void> loadMedia({
    required MediaItem item,
    required String streamUrl,
    String? audioUrl,
    Duration startAt = Duration.zero,
    double speed = 1.0,
  }) async {
    mediaItem.add(item);
    await _player.setRate(speed);
    // NOTE: media_kit ignores Media.extras['audio-file'] — the DASH audio
    // track must be attached via the mpv 'audio-file' property instead,
    // otherwise video-only streams (1080p/1440p/4K) play SILENT.
    await _player.open(
      Media(streamUrl, start: startAt),
      play: true,
    );
    // NOTE: setProperty is defined on NativePlayer (not Player) in
    // media_kit — access it via _player.platform with an `is` guard so
    // the DASH external-audio attachment keeps working on Android/iOS/
    // desktop and is a no-op on web.
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(
          'audio-file', audioUrl ?? 'no');
    }
    _broadcast();
  }

  /// Swap the stream URL (quality change / expiry refresh) keeping
  /// position and play state.
  Future<void> switchStream(
    String streamUrl, {
    String? audioUrl,
    Duration? resumeAt,
  }) async {
    final pos = resumeAt ?? _player.state.position;
    final wasPlaying = _player.state.playing;
    await _player.open(
      Media(streamUrl, start: pos),
      play: wasPlaying,
    );
    // 'no' clears a previously attached external audio track when
    // switching back to a muxed stream.
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(
          'audio-file', audioUrl ?? 'no');
    }
    _broadcast();
  }

  // ── MediaSession controls ───────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) =>
      _player.seek(position);

  @override
  Future<void> rewind() => _seekBy(const Duration(seconds: -10));

  @override
  Future<void> fastForward() =>
      _seekBy(const Duration(seconds: 10));

  Future<void> _seekBy(Duration offset) async {
    final target = _player.state.position + offset;
    final duration = _player.state.duration;
    final clamped = target.isNegative
        ? Duration.zero
        : (duration > Duration.zero && target > duration
            ? duration
            : target);
    await _player.seek(clamped);
  }

  @override
  Future<void> setSpeed(double speed) =>
      _player.setRate(speed);

  @override
  Future<void> skipToNext() =>
      onSkipNext?.call() ?? Future.value();

  @override
  Future<void> skipToPrevious() =>
      onSkipPrevious?.call() ?? Future.value();

  @override
  Future<void> onTaskRemoved() async {
    // Keep playing when the task is swiped away (user asked for
    // background audio). Stop only via notification close.
    _broadcast();
  }

  // ── State broadcast ─────────────────────────────────────────

  void _broadcast() {
    final playing = _player.state.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          if (playing)
            MediaControl.pause
          else
            MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 2, 4],
        processingState: _processingState(),
        playing: playing,
        updatePosition: _player.state.position,
        bufferedPosition: _player.state.buffer,
        speed: _player.state.rate,
      ),
    );
  }

  AudioProcessingState _processingState() {
    final s = _player.state;
    if (s.completed) return AudioProcessingState.completed;
    if (s.buffering) return AudioProcessingState.buffering;
    return AudioProcessingState.ready;
  }

  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _bufferingSub?.cancel();
    await _durationSub?.cancel();
    await _completedSub?.cancel();
    await _player.dispose();
  }
}

/// Bootstrap the [AudioService] foreground service.
/// Call once in `main()` before `runApp`.
Future<PureTubeAudioHandler> initAudioService() async {
  return AudioService.init(
    builder: () => PureTubeAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId:
          'com.puretube.channel.audio',
      androidNotificationChannelName: 'PureTube playback',
      androidNotificationOngoing: false,
      androidShowNotificationBadge: false,
      androidStopForegroundOnPause: false,
      // Keep the service alive for background audio.
      androidNotificationClickStartsActivity: true,
    ),
  ).then((h) => h as PureTubeAudioHandler);
}
