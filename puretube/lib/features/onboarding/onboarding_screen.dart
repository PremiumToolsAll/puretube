import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../home/presentation/screens/home_screen.dart';

/// 3-page onboarding (shown once on first launch).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Color get _accent => Theme.of(context).colorScheme.primary;
  final _pageCtrl = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardPage(
      icon: Icons.play_circle_filled,
      title: 'Welcome to PureTube',
      description:
          'A premium, ad-free YouTube client. No ads, no tracking — just your videos.',
    ),
    _OnboardPage(
      icon: Icons.picture_in_picture_alt_outlined,
      title: 'Background & Popup Play',
      description:
          'Keep listening while using other apps. Floating popup and picture-in-picture included.',
    ),
    _OnboardPage(
      icon: Icons.download_outlined,
      title: 'Downloads & Library',
      description:
          'Save videos offline in up to 4K. Organize with playlists, history, and subscriptions.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isOnboardingCompleted', true);
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _pages[i],
              ),
            ),
            SmoothPageIndicator(
              controller: _pageCtrl,
              count: _pages.length,
              effect: WormEffect(
                dotColor: Colors.white24,
                activeDotColor: _accent,
                dotHeight: 8,
                dotWidth: 8,
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_page < _pages.length - 1) {
                      _pageCtrl.nextPage(
                        duration:
                            const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      _finish();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _page < _pages.length - 1
                        ? 'Next'
                        : 'Get Started',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  const Color(0xFF00BCD4)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.4),
                  blurRadius: 32,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(icon,
                size: 64, color: Colors.white),
          ),
          const SizedBox(height: 40),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 16),
          Text(description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                  height: 1.5)),
        ],
      ),
    );
  }
}
