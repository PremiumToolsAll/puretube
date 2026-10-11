import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/player_controller.dart';

/// Sleep timer bottom sheet.
class SleepTimerSheet extends StatelessWidget {
  final PlayerController notifier;

  const SleepTimerSheet({
    super.key,
    required this.notifier,
  });

  static Future<void> show(
      BuildContext context,
      PlayerController notifier) {
    return showModalBottomSheet(
      context: context,
      builder: (_) =>
          SleepTimerSheet(notifier: notifier),
    );
  }

  static const _options = <String, Duration?>{
    'Off': Duration.zero,
    'End of video': null, // special-cased
    '15 minutes': Duration(minutes: 15),
    '30 minutes': Duration(minutes: 30),
    '45 minutes': Duration(minutes: 45),
    '60 minutes': Duration(hours: 1),
    '90 minutes': Duration(minutes: 90),
  };

  @override
  Widget build(BuildContext context) {
    final customCtrl = TextEditingController();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Sleep timer',
                style: AppTheme.subtitle),
          ),
          for (final e in _options.entries)
            ListTile(
              leading: const Icon(
                  Icons.bedtime_outlined),
              title: Text(e.key),
              onTap: () {
                Navigator.pop(context);
                try {
                  if (e.value == null) {
                    notifier
                        .setSleepTimerEndOfVideo();
                  } else {
                    notifier.setSleepTimer(
                        e.value!);
                  }
                } catch (_) {}
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                16, 4, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customCtrl,
                    keyboardType:
                        TextInputType.number,
                    decoration:
                        const InputDecoration(
                      hintText: 'Custom minutes…',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    final m = int.tryParse(
                        customCtrl.text.trim());
                    Navigator.pop(context);
                    if (m != null && m > 0) {
                      notifier.setSleepTimer(
                          Duration(minutes: m));
                    }
                  },
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        AppTheme.primary,
                  ),
                  child: const Text('Set'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
