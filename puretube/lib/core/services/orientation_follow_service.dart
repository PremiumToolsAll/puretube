import 'package:flutter/services.dart';

/// Fullscreen landscape follow: while the full player is open the
/// native side watches the device tilt (OrientationEventListener)
/// and locks the activity to the landscape side the phone is
/// actually held on — flipping when the user turns the phone over.
/// Dart only starts/stops it; the side logic is native because
/// Flutter's preferred-orientations list alone leaves many phones
/// stuck on one side.
class OrientationFollowService {
  static const MethodChannel _channel =
      MethodChannel('pure_tube/orientation');

  static Future<void> startLandscapeFollow() async {
    try {
      await _channel.invokeMethod('startLandscapeFollow');
    } catch (_) {}
  }

  static Future<void> stopLandscapeFollow() async {
    try {
      await _channel.invokeMethod('stopLandscapeFollow');
    } catch (_) {}
  }
}
