import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../player/presentation/player_screen.dart';
import '../data/library_database.dart';
import '../data/library_models.dart';

/// Tab 2: Playlists.
class PlaylistsTab extends StatefulWidget {
  const PlaylistsTab({super.key});

  @override
  State<PlaylistsTab> createState() =>
      _PlaylistsTabState();
}

class _PlaylistsTabState
    extends State<PlaylistsTab> {
  List<Playlist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await LibraryDatabase.instance
          .getPlaylists();
      if (mounted) {
        setState(() {
          _playlists = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('New playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  hintText: 'Playlist name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                  hintText:
                      'Description (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text('Create',
                  style: TextStyle(
                      color:
                          AppTheme.primary))),
        ],
      ),
    );
    if (ok == true &&
        nameCtrl.text.trim().isNotEmpty) {
      try {
        await LibraryDatabase.instance
            .createPlaylist(nameCtrl.text,
                descCtrl.text);
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(
                  content: Text(
                      'Playlist name already exists')));
        }
      }
    }
  }

  Future<void> _options(Playlist p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.play_arrow),
              title: const Text('Play all'),
              onTap: () =>
                  Navigator.pop(context, 'play'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.shuffle),
              title: const Text('Shuffle play'),
              onTap: () => Navigator.pop(
                  context, 'shuffle'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(
                  context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete,
                  color: AppTheme.error),
              title: const Text('Delete',
                  style: TextStyle(
                      color: AppTheme.error)),
              onTap: () => Navigator.pop(
                  context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final db = LibraryDatabase.instance;
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
              'Delete playlist?'),
          content: Text(
              '"${p.name}" will be deleted.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(
                    context, false),
                child:
                    const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(
                    context, true),
                child: const Text('Delete',
                    style: TextStyle(
                        color:
                            AppTheme.error))),
          ],
        ),
      );
      if (ok == true) {
        await db.deletePlaylist(p.id);
        _load();
      }
    } else if (action == 'rename') {
      final ctrl =
          TextEditingController(text: p.name);
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
              'Rename playlist'),
          content: TextField(
              controller: ctrl),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(
                    context, false),
                child:
                    const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(
                    context, true),
                child: const Text('Save',
                    style: TextStyle(
                        color: AppTheme
                            .primary))),
          ],
        ),
      );
      if (ok == true &&
          ctrl.text.trim().isNotEmpty) {
        await db.renamePlaylist(
            p.id, ctrl.text);
        _load();
      }
    } else if ((action == 'play' ||
            action == 'shuffle') &&
        p.videoIds.isNotEmpty) {
      final ids = [...p.videoIds];
      if (action == 'shuffle') ids.shuffle();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => PlayerScreen(
                  videoId: ids.first)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator())
          : _playlists.isEmpty
              ? Center(
                  child: Text(
                      'No playlists yet',
                      style: AppTheme.body.copyWith(
                          color: AppTheme
                              .textSecondary)),
                )
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _playlists.length,
                    itemBuilder: (_, i) {
                      final p = _playlists[i];
                      return ListTile(
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius:
                                BorderRadius.circular(
                                    8),
                          ),
                          child: const Icon(
                              Icons
                                  .playlist_play_outlined,
                              color:
                                  AppTheme.primary),
                        ),
                        title: Text(p.name,
                            style:
                                AppTheme.body),
                        subtitle: Text(
                            '${p.videoIds.length} videos • ${timeAgo(p.updatedAt)}',
                            style: AppTheme
                                .caption
                                .copyWith(
                                    color: AppTheme
                                        .textSecondary)),
                        trailing: IconButton(
                          icon: const Icon(
                              Icons.more_vert),
                          onPressed: () =>
                              _options(p),
                        ),
                        onTap: () =>
                            _openPlaylist(p),
                      );
                    },
                  ),
                ),
    );
  }

  void _openPlaylist(Playlist p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctrl) => Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(p.name,
                        style:
                            AppTheme.subtitle),
                  ),
                  TextButton.icon(
                    icon: const Icon(
                        Icons.play_arrow,
                        size: 18),
                    label:
                        const Text('Play all'),
                    onPressed:
                        p.videoIds.isNotEmpty
                            ? () {
                                Navigator.pop(
                                    context);
                                Navigator.of(
                                        context)
                                    .push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          PlayerScreen(
                                              videoId: p.videoIds
                                                  .first)),
                                );
                              }
                            : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: p.videoIds.isEmpty
                  ? Center(
                      child: Text(
                          'No videos in this playlist',
                          style: AppTheme.body
                              .copyWith(
                                  color: AppTheme
                                      .textSecondary)),
                    )
                  : ReorderableListView.builder(
                      controller: ctrl,
                      itemCount:
                          p.videoIds.length,
                      onReorder:
                          (oldI, newI) async {
                        final ids = [
                          ...p.videoIds
                        ];
                        if (newI > oldI)
                          newI--;
                        final item = ids
                            .removeAt(oldI);
                        ids.insert(
                            newI, item);
                        await LibraryDatabase
                            .instance
                            .reorderPlaylist(
                                p.id, ids);
                        _load();
                      },
                      itemBuilder: (_, i) {
                        final vid =
                            p.videoIds[i];
                        return Dismissible(
                          key: ValueKey(vid),
                          direction:
                              DismissDirection
                                  .endToStart,
                          background: Container(
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
                                .removeFromPlaylist(
                                    p.id, vid);
                            _load();
                          },
                          child: ListTile(
                            key: ValueKey(
                                'tile_$vid'),
                            leading:
                                const Icon(
                                    Icons
                                        .drag_handle,
                                    color: AppTheme
                                        .textSecondary),
                            title: Text(vid,
                                style:
                                    AppTheme
                                        .body),
                            subtitle: Text(
                                'Tap to play',
                                style: AppTheme
                                    .caption
                                    .copyWith(
                                        color: AppTheme
                                            .textSecondary)),
                            onTap: () {
                              Navigator.pop(
                                  context);
                              Navigator.of(
                                      context)
                                  .push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PlayerScreen(
                                            videoId:
                                                vid)),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
