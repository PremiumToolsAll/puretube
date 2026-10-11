import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';

class PureTubeApp extends StatefulWidget {
  const PureTubeApp({super.key});

  @override
  State<PureTubeApp> createState() => _PureTubeAppState();
}

class _PureTubeAppState extends State<PureTubeApp> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
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
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
