import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The exact exception if AudioService.init failed (shown in
/// Settings → Diagnostics so the real cause is visible on-device).
String? audioServiceError;

/// Persists the most recent fatal error so the home screen can show
/// it on the NEXT launch — when the app dies instantly, this text is
/// the evidence (the user can screenshot it instead of guessing).
const lastFatalKey = 'last_fatal_error';

Future<void> saveLastFatal(Object error, StackTrace stack) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final text = '${DateTime.now().toIso8601String()}\n$error\n$stack';
    await prefs.setString(
        lastFatalKey,
        text.length > 4000 ? text.substring(0, 4000) : text);
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch-all: never leave the user staring at a white screen, and
  // never die silently — record fatal errors for the next launch.
  FlutterError.onError = (details) {
    saveLastFatal(details.exception, details.stack ?? StackTrace.current);
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    saveLastFatal(error, stack);
    return true;
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

  /// Attempts AudioService.init. MainActivity extends audio_service's
  /// AudioServiceActivity, so the activity shares the plugin's engine and
  /// init is expected to succeed on the first attempt.
  Future<PureTubeAudioHandler?> tryAudioServiceInit() async {
    for (var attempt = 1; attempt <= 2; attempt++) {
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
        audioServiceError = null;
        if (attempt > 1) {
          debugPrint('AudioService init succeeded on attempt $attempt');
        }
        return handler;
      } catch (e) {
        // Persist the exact failure so Settings → Diagnostics shows the
        // real cause instead of guessing about phone settings.
        audioServiceError = e.toString();
        debugPrint('AudioService init attempt $attempt failed: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 1));
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
