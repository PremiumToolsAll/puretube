import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/database/hive_setup.dart';
import 'core/di/providers.dart';
import 'features/player/data/services/audio_player_handler.dart';

/// Tracks whether media_kit native libs loaded OK.
/// If false, the player shows a message instead of crashing.
bool mediaKitReady = false;

/// Sentry DSN placeholder — the user adds the real DSN later.
/// Leave empty to run without crash reporting.
const _sentryDsn = '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch-all: never leave the user staring at a white screen.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // media_kit native libs can fail on some devices/ABIs — don't let it
  // kill the whole app; the home feed works fine without it.
  try {
    MediaKit.ensureInitialized();
    mediaKitReady = true;
  } catch (e) {
    debugPrint('MediaKit init failed (non-fatal): $e');
    mediaKitReady = false;
  }

  try {
    await initHive();
  } catch (e) {
    debugPrint('Hive init failed (non-fatal): $e');
  }

  await _ensureNotificationPermission();

  // AudioService is nice-to-have for background playback; the app must
  // still open if it fails (e.g. manifest/service edge cases).
  // Fallback: plain handler without the foreground service.
  late final PureTubeAudioHandler audioHandler;
  try {
    audioHandler = await AudioService.init(
      builder: () => PureTubeAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.puretube.channel.audio',
        androidNotificationChannelName: 'PureTube playback',
        androidNotificationOngoing: true,
        androidShowNotificationBadge: false,
        androidStopForegroundOnPause: true,
      ),
    ) as PureTubeAudioHandler;
  } catch (e) {
    debugPrint('AudioService init failed, using fallback handler: $e');
    audioHandler = PureTubeAudioHandler();
  }

  Future<void> launchApp() async {
    runApp(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(audioHandler),
        ],
        child: const PureTubeApp(),
      ),
    );
  }

  // Sentry crash reporting — wrapped so the app always launches
  // even with no DSN or if Sentry itself fails.
  if (_sentryDsn.isNotEmpty) {
    try {
      await SentryFlutter.init(
        (o) {
          o.dsn = _sentryDsn;
          o.tracesSampleRate = 0.2;
        },
        appRunner: launchApp,
      );
      return;
    } catch (e) {
      debugPrint('Sentry init failed (non-fatal): $e');
    }
  }
  await launchApp();
}

/// Android 13+ needs a runtime grant before the playback notification
/// (and its controls) can appear. Audio itself works regardless.
Future<void> _ensureNotificationPermission() async {
  if (!Platform.isAndroid) return;
  try {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  } catch (_) {
    // Best effort; never block startup.
  }
}
