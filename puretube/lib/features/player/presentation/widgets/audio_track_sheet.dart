import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_controller.dart';

/// Dubbed-audio language picker bottom sheet (YouTube "Audio Track").
class AudioTrackSheet extends ConsumerWidget {
  const AudioTrackSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => const AudioTrackSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(playerControllerProvider);
    final notifier =
        ref.read(playerControllerProvider.notifier);
    final accent = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Audio Track',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          if (ui.audioLanguages.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No alternate audio tracks',
                  style: TextStyle(color: Colors.grey)),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: ui.audioLanguages.length,
              itemBuilder: (_, i) {
                final t = ui.audioLanguages[i];
                final active =
                    ui.activeAudioLanguage?.id == t.id;
                return ListTile(
                  title: Text(t.displayName),
                  subtitle: t.isDefault
                      ? const Text('Original',
                          style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12))
                      : null,
                  trailing: active
                      ? Icon(Icons.check, color: accent)
                      : null,
                  onTap: () {
                    notifier.setAudioLanguage(t);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
