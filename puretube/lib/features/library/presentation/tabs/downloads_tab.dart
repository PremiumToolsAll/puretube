import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../downloads/data/download_service.dart';
import '../../player/presentation/player_screen.dart';

/// Tab 4: Downloads (library view).
class DownloadsTab extends StatefulWidget {
  const DownloadsTab({super.key});

  @override
  State<DownloadsTab> createState() =>
      _DownloadsTabState();
}

class _DownloadsTabState
    extends State<DownloadsTab> {
  List<DownloadedFile> _files = [];
  bool _loading = true;
  String _filter = 'All';
  String _sort = 'Date';
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final svc = DownloadService.instance;
      final v = await svc.listDownloaded(false);
      final a = await svc.listDownloaded(true);
      var all = [...v, ...a];
      // Filter.
      if (_filter == 'Videos') {
        all = all
            .where((f) =>
                _isVideo(f.name))
            .toList();
      } else if (_filter == 'Audio') {
        all = all
            .where((f) =>
                !_isVideo(f.name))
            .toList();
      }
      // Sort.
      if (_sort == 'Size') {
        all.sort(
            (a, b) => b.size.compareTo(a.size));
      } else if (_sort == 'Name') {
        all.sort((a, b) =>
            a.name.compareTo(b.name));
      } else {
        all.sort((a, b) => b.modified
            .compareTo(a.modified));
      }
      if (mounted) {
        setState(() {
          _files = all;
          _loading = false;
          _selected.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool _isVideo(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.mp4') ||
        n.endsWith('.mkv') ||
        n.endsWith('.webm');
  }

  Future<void> _deleteSelected() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete files?'),
        content: Text(
            '${_selected.length} files will be deleted.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: AppTheme.error))),
        ],
      ),
    );
    if (ok == true) {
      for (final path in _selected) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DropdownButton<String>(
                value: _filter,
                dropdownColor: AppTheme.surface,
                style: AppTheme.body
                    .copyWith(fontSize: 13),
                items: ['All', 'Videos', 'Audio']
                    .map((s) =>
                        DropdownMenuItem(
                            value: s,
                            child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(
                        () => _filter = v);
                    _load();
                  }
                },
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _sort,
                dropdownColor: AppTheme.surface,
                style: AppTheme.body
                    .copyWith(fontSize: 13),
                items: ['Date', 'Size', 'Name']
                    .map((s) =>
                        DropdownMenuItem(
                            value: s,
                            child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(
                        () => _sort = v);
                    _load();
                  }
                },
              ),
              const Spacer(),
              if (_selected.isNotEmpty)
                IconButton(
                  icon: const Icon(
                      Icons.delete,
                      color: AppTheme.error),
                  onPressed: _deleteSelected,
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator())
              : _files.isEmpty
                  ? Center(
                      child: Text(
                          'No downloads yet',
                          style: AppTheme.body
                              .copyWith(
                                  color: AppTheme
                                      .textSecondary)),
                    )
                  : RefreshIndicator(
                      color:
                          AppTheme.primary,
                      onRefresh: _load,
                      child: GridView.builder(
                        padding:
                            const EdgeInsets.all(
                                12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio:
                              0.85,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount:
                            _files.length,
                        itemBuilder: (_, i) {
                          final f =
                              _files[i];
                          final sel = _selected
                              .contains(f.path);
                          return InkWell(
                            onTap: () {
                              if (_selected
                                  .isNotEmpty) {
                                setState(() {
                                  if (sel) {
                                    _selected.remove(
                                        f.path);
                                  } else {
                                    _selected.add(
                                        f.path);
                                  }
                                });
                              } else {
                                ScaffoldMessenger.of(
                                        context)
                                    .showSnackBar(SnackBar(
                                        content: Text(
                                            'Play offline: ${f.name}')));
                              }
                            },
                            onLongPress: () =>
                                setState(() {
                              if (sel) {
                                _selected.remove(
                                    f.path);
                              } else {
                                _selected
                                    .add(f.path);
                              }
                            }),
                            child: Container(
                              decoration:
                                  BoxDecoration(
                                color:
                                    AppTheme.card,
                                borderRadius:
                                    BorderRadius.circular(
                                        12),
                                border: sel
                                    ? Border.all(
                                        color: AppTheme
                                            .primary,
                                        width: 2)
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Expanded(
                                    child:
                                        Container(
                                      decoration:
                                          BoxDecoration(
                                        color: Colors
                                            .black26,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(
                                                    12)),
                                      ),
                                      child:
                                          Center(
                                        child: Icon(
                                            _isVideo(f.name)
                                                ? Icons.play_circle_outline
                                                : Icons.music_note,
                                            size: 48,
                                            color: AppTheme.primary),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets
                                            .all(
                                            8),
                                    child:
                                        Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [
                                        Text(
                                            f.name,
                                            maxLines:
                                                2,
                                            overflow:
                                                TextOverflow
                                                    .ellipsis,
                                            style:
                                                AppTheme
                                                    .body
                                                    .copyWith(
                                                        fontSize:
                                                            12)),
                                        const SizedBox(
                                            height:
                                                4),
                                        Text(
                                            '${f.sizeLabel} • ${timeAgo(f.modified)}',
                                            style: AppTheme
                                                .caption
                                                .copyWith(
                                                    color:
                                                        AppTheme
                                                            .textSecondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
