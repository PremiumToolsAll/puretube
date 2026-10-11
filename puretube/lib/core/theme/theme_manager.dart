import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Custom theme engine (Riverpod).
class ThemeConfig {
  final Color primary;
  final Color accent;
  final bool amoled;

  const ThemeConfig({
    this.primary = const Color(0xFF6200EA),
    this.accent = const Color(0xFF00BCD4),
    this.amoled = true,
  });

  ThemeConfig copyWith({
    Color? primary,
    Color? accent,
    bool? amoled,
  }) =>
      ThemeConfig(
        primary: primary ?? this.primary,
        accent: accent ?? this.accent,
        amoled: amoled ?? this.amoled,
      );
}

class ThemeManager
    extends Notifier<ThemeConfig> {
  @override
  ThemeConfig build() {
    _load();
    return const ThemeConfig();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences
          .getInstance();
      final primary =
          p.getInt('theme_primary');
      final accent =
          p.getInt('theme_accent');
      final amoled =
          p.getBool('theme_amoled') ?? true;
      state = ThemeConfig(
        primary: primary != null
            ? Color(primary)
            : const Color(0xFF6200EA),
        accent: accent != null
            ? Color(accent)
            : const Color(0xFF00BCD4),
        amoled: amoled,
      );
    } catch (_) {}
  }

  Future<void> setPrimary(Color c) async {
    state =
        state.copyWith(primary: c);
    try {
      final p = await SharedPreferences
          .getInstance();
      await p.setInt(
          'theme_primary', c.value);
    } catch (_) {}
  }

  Future<void> setAccent(Color c) async {
    state =
        state.copyWith(accent: c);
    try {
      final p = await SharedPreferences
          .getInstance();
      await p.setInt(
          'theme_accent', c.value);
    } catch (_) {}
  }

  Future<void> reset() async {
    state = const ThemeConfig();
    try {
      final p = await SharedPreferences
          .getInstance();
      await p.remove('theme_primary');
      await p.remove('theme_accent');
    } catch (_) {}
  }
}

final themeManagerProvider = NotifierProvider<
    ThemeManager,
    ThemeConfig>(ThemeManager.new);

/// Color picker sheet for theme customization.
class ThemePickerSheet extends ConsumerWidget {
  const ThemePickerSheet({super.key});

  static Future<void> show(
      BuildContext context) {
    return showModalBottomSheet(
      context: context,
      builder: (_) =>
          const ThemePickerSheet(),
    );
  }

  static const _swatches = [
    Color(0xFF6200EA),
    Color(0xFF2962FF),
    Color(0xFF00BCD4),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFFC107),
    Color(0xFFFF5722),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF795548),
  ];

  @override
  Widget build(
      BuildContext context, WidgetRef ref) {
    final theme =
        ref.watch(themeManagerProvider);
    final mgr = ref
        .read(themeManagerProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Custom theme',
                    style: AppTheme.subtitle),
                const Spacer(),
                TextButton(
                  onPressed: mgr.reset,
                  child: const Text('Reset',
                      style: TextStyle(
                          color: AppTheme
                              .primary)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Primary color',
                style: AppTheme.body.copyWith(
                    fontWeight:
                        FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: _swatches.map((c) {
                final on =
                    theme.primary.value ==
                        c.value;
                return InkWell(
                  onTap: () =>
                      mgr.setPrimary(c),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      shape:
                          BoxShape.circle,
                      border: on
                          ? Border.all(
                              color: Colors
                                  .white,
                              width: 3)
                          : null,
                    ),
                    child: on
                        ? const Icon(
                            Icons.check,
                            color: Colors
                                .white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('Accent color',
                style: AppTheme.body.copyWith(
                    fontWeight:
                        FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: _swatches.map((c) {
                final on =
                    theme.accent.value ==
                        c.value;
                return InkWell(
                  onTap: () =>
                      mgr.setAccent(c),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      shape:
                          BoxShape.circle,
                      border: on
                          ? Border.all(
                              color: Colors
                                  .white,
                              width: 3)
                          : null,
                    ),
                    child: on
                        ? const Icon(
                            Icons.check,
                            color: Colors
                                .white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
