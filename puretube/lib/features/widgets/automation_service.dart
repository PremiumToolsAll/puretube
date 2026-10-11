import 'package:android_intent_plus/android_intent.dart';

/// Broadcast intents for automation apps (Tasker, MacroDroid).
class AutomationService {
  AutomationService._();
  static final AutomationService instance =
      AutomationService._();

  static const _prefix = 'com.puretube';

  Future<void> _send(
      String action, Map<String, dynamic>? extras) async {
    try {
      final intent = AndroidIntent(
        action: action,
        arguments: extras,
      );
      await intent.sendBroadcast();
    } catch (_) {}
  }

  Future<void> playPause() =>
      _send('$_prefix.PLAY_PAUSE', null);

  Future<void> play() =>
      _send('$_prefix.PLAY', null);

  Future<void> pause() =>
      _send('$_prefix.PAUSE', null);

  Future<void> next() =>
      _send('$_prefix.NEXT', null);

  Future<void> previous() =>
      _send('$_prefix.PREVIOUS', null);

  Future<void> seekTo(int seconds) => _send(
      '$_prefix.SEEK_TO',
      {'seconds': seconds});

  Future<void> setVolume(int percent) =>
      _send('$_prefix.SET_VOLUME',
          {'percent': percent});

  Future<void> openVideo(String videoId) =>
      _send('$_prefix.OPEN_VIDEO',
          {'videoId': videoId});
}
