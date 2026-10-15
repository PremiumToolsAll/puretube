import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home-level Video / Audio mode switch.
///
/// `false` = classic video home feed, `true` = music-style audio home.
/// Persisted so the app reopens in the last used mode.
class HomeModeController extends Notifier<bool> {
  static const _key = 'homeAudioMode';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_key) ?? false;
      if (state != v) state = v;
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, state);
    } catch (_) {}
  }
}

final homeModeProvider =
    NotifierProvider<HomeModeController, bool>(HomeModeController.new);
