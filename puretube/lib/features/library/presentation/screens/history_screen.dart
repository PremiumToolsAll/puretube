import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/format.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../providers/library_providers.dart';
import 'playlists_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Library'),
          bottom: const TabBar(tabs: [
            Tab(text: 'History'),
            Tab(text: 'Playlists'),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear history',
              onPressed: () => _confirmClear(context, ref),
            ),
          ],
        ),
        body: const TabBarView(
          children: [_HistoryTab(), _PlaylistsTab()],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear watch history?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(historyControllerProvider.notifier)
                  .clear();
            },
            child: const Text('Clear',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyControllerProvider);
    if (history.isEmpty) {
      return const Center(
          child: Text('Nothing watched yet.',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: history.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Theme.of(context).colorScheme.surfaceContainer),
      itemBuilder: (ctx, i) {
        final e = history[i];
        final resume = e.positionSecs > 10
            ? Duration(seconds: e.positionSecs)
            : null;
        return Dismissible(
          key: ValueKey(e.videoId),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child:
                const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => ref
              .read(historyControllerProvider.notifier)
              .remove(e.videoId),
          child: ListTile(
            leading: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: e.thumbnailUrl,
                    width: 96,
                    height: 54,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainer),
                  ),
                ),
                if ((e.durationSecs ?? 0) > 0)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        formatDuration(Duration(
                            seconds: e.durationSecs!)),
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(e.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${e.author} • ${timeAgo(e.watchedAt)}'
              '${resume != null ? ' • Resume ${formatDuration(resume)}' : ''}',
              style:
                  const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                    videoId: e.videoId,
                    initialPosition: resume),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsControllerProvider);
    if (playlists.isEmpty) {
      return const Center(
          child: Text('No playlists yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: playlists.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Theme.of(context).colorScheme.surfaceContainer),
      itemBuilder: (ctx, i) {
        final p = playlists[i];
        return Dismissible(
          key: ValueKey(p.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child:
                const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => ref
              .read(playlistsControllerProvider.notifier)
              .delete(p.id),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.playlist_play,
                  color: Colors.grey),
            ),
            title: Text(p.name),
            subtitle: Text('${p.items.length} videos',
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(
                      playlistId: p.id)),
            ),
          ),
        );
      },
    );
  }
}
