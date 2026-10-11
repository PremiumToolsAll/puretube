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

  Future<String> buildFilePath(
      String videoId, String title, String label, bool audioOnly) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safeTitle =
        title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final short =
        safeTitle.length > 60 ? safeTitle.substring(0, 60) : safeTitle;
    final ext = audioOnly ? 'm4a' : 'mp4';
    final tag = label.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return '${dir.path}/${videoId}_$tag'
        '_${short.isEmpty ? 'video' : short}.$ext';
  }

  /// Streams to disk with resume: an existing partial file continues via
  /// the `Range` header instead of restarting. Progress is 0..1 when the
  /// total size is known. Cancel keeps the partial file for resume.
  Future<void> startDownload({
    required String id,
    required String url,
    required String savePath,
    required int? totalBytesHint,
    required void Function(double progress) onProgress,
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
          headers: {
            'User-Agent': _ua,
            if (startByte > 0) 'Range': 'bytes=$startByte-',
          },
        ),
      );

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
      try {
        await for (final chunk in res.data!.stream) {
          await raf.writeFrom(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await raf.close();
      }
      onProgress(1.0);
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
