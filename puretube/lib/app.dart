import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/player/presentation/widgets/popup_player.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

class PureTubeApp extends ConsumerStatefulWidget {
  const PureTubeApp({super.key});

  @override
  ConsumerState<PureTubeApp> createState() => _PureTubeAppState();
}

class _PureTubeAppState extends ConsumerState<PureTubeApp> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    loadSavedLocale(ref);
  }

  Future<void> _checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('isOnboardingCompleted') ?? false;
      if (mounted) setState(() => _showOnboarding = !done);
    } catch (_) {
      if (mounted) setState(() => _showOnboarding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: ref.watch(localeProvider),
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Floating popup player floats above every screen.
      builder: (context, child) => Stack(
        children: [
          child!,
          const PopupPlayerHost(),
        ],
      ),
      home: _showOnboarding == null
          ? const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF6200EA))),
            )
          : _showOnboarding!
              ? const OnboardingScreen()
              : const HomeScreen(),
    );
  }
}
