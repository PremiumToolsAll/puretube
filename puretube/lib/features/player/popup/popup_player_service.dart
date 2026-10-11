import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:system_alert_window/system_alert_window.dart';

/// Popup (floating overlay) player service.
/// Uses `system_alert_window` for draw-over-apps.
class PopupPlayerService {
  PopupPlayerService._();
  static final PopupPlayerService instance =
      PopupPlayerService._();

  bool _showing = false;
  String? _videoId;

  bool get isShowing => _showing;
  String? get currentVideoId => _videoId;

  final _stateCtrl =
      StreamController<bool>.broadcast();
  Stream<bool> get stateStream =>
      _stateCtrl.stream;

  /// Request overlay permission (Android 10+ needs manual grant).
  Future<bool> ensurePermission(
      BuildContext context) async {
    // system_alert_window handles the permission intent internally
    // on most devices; fall back to app settings.
    final status = await Permission
        .systemAlertWindow.status;
    if (status.isGranted) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
            const Color(0xFF121212),
        title: const Text('Popup player'),
        content: const Text(
            'PureTube needs "Draw over other apps" permission to show the floating player.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text('Allow',
                  style: TextStyle(
                      color:
                          Color(0xFF6200EA)))),
        ],
      ),
    );
    if (ok == true) {
      await openAppSettings();
    }
    return false;
  }

  /// Show the floating player overlay.
  Future<bool> show({
    required String videoId,
    required String title,
  }) async {
    if (_showing) await hide();
    try {
      await SystemAlertWindow.showSystemWindow(
        height: 220,
        width: 320,
        gravity: SystemAlertWindowGravity.center,
      );
      _showing = true;
      _videoId = videoId;
      _stateCtrl.add(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> hide() async {
    try {
      await SystemAlertWindow.closeSystemWindow();
    } catch (_) {}
    _showing = false;
    _videoId = null;
    _stateCtrl.add(false);
  }

  void dispose() => _stateCtrl.close();
}
