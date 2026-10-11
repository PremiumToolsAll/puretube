import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../downloads/data/download_service.dart';
import '../../../downloads/presentation/download_dialog.dart';
import '../../../player/domain/entities/models.dart';
import '../../../player/presentation/player_screen.dart';
import '../../data/library_database.dart';
import '../../data/library_models.dart';

/// Tab 5: Saved / bookmarks.
class SavedTab extends StatefulWidget {
  const SavedTab({super.key});

  @override
  State<SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<SavedTab> {
  List<SavedVideo> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list =
          await LibraryDatabase.instance.getSaved();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editNote(SavedVideo s) async {
    final ctrl =
        TextEditingController(text: s.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Add note'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'Optional note…'),
        ),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text('Save',
                  style: TextStyle(
                      color: AppTheme.primary))),
        ],
      ),
    );
    if (ok == true) {
      await LibraryDatabase.instance.setSavedNote(
          s.videoId, ctrl.text.trim());
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(
            child: CircularProgressIndicator())
        : _items.isEmpty
            ? Center(
                child: Text('No saved videos',
                    style: AppTheme.body.copyWith(
                        color:
                            AppTheme.textSecondary)),
              )
            : RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: _load,
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final s = _items[i];
                    return Dismissible(
                      key: ValueKey(s.videoId),
                      direction:
                          DismissDirection.endToStart,
                      background: Container(
                        color: AppTheme.error,
                        alignment:
                            Alignment.centerRight,
                        padding:
                            const EdgeInsets.only(
                                right: 20),
                        child: const Icon(
                            Icons.delete,
                            color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        await LibraryDatabase
                            .instance
                            .unsaveVideo(s.videoId);
                        _load();
                      },
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(
                                  8),
                          child: Image.network(
                            s.thumbnailUrl,
                            width: 110,
                            height: 62,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, __, ___) =>
                                    Container(
                                        width: 110,
                                        height: 62,
                                        color:
                                            AppTheme
                                                .card),
                          ),
                        ),
                        title: Text(s.title,
                            maxLines: 2,
                            overflow: TextOverflow
                                .ellipsis,
                            style:
                                AppTheme.body),
                        subtitle: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                                '${s.author} • ${timeAgo(s.savedAt)}',
                                style: AppTheme
                                    .caption
                                    .copyWith(
                                        color: AppTheme
                                            .textSecondary)),
                            if (s.note.isNotEmpty)
                              Text(s.note,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow
                                          .ellipsis,
                                  style: AppTheme
                                      .caption
                                      .copyWith(
                                          color: AppTheme
                                              .primary)),
                          ],
                        ),
                        trailing: PopupMenuButton<
                            String>(
                          color: AppTheme.surface,
                          onSelected: (v) async {
                            if (v ==
                                'note') {
                              _editNote(s);
                            } else if (v ==
                                'remove') {
                              await LibraryDatabase
                                  .instance
                                  .unsaveVideo(
                                      s.videoId);
                              _load();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'note',
                                child: Text(
                                    'Add note')),
                            const PopupMenuItem(
                                value: 'remove',
                                child: Text(
                                    'Remove')),
                          ],
                        ),
                        onTap: () =>
                            Navigator.of(context)
                                .push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  PlayerScreen(
                                      videoId:
                                          s.videoId)),
                        ),
                      ),
                    );
                  },
                ),
              );
  }
}
