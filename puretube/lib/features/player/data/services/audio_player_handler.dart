import 'dart:async';

import 'package:audio_service/audio_service.dart';

/// The MediaSession facade for the ONE playback engine (the
/// puretube_playback plugin: NewPipeExtractor + Media3/ExoPlayer).
///
/// This handler owns no player of its own. It describes the
/// plugin's playback to the system — foreground service,
/// notification, lock screen, headset buttons, PiP actions — and
/// routes every incoming command back to the plugin through the
/// callbacks PlayerController installs ([onExternalPlay] and
/// friends), so every surface controls the same main player.
/// (The old media_kit/mpv engine that used to live here was
/// removed entirely: two engines meant two truths, and every
/// desync bug — lying icons, foreign sounds, stuck loads —
/// traced back to that split.)
class PureTubeAudioHandler extends BaseAudioHandler with SeekHandler {
  // ---- external (mirror) mode ----
  //
  // Kept as an explicit engage/disengage pair: PlayerController
  // engages mirror mode when the plugin starts a video and
  // disengages on stop, so a stopped session broadcasts idle
  // instead of stale plugin state.
  bool externalMode = false;
  Future<void> Function()? onExternalPlay;
  Future<void> Function()? onExternalPause;
  Future<void> Function(Duration)? onExternalSeek;
  Future<void> Function(double)? onExternalSetSpeed;
  Future<void> Function()? onExternalStop;

  bool _extPlaying = false;
  bool _extBuffering = false;
  bool _extCompleted = false;
  Duration _extPosition = Duration.zero;
  Duration _extBuffered = Duration.zero;
  double _extSpeed = 1.0;

  /// Pushes the real (plugin) player's state into the media session.
  void setExternalState({
    required bool playing,
    required bool buffering,
    required bool completed,
    required Duration position,
    required Duration buffered,
    required double speed,
  }) {
    _extPlaying = playing;
    _extBuffering = buffering;
    _extCompleted = completed;
    _extPosition = position;
    _extBuffered = buffered;
    _extSpeed = speed;
    if (externalMode) _broadcastState();
  }

  /// Sets the media item shown on the lock screen / notification
  /// while the plugin plays.
  void setExternalMediaItem(MediaItem item) {
    mediaItem.add(item);
    // Publish a one-item queue too: some Android skins only enable
    // the skip buttons when the session carries a queue.
    queue.add([item]);
    if (externalMode) _broadcastState();
  }

  /// Re-broadcasts the current state (used when mirror mode is
  /// disengaged so the session settles immediately).
  void refreshState() => _broadcastState();

  @override
  Future<void> play() async {
    if (externalMode) {
      await onExternalPlay?.call();
    }
  }

  @override
  Future<void> pause() async {
    if (externalMode) {
      await onExternalPause?.call();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (externalMode) {
      await onExternalSeek?.call(position);
    }
  }

  @override
  Future<void> rewind() async {
    await _externalSeekBy(const Duration(seconds: -10));
  }

  @override
  Future<void> fastForward() async {
    await _externalSeekBy(const Duration(seconds: 10));
  }

  Future<void> _externalSeekBy(Duration offset) async {
    if (!externalMode) return;
    var target = _extPosition + offset;
    if (target < Duration.zero) target = Duration.zero;
    final duration = mediaItem.value?.duration ?? Duration.zero;
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    await onExternalSeek?.call(target);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (externalMode) {
      await onExternalSetSpeed?.call(speed);
    }
  }

  @override
  Future<void> stop() async {
    if (externalMode) {
      // The controller's stop flow turns mirror mode off first and
      // then calls stop() again for the real teardown — delegating
      // here keeps one single stop path.
      await onExternalStop?.call();
      return;
    }
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // App swiped away from recents: stop playback entirely.
    await stop();
  }

  void _broadcastState() {
    if (!externalMode) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
      return;
    }
    var updatePosition = _extPosition;
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
          if (_extPlaying) MediaControl.pause else MediaControl.play,
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
        androidCompactActionIndices: const [1],
        processingState: _extCompleted
            ? AudioProcessingState.completed
            : _extBuffering
                ? AudioProcessingState.buffering
                : AudioProcessingState.ready,
        playing: _extPlaying,
        updatePosition: updatePosition,
        bufferedPosition: _extBuffered,
        speed: _extSpeed,
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
    } else if (externalMode) {
      await onExternalSeek?.call(Duration.zero);
    }
  }

  /// Callbacks for queue navigation, set by PlayerController.
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
}
