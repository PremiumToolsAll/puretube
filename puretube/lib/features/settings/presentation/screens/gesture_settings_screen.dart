import 'package:flutter/material.dart';

import '../../../core/services/gesture_mapper.dart';
import '../../../core/theme/app_theme.dart';

/// Remap player gestures.
class GestureSettingsScreen
    extends StatefulWidget {
  const GestureSettingsScreen({super.key});

  @override
  State<GestureSettingsScreen>
      createState() =>
          _GestureSettingsScreenState();
}

class _GestureSettingsScreenState
    extends State<GestureSettingsScreen> {
  Map<String, String> _map = {};
  bool _loading = true;

  static const _gestures = {
    'doubleTapLeft': 'Double tap left',
    'doubleTapRight':
        'Double tap right',
    'swipeUpLeft': 'Swipe up (left)',
    'swipeDownLeft':
        'Swipe down (left)',
    'swipeUpRight':
        'Swipe up (right)',
    'swipeDownRight':
        'Swipe down (right)',
    'longPress': 'Long press',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m =
        await GestureMapper.instance.getAll();
    if (mounted) {
      setState(() {
        _map = m;
        _loading = false;
      });
    }
  }

  Future<void> _pick(String gesture) async {
    final current = _map[gesture] ?? 'none';
    final picked =
        await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Text(
                  _gestures[gesture] ?? gesture,
                  style:
                      AppTheme.subtitle),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: GestureMapper
                    .actionOptions
                    .map((a) => ListTile(
                          title: Text(
                              GestureMapper
                                  .actionLabel(
                                      a),
                              style: AppTheme
                                  .body),
                          trailing: a ==
                                  current
                              ? const Icon(
                                  Icons.check,
                                  color: AppTheme
                                      .primary)
                              : null,
                          onTap: () =>
                              Navigator.pop(
                                  context,
                                  a),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await GestureMapper.instance
          .setAction(gesture, picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          AppTheme.background,
      appBar: AppBar(
        backgroundColor:
            AppTheme.background,
        title:
            const Text('Gestures'),
        actions: [
          TextButton(
            onPressed: () async {
              await GestureMapper
                  .instance
                  .reset();
              _load();
            },
            child: const Text('Reset',
                style: TextStyle(
                    color:
                        AppTheme.primary)),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(
                      color:
                          AppTheme.primary))
          : ListView(
              children: _gestures.entries
                  .map((e) => ListTile(
                        title: Text(e.value,
                            style:
                                AppTheme.body),
                        subtitle: Text(
                            GestureMapper
                                .actionLabel(
                                    _map[e.key] ??
                                        'none'),
                            style: AppTheme
                                .caption
                                .copyWith(
                                    color: AppTheme
                                        .primary)),
                        trailing: const Icon(
                            Icons
                                .chevron_right,
                            color: AppTheme
                                .textSecondary),
                        onTap: () =>
                            _pick(e.key),
                      ))
                  .toList(),
            ),
    );
  }
}
