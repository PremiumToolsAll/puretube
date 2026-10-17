import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'sabr_client.dart';

/// A local HTTP server that serves SABR-downloaded media to mpv.
///
/// This enables the player to stream via HTTP with range request support,
/// instead of playing a local file directly.
class SabrHttpServer {
  HttpServer? _server;
  int get port => _server?.port ?? 0;
  String get baseUrl => 'http://127.0.0.1:$port';

  final Map<String, _FileStream> _streams = {};

  /// Starts the server on a random available port.
  Future<void> start() async {
    _server ??= await HttpServer.bind('127.0.0.1', 0);
  }

  /// Registers local files and returns HTTP URLs for video and audio.
  ///
  /// Returns {'videoUrl': String, 'audioUrl': String}.
  Map<String, String> registerFiles({
    required String videoId,
    required String videoPath,
    required String audioPath,
    required String videoMime,
    required String audioMime,
  }) {
    final videoKey = '${videoId}_v';
    final audioKey = '${videoId}_a';

    _streams[videoKey] = _FileStream(
      path: videoPath,
      mimeType: videoMime,
    );
    _streams[audioKey] = _FileStream(
      path: audioPath,
      mimeType: audioMime,
    );

    // Start listening (idempotent).
    _server?.listen(_handleRequest);

    return {
      'videoUrl': '$baseUrl/$videoKey',
      'audioUrl': '$baseUrl/$audioKey',
    };
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path.substring(1);
    final stream = _streams[path];

    if (stream == null) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }

    try {
      final file = File(stream.path);
      if (!await file.exists()) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      final length = await file.length();
      final rangeHeader = request.headers.value('range');

      int start = 0;
      int end = length - 1;

      if (rangeHeader != null) {
        final match =
            RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
        if (match != null) {
          start = int.parse(match.group(1)!);
          final endStr = match.group(2)!;
          end = endStr.isEmpty ? length - 1 : int.parse(endStr);
          end = end.clamp(0, length - 1);
        }
        request.response.statusCode = 206;
        request.response.headers.set(
          'Content-Range',
          'bytes $start-$end/$length',
        );
      }

      final contentType = stream.mimeType.contains('webm')
          ? 'video/webm'
          : stream.mimeType.contains('audio')
              ? 'audio/mp4'
              : 'video/mp4';
      request.response.headers.contentType =
          ContentType.parse(contentType);
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.contentLength = end - start + 1;

      // Stream the file range.
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        var remaining = end - start + 1;
        const chunkSize = 64 * 1024;
        while (remaining > 0) {
          final toRead =
              remaining > chunkSize ? chunkSize : remaining;
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;
          request.response.add(chunk);
          remaining -= chunk.length;
        }
      } finally {
        await raf.close();
      }
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  void unregister(String videoId) {
    _streams.remove('${videoId}_v');
    _streams.remove('${videoId}_a');
  }

  Future<void> stop() async {
    _streams.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

class _FileStream {
  final String path;
  final String mimeType;

  _FileStream({required this.path, required this.mimeType});
}
