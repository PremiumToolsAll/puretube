import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../player/presentation/player_screen.dart';
import '../../data/library_database.dart';
import '../../data/library_models.dart';

/// Tab 1: Watch history.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() =>
      _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<HistoryEntry> _entries = [];
  bool _loading = true;
  bool _historyPaused = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await LibraryDatabase.instance
          .getHistory(query: _searchCtrl.text);
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Clear history?'),
        content: const Text(
            'All watch history will be deleted.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text('Clear',
                  style: TextStyle(
                      color: AppTheme.error))),
        ],
      ),
    );
    if (ok == true) {
      await LibraryDatabase.instance.clearHistory();
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
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText:
                        'Search history…',
                    prefixIcon:
                        Icon(Icons.search, size: 20),
                    contentPadding:
                        EdgeInsets.symmetric(
                            vertical: 8),
                  ),
                  onChanged: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                    _historyPaused
                        ? Icons.play_arrow
                        : Icons.pause,
                    color: AppTheme.primary),
                tooltip: _historyPaused
                    ? 'Resume history'
                    : 'Pause history',
                onPressed: () => setState(() =>
                    _historyPaused =
                        !_historyPaused),
              ),
              IconButton(
                icon: const Icon(
                    Icons.delete_sweep_outlined),
                tooltip: 'Clear all',
                onPressed: _clearAll,
              ),
            ],
          ),
        ),
        if (_historyPaused)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: AppTheme.primary
                .withOpacity(0.15),
            child: Text(
              'History is paused',
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(
                  color: AppTheme.primary),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Text(
                          'No watch history yet',
                          style: AppTheme.body
                              .copyWith(
                                  color: AppTheme
                                      .textSecondary)),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount:
                            _entries.length,
                        itemBuilder: (_, i) {
                          final e =
                              _entries[i];
                          final progress = e
                                      .durationSeconds >
                                  0
                              ? (e.positionSeconds /
                                      e.durationSeconds)
                                  .clamp(0.0, 1.0)
                              : 0.0;
                          return Dismissible(
                            key: ValueKey(
                                e.videoId),
                            direction:
                                DismissDirection
                                    .endToStart,
                            background:
                                Container(
                              color:
                                  AppTheme.error,
                              alignment: Alignment
                                  .centerRight,
                              padding:
                                  const EdgeInsets
                                      .only(
                                      right: 20),
                              child: const Icon(
                                  Icons.delete,
                                  color: Colors
                                      .white),
                            ),
                            onDismissed: (_) async {
                              await LibraryDatabase
                                  .instance
                                  .removeHistory(
                                      e.videoId);
                              _load();
                            },
                            child: ListTile(
                              leading: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                                8),
                                    child:
                                        Image.network(
                                      e.thumbnailUrl,
                                      width: 110,
                                      height: 62,
                                      fit: BoxFit
                                          .cover,
                                      errorBuilder: (_,
                                              __,
                                              ___) =>
                                          Container(
                                              width:
                                                  110,
                                              height:
                                                  62,
                                              color: AppTheme
                                                  .card),
                                    ),
                                  ),
                                  if (progress >
                                      0)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child:
                                          LinearProgressIndicator(
                                        value:
                                            progress,
                                        minHeight:
                                            3,
                                        backgroundColor:
                                            Colors
                                                .white24,
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                                AppTheme
                                                    .primary),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(
                                  e.title,
                                  maxLines: 2,
                                  overflow:
                                      TextOverflow
                                          .ellipsis,
                                  style:
                                      AppTheme.body),
                              subtitle: Text(
                                  '${e.author} • ${timeAgo(e.watchedAt)}',
                                  style: AppTheme
                                      .caption
                                      .copyWith(
                                          color: AppTheme
                                              .textSecondary)),
                              trailing: IconButton(
                                icon: const Icon(
                                    Icons
                                        .replay_outlined,
                                    size: 20),
                                tooltip:
                                    'Watch again',
                                onPressed: () =>
                                    Navigator.of(
                                            context)
                                        .push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          PlayerScreen(
                                              videoId: e
                                                  .videoId)),
                                ),
                              ),
                              onTap: () =>
                                  Navigator.of(
                                          context)
                                      .push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PlayerScreen(
                                            videoId: e
                                                .videoId)),
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
