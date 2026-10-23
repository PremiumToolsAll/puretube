import 'dart:async';

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
final subscriptionRepositoryProvider =
    Provider<SubscriptionRepository>(
        (ref) => SubscriptionRepository());
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
  // Auto-retry (SparkTube/NewPipe-style resilience): a failed download
  // re-extracts fresh stream URLs and resumes by itself — up to 3
  // attempts with backoff — instead of sitting failed until the user
  // notices and taps Resume. Manual retry/cancel/remove clear any
  // pending attempt.
  final Map<String, int> _autoRetryCounts = {};
  final Map<String, Timer> _autoRetryTimers = {};

  void _scheduleAutoRetry(String id) {
    final count = (_autoRetryCounts[id] ?? 0) + 1;
    if (count > 3) return;
    _autoRetryCounts[id] = count;
    _autoRetryTimers[id]?.cancel();
    final delay =
        Duration(seconds: count == 1 ? 5 : count == 2 ? 15 : 30);
    _autoRetryTimers[id] = Timer(delay, () {
      _autoRetryTimers.remove(id);
      final cur = state[id];
      if (cur != null && cur.status == DownloadStatus.failed) {
        retry(id);
      }
    });
  }

  void _clearAutoRetry(String id) {
    _autoRetryTimers.remove(id)?.cancel();
    _autoRetryCounts.remove(id);
  }

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

  /// Starts a download. When [option] is a video-only DASH stream and
  /// [audioOption] is given, both files are fetched (video, then audio)
  /// and the record keeps the audio path so the offline player can
  /// attach it via mpv's `audio-file` — video plays WITH audio without
  /// an FFmpeg merge step.
  Future<void> startDownload(DownloadOption option,
      VideoDetails video, {DownloadOption? audioOption}) async {
    final service = ref.read(downloadServiceProvider);
    final repo = ref.read(downloadRepositoryProvider);
    final id = '${video.id}_${option.label}';
    if (state[id]?.status == DownloadStatus.downloading) return;

    // Video-only DASH + a chosen audio track => paired download.
    final pairAudio =
        option.videoOnly && !option.audioOnly ? audioOption : null;

    final savePath = await service.buildFilePath(
        video.id, video.title, option.label, option.audioOnly);
    final audioSavePath = pairAudio == null
        ? null
        : await service.buildFilePath(video.id, video.title,
            pairAudio.label, true,
            role: 'audio');
    var record = DownloadRecord(
      id: id,
      videoId: video.id,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnailUrl,
      qualityLabel: option.label,
      audioOnly: option.audioOnly,
      filePath: savePath,
      audioFilePath: audioSavePath,
      videoOnly: option.videoOnly,
      audioQualityLabel: pairAudio?.label,
      totalBytes: option.sizeBytes,
      status: DownloadStatus.downloading,
      createdAt: DateTime.now(),
    );
    _upsert(record);
    await repo.save(record);

    void reportProgress(double p) {
      final cur = state[id];
      if (cur != null &&
          cur.status == DownloadStatus.downloading) {
        _upsert(cur.copyWith(progress: p.clamp(0.0, 1.0)));
      }
    }

    void reportSpeed(double mbps) {
      final cur = state[id];
      if (cur != null &&
          cur.status == DownloadStatus.downloading) {
        _upsert(cur.copyWith(speedMbps: mbps));
      }
    }

    try {
      if (pairAudio == null) {
        await service.startDownload(
          id: id,
          url: option.url,
          savePath: savePath,
          totalBytesHint: option.sizeBytes,
          onProgress: reportProgress,
          onSpeed: reportSpeed,
        );
      } else {
        // Weighted progress: video ~80%, audio ~20% of the bar.
        final videoBytes = option.sizeBytes ?? 0;
        final audioBytes = pairAudio.sizeBytes ?? 0;
        final totalBytes = videoBytes + audioBytes;
        final videoShare = totalBytes > 0
            ? videoBytes / totalBytes
            : 0.8;
        await service.startDownload(
          id: '${id}_video',
          url: option.url,
          savePath: savePath,
          totalBytesHint: option.sizeBytes,
          onProgress: (p) => reportProgress(p * videoShare),
          onSpeed: reportSpeed,
        );
        await service.startDownload(
          id: '${id}_audio',
          url: pairAudio.url,
          savePath: audioSavePath!,
          totalBytesHint: pairAudio.sizeBytes,
          onProgress: (p) =>
              reportProgress(videoShare + p * (1 - videoShare)),
          onSpeed: reportSpeed,
        );
      }
      final done = state[id];
      if (done != null) {
        _clearAutoRetry(id);
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
        _scheduleAutoRetry(id);
      }
    }
  }

  /// Stream URLs expire: re-extract before every (re)start, then resume
  /// into the same deterministic file path.
  Future<void> retry(String id) async {
    _autoRetryTimers.remove(id)?.cancel();
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
    DownloadOption? audioMatch;
    if (record.videoOnly && record.audioFilePath != null) {
      final audioOpts = fresh.where((o) => o.audioOnly).toList();
      if (audioOpts.isNotEmpty) {
        final wanted = record.audioQualityLabel;
        audioMatch = wanted == null
            ? audioOpts.first
            : audioOpts.firstWhere(
                (o) => o.label == wanted,
                orElse: () => audioOpts.first,
              );
      }
    }
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
        likeCount: null,
        uploadDate: null,
        description: '',
      ),
      audioOption: audioMatch,
    );
  }

  Future<void> cancel(String id) async {
    _clearAutoRetry(id);
    final service = ref.read(downloadServiceProvider);
    service.cancel(id);
    // Paired DASH downloads use suffixed token ids.
    service.cancel('${id}_video');
    service.cancel('${id}_audio');
  }

  Future<void> remove(String id) async {
    _clearAutoRetry(id);
    final record = state[id];
    cancel(id);
    if (record != null) {
      final service = ref.read(downloadServiceProvider);
      await service.deleteFile(record.filePath);
      final audioPath = record.audioFilePath;
      if (audioPath != null) await service.deleteFile(audioPath);
      await ref.read(downloadRepositoryProvider).delete(id);
    }
    state = {...state}..remove(id);
  }
}

final downloadsControllerProvider = NotifierProvider<
    DownloadsController, Map<String, DownloadRecord>>(
    DownloadsController.new);
