import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../domain/entities/library_models.dart';
import '../providers/library_providers.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsControllerProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          title: const Text('Playlists'),
          backgroundColor: Colors.black),
      body: playlists.isEmpty
          ? const Center(
              child: Text('No playlists yet.',
                  style: TextStyle(color: Colors.grey)))
          : ListView.separated(
              itemCount: playlists.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1, color: Theme.of(context).colorScheme.surfaceContainer),
              itemBuilder: (ctx, i) {
                final p = playlists[i];
                return Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding:
                        const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete,
                        color: Colors.white),
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
                          builder: (_) =>
                              PlaylistDetailScreen(
                                  playlistId: p.id)),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _createDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Name'),
          onSubmitted: (_) {
            ref
                .read(playlistsControllerProvider.notifier)
                .create(controller.text);
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref
                  .read(playlistsControllerProvider.notifier)
                  .create(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;
  const PlaylistDetailScreen(
      {super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref
        .watch(playlistsControllerProvider)
        .where((p) => p.id == playlistId)
        .firstOrNull;
    if (playlist == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body:
              Center(child: Text('Playlist deleted.')));
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          title: Text(playlist.name),
          backgroundColor: Colors.black),
      body: playlist.items.isEmpty
          ? const Center(
              child: Text('Empty playlist.',
                  style: TextStyle(color: Colors.grey)))
          : ListView.separated(
              itemCount: playlist.items.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1, color: Theme.of(context).colorScheme.surfaceContainer),
              itemBuilder: (ctx, i) {
                final item = playlist.items[i];
                return Dismissible(
                  key: ValueKey(item.videoId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding:
                        const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete,
                        color: Colors.white),
                  ),
                  onDismissed: (_) => ref
                      .read(
                          playlistsControllerProvider.notifier)
                      .removeVideo(playlistId, item.videoId),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: item.thumbnailUrl,
                        width: 96,
                        height: 54,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer),
                      ),
                    ),
                    title: Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 13)),
                    subtitle: Text(item.author,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                              videoId: item.videoId)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Bottom sheet: pick a playlist (or create one) to save [video] into.
/// Usage: showSaveToPlaylistSheet(context, videoDetails)
Future<void> showSaveToPlaylistSheet(
    BuildContext context, VideoDetails video) {
  return showModalBottomSheet(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final playlists =
            ref.watch(playlistsControllerProvider);
        final notifier =
            ref.read(playlistsControllerProvider.notifier);
        final nameController = TextEditingController();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                  title: Text('Save to playlist',
                      style: TextStyle(
                          fontWeight: FontWeight.bold))),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (c, i) {
                    final p = playlists[i];
                    final contains = p.items.any(
                        (e) => e.videoId == video.id);
                    return ListTile(
                      leading:
                          const Icon(Icons.playlist_play),
                      title: Text(p.name),
                      subtitle: Text('${p.items.length} videos',
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12)),
                      trailing: contains
                          ? const Icon(Icons.check,
                              color: Colors.green)
                          : null,
                      onTap: () async {
                        final added =
                            await notifier.addVideo(
                          p.id,
                          PlaylistItem(
                            videoId: video.id,
                            title: video.title,
                            author: video.author,
                            thumbnailUrl:
                                video.thumbnailUrl,
                            addedAt: DateTime.now(),
                          ),
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(SnackBar(
                            content: Text(added
                                ? 'Saved to ${p.name}'
                                : 'Already in ${p.name}'),
                            duration: const Duration(
                                seconds: 2),
                          ));
                        }
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          hintText: 'New playlist name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () async {
                        final created = await ref
                            .read(playlistRepositoryProvider)
                            .create(nameController.text);
                        await notifier.addVideo(
                          created.id,
                          PlaylistItem(
                            videoId: video.id,
                            title: video.title,
                            author: video.author,
                            thumbnailUrl:
                                video.thumbnailUrl,
                            addedAt: DateTime.now(),
                          ),
                        );
                        ref.invalidate(
                            playlistsControllerProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
