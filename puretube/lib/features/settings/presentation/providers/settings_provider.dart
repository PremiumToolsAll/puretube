import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Persistent app settings stored in Hive.
class AppSettings {
  static const _boxName = 'app_settings';

  static const keyQuality = 'default_quality';
  static const keyBackgroundPlay = 'background_play';
  static const keyAutoplay = 'autoplay';
  static const keySponsorBlock = 'sponsorblock';

  static const qualities = ['Auto', '720p', '480p', '360p'];

  final String defaultQuality;
  final bool backgroundPlay;
  final bool autoplay;
  final bool sponsorBlock;

  const AppSettings({
    this.defaultQuality = 'Auto',
    this.backgroundPlay = true,
    this.autoplay = false,
    this.sponsorBlock = true,
  });

  AppSettings copyWith({
    String? defaultQuality,
    bool? backgroundPlay,
    bool? autoplay,
    bool? sponsorBlock,
  }) =>
      AppSettings(
        defaultQuality: defaultQuality ?? this.defaultQuality,
        backgroundPlay: backgroundPlay ?? this.backgroundPlay,
        autoplay: autoplay ?? this.autoplay,
        sponsorBlock: sponsorBlock ?? this.sponsorBlock,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Box? _box;

  Future<void> _load() async {
    try {
      _box = await Hive.openBox(AppSettings._boxName);
      state = AppSettings(
        defaultQuality:
            _box!.get(AppSettings.keyQuality, defaultValue: 'Auto') as String,
        backgroundPlay: _box!.get(AppSettings.keyBackgroundPlay,
            defaultValue: true) as bool,
        autoplay:
            _box!.get(AppSettings.keyAutoplay, defaultValue: false) as bool,
        sponsorBlock: _box!.get(AppSettings.keySponsorBlock,
            defaultValue: true) as bool,
      );
    } catch (_) {
      // Defaults stand.
    }
  }

  Future<void> _save(String key, Object value) async {
    try {
      _box ??= await Hive.openBox(AppSettings._boxName);
      await _box!.put(key, value);
    } catch (_) {}
  }

  void setQuality(String q) {
    state = state.copyWith(defaultQuality: q);
    _save(AppSettings.keyQuality, q);
  }

  void setBackgroundPlay(bool v) {
    state = state.copyWith(backgroundPlay: v);
    _save(AppSettings.keyBackgroundPlay, v);
  }

  void setAutoplay(bool v) {
    state = state.copyWith(autoplay: v);
    _save(AppSettings.keyAutoplay, v);
  }

  void setSponsorBlock(bool v) {
    state = state.copyWith(sponsorBlock: v);
    _save(AppSettings.keySponsorBlock, v);
  }

  Future<void> clearHistory() async {
    try {
      final box = await Hive.openBox<Map>('history');
      await box.clear();
    } catch (_) {}
  }

  Future<void> clearCache() async {
    // Placeholder for future cache clearing.
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);
