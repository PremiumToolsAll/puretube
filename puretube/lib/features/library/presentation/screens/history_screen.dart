import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/format.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../providers/library_providers.dart';

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
            Tab(text: 'Bookmarks'),
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
          children: [_HistoryTab(), _BookmarksTab()],
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
          const Divider(height: 1, color: Color(0xFF0E1512)),
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
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: e.thumbnailUrl,
                width: 96,
                height: 54,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: const Color(0xFF0E1512)),
              ),
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

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarkControllerProvider);
    if (bookmarks.isEmpty) {
      return const Center(
          child: Text(
              'No bookmarks yet.\nBookmark from the player ⋮ menu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: bookmarks.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFF0E1512)),
      itemBuilder: (ctx, i) {
        final b = bookmarks[i];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: b.thumbnailUrl,
              width: 96,
              height: 54,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(color: const Color(0xFF0E1512)),
            ),
          ),
          title: Text(b.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          subtitle: Text(b.author,
              style:
                  const TextStyle(color: Colors.grey, fontSize: 11)),
          trailing: IconButton(
            icon:
                const Icon(Icons.bookmark_remove_outlined),
            onPressed: () => ref
                .read(bookmarkControllerProvider.notifier)
                .remove(b.videoId),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    PlayerScreen(videoId: b.videoId)),
          ),
        );
      },
    );
  }
}
