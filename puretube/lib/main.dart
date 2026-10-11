import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/audio_player_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/permission_utils.dart';
import 'features/downloads/data/download_service.dart';
import 'features/home/presentation/providers/search_provider.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/player/presentation/player_screen.dart';

final _navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Crash reporting (Sentry — configure DSN in production).
      await SentryFlutter.init(
        (options) {
          // TODO: Set your Sentry DSN for production.
          // options.dsn = 'https://xxx@sentry.io/xxx';
          options.debug = kDebugMode;
          options.tracesSampleRate = 0.2;
        },
      );

      FlutterError.onError =
          (details) {
        Sentry.captureException(
          details.exception,
          stackTrace: details.stack,
        );
        FlutterError.presentError(details);
      };

      // media_kit native libs.
      MediaKit.ensureInitialized();

      // Foreground audio service (MediaSession).
      final audioHandler =
          await initAudioService();

      // Background download engine.
      await DownloadService.instance.init();

      // Notification permission (Android 13+).
      await PermissionUtils
          .ensureNotifications();

      // Onboarding check.
      bool showOnboarding = false;
      try {
        final prefs = await SharedPreferences
            .getInstance();
        showOnboarding = !(prefs.getBool(
                'isOnboardingCompleted') ??
            false);
      } catch (_) {}

      runApp(
        ProviderScope(
          overrides: [
            audioHandlerProvider
                .overrideWithValue(
                    audioHandler),
          ],
          child: PureTubeApp(
              showOnboarding:
                  showOnboarding),
        ),
      );

      // Deep links.
      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        DeepLinkService.instance.init(
          onVideo: (videoId) {
            final ctx =
                _navKey.currentContext;
            if (ctx != null) {
              Navigator.of(ctx).push(
                MaterialPageRoute(
                    builder: (_) =>
                        PlayerScreen(
                            videoId:
                                videoId)),
              );
            }
          },
        );
      });
    },
    (error, stack) {
      // Catch-all for unhandled async errors.
      Sentry.captureException(error,
          stackTrace: stack);
      _showCrashDialog(error);
    },
  );
}

/// User-friendly crash dialog (instead of silent crash).
void _showCrashDialog(Object error) {
  final ctx = _navKey.currentContext;
  if (ctx == null) return;
  showDialog(
    context: ctx,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor:
          const Color(0xFF121212),
      title: const Text(
          'Something went wrong'),
      content: Text(
        'PureTube encountered an unexpected error. The app will try to recover.\n\n${error.toString().split('\n').first}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx),
          child: const Text('OK',
              style: TextStyle(
                  color:
                      Color(0xFF6200EA))),
        ),
      ],
    ),
  );
}

class PureTubeApp extends StatelessWidget {
  final bool showOnboarding;

  const PureTubeApp({
    super.key,
    this.showOnboarding = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: _navKey,
      // Localization.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('bn'),
      ],
      home: showOnboarding
          ? const OnboardingScreen()
          : const HomeScreen(),
      builder: (context, child) {
        // Global error boundary for widget errors.
        ErrorWidget.builder =
            (details) => Scaffold(
          backgroundColor:
              AppTheme.background,
          body: Center(
            child: Padding(
              padding:
                  const EdgeInsets.all(24),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.white30),
                  const SizedBox(
                      height: 16),
                  const Text(
                    'Something went wrong',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please restart the app.',
                    style: TextStyle(
                        color: Colors.white
                            .withOpacity(0.6)),
                  ),
                ],
              ),
            ),
          ),
        );
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
