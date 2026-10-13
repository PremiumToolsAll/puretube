import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/presentation/providers/player_controller.dart';
import '../providers/quality_providers.dart';

/// PureTube's own stream-quality picker.
///
/// Deliberately NOT a radio-button dialog: a WILLOW bottom sheet with a
/// Wi-Fi / Mobile data segmented toggle on top, then horizontal rows of
/// glowing quality cards (resolution + tier badge + data estimate).
/// Tapping a card applies it instantly — no Cancel/Save buttons.
class QualitySettingsSheet extends ConsumerStatefulWidget {
  const QualitySettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const QualitySettingsSheet(),
    );
  }

  @override
  ConsumerState<QualitySettingsSheet> createState() =>
      _QualitySettingsSheetState();
}

/// Static card metadata: value, big label, tier badge, data estimate.
class _VideoOpt {
  final String value;
  final String label;
  final String badge;
  final String usage;
  const _VideoOpt(this.value, this.label, this.badge, this.usage);
}

const _videoOpts = [
  _VideoOpt('auto', 'Auto', 'AUTO', 'Adapts'),
  _VideoOpt('2160', '2160p', '2K', '~12 GB/hr'),
  _VideoOpt('1440', '1440p', '1.5K', '~6 GB/hr'),
  _VideoOpt('1080', '1080p', 'FHD', '~3 GB/hr'),
  _VideoOpt('720', '720p', 'HD', '~1.5 GB/hr'),
  _VideoOpt('480', '480p', 'SD', '~700 MB/hr'),
  _VideoOpt('360', '360p', 'SD', '~400 MB/hr'),
  _VideoOpt('240', '240p', 'LD', '~250 MB/hr'),
  _VideoOpt('144', '144p', 'LD', '~120 MB/hr'),
];

class _AudioOpt {
  final String value;
  final String label;
  final String badge;
  final String desc;
  const _AudioOpt(this.value, this.label, this.badge, this.desc);
}

const _audioOpts = [
  _AudioOpt('auto', 'Smart', 'AUTO', 'Adapts to network'),
  _AudioOpt('best', 'Hi-Fi', 'BEST', 'Highest bitrate'),
  _AudioOpt('worst', 'Saver', 'LOW', 'Least data'),
];

class _QualitySettingsSheetState
    extends ConsumerState<QualitySettingsSheet> {
  /// True = editing Wi-Fi preferences, false = Mobile data.
  bool _wifi = true;

  static const _bg = Color(0xFF0C110E);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final accentLight = Theme.of(context).colorScheme.secondary;
    final card = Theme.of(context).colorScheme.surfaceContainer;
    final maxH = MediaQuery.of(context).size.height * 0.88;

    final videoProvider =
        _wifi ? wifiVideoQualityProvider : mobileVideoQualityProvider;
    final nofsProvider = _wifi
        ? wifiNoFullscreenQualityProvider
        : mobileNoFullscreenQualityProvider;
    final audioProvider =
        _wifi ? wifiAudioQualityProvider : mobileAudioQualityProvider;
    final videoKey = _wifi ? kPrefWifiVideo : kPrefMobileVideo;
    final nofsKey =
        _wifi ? kPrefWifiNoFullscreen : kPrefMobileNoFullscreen;
    final audioKey = _wifi ? kPrefWifiAudio : kPrefMobileAudio;

    final videoValue = ref.watch(videoProvider);
    final nofsValue = ref.watch(nofsProvider);
    final audioValue = ref.watch(audioProvider);

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF10B981), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.hd_outlined, color: accent, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Stream quality',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Wi-Fi / Mobile data segmented toggle.
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    _networkTab(
                      selected: _wifi,
                      icon: Icons.wifi,
                      label: 'Wi-Fi',
                      onTap: () => setState(() => _wifi = true),
                    ),
                    _networkTab(
                      selected: !_wifi,
                      icon: Icons.signal_cellular_alt,
                      label: 'Mobile data',
                      onTap: () => setState(() => _wifi = false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(context, 'VIDEO'),
                    _cardRow(
                      context: context,
                      children: [
                        for (final o in _videoOpts)
                          _qualityCard(
                            context: context,
                            selected: videoValue == o.value,
                            label: o.label,
                            badge: o.badge,
                            sub: o.usage,
                            onTap: () => _pick(
                                videoProvider, videoKey, o.value),
                          ),
                      ],
                    ),
                    _sectionLabel(context, 'WHEN NOT FULLSCREEN'),
                    _cardRow(
                      context: context,
                      children: [
                        _qualityCard(
                          context: context,
                          selected: nofsValue == 'same',
                          label: 'Same',
                          badge: 'LINK',
                          sub: 'As fullscreen',
                          onTap: () =>
                              _pick(nofsProvider, nofsKey, 'same'),
                        ),
                        for (final o in _videoOpts.skip(1))
                          _qualityCard(
                            context: context,
                            selected: nofsValue == o.value,
                            label: o.label,
                            badge: o.badge,
                            sub: o.usage,
                            onTap: () => _pick(
                                nofsProvider, nofsKey, o.value),
                          ),
                      ],
                    ),
                    _sectionLabel(context, 'AUDIO'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20),
                      child: Row(
                        children: [
                          for (var i = 0;
                              i < _audioOpts.length;
                              i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _qualityCard(
                                context: context,
                                selected:
                                    audioValue == _audioOpts[i].value,
                                label: _audioOpts[i].label,
                                badge: _audioOpts[i].badge,
                                sub: _audioOpts[i].desc,
                                onTap: () => _pick(
                                    audioProvider,
                                    audioKey,
                                    _audioOpts[i].value),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          20, 16, 20, 4),
                      child: Text(
                        'Applies to new videos. Changing between fullscreen and portrait re-applies your choice.',
                        style: TextStyle(
                          color: accentLight.withValues(alpha: 0.7),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
                height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  /// Persist one choice and refresh the player's pre-load cache so the
  /// new preference is honored for upcoming videos.
  Future<void> _pick(StateProvider<String> provider, String key,
      String value) async {
    HapticFeedback.lightImpact();
    ref.read(provider.notifier).state = value;
    await saveQualitySetting(key, value);
    try {
      ref.read(playerControllerProvider.notifier).refreshPrecache();
    } catch (_) {}
  }

  Widget _networkTab({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? accent : Colors.grey),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _cardRow(
      {required BuildContext context,
      required List<Widget> children}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            children[i],
          ],
        ],
      ),
    );
  }

  /// A single selectable quality card with tier badge and data estimate.
  /// Selected cards glow emerald; everything else stays quiet.
  Widget _qualityCard({
    required BuildContext context,
    required bool selected,
    required String label,
    required String badge,
    required String sub,
    required VoidCallback onTap,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    final card = Theme.of(context).colorScheme.surfaceContainer;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 96,
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? accent
                : Theme.of(context)
                    .colorScheme
                    .outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? accent
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color:
                      selected ? Colors.black : Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? accent : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
