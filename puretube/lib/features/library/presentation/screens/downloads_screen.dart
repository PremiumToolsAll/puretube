import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/library_models.dart';
import '../providers/library_providers.dart';
import 'offline_player_screen.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsControllerProvider);
    final list = downloads.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          title: const Text('Downloads'),
          backgroundColor: Colors.black),
      body: list.isEmpty
          ? const Center(
              child: Text(
                'No downloads yet.\nOpen a video → ⋮ → Download.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(
                  height: 1, color: Color(0xFF1A1A1A)),
              itemBuilder: (ctx, i) =>
                  _DownloadTile(record: list[i]),
            ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  final DownloadRecord record;
  const _DownloadTile({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        ref.read(downloadsControllerProvider.notifier);
    final exists = File(record.filePath).existsSync();

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          record.audioOnly ? Icons.audio_file : Icons.video_file,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      title: Text(record.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${record.qualityLabel} • ${_statusLabel()}'
            '${record.totalBytes != null ? ' • ${_fileSize(record.totalBytes!)}' : ''}',
            style:
                const TextStyle(color: Colors.grey, fontSize: 11),
          ),
          if (record.status == DownloadStatus.downloading ||
              record.status == DownloadStatus.paused) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: record.progress,
              backgroundColor: Colors.white12,
              minHeight: 4,
            ),
          ],
          if (record.status == DownloadStatus.failed &&
              record.error != null)
            Text(record.error!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 11)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.status == DownloadStatus.downloading)
            IconButton(
              icon: const Icon(Icons.cancel),
              tooltip: 'Pause',
              onPressed: () => controller.cancel(record.id),
            ),
          if (record.status == DownloadStatus.paused ||
              record.status == DownloadStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Resume',
              onPressed: () => controller.retry(record.id),
            ),
          if (record.status == DownloadStatus.completed && exists)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      OfflinePlayerScreen(record: record),
                ),
              ),
            ),
          IconButton(
            icon:
                const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _confirmDelete(context, controller),
          ),
        ],
      ),
    );
  }

  String _statusLabel() => switch (record.status) {
        DownloadStatus.queued => 'Queued',
        DownloadStatus.downloading =>
          '${(record.progress * 100).round()}%',
        DownloadStatus.paused => 'Paused',
        DownloadStatus.completed => 'Completed',
        DownloadStatus.failed => 'Failed',
        DownloadStatus.canceled => 'Canceled',
      };

  String _fileSize(int bytes) {
    if (bytes >= 1 << 30) {
      return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1 << 20) {
      return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  void _confirmDelete(
      BuildContext context, DownloadsController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete download?'),
        content: const Text(
            'The downloaded file will be removed from storage.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.remove(record.id);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
