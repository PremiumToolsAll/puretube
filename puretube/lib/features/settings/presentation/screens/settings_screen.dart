import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../library/data/library_database.dart';
import '../../../search/data/app_database.dart';
import '../../data/settings_service.dart';

/// Comprehensive settings screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() =>
      _SettingsScreenState();
}

class _SettingsScreenState
    extends State<SettingsScreen> {
  final _s = SettingsService.instance;
  final Map<String, dynamic> _vals = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = <String, dynamic>{
      'theme_mode': await _s.themeMode,
      'dynamic_color': await _s.dynamicColor,
      'grid_columns': await _s.gridColumns,
      'default_quality': await _s.defaultQuality,
      'default_speed': await _s.defaultSpeed,
      'autoplay_next': await _s.autoplayNext,
      'remember_position':
          await _s.rememberPosition,
      'double_tap_seconds':
          await _s.doubleTapSeconds,
      'wifi_only': await _s.wifiOnly,
      'max_parallel': await _s.maxParallel,
      'sb_enabled':
          await _s.sponsorBlockEnabled,
      'sb_categories': await _s.sbCategories,
      'sb_autoskip': await _s.sbAutoSkip,
      'background_audio':
          await _s.backgroundAudio,
      'pip_enabled': await _s.pipEnabled,
      'popup_enabled': await _s.popupEnabled,
      'incognito': await _s.incognito,
      'history_retention':
          await _s.historyRetentionDays,
    };
    if (mounted) {
      setState(() {
        _vals.addAll(v);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Settings'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator())
          : ListView(
              children: [
                _section('Appearance'),
                _dropdown(
                    'Theme',
                    _vals['theme_mode'],
                    ['light', 'dark', 'amoled', 'system'],
                    (v) {
                  _s.setThemeMode(v);
                  setState(() =>
                      _vals['theme_mode'] = v);
                }),
                _switch(
                    'Dynamic color (Material You)',
                    _vals['dynamic_color'],
                    (v) {
                  _s.setDynamicColor(v);
                  setState(() =>
                      _vals['dynamic_color'] = v);
                }),
                _dropdown(
                    'Video grid columns',
                    '${_vals['grid_columns']}',
                    ['1', '2', '3'], (v) {
                  final n =
                      int.parse(v);
                  _s.setGridColumns(n);
                  setState(() =>
                      _vals['grid_columns'] = n);
                }),
                _section('Player'),
                _dropdown(
                    'Default quality',
                    '${_vals['default_quality']}p',
                    [
                      '144p',
                      '240p',
                      '360p',
                      '480p',
                      '720p',
                      '1080p',
                      '1440p',
                      '2160p'
                    ],
                    (v) {
                  final n = int.parse(
                      v.replaceAll('p', ''));
                  _s.setDefaultQuality(n);
                  setState(() =>
                      _vals['default_quality'] =
                          n);
                }),
                _dropdown(
                    'Default speed',
                    '${_vals['default_speed']}x',
                    [
                      '0.5x',
                      '1.0x',
                      '1.25x',
                      '1.5x',
                      '2.0x'
                    ],
                    (v) {
                  final n = double.parse(
                      v.replaceAll('x', ''));
                  _s.setDefaultSpeed(n);
                  setState(() =>
                      _vals['default_speed'] =
                          n);
                }),
                _switch(
                    'Auto-play next video',
                    _vals['autoplay_next'],
                    (v) {
                  _s.setAutoplayNext(v);
                  setState(() =>
                      _vals['autoplay_next'] =
                          v);
                }),
                _switch(
                    'Remember playback position',
                    _vals['remember_position'],
                    (v) {
                  _s.setRememberPosition(v);
                  setState(() =>
                      _vals['remember_position'] =
                          v);
                }),
                _dropdown(
                    'Double-tap seek',
                    '${_vals['double_tap_seconds']}s',
                    [
                      '5s',
                      '10s',
                      '15s',
                      '20s',
                      '30s'
                    ],
                    (v) {
                  final n = int.parse(
                      v.replaceAll('s', ''));
                  _s.setDoubleTapSeconds(n);
                  setState(() =>
                      _vals['double_tap_seconds'] =
                          n);
                }),
                _section('Downloads'),
                _switch(
                    'Wi-Fi only downloads',
                    _vals['wifi_only'], (v) {
                  _s.setWifiOnly(v);
                  setState(() =>
                      _vals['wifi_only'] = v);
                }),
                _dropdown(
                    'Max parallel downloads',
                    '${_vals['max_parallel']}',
                    ['1', '2', '3', '5'],
                    (v) {
                  final n =
                      int.parse(v);
                  _s.setMaxParallel(n);
                  setState(() =>
                      _vals['max_parallel'] =
                          n);
                }),
                _section('SponsorBlock'),
                _switch(
                    'Enable SponsorBlock',
                    _vals['sb_enabled'], (v) {
                  _s.setSponsorBlockEnabled(v);
                  setState(() =>
                      _vals['sb_enabled'] = v);
                }),
                _switch(
                    'Auto-skip segments',
                    _vals['sb_autoskip'], (v) {
                  _s.setSbAutoSkip(v);
                  setState(() =>
                      _vals['sb_autoskip'] = v);
                }),
                _categories(),
                _section('Background & Popup'),
                _switch(
                    'Background audio',
                    _vals['background_audio'],
                    (v) {
                  _s.setBackgroundAudio(v);
                  setState(() =>
                      _vals['background_audio'] =
                          v);
                }),
                _switch('PiP mode',
                    _vals['pip_enabled'], (v) {
                  _s.setPipEnabled(v);
                  setState(() =>
                      _vals['pip_enabled'] = v);
                }),
                _switch(
                    'Popup player',
                    _vals['popup_enabled'],
                    (v) {
                  _s.setPopupEnabled(v);
                  setState(() =>
                      _vals['popup_enabled'] =
                          v);
                }),
                _section('Privacy & Data'),
                _switch('Incognito mode',
                    _vals['incognito'], (v) {
                  _s.setIncognito(v);
                  setState(() =>
                      _vals['incognito'] = v);
                }),
                _dropdown(
                    'Auto-delete history',
                    '${_vals['history_retention']} days',
                    [
                      '30 days',
                      '90 days',
                      '180 days',
                      'Never'
                    ],
                    (v) async {
                  final days = v == 'Never'
                      ? 36500
                      : int.parse(
                          v.split(' ')[0]);
                  await _s
                      .setHistoryRetentionDays(
                          days);
                  setState(() =>
                      _vals['history_retention'] =
                          days);
                  await LibraryDatabase
                      .instance
                      .pruneHistory(days);
                }),
                ListTile(
                  leading: const Icon(
                      Icons.delete_sweep_outlined),
                  title: const Text(
                      'Clear watch history'),
                  onTap: () async {
                    await LibraryDatabase
                        .instance
                        .clearHistory();
                    if (mounted) {
                      ScaffoldMessenger.of(
                              context)
                          .showSnackBar(const SnackBar(
                              content: Text(
                                  'History cleared')));
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(
                      Icons.search_off_outlined),
                  title: const Text(
                      'Clear search history'),
                  onTap: () async {
                    await AppDatabase
                        .instance
                        .clearHistory();
                    if (mounted) {
                      ScaffoldMessenger.of(
                              context)
                          .showSnackBar(const SnackBar(
                              content: Text(
                                  'Search history cleared')));
                    }
                  },
                ),
                _section('About'),
                const ListTile(
                  leading:
                      Icon(Icons.info_outlined),
                  title: Text('PureTube'),
                  subtitle:
                      Text('Version 1.0.0'),
                ),
                ListTile(
                  leading: const Icon(
                      Icons.share_outlined),
                  title:
                      const Text('Share app'),
                  onTap: () {},
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          16, 20, 16, 4),
      child: Text(title,
          style: AppTheme.subtitle.copyWith(
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14)),
    );
  }

  Widget _switch(String title, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: AppTheme.body),
      value: value,
      activeColor: AppTheme.primary,
      onChanged: onChanged,
    );
  }

  Widget _dropdown(String title, String value,
      List<String> options,
      ValueChanged<String> onChanged) {
    return ListTile(
      title: Text(title, style: AppTheme.body),
      trailing: DropdownButton<String>(
        value: value,
        dropdownColor: AppTheme.surface,
        style: AppTheme.body
            .copyWith(fontSize: 13),
        underline: const SizedBox.shrink(),
        items: options
            .map((o) => DropdownMenuItem(
                value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _categories() {
    const all = {
      'sponsor': 'Sponsor segments',
      'selfpromo': 'Unpaid/self promotion',
      'outro': 'Outro/credits',
      'intro': 'Intro/intermission',
      'preview': 'Preview/recap',
      'interaction': 'Interaction reminder',
      'filler': 'Filler tangents',
      'music_offtopic': 'Non-music sections',
    };
    final selected =
        List<String>.from(_vals['sb_categories'] ?? []);
    return ExpansionTile(
      title:
          Text('Categories to skip', style: AppTheme.body),
      children: all.entries.map((e) {
        final on = selected.contains(e.key);
        return CheckboxListTile(
          title: Text(e.value,
              style: AppTheme.body
                  .copyWith(fontSize: 13)),
          value: on,
          activeColor: AppTheme.primary,
          dense: true,
          onChanged: (v) {
            final next =
                List<String>.from(selected);
            if (v == true) {
              next.add(e.key);
            } else {
              next.remove(e.key);
            }
            _s.setSbCategories(next);
            setState(() =>
                _vals['sb_categories'] = next);
          },
        );
      }).toList(),
    );
  }
}
