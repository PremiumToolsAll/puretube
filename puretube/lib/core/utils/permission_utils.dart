import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized permission helpers with user-friendly flows.
class PermissionUtils {
  PermissionUtils._();

  /// Storage permission for downloads (handles Android 10-14).
  static Future<bool> ensureStorage(
      [BuildContext? context]) async {
    if (!Platform.isAndroid) return true;
    try {
      // Android 13+: media permissions are granular; for our
      // public PureTube folder we need manageExternalStorage on 11+.
      var status =
          await Permission.storage.status;
      if (status.isGranted) return true;

      status =
          await Permission.storage.request();
      if (status.isGranted) return true;

      // Android 11+ scoped storage: request all-files access.
      if (await Permission
          .manageExternalStorage.isRestricted) {
        final manage =
            await Permission.manageExternalStorage
                .request();
        if (manage.isGranted) return true;
      }

      if (context != null &&
          context.mounted &&
          status.isPermanentlyDenied) {
        final open =
            await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title:
                const Text('Storage permission'),
            content: const Text(
                'PureTube needs storage access to save downloads. Please enable it in app settings.'),
            actions: [
              TextButton(
                  onPressed: () =>
                      Navigator.pop(
                          context, false),
                  child:
                      const Text('Cancel')),
              TextButton(
                  onPressed: () =>
                      Navigator.pop(
                          context, true),
                  child: const Text(
                      'Open settings')),
            ],
          ),
        );
        if (open == true) {
          await openAppSettings();
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Notification permission (Android 13+).
  static Future<bool> ensureNotifications() async {
    if (!Platform.isAndroid) return true;
    try {
      var status = await Permission
          .notification.status;
      if (status.isGranted) return true;
      status =
          await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Overlay permission for popup player.
  static Future<bool> ensureOverlay(
      BuildContext context) async {
    try {
      var status = await Permission
          .systemAlertWindow.status;
      if (status.isGranted) return true;

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title:
              const Text('Draw over other apps'),
          content: const Text(
              'Allow PureTube to display the floating popup player over other apps.'),
          actions: [
            TextButton(
                onPressed: () =>
                    Navigator.pop(context, false),
                child:
                    const Text('Cancel')),
            TextButton(
                onPressed: () =>
                    Navigator.pop(context, true),
                child: const Text('Allow')),
          ],
        ),
      );
      if (ok == true) {
        await openAppSettings();
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
