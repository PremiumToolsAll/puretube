import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kids mode + parental controls.
class KidsModeService {
  KidsModeService._();
  static final KidsModeService instance =
      KidsModeService._();

  final _notifier =
      ValueNotifier<bool>(false);
  ValueNotifier<bool> get notifier =>
      _notifier;

  Future<void> init() async {
    try {
      final p = await SharedPreferences
          .getInstance();
      _notifier.value =
          p.getBool('kids_mode') ?? false;
    } catch (_) {}
  }

  bool get enabled => _notifier.value;

  Future<void> setEnabled(bool v) async {
    _notifier.value = v;
    try {
      final p = await SharedPreferences
          .getInstance();
      await p.setBool('kids_mode', v);
    } catch (_) {}
  }

  // ── Usage timer ───────────────────────────────────────────

  /// Daily limit in minutes (0 = no limit).
  Future<int> get dailyLimit async {
    try {
      final p = await SharedPreferences
          .getInstance();
      return p.getInt('kids_daily_limit') ??
          0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setDailyLimit(int mins) async {
    try {
      final p = await SharedPreferences
          .getInstance();
      await p.setInt(
          'kids_daily_limit', mins);
    } catch (_) {}
  }

  /// Minutes used today.
  Future<int> get usedToday async {
    try {
      final p = await SharedPreferences
          .getInstance();
      final day = DateTime.now()
          .toIso8601String()
          .substring(0, 10);
      final savedDay =
          p.getString('kids_usage_day');
      if (savedDay != day) {
        await p.setString(
            'kids_usage_day', day);
        await p.setInt(
            'kids_usage_mins', 0);
        return 0;
      }
      return p.getInt('kids_usage_mins') ??
          0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> addUsage(int mins) async {
    try {
      final p = await SharedPreferences
          .getInstance();
      final cur = await usedToday;
      await p.setInt(
          'kids_usage_mins', cur + mins);
    } catch (_) {}
  }

  Future<bool> get isLockedOut async {
    final limit = await dailyLimit;
    if (limit <= 0) return false;
    return await usedToday >= limit;
  }
}

/// Full-screen lock when kids daily limit is reached.
class KidsLockScreen extends StatelessWidget {
  const KidsLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFFFF3E0),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(
                32),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Text('⏰',
                    style: TextStyle(
                        fontSize: 80)),
                const SizedBox(
                    height: 24),
                const Text(
                  'Time\'s up for today!',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight:
                          FontWeight.bold,
                      color:
                          Color(0xFF5D4037)),
                ),
                const SizedBox(
                    height: 12),
                const Text(
                  'You\'ve reached your daily watch limit. Come back tomorrow!',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      color:
                          Color(0xFF8D6E63)),
                ),
                const SizedBox(
                    height: 24),
                ElevatedButton(
                  onPressed: () {},
                  style:
                      ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(
                                  0xFFFF9800),
                          padding:
                              const EdgeInsets
                                  .symmetric(
                                  horizontal:
                                      32,
                                  vertical:
                                      14)),
                  child: const Text(
                      'Ask a parent',
                      style: TextStyle(
                          color: Colors
                              .white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
