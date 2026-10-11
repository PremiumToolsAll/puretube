import 'package:shared_preferences/shared_preferences.dart';

/// App settings backed by SharedPreferences.
class SettingsService {
  SettingsService._();
  static final SettingsService instance =
      SettingsService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Appearance ────────────────────────────────────────────
  Future<String> get themeMode async =>
      (await prefs).getString('theme_mode') ??
      'amoled';
  Future<void> setThemeMode(String v) async =>
      (await prefs).setString('theme_mode', v);

  Future<bool> get dynamicColor async =>
      (await prefs).getBool('dynamic_color') ?? false;
  Future<void> setDynamicColor(bool v) async =>
      (await prefs).setBool('dynamic_color', v);

  Future<int> get gridColumns async =>
      (await prefs).getInt('grid_columns') ?? 1;
  Future<void> setGridColumns(int v) async =>
      (await prefs).setInt('grid_columns', v);

  // ── Player ────────────────────────────────────────────────
  Future<int> get defaultQuality async =>
      (await prefs).getInt('default_quality') ??
      720;
  Future<void> setDefaultQuality(int v) async =>
      (await prefs).setInt('default_quality', v);

  Future<double> get defaultSpeed async =>
      (await prefs).getDouble('default_speed') ??
      1.0;
  Future<void> setDefaultSpeed(double v) async =>
      (await prefs).setDouble('default_speed', v);

  Future<bool> get autoplayNext async =>
      (await prefs).getBool('autoplay_next') ??
      true;
  Future<void> setAutoplayNext(bool v) async =>
      (await prefs).setBool('autoplay_next', v);

  Future<bool> get rememberPosition async =>
      (await prefs)
          .getBool('remember_position') ??
      true;
  Future<void> setRememberPosition(
          bool v) async =>
      (await prefs)
          .setBool('remember_position', v);

  Future<int> get doubleTapSeconds async =>
      (await prefs)
          .getInt('double_tap_seconds') ??
      10;
  Future<void> setDoubleTapSeconds(
          int v) async =>
      (await prefs)
          .setInt('double_tap_seconds', v);

  // ── Downloads ─────────────────────────────────────────────
  Future<bool> get wifiOnly async =>
      (await prefs).getBool('wifi_only') ?? false;
  Future<void> setWifiOnly(bool v) async =>
      (await prefs).setBool('wifi_only', v);

  Future<int> get maxParallel async =>
      (await prefs).getInt('max_parallel') ?? 3;
  Future<void> setMaxParallel(int v) async =>
      (await prefs).setInt('max_parallel', v);

  // ── SponsorBlock ──────────────────────────────────────────
  Future<bool> get sponsorBlockEnabled async =>
      (await prefs)
          .getBool('sb_enabled') ??
      true;
  Future<void> setSponsorBlockEnabled(
          bool v) async =>
      (await prefs).setBool('sb_enabled', v);

  Future<List<String>> get sbCategories async =>
      (await prefs)
          .getStringList('sb_categories') ??
      [
        'sponsor',
        'intro',
        'outro',
        'selfpromo',
        'interaction',
        'preview'
      ];
  Future<void> setSbCategories(
          List<String> v) async =>
      (await prefs)
          .setStringList('sb_categories', v);

  Future<bool> get sbAutoSkip async =>
      (await prefs).getBool('sb_autoskip') ??
      true;
  Future<void> setSbAutoSkip(bool v) async =>
      (await prefs).setBool('sb_autoskip', v);

  // ── Background ────────────────────────────────────────────
  Future<bool> get backgroundAudio async =>
      (await prefs)
          .getBool('background_audio') ??
      true;
  Future<void> setBackgroundAudio(
          bool v) async =>
      (await prefs)
          .setBool('background_audio', v);

  Future<bool> get pipEnabled async =>
      (await prefs).getBool('pip_enabled') ??
      true;
  Future<void> setPipEnabled(bool v) async =>
      (await prefs).setBool('pip_enabled', v);

  Future<bool> get popupEnabled async =>
      (await prefs).getBool('popup_enabled') ??
      true;
  Future<void> setPopupEnabled(bool v) async =>
      (await prefs).setBool('popup_enabled', v);

  // ── Privacy ───────────────────────────────────────────────
  Future<bool> get incognito async =>
      (await prefs).getBool('incognito') ?? false;
  Future<void> setIncognito(bool v) async =>
      (await prefs).setBool('incognito', v);

  Future<int> get historyRetentionDays async =>
      (await prefs)
          .getInt('history_retention') ??
      90;
  Future<void> setHistoryRetentionDays(
          int v) async =>
      (await prefs)
          .setInt('history_retention', v);
}
