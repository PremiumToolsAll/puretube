import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/format.dart';
import '../data/download_model.dart';
import '../data/download_service.dart';

/// Downloads screen — queue (Isar-persisted) + files on disk.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() =>
      _DownloadsScreenState();
}

class _DownloadsScreenState
    extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  StreamSubscription? _sub;
  List<DownloadRecord> _queue = [];
  List<DownloadedFile> _videos = [];
  List<DownloadedFile> _audios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
        length: 3, vsync: this);
    _load();
    _sub = DownloadService
        .instance.queueStream
        .listen((q) {
      if (mounted) {
        setState(() => _queue = q);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final svc = DownloadService.instance;
      final q = await svc.getQueue();
      final v = await svc.listDownloaded(false);
      final a = await svc.listDownloaded(true);
      if (mounted) {
        setState(() {
          _queue = q;
          _videos = v;
          _audios = a;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Downloads'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Queue'),
            Tab(text: 'Videos'),
            Tab(text: 'Audio'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _queueList(),
                _fileList(_videos, true),
                _fileList(_audios, false),
              ],
            ),
    );
  }

  // ── Queue tab ─────────────────────────────────────────────

  Widget _queueList() {
    final active = _queue
        .where((r) =>
            r.status == 'queued' ||
            r.status == 'downloading' ||
            r.status == 'paused' ||
            r.status == 'failed')
        .toList();
    if (active.isEmpty) {
      return Center(
        child: Text('Queue is empty',
            style: AppTheme.body.copyWith(
                color: AppTheme.textSecondary)),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: ListView.builder(
        itemCount: active.length,
        itemBuilder: (_, i) {
          final r = active[i];
          return Card(
            color: AppTheme.card,
            margin: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          r.isAudio
                              ? Icons.music_note
                              : Icons
                                  .videocam_outlined,
                          size: 20,
                          color:
                              AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.title,
                            maxLines: 2,
                            overflow: TextOverflow
                                .ellipsis,
                            style:
                                AppTheme.body),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: r.progress / 100,
                    backgroundColor:
                        Colors.white10,
                    valueColor:
                        const AlwaysStoppedAnimation(
                            AppTheme.primary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                          '${r.progress}% • ${_statusLabel(r.status)}',
                          style: AppTheme
                              .caption
                              .copyWith(
                                  color: AppTheme
                                      .textSecondary)),
                      const Spacer(),
                      _queueActions(r),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'downloading':
        return 'Downloading';
      case 'paused':
        return 'Paused';
      case 'failed':
        return 'Failed';
      case 'complete':
        return 'Complete';
      default:
        return 'Queued';
    }
  }

  Widget _queueActions(DownloadRecord r) {
    final svc = DownloadService.instance;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r.status == 'downloading')
          IconButton(
            icon:
                const Icon(Icons.pause, size: 20),
            tooltip: 'Pause',
            onPressed: () =>
                svc.pauseDownload(r.id),
          ),
        if (r.status == 'paused' ||
            r.status == 'queued')
          IconButton(
            icon: const Icon(
                Icons.play_arrow,
                size: 20),
            tooltip: 'Resume',
            onPressed: () =>
                svc.resumeDownload(r.id),
          ),
        if (r.status == 'failed')
          IconButton(
            icon:
                const Icon(Icons.refresh, size: 20),
            tooltip: 'Retry',
            onPressed: () =>
                svc.retryDownload(r.id),
          ),
        if (r.status != 'complete')
          IconButton(
            icon:
                const Icon(Icons.close, size: 20),
            tooltip: 'Cancel',
            onPressed: () =>
                svc.cancelDownload(r.id),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline,
              size: 20),
          tooltip: 'Remove',
          onPressed: () =>
              svc.removeRecord(r.id),
        ),
      ],
    );
  }

  // ── Files tabs ────────────────────────────────────────────

  Widget _fileList(
      List<DownloadedFile> files, bool isVideo) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isVideo
                    ? Icons.videocam_outlined
                    : Icons.music_note_outlined,
                size: 64,
                color: AppTheme.textSecondary
                    .withOpacity(0.4)),
            const SizedBox(height: 12),
            Text('No downloads yet',
                style: AppTheme.body.copyWith(
                    color:
                        AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: ListView.builder(
        itemCount: files.length,
        itemBuilder: (_, i) {
          final f = files[i];
          return Dismissible(
            key: ValueKey(f.path),
            direction:
                DismissDirection.endToStart,
            background: Container(
              color: AppTheme.error,
              alignment: Alignment.centerRight,
              padding:
                  const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete,
                  color: Colors.white),
            ),
            confirmDismiss: (_) async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor:
                      AppTheme.surface,
                  title:
                      const Text('Delete file?'),
                  content: Text(f.name),
                  actions: [
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(
                                context, false),
                        child: const Text(
                            'Cancel')),
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(
                                context, true),
                        child: const Text('Delete',
                            style: TextStyle(
                                color: AppTheme
                                    .error))),
                  ],
                ),
              );
              return ok ?? false;
            },
            onDismissed: (_) async {
              try {
                await File(f.path).delete();
              } catch (_) {}
              _load();
            },
            child: ListTile(
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: Icon(
                    isVideo
                        ? Icons.play_arrow
                        : Icons.music_note,
                    color: AppTheme.primary),
              ),
              title: Text(f.name,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  style: AppTheme.body),
              subtitle: Text(
                  '${f.sizeLabel} • ${timeAgo(f.modified)}',
                  style: AppTheme.caption.copyWith(
                      color:
                          AppTheme.textSecondary)),
              trailing: IconButton(
                icon: const Icon(
                    Icons.open_in_new,
                    size: 20),
                tooltip: 'Open',
                onPressed: () =>
                    FileUtils.open(f.path),
              ),
              onTap: () =>
                  FileUtils.open(f.path),
            ),
          );
        },
      ),
    );
  }
}
