import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/services/audio_player_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/permission_utils.dart';
import 'features/downloads/data/download_service.dart';
import 'features/home/presentation/providers/search_provider.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/player/presentation/player_screen.dart';

final _navKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit native libs.
  MediaKit.ensureInitialized();

  // Foreground audio service (MediaSession).
  final audioHandler = await initAudioService();

  // Background download engine (resumes interrupted queue).
  await DownloadService.instance.init();

  // Notification permission (Android 13+).
  await PermissionUtils.ensureNotifications();

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider
            .overrideWithValue(audioHandler),
      ],
      child: const PureTubeApp(),
    ),
  );

  // Deep links (after first frame so Navigator exists).
  WidgetsBinding.instance
      .addPostFrameCallback((_) {
    DeepLinkService.instance.init(
      onVideo: (videoId) {
        final ctx = _navKey.currentContext;
        if (ctx != null) {
          Navigator.of(ctx).push(
            MaterialPageRoute(
                builder: (_) => PlayerScreen(
                    videoId: videoId)),
          );
        }
      },
    );
  });
}

class PureTubeApp extends StatelessWidget {
  const PureTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: _navKey,
      home: const HomeScreen(),
    );
  }
}
