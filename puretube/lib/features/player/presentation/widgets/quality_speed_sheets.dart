import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../domain/entities/models.dart';
import '../providers/player_controller.dart';

/// Quality selector bottom sheet.
class QualitySheet extends StatelessWidget {
  final PlayerController notifier;
  final PlayerUiState ui;

  const QualitySheet({
    super.key,
    required this.notifier,
    required this.ui,
  });

  static Future<void> show(
      BuildContext context,
      PlayerController notifier,
      PlayerUiState ui) {
    if (ui.streams == null) return Future.value();
    return showModalBottomSheet(
      context: context,
      builder: (_) => QualitySheet(
          notifier: notifier, ui: ui),
    );
  }

  @override
  Widget build(BuildContext context) {
    final streams = ui.streams!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Quality',
                style: AppTheme.subtitle),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: const Text(
                      'Auto (recommended)'),
                  trailing: ui.currentQualityHeight ==
                          streams.muxedHeight &&
                      !ui.audioOnly
                      ? const Icon(Icons.check,
                          color: AppTheme.primary)
                      : null,
                  onTap: () {
                    try {
                      final auto = streams
                          .qualities
                          .firstWhere(
                        (q) =>
                            q.height ==
                            streams.muxedHeight,
                        orElse: () => streams
                            .qualities.first,
                      );
                      if (ui.audioOnly) {
                        notifier
                            .toggleAudioOnly();
                      }
                      notifier
                          .setQuality(auto);
                    } catch (_) {}
                    Navigator.pop(context);
                  },
                ),
                for (final q
                    in streams.qualities)
                  ListTile(
                    title: Text(q.label),
                    subtitle: q.isVideoOnly
                        ? Text('Video + audio',
                            style: AppTheme
                                .caption
                                .copyWith(
                                    color: AppTheme
                                        .textSecondary))
                        : null,
                    trailing: q.height ==
                                ui.currentQualityHeight &&
                            !ui.audioOnly
                        ? const Icon(Icons.check,
                            color:
                                AppTheme.primary)
                        : null,
                    onTap: () {
                      if (ui.audioOnly) {
                        notifier
                            .toggleAudioOnly();
                      }
                      notifier.setQuality(q);
                      Navigator.pop(context);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons
                      .music_note_outlined),
                  title:
                      const Text('Audio only'),
                  trailing: ui.audioOnly
                      ? const Icon(Icons.check,
                          color: AppTheme.primary)
                      : null,
                  onTap: () {
                    if (!ui.audioOnly) {
                      notifier.toggleAudioOnly();
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Playback speed selector bottom sheet.
class SpeedSheet extends StatelessWidget {
  final PlayerController notifier;
  final double currentSpeed;

  const SpeedSheet({
    super.key,
    required this.notifier,
    required this.currentSpeed,
  });

  static Future<void> show(
      BuildContext context,
      PlayerController notifier,
      double currentSpeed) {
    return showModalBottomSheet(
      context: context,
      builder: (_) => SpeedSheet(
          notifier: notifier,
          currentSpeed: currentSpeed),
    );
  }

  static const _speeds = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    3.0
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Playback speed',
                style: AppTheme.subtitle),
          ),
          for (final s in _speeds)
            ListTile(
              title: Text(s == 1.0
                  ? '1.0x (Normal)'
                  : '${s}x'),
              trailing: s == currentSpeed
                  ? const Icon(Icons.check,
                      color: AppTheme.primary)
                  : null,
              onTap: () {
                notifier.setSpeed(s);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}
