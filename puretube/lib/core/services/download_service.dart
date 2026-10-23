import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Download engine — SparkTube-style.
///
/// Files are probed with a 1-byte Range request; when the server
/// reports a total size and honors ranges, the file is split into
/// parallel segments fetched over separate connections (several
/// times faster than one stream on high-latency links), each
/// segment retrying on its own and resuming from its own byte
/// offset. Segment offsets are checkpointed through [onCheckpoint]
/// so a pause, a failure, or an app restart resumes every segment
/// exactly where it stopped — nothing restarts from zero.
/// Servers without range support fall back to the classic single
/// stream with append-resume.
class DownloadService {
  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  /// Parallel connections per file (SparkTube uses 6).
  static const _segments = 5;

  /// Below this size, splitting costs more than it gains.
  static const _minSplitBytes = 2 * 1024 * 1024;

  /// Per-segment attempts before the download fails.
  static const _segmentRetries = 3;

  final Dio _dio;
  final Map<String, Set<CancelToken>> _tokens = {};

  CancelToken _register(String id) {
    final t = CancelToken();
    (_tokens[id] ??= <CancelToken>{}).add(t);
    return t;
  }

  void _unregister(String id, CancelToken t) {
    _tokens[id]?.remove(t);
  }

  Options _opts(CancelToken token, {String? range}) => Options(
        responseType: ResponseType.stream,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        validateStatus: (s) => s != null && s < 500,
        headers: {
          'User-Agent': _ua,
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          'Referer': 'https://www.youtube.com/',
          if (range != null) 'Range': range,
        },
      );

  /// Downloads live in the app-specific EXTERNAL folder
  /// (Android/data/<pkg>/files/PureTube — SparkTube does the same
  /// with its own folder): visible in a file manager, no storage
  /// permission needed. Falls back to app documents when external
  /// storage is unavailable.
  Future<String> buildFilePath(String videoId, String title,
      String label, bool audioOnly,
      {String? role}) async {
    Directory base;
    try {
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/PureTube');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safeTitle =
        title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final short =
        safeTitle.length > 60 ? safeTitle.substring(0, 60) : safeTitle;
    final ext = audioOnly ? 'm4a' : 'mp4';
    final tag = label.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final roleSuffix = role == null ? '' : '_$role';
    return '${dir.path}/${videoId}_$tag$roleSuffix'
        '_${short.isEmpty ? 'video' : short}.$ext';
  }

  /// Downloads [url] to [savePath].
  ///
  /// [resumeOffsets] are the per-segment byte counts a previous run
  /// checkpointed (see [onCheckpoint]); when they match a fresh
  /// probe of the same total size, every segment continues from its
  /// own offset. Progress is 0..1; [onSpeed] reports Mbps.
  Future<void> startDownload({
    required String id,
    required String url,
    required String savePath,
    required int? totalBytesHint,
    required void Function(double progress) onProgress,
    void Function(double mbps)? onSpeed,
    List<int>? resumeOffsets,
    void Function(List<int> offsets, int totalBytes)? onCheckpoint,
  }) async {
    final file = File(savePath);
    await file.parent.create(recursive: true);

    // ---- Probe: total size + REAL range support (1-byte range).
    var total = 0;
    var ranges = false;
    final probeToken = _register(id);
    try {
      final res = await _dio.get<ResponseBody>(
        url,
        cancelToken: probeToken,
        options: _opts(probeToken, range: 'bytes=0-0'),
      );
      final code = res.statusCode ?? 0;
      if (code == 403 || code == 410) {
        throw const DownloadFailed(
            'Link expired. Tap Resume to retry with a fresh link.');
      }
      if (code < 200 || code >= 300) {
        throw DownloadFailed('Download failed (HTTP $code).');
      }
      // Consume one chunk then drop the body: on a range-ignoring
      // server a full drain would download the whole file just to
      // probe it. One chunk is enough to close cleanly.
      await res.data?.stream.take(1).drain<void>();
      final contentRange = res.headers.value('content-range');
      if (code == 206 && contentRange != null) {
        total =
            int.tryParse(contentRange.split('/').last.trim()) ?? 0;
        ranges = true;
      } else {
        total = int.tryParse(
                res.headers.value(Headers.contentLengthHeader) ?? '') ??
            0;
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const DownloadCanceled();
      }
      throw DownloadFailed(
          'Download failed: ${e.message ?? e.type.name}');
    } finally {
      _unregister(id, probeToken);
    }
    if (total <= 0) total = totalBytesHint ?? 0;

    if (ranges && total >= _minSplitBytes) {
      await _segmented(
        id: id,
        url: url,
        file: file,
        total: total,
        onProgress: onProgress,
        onSpeed: onSpeed,
        resumeOffsets: resumeOffsets,
        onCheckpoint: onCheckpoint,
      );
    } else {
      await _singleStream(
        id: id,
        url: url,
        file: file,
        totalBytesHint: total > 0 ? total : totalBytesHint,
        onProgress: onProgress,
        onSpeed: onSpeed,
      );
    }
  }

  // ---------------- segmented engine ----------------

  Future<void> _segmented({
    required String id,
    required String url,
    required File file,
    required int total,
    required void Function(double) onProgress,
    required void Function(double)? onSpeed,
    required List<int>? resumeOffsets,
    required void Function(List<int>, int)? onCheckpoint,
  }) async {
    final n = _segments;
    final bounds = List.generate(n, (i) {
      final start = total * i ~/ n;
      final end = (i == n - 1) ? total - 1 : (total * (i + 1) ~/ n) - 1;
      return (start, end);
    });

    // Resume offsets are only trusted when they tile the SAME
    // total with the SAME segment count, stay inside their bounds,
    // and the partial file on disk is at least that long.
    final done = List<int>.filled(n, 0);
    var resumable = false;
    if (resumeOffsets != null && resumeOffsets.length == n) {
      var ok = true;
      var sum = 0;
      for (var i = 0; i < n; i++) {
        final segLen = bounds[i].$2 - bounds[i].$1 + 1;
        if (resumeOffsets[i] < 0 || resumeOffsets[i] > segLen) {
          ok = false;
          break;
        }
        sum += resumeOffsets[i];
      }
      if (ok && await file.exists() && await file.length() >= sum) {
        for (var i = 0; i < n; i++) {
          done[i] = resumeOffsets[i];
        }
        resumable = true;
      }
    }
    if (!resumable) {
      // Fresh start: preallocate so segments can write at offsets.
      final raf = await file.open(mode: FileMode.write);
      try {
        await raf.truncate(total);
      } finally {
        await raf.close();
      }
    }

    var received = done.fold<int>(0, (a, b) => a + b);
    var canceled = false;
    var lastCheckpoint = received;
    Timer? speedTimer;
    if (onSpeed != null) {
      var lastBytes = received;
      var lastTick = DateTime.now();
      speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final now = DateTime.now();
        final ms = now.difference(lastTick).inMilliseconds;
        if (ms > 0) {
          onSpeed((received - lastBytes) * 8 / ms / 1000);
        }
        lastBytes = received;
        lastTick = now;
      });
    }

    void emitProgress() {
      onProgress((received / total).clamp(0.0, 1.0));
      if (onCheckpoint != null &&
          (received - lastCheckpoint >= 512 * 1024 ||
              received >= total)) {
        lastCheckpoint = received;
        onCheckpoint(List<int>.of(done), total);
      }
    }

    Future<void> runSegment(int i) async {
      final (segStart, segEnd) = bounds[i];
      final segLen = segEnd - segStart + 1;
      if (done[i] >= segLen) return;
      final raf = await file.open(mode: FileMode.write);
      try {
        await raf.setPosition(segStart + done[i]);
        var attempt = 0;
        while (done[i] < segLen) {
          final token = _register(id);
          try {
            final res = await _dio.get<ResponseBody>(
              url,
              cancelToken: token,
              options: _opts(token,
                  range: 'bytes=${segStart + done[i]}-$segEnd'),
            );
            final code = res.statusCode ?? 0;
            if (code == 403 || code == 410) {
              throw const DownloadFailed(
                  'Link expired. Tap Resume to retry with a fresh link.');
            }
            if (code != 206) {
              throw DownloadFailed(
                  'Segment failed (HTTP $code).');
            }
            final cr = res.headers.value('content-range') ?? '';
            final m = RegExp(r'bytes (\d+)-(\d+)/(\d+|\*)').firstMatch(cr);
            if (m == null ||
                int.parse(m.group(1)!) != segStart + done[i] ||
                int.parse(m.group(2)!) != segEnd) {
              throw const DownloadFailed('Bad range response.');
            }
            await for (final chunk in res.data!.stream) {
              await raf.writeFrom(chunk);
              done[i] += chunk.length;
              received += chunk.length;
              emitProgress();
            }
          } on DioException catch (e) {
            if (e.type == DioExceptionType.cancel) {
              canceled = true;
              throw const DownloadCanceled();
            }
            attempt++;
            if (attempt > _segmentRetries) {
              throw DownloadFailed(
                  'Download failed: ${e.message ?? e.type.name}');
            }
            await Future.delayed(
                Duration(milliseconds: 300 * attempt));
          } finally {
            _unregister(id, token);
          }
        }
      } finally {
        await raf.close();
      }
    }

    emitProgress();
    try {
      await Future.wait(
          [for (var i = 0; i < n; i++) runSegment(i)]);
    } finally {
      speedTimer?.cancel();
      onCheckpoint?.call(List<int>.of(done), total);
    }
    if (canceled) throw const DownloadCanceled();
    if (received < total) {
      throw DownloadFailed(
          'Download incomplete ($received of $total bytes).');
    }
    onProgress(1.0);
    onSpeed?.call(0);
  }

  // ------------- single-stream fallback (no ranges) -------------

  Future<void> _singleStream({
    required String id,
    required String url,
    required File file,
    required int? totalBytesHint,
    required void Function(double) onProgress,
    required void Function(double)? onSpeed,
  }) async {
    var startByte = 0;
    if (await file.exists()) startByte = await file.length();

    final token = _register(id);
    var received = startByte;
    try {
      final res = await _dio.get<ResponseBody>(
        url,
        cancelToken: token,
        options: _opts(token,
            range: startByte > 0 ? 'bytes=$startByte-' : null),
      );
      final code = res.statusCode ?? 0;
      if (code == 403 || code == 410) {
        throw const DownloadFailed(
            'Link expired. Tap Resume to retry with a fresh link.');
      }
      if (code == 416) {
        if (await file.exists() && await file.length() > 0) {
          onProgress(1.0);
          onSpeed?.call(0);
          return;
        }
        await file.delete();
        throw const DownloadFailed(
            'Could not resume. Tap Resume to restart the download.');
      }
      if (code < 200 || code >= 300) {
        throw DownloadFailed('Download failed (HTTP $code).');
      }
      if (code == 200 && startByte > 0) {
        // Server ignored Range: restart from scratch.
        startByte = 0;
        received = 0;
      }
      final remaining = int.tryParse(
          res.headers.value(Headers.contentLengthHeader) ?? '');
      final total = (remaining ?? totalBytesHint ?? 0) + startByte;

      final raf = await file.open(mode: FileMode.writeOnlyAppend);
      var windowBytes = 0;
      var windowStart = DateTime.now();
      try {
        await for (final chunk in res.data!.stream) {
          await raf.writeFrom(chunk);
          received += chunk.length;
          windowBytes += chunk.length;
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
          final now = DateTime.now();
          final elapsed = now.difference(windowStart).inMilliseconds;
          if (elapsed >= 1000 && onSpeed != null) {
            onSpeed(windowBytes * 8 / elapsed / 1000);
            windowBytes = 0;
            windowStart = now;
          }
        }
      } finally {
        await raf.close();
      }
      onProgress(1.0);
      onSpeed?.call(0);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const DownloadCanceled();
      }
      throw DownloadFailed(
          'Download failed: ${e.message ?? e.type.name}');
    } finally {
      _unregister(id, token);
    }
  }

  /// Cancels every in-flight request for [id] (probe, segments or
  /// single stream). Partial files and checkpoints stay on disk so
  /// the download can resume — this is also the pause mechanism.
  void cancel(String id) {
    final set = _tokens[id];
    if (set == null) return;
    for (final t in List<CancelToken>.of(set)) {
      t.cancel();
    }
  }

  Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

class DownloadCanceled implements Exception {
  const DownloadCanceled();
}

class DownloadFailed implements Exception {
  final String message;
  const DownloadFailed(this.message);
}
