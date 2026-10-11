import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Settings',
          style: TextStyle(
              color: Color(0xFF6200EA), fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        children: [
          _section('Playback'),
          _qualityTile(context, settings, notifier),
          SwitchListTile(
            title: const Text('Background playback',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Keep playing when app is in background',
                style: TextStyle(color: Colors.grey)),
            value: settings.backgroundPlay,
            activeColor: const Color(0xFF6200EA),
            onChanged: notifier.setBackgroundPlay,
          ),
          SwitchListTile(
            title: const Text('Autoplay next',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Automatically play the next video',
                style: TextStyle(color: Colors.grey)),
            value: settings.autoplay,
            activeColor: const Color(0xFF6200EA),
            onChanged: notifier.setAutoplay,
          ),
          SwitchListTile(
            title: const Text('SponsorBlock',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Skip sponsored segments automatically',
                style: TextStyle(color: Colors.grey)),
            value: settings.sponsorBlock,
            activeColor: const Color(0xFF6200EA),
            onChanged: notifier.setSponsorBlock,
          ),
          _section('Storage'),
          ListTile(
            leading:
                const Icon(Icons.history, color: Colors.white70),
            title: const Text('Clear watch history',
                style: TextStyle(color: Colors.white)),
            onTap: () async {
              await notifier.clearHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Watch history cleared')),
                );
              }
            },
          ),
          _section('About'),
          const ListTile(
            leading: Icon(Icons.info_outline, color: Colors.white70),
            title: Text('PureTube',
                style: TextStyle(color: Colors.white)),
            subtitle: Text('v1.0.0 — ad-free YouTube client',
                style: TextStyle(color: Colors.grey)),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Streams are fetched directly from YouTube. '
              'If videos fail to load, YouTube may be rate-limiting '
              'this network — wait a while or switch networks.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
              color: Color(0xFF6200EA),
              fontWeight: FontWeight.bold,
              fontSize: 12),
        ),
      );

  Widget _qualityTile(BuildContext context, AppSettings settings,
      SettingsNotifier notifier) {
    return ListTile(
      leading:
          const Icon(Icons.high_quality, color: Colors.white70),
      title: const Text('Default video quality',
          style: TextStyle(color: Colors.white)),
      subtitle: Text(settings.defaultQuality,
          style: const TextStyle(color: Colors.grey)),
      onTap: () => showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Video quality',
              style: TextStyle(color: Colors.white)),
          children: AppSettings.qualities
              .map((q) => SimpleDialogOption(
                    onPressed: () {
                      notifier.setQuality(q);
                      Navigator.pop(ctx);
                    },
                    child: Text(q,
                        style: TextStyle(
                            color: q == settings.defaultQuality
                                ? const Color(0xFF6200EA)
                                : Colors.white)),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
