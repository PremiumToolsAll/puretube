import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_theme.dart';

/// 5-band audio equalizer UI.
/// NOTE: media_kit exposes audio filters via `mpv` lavfi.
/// These map to `anequalizer` filter parameters applied
/// through the player's audio filter chain.
class EqualizerWidget extends StatefulWidget {
  final Player player;

  const EqualizerWidget(
      {super.key, required this.player});

  static Future<void> show(
      BuildContext context, Player player) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, ctrl) =>
            EqualizerWidget(
                player: player),
      ),
    );
  }

  @override
  State<EqualizerWidget> createState() =>
      _EqualizerWidgetState();
}

class _EqualizerWidgetState
    extends State<EqualizerWidget> {
  // 5 bands: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz. Range -12..+12 dB.
  List<double> _bands =
      List.filled(5, 0.0);
  String _preset = 'Flat';

  static const _freqs = [
    '60Hz',
    '230Hz',
    '910Hz',
    '3.6k',
    '14k'
  ];

  static const _presets = {
    'Flat': [0.0, 0.0, 0.0, 0.0, 0.0],
    'Pop': [-1.0, 2.0, 4.0, 2.0, -1.0],
    'Rock': [4.0, 2.0, -1.0, 2.0, 4.0],
    'Classical': [3.0, 2.0, -1.0, 2.0, 3.0],
    'Bass Boost': [8.0, 5.0, 1.0, 0.0, 0.0],
    'Vocal': [-2.0, 1.0, 4.0, 4.0, 1.0],
  };

  Future<void> _apply() async {
    try {
      // mpv anequalizer: c0..c4 gains.
      final gains = _bands
          .map((b) =>
              'c${_bands.indexOf(b)} f=${_freqFor(_bands.indexOf(b))} w=1 g=$b')
          .join('|');
      await widget.player.setProperty(
          'af', 'anequalizer=$gains');
    } catch (_) {
      // Equalizer not supported on this build — UI still works.
    }
  }

  String _freqFor(int i) {
    switch (i) {
      case 0:
        return '60';
      case 1:
        return '230';
      case 2:
        return '910';
      case 3:
        return '3600';
      default:
        return '14000';
    }
  }

  void _setPreset(String name) {
    setState(() {
      _preset = name;
      _bands =
          List.from(_presets[name]!);
    });
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Equalizer',
                    style: AppTheme.subtitle),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      _setPreset('Flat'),
                  child: const Text('Reset',
                      style: TextStyle(
                          color: AppTheme
                              .primary)),
                ),
              ],
            ),
          ),
          // Presets.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection:
                  Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(
                      horizontal: 16),
              children: _presets.keys.map(
                (p) {
                  final on =
                      _preset == p;
                  return Padding(
                    padding:
                        const EdgeInsets.only(
                            right: 8),
                    child: ChoiceChip(
                      label: Text(p),
                      selected: on,
                      onSelected: (_) =>
                          _setPreset(p),
                      selectedColor:
                          AppTheme.primary,
                      backgroundColor:
                          AppTheme.card,
                      labelStyle:
                          AppTheme.body.copyWith(
                              color: Colors
                                  .white,
                              fontSize: 13),
                    ),
                  );
                },
              ).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Bands.
          Expanded(
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceEvenly,
              children: List.generate(
                  5,
                  (i) => Column(
                        children: [
                          Expanded(
                            child:
                                RotatedBox(
                              quarterTurns: 3,
                              child: Slider(
                                value:
                                    _bands[i],
                                min: -12,
                                max: 12,
                                divisions:
                                    24,
                                activeColor: AppTheme
                                    .primary,
                                onChanged:
                                    (v) {
                                  setState(
                                      () {
                                    _bands[i] =
                                        v;
                                    _preset =
                                        'Custom';
                                  });
                                  _apply();
                                },
                              ),
                            ),
                          ),
                          Text(
                              '${_bands[i].toStringAsFixed(0)}dB',
                              style: AppTheme
                                  .caption
                                  .copyWith(
                                      color: AppTheme
                                          .textSecondary)),
                          const SizedBox(
                              height: 4),
                          Text(_freqs[i],
                              style: AppTheme
                                  .caption
                                  .copyWith(
                                      color: Colors
                                          .white)),
                        ],
                      )),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
