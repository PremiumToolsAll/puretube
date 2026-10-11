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
    _positionSub = _player.stream.position.listen((_) => _broadcastState());
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
  Future<void> switchStream(String streamUrl,
      {Duration? resumeAt}) async {
    final pos = resumeAt ?? _player.state.position;
    final wasPlaying = _player.state.playing;
    await _player.open(Media(streamUrl, start: pos), play: wasPlaying);
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
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
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
        updatePosition: _player.state.position,
        bufferedPosition: _player.state.buffer,
        speed: _player.state.rate,
        queueIndex: 0,
      ),
    );
  }

  AudioProcessingState _mapProcessingState() {
    final s = _player.state;
    if (s.completed) return AudioProcessingState.completed;
    if (s.buffering) return AudioProcessingState.buffering;
    return AudioProcessingState.ready;
  }
}
