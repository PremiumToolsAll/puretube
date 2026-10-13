import 'package:flutter/material.dart';

/// Search filter options (applied as post-filtering on results).
class SearchFilters {
  final String? uploadDate; // hour, today, week, month, year
  final String? type; // video, channel, playlist
  final String? duration; // short, medium, long

  const SearchFilters({
    this.uploadDate,
    this.type,
    this.duration,
  });

  SearchFilters copyWith({
    String? uploadDate,
    String? type,
    String? duration,
  }) =>
      SearchFilters(
        uploadDate: uploadDate ?? this.uploadDate,
        type: type ?? this.type,
        duration: duration ?? this.duration,
      );

  bool get isEmpty =>
      uploadDate == null &&
      type == null &&
      duration == null;
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
          initialChildSize: 0.6,
          builder: (_, __) =>
              SearchFilterSheet(initial: initial),
        ),
      );

  @override
  State<SearchFilterSheet> createState() =>
      _SearchFilterSheetState();
}

class _SearchFilterSheetState
    extends State<SearchFilterSheet> {
  static const _accent = Color(0xFF10B981);
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
                const Text('Search filters',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(
                      context,
                      const SearchFilters()),
                  child: const Text('Reset',
                      style:
                          TextStyle(color: _accent)),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, _f),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black),
                  child: const Text('Apply',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  16, 0, 16, 16),
              children: [
                _section('Upload date', [
                  'Last hour',
                  'Today',
                  'This week',
                  'This month',
                  'This year'
                ], [
                  'hour',
                  'today',
                  'week',
                  'month',
                  'year'
                ], _f.uploadDate,
                    (v) => setState(() => _f = _f.copyWith(uploadDate: v))),
                _section('Type', ['Video', 'Channel', 'Playlist'],
                    ['video', 'channel', 'playlist'], _f.type,
                    (v) => setState(
                        () => _f = _f.copyWith(type: v))),
                _section(
                    'Duration',
                    [
                      'Under 4 min',
                      '4-20 min',
                      'Over 20 min'
                    ],
                    ['short', 'medium', 'long'],
                    _f.duration,
                    (v) => setState(() =>
                        _f = _f.copyWith(duration: v))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<String> labels,
      List<String> values, String? selected,
      ValueChanged<String?> onPick) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Wrap(
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
                selectedColor: _accent,
                backgroundColor:
                    const Color(0xFF16211C),
                labelStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13),
              );
            }),
          ),
        ],
      ),
    );
  }
}
