import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/services/download_service.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/entities/library_models.dart';

final historyRepositoryProvider =
    Provider<HistoryRepository>((ref) => HistoryRepository());
final bookmarkRepositoryProvider =
    Provider<BookmarkRepository>((ref) => BookmarkRepository());
final playlistRepositoryProvider =
    Provider<PlaylistRepository>((ref) => PlaylistRepository());
final downloadRepositoryProvider =
    Provider<DownloadRepository>((ref) => DownloadRepository());
final downloadServiceProvider =
    Provider<DownloadService>((ref) => DownloadService());

// ---------------- history ----------------

class HistoryController extends Notifier<List<HistoryEntry>> {
  @override
  List<HistoryEntry> build() =>
      ref.read(historyRepositoryProvider).getAll();

  Future<void> refresh() async =>
      state = ref.read(historyRepositoryProvider).getAll();

  Future<void> remove(String videoId) async {
    await ref.read(historyRepositoryProvider).remove(videoId);
    state = state.where((e) => e.videoId != videoId).toList();
  }

  Future<void> clear() async {
    await ref.read(historyRepositoryProvider).clear();
    state = const [];
  }
}

final historyControllerProvider =
    NotifierProvider<HistoryController, List<HistoryEntry>>(
        HistoryController.new);

// ---------------- bookmarks ----------------

class BookmarkController extends Notifier<List<BookmarkEntry>> {
  @override
  List<BookmarkEntry> build() =>
      ref.read(bookmarkRepositoryProvider).getAll();

  bool isBookmarked(String videoId) =>
      state.any((e) => e.videoId == videoId);

  Future<void> toggle(BookmarkEntry entry) async {
    await ref.read(bookmarkRepositoryProvider).toggle(entry);
    state = ref.read(bookmarkRepositoryProvider).getAll();
  }

  Future<void> remove(String videoId) async {
    await ref.read(bookmarkRepositoryProvider).remove(videoId);
    state = state.where((e) => e.videoId != videoId).toList();
  }
}

final bookmarkControllerProvider =
    NotifierProvider<BookmarkController, List<BookmarkEntry>>(
        BookmarkController.new);

// ---------------- playlists ----------------

class PlaylistsController extends Notifier<List<Playlist>> {
  @override
  List<Playlist> build() =>
      ref.read(playlistRepositoryProvider).getAll();

  Future<void> create(String name) async {
    await ref.read(playlistRepositoryProvider).create(name);
    state = ref.read(playlistRepositoryProvider).getAll();
  }

  Future<void> delete(String id) async {
    await ref.read(playlistRepositoryProvider).delete(id);
    state = state.where((p) => p.id != id).toList();
  }

  Future<bool> addVideo(
      String playlistId, PlaylistItem item) async {
    final added = await ref
        .read(playlistRepositoryProvider)
        .addVideo(playlistId, item);
    state = ref.read(playlistRepositoryProvider).getAll();
    return added;
  }

  Future<void> removeVideo(
      String playlistId, String videoId) async {
    await ref
        .read(playlistRepositoryProvider)
        .removeVideo(playlistId, videoId);
    state = ref.read(playlistRepositoryProvider).getAll();
  }
}

final playlistsControllerProvider =
    NotifierProvider<PlaylistsController, List<Playlist>>(
        PlaylistsController.new);

// ---------------- downloads ----------------

class DownloadsController
    extends Notifier<Map<String, DownloadRecord>> {
  @override
  Map<String, DownloadRecord> build() {
    final map =
        ref.read(downloadRepositoryProvider).getAllAsMap();
    // Anything mid-flight when the app died returns to paused (resumable).
    for (final e in map.entries) {
      if (e.value.status == DownloadStatus.downloading ||
          e.value.status == DownloadStatus.queued) {
        map[e.key] =
            e.value.copyWith(status: DownloadStatus.paused);
      }
    }
    return map;
  }

  void _upsert(DownloadRecord r) =>
      state = {...state, r.id: r};

  Future<void> startDownload(
      DownloadOption option, VideoDetails video) async {
    final service = ref.read(downloadServiceProvider);
    final repo = ref.read(downloadRepositoryProvider);
    final id = '${video.id}_${option.label}';
    if (state[id]?.status == DownloadStatus.downloading) return;

    final savePath = await service.buildFilePath(
        video.id, video.title, option.label, option.audioOnly);
    var record = DownloadRecord(
      id: id,
      videoId: video.id,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnailUrl,
      qualityLabel: option.label,
      audioOnly: option.audioOnly,
      filePath: savePath,
      totalBytes: option.sizeBytes,
      status: DownloadStatus.downloading,
      createdAt: DateTime.now(),
    );
    _upsert(record);
    await repo.save(record);

    try {
      await service.startDownload(
        id: id,
        url: option.url,
        savePath: savePath,
        totalBytesHint: option.sizeBytes,
        onProgress: (p) {
          final cur = state[id];
          if (cur != null &&
              cur.status == DownloadStatus.downloading) {
            _upsert(cur.copyWith(progress: p));
          }
        },
      );
      final done = state[id];
      if (done != null) {
        final finished = done.copyWith(
            status: DownloadStatus.completed, progress: 1.0);
        _upsert(finished);
        await repo.save(finished);
      }
    } on DownloadCanceled {
      final cur = state[id];
      if (cur != null) {
        final paused =
            cur.copyWith(status: DownloadStatus.paused);
        _upsert(paused);
        await repo.save(paused);
      }
    } catch (e) {
      final cur = state[id];
      if (cur != null) {
        final failed = cur.copyWith(
          status: DownloadStatus.failed,
          error: e is DownloadFailed ? e.message : e.toString(),
        );
        _upsert(failed);
        await repo.save(failed);
      }
    }
  }

  /// Stream URLs expire: re-extract before every (re)start, then resume
  /// into the same deterministic file path.
  Future<void> retry(String id) async {
    final record = state[id];
    if (record == null ||
        record.status == DownloadStatus.downloading) {
      return;
    }
    final fresh = await ref
        .read(extractorProvider)
        .getDownloadOptions(record.videoId);
    final match = fresh.firstWhere(
      (o) =>
          o.label == record.qualityLabel &&
          o.audioOnly == record.audioOnly,
      orElse: () => fresh.first,
    );
    await startDownload(
      match,
      VideoDetails(
        id: record.videoId,
        title: record.title,
        author: record.author,
        channelId: '',
        duration: null,
        thumbnailUrl: record.thumbnailUrl,
        viewCount: null,
        uploadDate: null,
        description: '',
      ),
    );
  }

  Future<void> cancel(String id) async {
    ref.read(downloadServiceProvider).cancel(id);
  }

  Future<void> remove(String id) async {
    final record = state[id];
    ref.read(downloadServiceProvider).cancel(id);
    if (record != null) {
      await ref
          .read(downloadServiceProvider)
          .deleteFile(record.filePath);
      await ref.read(downloadRepositoryProvider).delete(id);
    }
    state = {...state}..remove(id);
  }
}

final downloadsControllerProvider = NotifierProvider<
    DownloadsController, Map<String, DownloadRecord>>(
    DownloadsController.new);
