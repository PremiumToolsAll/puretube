import 'dart:async';

import 'package:flutter/services.dart';

/// Talks to MainActivity over the `pure_tube/pip` channel.
/// All calls degrade to `false` on platforms without PiP (iOS, old Android).
class PipService {
  static const _channel = MethodChannel('pure_tube/pip');

  final _controller = StreamController<bool>.broadcast();
  final _actionController = StreamController<String>.broadcast();
  bool _initialized = false;

  /// Emits true/false as the activity enters/exits PiP mode.
  Stream<bool> get onPipChanged => _controller.stream;

  /// PiP window transport buttons: "playPause" / "next" / "previous".
  Stream<String> get onPipAction => _actionController.stream;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        _controller.add((call.arguments as bool?) ?? false);
      } else if (call.method == 'onPipAction') {
        _actionController.add((call.arguments as String?) ?? '');
      }
    });
  }

  Future<bool> get isPipSupported async {
    try {
      return await _channel.invokeMethod<bool>('isPipSupported') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> get isInPip async {
    try {
      return await _channel.invokeMethod<bool>('isInPip') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> enterPip() async {
    try {
      return await _channel.invokeMethod<bool>('enterPip') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Tells the native side whether playback is running so the PiP
  /// window's play/pause action shows the right icon.
  Future<void> setPlaying(bool playing) async {
    try {
      await _channel.invokeMethod<void>('setPipPlaying', {'playing': playing});
    } on PlatformException {
      // PiP unavailable — nothing to sync.
    }
  }

  void dispose() {
    _controller.close();
    _actionController.close();
  }
}
