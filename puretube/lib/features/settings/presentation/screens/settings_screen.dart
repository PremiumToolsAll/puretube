import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../library/presentation/providers/library_providers.dart';

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

/// Basic settings: language, clear history, clear cache, about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _accent = Color(0xFF6200EA);

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

  void _showLanguageDialog(
      BuildContext context, WidgetRef ref, Locale? current) {
    Locale? picked = current;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
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

  Future<void> _confirmClearHistory(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
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

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('PureTube',
            style: TextStyle(
                color: _accent, fontWeight: FontWeight.bold)),
        content: const Text(
          'PureTube v1.0.0\n\nA lightweight YouTube client.\nStreams load directly from YouTube — '
          'no middleman servers.',
          style: TextStyle(color: Colors.grey),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Settings',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: [
          ListTile(
            leading:
                const Icon(Icons.language, color: Colors.white70),
            title: const Text('Language',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(_localeLabel(locale),
                style: const TextStyle(color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right,
                color: Colors.grey),
            onTap: () =>
                _showLanguageDialog(context, ref, locale),
          ),
          const Divider(color: Color(0xFF1A1A1A)),
          ListTile(
            leading:
                const Icon(Icons.history, color: Colors.white70),
            title: const Text('Clear watch history',
                style: TextStyle(color: Colors.white)),
            onTap: () => _confirmClearHistory(context, ref),
          ),
          FutureBuilder<String>(
            future: _cacheSize(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.cleaning_services_outlined,
                  color: Colors.white70),
              title: const Text('Clear cache',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text('Cached images & temp files'
                  '${snap.hasData ? ' (${snap.data})' : ''}',
                  style: const TextStyle(color: Colors.grey)),
              onTap: () => _clearCache(context),
            ),
          ),
          const Divider(color: Color(0xFF1A1A1A)),
          ListTile(
            leading:
                const Icon(Icons.info_outline, color: Colors.white70),
            title: const Text('About',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('PureTube v1.0.0',
                style: TextStyle(color: Colors.grey)),
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }
}
