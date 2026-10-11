import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Search filter options.
class SearchFilters {
  final String? uploadDate; // hour, today, week, month, year
  final String? type; // video, channel, playlist, movie
  final String? duration; // short, medium, long
  final Set<String> features; // 4k, hd, cc, live, 360, vr180

  const SearchFilters({
    this.uploadDate,
    this.type,
    this.duration,
    this.features = const {},
  });

  SearchFilters copyWith({
    String? uploadDate,
    String? type,
    String? duration,
    Set<String>? features,
  }) =>
      SearchFilters(
        uploadDate:
            uploadDate ?? this.uploadDate,
        type: type ?? this.type,
        duration: duration ?? this.duration,
        features: features ?? this.features,
      );

  bool get isEmpty =>
      uploadDate == null &&
      type == null &&
      duration == null &&
      features.isEmpty;

  /// InnerTube search params (base64-encoded filter protobuf).
  /// Full protobuf encoding is complex; we pass structured
  /// hints that youtube_explode_dart's search can use via
  /// post-filtering in the service layer.
  Map<String, String> toQueryParams() {
    final p = <String, String>{};
    if (uploadDate != null) {
      p['uploadDate'] = uploadDate!;
    }
    if (type != null) p['type'] = type!;
    if (duration != null) {
      p['duration'] = duration!;
    }
    if (features.isNotEmpty) {
      p['features'] =
          features.join(',');
    }
    return p;
  }
}

/// Filter bottom sheet.
class SearchFilterSheet extends StatefulWidget {
  final SearchFilters initial;

  const SearchFilterSheet({
    super.key,
    this.initial = const SearchFilters(),
  });

  static Future<SearchFilters?> show(
          BuildContext context,
          SearchFilters initial) =>
      showModalBottomSheet<SearchFilters>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (_, ctrl) =>
              SearchFilterSheet(
                  initial: initial),
        ),
      );

  @override
  State<SearchFilterSheet> createState() =>
      _SearchFilterSheetState();
}

class _SearchFilterSheetState
    extends State<SearchFilterSheet> {
  late SearchFilters _f;

  @override
  void initState() {
    super.initState();
    _f = widget.initial;
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
                Text('Search filters',
                    style:
                        AppTheme.subtitle),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                          context,
                          const SearchFilters()),
                  child: const Text('Reset',
                      style: TextStyle(
                          color: AppTheme
                              .primary)),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(
                          context, _f),
                  style:
                      ElevatedButton.styleFrom(
                          backgroundColor:
                              AppTheme.primary),
                  child:
                      const Text('Apply'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(
                      16, 0, 16, 16),
              children: [
                _section('Upload date'),
                _chips(
                  ['Last hour', 'Today', 'This week', 'This month', 'This year'],
                  ['hour', 'today', 'week', 'month', 'year'],
                  _f.uploadDate,
                  (v) => setState(() => _f =
                      _f.copyWith(
                          uploadDate: v)),
                ),
                _section('Type'),
                _chips(
                  ['Video', 'Channel', 'Playlist', 'Movie'],
                  ['video', 'channel', 'playlist', 'movie'],
                  _f.type,
                  (v) => setState(() => _f =
                      _f.copyWith(
                          type: v)),
                ),
                _section('Duration'),
                _chips(
                  ['Under 4 min', '4-20 min', 'Over 20 min'],
                  ['short', 'medium', 'long'],
                  _f.duration,
                  (v) => setState(() => _f =
                      _f.copyWith(
                          duration: v)),
                ),
                _section('Features'),
                Wrap(
                  spacing: 8,
                  children: [
                    '4K',
                    'HD',
                    'CC',
                    'Live',
                    '360°',
                    'VR180'
                  ]
                      .map((feat) {
                    final key = feat
                        .toLowerCase()
                        .replaceAll(
                            '°', '');
                    final on = _f.features
                        .contains(key);
                    return FilterChip(
                      label: Text(feat),
                      selected: on,
                      onSelected: (_) {
                        final next = Set<
                                String>.from(
                            _f.features);
                        if (on) {
                          next.remove(key);
                        } else {
                          next.add(key);
                        }
                        setState(() => _f =
                            _f.copyWith(
                                features:
                                    next));
                      },
                      selectedColor:
                          AppTheme.primary,
                      backgroundColor:
                          AppTheme.card,
                      labelStyle:
                          AppTheme.body.copyWith(
                              color: Colors
                                  .white,
                              fontSize: 13),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding:
          const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title,
          style: AppTheme.body.copyWith(
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _chips(
      List<String> labels,
      List<String> values,
      String? selected,
      ValueChanged<String?> onPick) {
    return Wrap(
      spacing: 8,
      children: List.generate(
          labels.length, (i) {
        final v = values[i];
        final on = selected == v;
        return ChoiceChip(
          label: Text(labels[i]),
          selected: on,
          onSelected: (_) =>
              onPick(on ? null : v),
          selectedColor: AppTheme.primary,
          backgroundColor: AppTheme.card,
          labelStyle:
              AppTheme.body.copyWith(
                  color: Colors.white,
                  fontSize: 13),
        );
      }),
    );
  }
}
