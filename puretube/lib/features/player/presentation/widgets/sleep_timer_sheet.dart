import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../providers/player_controller.dart';

/// Beautiful WILLOW-themed sleep timer bottom sheet, shared by the
/// fullscreen player and the popup player.
///
/// Options: Off, 10/15/20/30/45 minutes, 1 hour, End of video, Custom.
/// The timer itself lives in [PlayerController] and is persisted to Hive
/// so it keeps working while the app is backgrounded.
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});


  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const SleepTimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(playerControllerProvider);
    final notifier = ref.read(playerControllerProvider.notifier);
    final remaining = ui.sleepRemaining;

    final playerState = ref.read(mediaKitPlayerProvider).state;
    final videoLeft =
        playerState.duration - playerState.position;

    final bg = Theme.of(context).scaffoldBackgroundColor;
    final card = Theme.of(context).colorScheme.surfaceContainer;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: accent, width: 1.5)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.bedtime, color: accent, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Sleep timer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (remaining != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: accent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '⏾ ${formatDuration(remaining)} left',
                        style: TextStyle(
                            color: accent, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _option(
                      context,
                      icon: Icons.close,
                      label: 'Off',
                      selected: remaining == null,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        notifier.cancelSleepTimer();
                        Navigator.pop(context);
                      },
                    ),
                    for (final m in [10, 15, 20, 30, 45])
                      _option(
                        context,
                        icon: Icons.timer_outlined,
                        label: '$m minutes',
                        selected: _matches(
                            remaining, Duration(minutes: m)),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          notifier.startSleepTimer(
                              Duration(minutes: m));
                          Navigator.pop(context);
                        },
                      ),
                    _option(
                      context,
                      icon: Icons.hourglass_bottom,
                      label: '1 hour',
                      selected: _matches(
                          remaining, const Duration(hours: 1)),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        notifier.startSleepTimer(
                            const Duration(hours: 1));
                        Navigator.pop(context);
                      },
                    ),
                    _option(
                      context,
                      icon: Icons.movie_outlined,
                      label: videoLeft > Duration.zero
                          ? 'End of video (${formatDuration(videoLeft)})'
                          : 'End of video',
                      selected: false,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        final ok = notifier
                            .startSleepTimerUntilEndOfVideo();
                        Navigator.pop(context);
                        if (!ok) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Could not determine video length'),
                            ),
                          );
                        }
                      },
                    ),
                    _option(
                      context,
                      icon: Icons.edit_outlined,
                      label: 'Custom…',
                      selected: false,
                      onTap: () {
                        Navigator.pop(context);
                        _showCustomDialog(context, ref);
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
                height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  /// Matches the current remaining time against a preset option,
  /// tolerating up to 90 seconds of elapsed drift.
  bool _matches(Duration? remaining, Duration preset) {
    if (remaining == null) return false;
    return (remaining - preset).abs() <
        const Duration(seconds: 90);
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? accent : Colors.white70,
                  size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color:
                        selected ? accent : Colors.white,
                    fontSize: 16,
                    fontWeight: selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check,
                    color: accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    final card = Theme.of(context).colorScheme.surfaceContainer;
    final accent = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accent, width: 1),
        ),
        title: const Text('Custom timer',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Minutes (e.g. 25)',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accent),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide:
                  BorderSide(color: accent, width: 2),
            ),
          ),
          onSubmitted: (_) =>
              _submitCustom(ctx, ref, ctrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () =>
                _submitCustom(ctx, ref, ctrl),
            child: Text('Set',
                style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _submitCustom(
      BuildContext ctx, WidgetRef ref, TextEditingController ctrl) {
    final m = int.tryParse(ctrl.text.trim());
    if (m != null && m > 0 && m <= 720) {
      HapticFeedback.lightImpact();
      ref
          .read(playerControllerProvider.notifier)
          .startSleepTimer(Duration(minutes: m));
      Navigator.pop(ctx);
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
            content: Text('Enter 1–720 minutes')),
      );
    }
  }
}
