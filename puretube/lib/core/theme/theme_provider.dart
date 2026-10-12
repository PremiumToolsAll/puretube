import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Currently selected accent theme. Default: emerald (WILLOW).
final themeOptionProvider =
    StateProvider<AppThemeOption>((ref) => AppThemeOption.emerald);

/// Loads the saved theme choice (if any) at startup.
Future<void> loadSavedThemeOption(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    ref.read(themeOptionProvider.notifier).state =
        AppThemeOption.fromName(prefs.getString('theme_option'));
  } catch (_) {}
}

/// Persists the theme choice and updates the provider.
Future<void> saveThemeOption(
    WidgetRef ref, AppThemeOption option) async {
  ref.read(themeOptionProvider.notifier).state = option;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_option', option.name);
  } catch (_) {}
}
