library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

int _integer(Object? value) => (value as num?)?.toInt() ?? 0;

class PureTubeAudioTrack {
  const PureTubeAudioTrack(
      {required this.id, required this.label, required this.isOriginal});
  factory PureTubeAudioTrack.fromMap(Map<Object?, Object?> map) =>
      PureTubeAudioTrack(
        id: map['id'] as String? ?? 'default',
        label: map['label'] as String? ?? 'Default',
        isOriginal: map['isOriginal'] == true,
      );
  final String id;
  final String label;
  final bool isOriginal;
}

class PureTubeCatalog {
  PureTubeCatalog.fromMap(Map<Object?, Object?> map)
      : url = map['url'] as String? ?? '',
        title = map['title'] as String? ?? '',
        duration = Duration(milliseconds: _integer(map['durationMs'])),
        hasVideo = map['hasVideo'] == true,
        qualities = List<int>.unmodifiable(
            (map['qualities'] as List? ?? []).map(_integer)),
        audioTracks = List<PureTubeAudioTrack>.unmodifiable(
          (map['audioTracks'] as List? ?? []).map((e) =>
              PureTubeAudioTrack.fromMap(Map<Object?, Object?>.from(e as Map))),
        );
  final String url;
  final String title;
  final Duration duration;
  final bool hasVideo;

  /// Available heights, not a promise that the device can decode every codec.
  final List<int> qualities;
  final List<PureTubeAudioTrack> audioTracks;
}

class PureTubeVideo {
  PureTubeVideo.fromMap(Map<Object?, Object?> map)
      : url = map['url'] as String? ?? '',
        title = map['title'] as String? ?? '',
        uploader = map['uploader'] as String? ?? '',
        thumbnailUrl = map['thumbnailUrl'] as String? ?? '',
        duration = Duration(milliseconds: _integer(map['durationMs']));
  final String url, title, uploader, thumbnailUrl;
  final Duration duration;
}

/// One controller / native player per Flutter engine. Android only.
/// Keep it above route widgets if playback should survive route changes.
/// Call close() when the playback session is finished; dispose() also closes it.
class PureTubeController extends ChangeNotifier {
  PureTubeController() {
    if (_claimed) {
      throw StateError(
          'Only one PureTubeController may be active. Await close() before creating another.');
    }
    _claimed = true;
    _subscription = _events.receiveBroadcastStream().listen(_onEvent,
        onError: (Object error) {
      if (_closed) return;
      this.error = error.toString();
      notifyListeners();
    });
  }

  static const _methods = MethodChannel('puretube_playback/methods');
  static const _events = EventChannel('puretube_playback/events');
  static bool _claimed = false;
  late final StreamSubscription<dynamic> _subscription;
  bool _closed = false;

  /// Which app surface currently owns the shared native engine
  /// ('main' player, 'shorts', 'offline'). The native engine is a
  /// single player; surfaces stamp this before loading so the
  /// main PlayerController can ignore state events for loads it
  /// did not start.
  static String? ownerTag;
  Future<void>? _closing;
  int _loadGeneration = 0;

  PureTubeCatalog? catalog;
  bool isPlaying = false, buffering = false, ended = false, resolving = false;
  Duration position = Duration.zero,
      duration = Duration.zero,
      bufferedPosition = Duration.zero;
  int videoWidth = 0, videoHeight = 0;
  String? error;

  Future<int>? _textureIdFuture;

  /// The engine-owned render texture. The native player draws into it
  /// permanently; any number of [PureTubeVideoView]s may display it and
  /// mounting/unmounting them never touches playback.
  Future<int> get textureId =>
      _textureIdFuture ??= _invoke<int>('textureId').then((v) => v ?? -1);

  void _onEvent(dynamic raw) {
    if (_closed || raw is! Map) return;
    final map = Map<Object?, Object?>.from(raw);
    switch (map['type']) {
      case 'state':
        isPlaying = map['isPlaying'] == true;
        buffering = map['buffering'] == true;
        ended = map['ended'] == true;
        position = Duration(milliseconds: _integer(map['positionMs']));
        duration = Duration(milliseconds: _integer(map['durationMs']));
        bufferedPosition =
            Duration(milliseconds: _integer(map['bufferedPositionMs']));
        videoWidth = _integer(map['videoWidth']);
        videoHeight = _integer(map['videoHeight']);
      case 'catalog':
        catalog = PureTubeCatalog.fromMap(map);
      case 'error':
        error =
            '${map['code'] ?? 'PLAYBACK'}: ${map['message'] ?? 'Playback failed'}';
      default:
        return;
    }
    notifyListeners();
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    if (_closed) throw StateError('Controller is closed');
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      if (!_closed && e.code != 'superseded') {
        error = '${e.code}: ${e.message ?? 'Native playback failed'}';
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Metadata / stream URLs are extracted on Android, never stored in Dart.
  Future<PureTubeCatalog> resolve(String url) async {
    final raw = await _invoke<Map<Object?, Object?>>('resolve', {'url': url});
    return PureTubeCatalog.fromMap(raw ?? {});
  }

  Future<PureTubeCatalog> load(String url,
      {int? height,
      String? audioTrackId,
      bool audioOnly = false,
      Duration position = Duration.zero,
      bool autoplay = true}) async {
    final generation = ++_loadGeneration;
    resolving = true;
    error = null;
    notifyListeners();
    try {
      final raw = await _invoke<Map<Object?, Object?>>('load', {
        'url': url,
        'height': height,
        'audioTrackId': audioTrackId,
        'audioOnly': audioOnly,
        'positionMs': position.inMilliseconds,
        'autoplay': autoplay,
      });
      final result = PureTubeCatalog.fromMap(raw ?? {});
      if (!_closed && generation == _loadGeneration) catalog = result;
      return result;
    } finally {
      if (!_closed && generation == _loadGeneration) {
        resolving = false;
        notifyListeners();
      }
    }
  }

  /// Plays a downloaded file (offline playback), merging the
  /// optional companion audio file natively. No network involved.
  Future<void> loadLocal({
    required String path,
    String? audioPath,
    bool audioOnly = false,
    Duration position = Duration.zero,
    bool autoplay = true,
  }) async {
    ++_loadGeneration;
    resolving = true;
    error = null;
    notifyListeners();
    try {
      await _invoke<void>('loadLocal', {
        'path': path,
        'audioPath': audioPath,
        'audioOnly': audioOnly,
        'positionMs': position.inMilliseconds,
        'autoplay': autoplay,
      });
    } finally {
      if (!_closed) {
        resolving = false;
        notifyListeners();
      }
    }
  }

  /// First result page only. No embedded API key or third-party proxy server.
  Future<List<PureTubeVideo>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final raw = await _invoke<List<Object?>>('search', {'query': query.trim()});
    return (raw ?? [])
        .map((e) => PureTubeVideo.fromMap(Map<Object?, Object?>.from(e as Map)))
        .toList(growable: false);
  }

  Future<void> play() async {
    await _invoke<void>('play');
  }

  Future<void> pause() async {
    await _invoke<void>('pause');
  }

  Future<void> stop() async {
    await _invoke<void>('stop');
  }

  Future<void> seek(Duration value) async {
    await _invoke<void>('seek',
        {'positionMs': value.inMilliseconds < 0 ? 0 : value.inMilliseconds});
  }

  Future<void> setQuality(int? height) async {
    await _invoke<void>('setQuality', {'height': height});
  }

  /// Accepted for API compatibility; with texture rendering the fit
  /// is applied on the Dart side by [PureTubeVideoView]'s `fit`.
  Future<void> setResizeMode(int mode) async {
    await _invoke<void>('setResizeMode', {'mode': mode});
  }

  /// Whether the plugin's own foreground-service notification may
  /// show. The app disables it when its audio_service media session
  /// already provides the one connected notification (mirror mode),
  /// so the same playback never produces two notifications.
  Future<void> setServiceNotificationEnabled(bool enabled) async {
    await _invoke<void>(
        'setNotificationEnabled', {'enabled': enabled});
  }

  Future<void> setAudioTrack(String id) async {
    await _invoke<void>('setAudioTrack', {'id': id});
  }

  /// Mutes/unmutes the engine's audio output (Shorts mute button).
  /// Playback volume otherwise follows the system media volume.
  Future<void> setMuted(bool muted) async {
    await _invoke<void>('setMuted', {'muted': muted});
  }

  Future<void> setAudioOnly(bool enabled) async {
    await _invoke<void>('setAudioOnly', {'enabled': enabled});
  }

  Future<void> setSpeed(double speed) async {
    if (!speed.isFinite || speed < 0.25 || speed > 3) {
      throw ArgumentError.value(speed, 'speed', 'Use 0.25–3.0');
    }
    await _invoke<void>('setSpeed', {'speed': speed});
  }

  Future<void> close() {
    if (!_closed) dispose();
    return _closing!;
  }

  Future<void> _release() async {
    try {
      await _subscription.cancel();
      await _methods.invokeMethod<void>('dispose');
    } finally {
      _claimed = false;
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    super.dispose();
    _closing = _release();
    // Widget disposal is synchronous; close() exposes release failures.
    unawaited(_closing!.catchError((Object _) {}));
  }
}

/// The shared native player's picture, as a Flutter texture.
///
/// The player renders into ONE engine-owned surface (SparkTube's
/// one-player model): this widget is a pure render target, so the
/// full player, the popup and PiP can mount/unmount it freely —
/// playback position and picture survive every transition.
class PureTubeVideoView extends StatelessWidget {
  const PureTubeVideoView({
    super.key,
    required this.textureId,
    required this.aspectRatio,
    this.fit = BoxFit.contain,
  });

  final int textureId;

  /// Video width / height; <= 0 falls back to 16:9.
  final double aspectRatio;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (textureId <= 0 ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    final ar = aspectRatio > 0 ? aspectRatio : 16 / 9;
    final texture = Texture(textureId: textureId);
    if (fit == BoxFit.fill) return texture;
    return SizedBox.expand(
      child: FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: ar * 1000,
          height: 1000,
          child: texture,
        ),
      ),
    );
  }
}
