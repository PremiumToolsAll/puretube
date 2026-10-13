import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stream quality preferences ("Audio and video" in Settings).
///
/// PureTube's own take on quality settings — no YouTube clone UI.
///
/// Video values: 'auto', '2160', '1440', '1080', '720', '480', '360',
/// '240', '144'. 'auto' keeps the current behavior (best muxed stream).
/// No-fullscreen values: 'same' (mirror the fullscreen choice) plus the
/// video values. Audio values: 'auto', 'best', 'worst'.

/// All selectable video heights, highest first.
const kVideoQualityValues = [
  'auto',
  '2160',
  '1440',
  '1080',
  '720',
  '480',
  '360',
  '240',
  '144',
];

/// No-fullscreen choices: mirror fullscreen, or pin a height.
const kNoFullscreenQualityValues = [
  'same',
  '2160',
  '1440',
  '1080',
  '720',
  '480',
  '360',
  '240',
  '144',
];

/// Audio choices.
const kAudioQualityValues = ['auto', 'best', 'worst'];

const _kWifiVideo = 'quality_wifi_video';
const _kWifiNoFullscreen = 'quality_wifi_nofs';
const _kWifiAudio = 'quality_wifi_audio';
const _kMobileVideo = 'quality_mob_video';
const _kMobileNoFullscreen = 'quality_mob_nofs';
const _kMobileAudio = 'quality_mob_audio';

final wifiVideoQualityProvider = StateProvider<String>((ref) => 'auto');
final wifiNoFullscreenQualityProvider =
    StateProvider<String>((ref) => 'same');
final wifiAudioQualityProvider = StateProvider<String>((ref) => 'auto');
final mobileVideoQualityProvider = StateProvider<String>((ref) => 'auto');
final mobileNoFullscreenQualityProvider =
    StateProvider<String>((ref) => 'same');
final mobileAudioQualityProvider = StateProvider<String>((ref) => 'auto');

/// Parses a stored video-quality value to a height in pixels.
/// Returns null for 'auto' (and 'same' — callers resolve that first).
int? qualityValueToHeight(String value) {
  if (value == 'auto' || value == 'same') return null;
  return int.tryParse(value);
}

/// Short display label, e.g. 'auto' -> 'Auto', '1080' -> '1080p',
/// 'same' -> 'Same'.
String qualityValueLabel(String value) {
  switch (value) {
    case 'auto':
      return 'Auto';
    case 'same':
      return 'Same';
    case 'best':
      return 'Best';
    case 'worst':
      return 'Worst';
    default:
      return '${value}p';
  }
}

/// Loads all six saved quality preferences at startup.
Future<void> loadSavedQualitySettings(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final pairs = <StateProvider<String>, String>{
      wifiVideoQualityProvider: _kWifiVideo,
      wifiNoFullscreenQualityProvider: _kWifiNoFullscreen,
      wifiAudioQualityProvider: _kWifiAudio,
      mobileVideoQualityProvider: _kMobileVideo,
      mobileNoFullscreenQualityProvider: _kMobileNoFullscreen,
      mobileAudioQualityProvider: _kMobileAudio,
    };
    final valid = <String, List<String>>{
      _kWifiVideo: kVideoQualityValues,
      _kMobileVideo: kVideoQualityValues,
      _kWifiNoFullscreen: kNoFullscreenQualityValues,
      _kMobileNoFullscreen: kNoFullscreenQualityValues,
      _kWifiAudio: kAudioQualityValues,
      _kMobileAudio: kAudioQualityValues,
    };
    pairs.forEach((provider, key) {
      final v = prefs.getString(key);
      if (v != null && valid[key]!.contains(v)) {
        ref.read(provider.notifier).state = v;
      }
    });
  } catch (_) {}
}

/// Persists one quality preference.
Future<void> saveQualitySetting(String key, String value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  } catch (_) {}
}

/// SharedPreferences keys (exposed for the settings sheet).
String get kPrefWifiVideo => _kWifiVideo;
String get kPrefWifiNoFullscreen => _kWifiNoFullscreen;
String get kPrefWifiAudio => _kWifiAudio;
String get kPrefMobileVideo => _kMobileVideo;
String get kPrefMobileNoFullscreen => _kMobileNoFullscreen;
String get kPrefMobileAudio => _kMobileAudio;
