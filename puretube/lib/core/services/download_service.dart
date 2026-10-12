import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Raw file downloader. Progress/state bookkeeping lives in
/// DownloadsController; this class only moves bytes.
class DownloadService {
  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  final Dio _dio;
  final Map<String, CancelToken> _tokens = {};

  Future<String> buildFilePath(String videoId, String title,
      String label, bool audioOnly,
      {String? role}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
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

  /// Streams to disk with resume: an existing partial file continues via
  /// the `Range` header instead of restarting. Progress is 0..1 when the
  /// total size is known. Cancel keeps the partial file for resume.
  /// onSpeed reports current download speed in Mbps (megabits/second).
  Future<void> startDownload({
    required String id,
    required String url,
    required String savePath,
    required int? totalBytesHint,
    required void Function(double progress) onProgress,
    void Function(double mbps)? onSpeed,
  }) async {
    final file = File(savePath);
    var startByte = 0;
    if (await file.exists()) startByte = await file.length();

    final token = CancelToken();
    _tokens[id] = token;
    var received = startByte;

    try {
      final res = await _dio.get<ResponseBody>(
        url,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 15),
          // Let 4xx statuses surface here so we can translate them
          // into actionable messages instead of a generic failure.
          validateStatus: (s) => s != null && s < 500,
          headers: {
            'User-Agent': _ua,
            'Accept': '*/*',
            'Accept-Encoding': 'identity',
            'Referer': 'https://www.youtube.com/',
            if (startByte > 0) 'Range': 'bytes=$startByte-',
          },
        ),
      );

      final code = res.statusCode ?? 0;
      if (code == 403 || code == 410) {
        // Signed stream URL expired or revoked: the controller's retry()
        // re-extracts fresh URLs, so tell the user exactly that.
        throw const DownloadFailed(
            'Link expired. Tap Resume to retry with a fresh link.');
      }
      if (code == 416) {
        // Range not satisfiable: the local file is already complete
        // (or longer than the remote). Treat as done, don't error out.
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

      if (res.statusCode == 200 && startByte > 0) {
        // Server ignored Range: restart from scratch.
        await file.delete();
        startByte = 0;
        received = 0;
      }

      final remaining = int.tryParse(
          res.headers.value(Headers.contentLengthHeader) ?? '');
      final total = (remaining ?? totalBytesHint ?? 0) + startByte;

      final raf = await file.open(mode: FileMode.writeOnlyAppend);
      // Speed tracking: bytes received in each 1-second window.
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
          final elapsed =
              now.difference(windowStart).inMilliseconds;
          if (elapsed >= 1000 && onSpeed != null) {
            // Mbps = (bytes * 8 bits) / ms / 1000
            final mbps = windowBytes * 8 / elapsed / 1000;
            onSpeed(mbps);
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
      _tokens.remove(id);
    }
  }

  void cancel(String id) => _tokens[id]?.cancel();

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
