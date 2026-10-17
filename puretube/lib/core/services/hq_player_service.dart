import 'package:flutter/services.dart';

/// Dart side of the native HQ player ([HqPlayerPlugin] Kotlin).
///
/// Used ONLY for explicit 1080p+ DASH selection — everything else keeps
/// using mpv via media_kit. The native player renders into a Flutter
/// [Texture] and speaks NewPipe's HTTP shape (POST + &rn= + &range=),
/// which is what makes 1080p actually play on this phone.
///
/// Single active instance at a time: [dispose] before [create] again.
class HqPlayerService {
  static const MethodChannel _ch = MethodChannel('puretube_hq_player');

  int? _textureId;
  bool _handlerSet = false;

  /// Raw native error message (already loud — surface it, don't downgrade).
  void Function(String message)? onError;

  /// Fired when ExoPlayer reaches STATE_READY.
  void Function(Duration duration, int videoWidth, int videoHeight)? onReady;

  /// Fired when playback completes.
  void Function()? onCompleted;

  int? get textureId => _textureId;
  bool get isActive => _textureId != null;

  void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onHqError':
          final args = call.arguments as Map?;
          onError?.call(
              args?['message']?.toString() ?? 'HQ playback error');
        case 'onHqReady':
          final args = call.arguments as Map?;
          final ms = (args?['durationMs'] as num?)?.toInt() ?? 0;
          final w = (args?['videoWidth'] as num?)?.toInt() ?? 0;
          final h = (args?['videoHeight'] as num?)?.toInt() ?? 0;
          onReady?.call(Duration(milliseconds: ms), w, h);
        case 'onHqCompleted':
          onCompleted?.call();
      }
    });
  }

  /// Creates the native player + texture. Returns the texture id for
  /// the [Texture] widget.
  Future<int> create() async {
    _ensureHandler();
    await dispose();
    final id = await _ch.invokeMethod<int>('create');
    if (id == null) throw StateError('HQ player: create returned null');
    _textureId = id;
    return id;
  }

  Future<void> loadDash({
    required String videoUrl,
    required String audioUrl,
    required String videoCodec,
    required int width,
    required int height,
    required int fps,
    required int videoBitrateBps,
    required String audioCodec,
    required int audioBitrateBps,
    required int audioSampleRate,
    Duration startAt = Duration.zero,
    double speed = 1.0,
  }) {
    final id = _textureId;
    if (id == null) throw StateError('HQ player: not created');
    return _ch.invokeMethod('loadDash', {
      'textureId': id,
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'videoCodec': videoCodec,
      'width': width,
      'height': height,
      'fps': fps,
      'videoBitrateBps': videoBitrateBps,
      'audioCodec': audioCodec,
      'audioBitrateBps': audioBitrateBps,
      'audioSampleRate': audioSampleRate,
      'startPositionMs': startAt.inMilliseconds,
      'speed': speed,
    });
  }

  Future<void> _call(String method, [Map<String, Object?>? args]) {
    final id = _textureId;
    if (id == null) return Future.value();
    return _ch.invokeMethod(method, {'textureId': id, ...?args});
  }

  Future<void> play() => _call('play');
  Future<void> pause() => _call('pause');
  Future<void> seekTo(Duration position) =>
      _call('seekTo', {'positionMs': position.inMilliseconds});
  Future<void> setSpeed(double speed) => _call('setSpeed', {'speed': speed});
  Future<void> setVolume(double volume) =>
      _call('setVolume', {'volume': volume});

  Future<Duration> position() async {
    final id = _textureId;
    if (id == null) return Duration.zero;
    final ms = await _ch.invokeMethod<int>(
        'getPosition', {'textureId': id});
    return Duration(milliseconds: ms ?? 0);
  }

  Future<Duration> duration() async {
    final id = _textureId;
    if (id == null) return Duration.zero;
    final ms = await _ch.invokeMethod<int>(
        'getDuration', {'textureId': id});
    return Duration(milliseconds: ms ?? 0);
  }

  Future<bool> isPlaying() async {
    final id = _textureId;
    if (id == null) return false;
    return await _ch.invokeMethod<bool>(
            'isPlaying', {'textureId': id}) ??
        false;
  }

  Future<void> dispose() async {
    final id = _textureId;
    _textureId = null;
    if (id == null) return;
    try {
      await _ch.invokeMethod('dispose', {'textureId': id});
    } catch (_) {}
  }
}
