import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'core/database/hive_setup.dart';
import 'core/di/providers.dart';
import 'features/player/data/services/audio_player_handler.dart';

/// Tracks whether media_kit native libs loaded OK.
/// If false, the player shows a message instead of crashing.
bool mediaKitReady = false;

/// Tracks whether AudioService.init succeeded (true) or fell back (false).
/// Used for background-playback diagnostics.
bool audioServiceReady = false;

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
  bool audioServiceOk = false;

  /// Attempts AudioService.init with retries. Transient failures (e.g.
  /// service not yet ready, race conditions on some devices) can succeed
  /// on a second attempt.
  Future<PureTubeAudioHandler?> tryAudioServiceInit() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final handler = await AudioService.init(
          builder: () => PureTubeAudioHandler(),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.puretube.channel.audio',
            androidNotificationChannelName: 'PureTube playback',
            androidShowNotificationBadge: false,
            // Keep the service in foreground while paused so the notification
            // (and its controls) stays alive and responsive.
            androidStopForegroundOnPause: false,
            androidNotificationClickStartsActivity: true,
            // Rewind/fast-forward buttons seek ±10s via handler.rewind/fastForward.
            fastForwardInterval: Duration(seconds: 10),
            rewindInterval: Duration(seconds: 10),
          ),
        );
        if (attempt > 1) {
          debugPrint('AudioService init succeeded on attempt $attempt');
        }
        return handler;
      } catch (e) {
        debugPrint('AudioService init attempt $attempt failed: $e');
        if (attempt < 3) {
          // Brief pause before retry; the system may need a moment.
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return null;
  }

  final serviceHandler = await tryAudioServiceInit();
  if (serviceHandler != null) {
    audioHandler = serviceHandler;
    audioServiceOk = true;
  } else {
    debugPrint('AudioService init failed after retries, using fallback handler');
    audioHandler = PureTubeAudioHandler();
  }
  // Store for diagnostics UI.
  audioServiceReady = audioServiceOk;

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
