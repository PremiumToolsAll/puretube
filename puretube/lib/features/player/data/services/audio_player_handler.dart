import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';

/// Bridges audio_service (foreground service, notification, lockscreen,
/// headset buttons) with a media_kit [Player] (the thing that really plays).
/// Created once in main() via AudioService.init and shared by the whole app,
/// so playback survives the UI being destroyed.
class PureTubeAudioHandler extends BaseAudioHandler with SeekHandler {
  PureTubeAudioHandler() {
    _playingSub = _player.stream.playing.listen((_) => _broadcastState());
    _positionSub = _player.stream.position.listen((_) {
      // Position ticks arrive several times per second; the media
      // notification only needs ~1 update/sec. State changes
      // (play/pause, buffering, duration, completion) always broadcast
      // immediately. Flooding the platform channel with playbackState
      // updates can destabilize or suppress the notification.
      final now = DateTime.now();
      if (_lastPositionBroadcast == null ||
          now.difference(_lastPositionBroadcast!) >=
              const Duration(milliseconds: 900)) {
        _lastPositionBroadcast = now;
        _broadcastState();
      }
    });
    _bufferingSub =
        _player.stream.buffering.listen((_) => _broadcastState());
    _durationSub = _player.stream.duration.listen((duration) {
      final item = mediaItem.value;
      if (item != null && item.duration != duration) {
        mediaItem.add(item.copyWith(duration: duration));
      }
      _broadcastState();
    });
    _completedSub =
        _player.stream.completed.listen((_) => _broadcastState());
    // Fatal player errors are handled by PlayerController, which also
    // listens to player.stream.error for expiry recovery.
    //
    // YouTube's DASH (video-only) URLs are picky about the client: mpv's
    // default user-agent gets "Failed to open" on some itags. Spoof the
    // same Chrome UA that youtube_explode_dart uses so mpv is treated
    // like a regular browser.
    final platform = _player.platform;
    if (platform is NativePlayer) {
      unawaited(platform.setProperty('user-agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'));
    }
  }

  final Player _player = Player(
    configuration: const PlayerConfiguration(title: 'PureTube'),
  );

  /// The single player the video UI attaches its VideoController to.
  Player get player => _player;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;

  /// Last time a position-driven _broadcastState went out (throttle).
  DateTime? _lastPositionBroadcast;

  Future<void> loadMedia({
    required MediaItem mediaItem,
    required String streamUrl,
    Duration? startAt,
    double speed = 1.0,
  }) async {
    this.mediaItem.add(mediaItem);
    await _player.setRate(speed);
    await _player.open(
      Media(streamUrl, start: startAt ?? Duration.zero),
      play: true,
    );
    _broadcastState();
  }

  /// Swap the underlying URL (audio<->video, or a refreshed URL after
  /// expiry) without losing position or play state.
  ///
  /// [audioUrl] attaches a separate audio track via mpv's 'audio-file'
  /// property — required for video-only DASH streams (1080p/1440p/2160p),
  /// which would otherwise play SILENT. Pass null (or switch back to a
  /// muxed URL without audioUrl) to clear it with 'no'.
  Future<void> switchStream(String streamUrl,
      {String? audioUrl, Duration? resumeAt}) async {
    final pos = resumeAt ?? _player.state.position;
    final wasPlaying = _player.state.playing;
    // mpv's 'audio-file' must be set BEFORE opening the media, otherwise
    // the external audio track is not attached. Guard with `is` so this
    // is a no-op on web (setProperty is defined on NativePlayer).
    // A brief pause after setProperty ensures mpv processes the property
    // before loadfile starts — without it the audio track is silently
    // dropped on some devices. 500ms gives slow devices enough margin;
    // this only runs for DASH (audioUrl != null) switches.
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('audio-file', audioUrl ?? 'no');
        if (audioUrl != null) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (_) {
        // Property set failed; continue — video may still play.
      }
    }
    await _player.open(Media(streamUrl, start: pos), play: wasPlaying);
    // The stream listeners will fire, but broadcast explicitly so the
    // notification updates promptly (new duration, position).
    _broadcastState();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> rewind() => _handlerSeek(
      _player.state.position - const Duration(seconds: 10));

  @override
  Future<void> fastForward() => _handlerSeek(
      _player.state.position + const Duration(seconds: 10));

  Future<void> _handlerSeek(Duration target) async {
    final duration = _player.state.duration;
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (duration > Duration.zero && clamped > duration) {
      clamped = duration;
    }
    await _player.seek(clamped);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // App swiped away from recents: stop playback entirely.
    await stop();
  }

  void _broadcastState() {
    final playing = _player.state.playing;
    // audio_service misbehaves when updatePosition exceeds the media
    // item's duration (can suppress or break the notification), which
    // happens transiently when the extractor's duration estimate differs
    // from mpv's real duration. Clamp defensively.
    var updatePosition = _player.state.position;
    final itemDuration = mediaItem.value?.duration;
    if (itemDuration != null &&
        itemDuration > Duration.zero &&
        updatePosition > itemDuration) {
      updatePosition = itemDuration;
    }
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
        },
        androidCompactActionIndices: const [1],
        processingState: _mapProcessingState(),
        playing: playing,
        updatePosition: updatePosition,
        bufferedPosition: _player.state.buffer,
        speed: _player.state.rate,
        queueIndex: 0,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    // Delegate to the app's queue via callback set by PlayerController.
    if (onSkipToNext != null) {
      await onSkipToNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onSkipToPrevious != null) {
      await onSkipToPrevious!();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  /// Callbacks for queue navigation, set by PlayerController.
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  AudioProcessingState _mapProcessingState() {
    final s = _player.state;
    if (s.completed) return AudioProcessingState.completed;
    if (s.buffering) return AudioProcessingState.buffering;
    return AudioProcessingState.ready;
  }
}
