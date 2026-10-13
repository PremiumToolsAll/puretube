import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../library/presentation/providers/library_providers.dart';
import '../../../player/presentation/providers/player_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../main.dart';

/// null = follow the system language.
final localeProvider = StateProvider<Locale?>((ref) => null);

/// Loads the saved language choice (if any) at startup.
Future<void> loadSavedLocale(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('app_locale');
    if (code != null && code.isNotEmpty) {
      ref.read(localeProvider.notifier).state = Locale(code);
    }
  } catch (_) {}
}

Future<void> _saveLocale(String? code) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove('app_locale');
    } else {
      await prefs.setString('app_locale', code);
    }
  } catch (_) {}
}

/// Double-tap seek interval in seconds (YouTube parity: 5/10/15/20/30/60).
final doubleTapSecondsProvider = StateProvider<int>((ref) => 10);

/// Loads the saved double-tap seek interval at startup.
Future<void> loadSavedDoubleTapSeconds(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('double_tap_seconds');
    if (v != null && [5, 10, 15, 20, 30, 60].contains(v)) {
      ref.read(doubleTapSecondsProvider.notifier).state = v;
    }
  } catch (_) {}
}

Future<void> saveDoubleTapSeconds(int seconds) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('double_tap_seconds', seconds);
  } catch (_) {}
}

/// Synchronous read of the double-tap interval (for gesture handlers).
/// Falls back to 10s if prefs are unavailable.
Future<int> getDoubleTapSeconds() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('double_tap_seconds') ?? 10;
  } catch (_) {
    return 10;
  }
}

/// Skip sponsored segments (SponsorBlock). Default ON.
final skipSponsorsProvider = StateProvider<bool>((ref) => true);

/// Loads the saved sponsor-skip preference at startup.
Future<void> loadSavedSkipSponsors(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool('skip_sponsors');
    if (v != null) {
      ref.read(skipSponsorsProvider.notifier).state = v;
    }
  } catch (_) {}
}

Future<void> saveSkipSponsors(bool value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('skip_sponsors', value);
  } catch (_) {}
}

/// Basic settings: language, clear history, clear cache, about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _accent = Color(0xFF10B981);
  static const _accentLight = Color(0xFF34D399);
  static const _bg = Color(0xFF0C110E);
  static const _card = Color(0xFF16211C);

  /// Real app version from pubspec (via package_info_plus), fetched once.
  static final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();

  String _versionText(PackageInfo info) =>
      'v${info.version} (${info.buildNumber})';

  String _localeLabel(Locale? locale) {
    if (locale == null) return 'System default';
    switch (locale.languageCode) {
      case 'bn':
        return 'বাংলা';
      case 'en':
      default:
        return 'English';
    }
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref,
      AppThemeOption current) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16211C),
        title: const Text('Theme',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: AppThemeOption.values.length,
            itemBuilder: (ctx, i) {
              final option = AppThemeOption.values[i];
              return RadioListTile<AppThemeOption>(
                value: option,
                groupValue: current,
                title: Text(option.label,
                    style:
                        const TextStyle(color: Colors.white)),
                secondary: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: option.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white24),
                  ),
                ),
                activeColor: _accent,
                onChanged: (v) async {
                  if (v != null) {
                    await saveThemeOption(ref, v);
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: _accentLight)),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(
      BuildContext context, WidgetRef ref, Locale? current) {
    Locale? picked = current;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF16211C),
          title: const Text('Language',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in <MapEntry<String?, String>>[
                const MapEntry(null, 'System default'),
                const MapEntry('en', 'English'),
                const MapEntry('bn', 'বাংলা'),
              ])
                RadioListTile<String?>(
                  value: entry.key,
                  groupValue: picked?.languageCode,
                  title: Text(entry.value,
                      style:
                          const TextStyle(color: Colors.white)),
                  activeColor: _accent,
                  onChanged: (v) =>
                      setState(() => picked = v == null ? null : Locale(v)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                ref.read(localeProvider.notifier).state = picked;
                await _saveLocale(picked?.languageCode);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Apply',
                  style: TextStyle(color: _accent)),
            ),
          ],
        ),
      ),
    );
  }

  /// Double-tap seek interval picker (YouTube parity: 5/10/15/20/30/60s).
  void _showDoubleTapDialog(
      BuildContext context, WidgetRef ref, int current) {
    int picked = current;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF16211C),
          title: const Text('Double-tap to seek',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in [5, 10, 15, 20, 30, 60])
                RadioListTile<int>(
                  value: s,
                  groupValue: picked,
                  title: Text('$s seconds',
                      style:
                          const TextStyle(color: Colors.white)),
                  activeColor: _accent,
                  onChanged: (v) =>
                      setState(() => picked = v ?? 10),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                ref.read(doubleTapSecondsProvider.notifier).state =
                    picked;
                await saveDoubleTapSeconds(picked);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Apply',
                  style: TextStyle(color: _accent)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearHistory(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16211C),
        title: const Text('Clear watch history?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This removes all watched videos from history.',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await ref
          .read(historyControllerProvider.notifier)
          .clear();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Watch history cleared')),
        );
      }
    }
  }

  Future<void> _clearCache(BuildContext context) async {
    try {
      await DefaultCacheManager().emptyCache();
      final tmp = await getTemporaryDirectory();
      if (await tmp.exists()) {
        await for (final e in tmp.list()) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
      // Also drop the internal image cache.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
  }

  Future<String> _cacheSize() async {
    try {
      int bytes = 0;
      final tmp = await getTemporaryDirectory();
      if (await tmp.exists()) {
        await for (final e in tmp.list(recursive: true)) {
          if (e is File) {
            try {
              bytes += await e.length();
            } catch (_) {}
          }
        }
      }
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(0)} KB';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '—';
    }
  }

  void _showAbout(BuildContext context) async {
    PackageInfo? info;
    try {
      info = await _packageInfoFuture;
    } catch (_) {}
    if (!context.mounted) return;
    final versionLine =
        info != null ? 'PureTube ${_versionText(info)}' : 'PureTube';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('PureTube',
            style: TextStyle(
                color: _accent, fontWeight: FontWeight.bold)),
        content: Text(
          '$versionLine\n\nA lightweight YouTube client.\nStreams load directly from YouTube — '
          'no middleman servers.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  /// Small uppercase section header for a premium grouped look.
  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: _accentLight,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.4,
          ),
        ),
      );

  /// WILLOW card used for grouped rows.
  Widget _settingsCard({required List<Widget> children}) {
    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      separated.add(children[i]);
      if (i < children.length - 1) {
        separated.add(const Divider(
            color: Color(0xFF1B2A22), height: 1, indent: 56));
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _accent.withValues(alpha: 0.18)),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min, children: separated),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Settings',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Premium app header card with real version.
          FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (context, snap) {
              final versionText = snap.hasData
                  ? _versionText(snap.data!)
                  : '…';
              return Container(
                margin:
                    const EdgeInsets.fromLTRB(12, 12, 12, 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: _accent.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color:
                          _accent.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_accent, _accentLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius:
                            BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(
                                alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text('PureTube',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(versionText,
                            style: const TextStyle(
                                color: _accentLight,
                                fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          _sectionHeader('Appearance'),
          _settingsCard(children: [
            Consumer(
              builder: (context, ref, _) {
                final current =
                    ref.watch(themeOptionProvider);
                return ListTile(
                  leading: const Icon(Icons.palette_outlined,
                      color: _accentLight),
                  title: const Text('Theme',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(current.label,
                      style:
                          const TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.grey),
                  onTap: () =>
                      _showThemeDialog(context, ref, current),
                );
              },
            ),
          ]),
          _sectionHeader('General'),
          _settingsCard(children: [
            ListTile(
              leading: const Icon(Icons.language,
                  color: _accentLight),
              title: const Text('Language',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(_localeLabel(locale),
                  style:
                      const TextStyle(color: Colors.grey)),
              trailing: const Icon(Icons.chevron_right,
                  color: Colors.grey),
              onTap: () =>
                  _showLanguageDialog(context, ref, locale),
            ),
            Consumer(
              builder: (context, ref, _) {
                final secs =
                    ref.watch(doubleTapSecondsProvider);
                return ListTile(
                  leading: const Icon(
                      Icons.touch_app_outlined,
                      color: _accentLight),
                  title: const Text('Double-tap to seek',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text('$secs seconds',
                      style:
                          const TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.grey),
                  onTap: () =>
                      _showDoubleTapDialog(context, ref, secs),
                );
              },
            ),
            Consumer(
              builder: (context, ref, _) {
                final skip = ref.watch(skipSponsorsProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.block_outlined,
                      color: _accentLight),
                  title: const Text('Skip sponsors',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Auto-skip sponsored segments',
                      style: TextStyle(color: Colors.grey)),
                  value: skip,
                  activeThumbColor: _accent,
                  activeTrackColor:
                      _accent.withValues(alpha: 0.35),
                  onChanged: (v) async {
                    ref
                        .read(skipSponsorsProvider.notifier)
                        .state = v;
                    await saveSkipSponsors(v);
                    // Sync with the player controller if it's alive.
                    try {
                      ref
                          .read(playerControllerProvider
                              .notifier)
                          .toggleSkipSponsors(v);
                    } catch (_) {}
                  },
                );
              },
            ),
          ]),
          _sectionHeader('Library'),
          _settingsCard(children: [
            ListTile(
              leading: const Icon(Icons.history,
                  color: _accentLight),
              title: const Text('Clear watch history',
                  style: TextStyle(color: Colors.white)),
              onTap: () =>
                  _confirmClearHistory(context, ref),
            ),
            FutureBuilder<String>(
              future: _cacheSize(),
              builder: (context, snap) => ListTile(
                leading: const Icon(
                    Icons.cleaning_services_outlined,
                    color: _accentLight),
                title: const Text('Clear cache',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text('Cached images & temp files'
                    '${snap.hasData ? ' (${snap.data})' : ''}',
                    style:
                        const TextStyle(color: Colors.grey)),
                onTap: () => _clearCache(context),
              ),
            ),
          ]),
          _sectionHeader('About'),
          _settingsCard(children: [
            FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snap) => ListTile(
                leading: const Icon(Icons.info_outline,
                    color: _accentLight),
                title: const Text('About',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                    snap.hasData
                        ? 'PureTube ${_versionText(snap.data!)}'
                        : 'PureTube',
                    style:
                        const TextStyle(color: Colors.grey)),
                onTap: () => _showAbout(context),
              ),
            ),
          ]),
          _sectionHeader('Diagnostics'),
          _settingsCard(children: [
            // Background playback diagnostic.
            ListTile(
              leading: Icon(
                  audioServiceReady
                      ? Icons.check_circle
                      : Icons.error,
                  color: audioServiceReady
                      ? _accent
                      : Colors.redAccent),
              title: const Text('Background service',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                  audioServiceReady
                      ? 'Running — background playback and notification controls should work.'
                      : 'NOT running — background audio may stop when you leave the app. '
                          'Fix: enable Notifications, set Battery to "No restrictions", '
                          'allow Autostart for PureTube, then restart the app.',
                  style:
                      const TextStyle(color: Colors.grey)),
            ),
          ]),
        ],
      ),
    );
  }
}
