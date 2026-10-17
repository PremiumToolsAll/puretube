import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Local HTTP proxy that applies NewPipe's YouTube streaming tricks.
///
/// NewPipe's YoutubeHttpDataSource does three critical things:
/// 1. Uses `&range=START-END` URL parameter instead of HTTP Range header
/// 2. Appends incrementing `&rn=N` (request number) to defeat throttling
/// 3. Sends YouTube-required headers (Origin, Referer, User-Agent)
///
/// mpv sends standard Range headers which YouTube throttles. This proxy
/// converts them to NewPipe's format, making high-quality DASH work.
class YoutubeProxyServer {
  HttpServer? _server;
  int _rn = 0;

  int get port => _server?.port ?? 0;
  String get baseUrl => 'http://127.0.0.1:$port';

  /// Maps local path keys to real YouTube URLs.
  final Map<String, String> _urlMap = {};

  Future<void> start() async {
    _server ??= await HttpServer.bind('127.0.0.1', 0);
    _server!.listen(_handleRequest);
  }

  /// Registers a YouTube URL and returns the proxied local URL.
  String proxyUrl(String youtubeUrl) {
    final key = 'yt_${_urlMap.length}';
    _urlMap[key] = youtubeUrl;
    return '$baseUrl/$key';
  }

  void clear() => _urlMap.clear();

  Future<void> _handleRequest(HttpRequest request) async {
    final key = request.uri.path.substring(1);
    final youtubeUrl = _urlMap[key];

    if (youtubeUrl == null) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }

    try {
      _rn++;
      var targetUrl = youtubeUrl;

      // Convert Range header to &range= URL parameter (NewPipe trick).
      final rangeHeader =
          request.headers.value('range');
      String? rangeParam;
      if (rangeHeader != null) {
        final match = RegExp(r'bytes=(\d+)-(\d*)')
            .firstMatch(rangeHeader);
        if (match != null) {
          final start = match.group(1)!;
          final end = match.group(2)!;
          rangeParam =
              end.isEmpty ? '$start-' : '$start-$end';
        }
      }

      // Build URL with rn and range parameters.
      final sep = targetUrl.contains('?') ? '&' : '?';
      targetUrl = '$targetUrl${sep}rn=$_rn';
      if (rangeParam != null) {
        targetUrl += '&range=$rangeParam';
      }

      // Forward with YouTube-required headers.
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(targetUrl));
        req.headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
        req.headers['Origin'] = 'https://www.youtube.com';
        req.headers['Referer'] = 'https://www.youtube.com/';
        req.headers['Accept'] = '*/*';

        final streamed =
            await client.send(req).timeout(
                  const Duration(seconds: 30),
                );

        request.response.statusCode =
            streamed.statusCode;

        // Forward response headers.
        final contentType =
            streamed.headers['content-type'];
        if (contentType != null) {
          request.response.headers.contentType =
              ContentType.parse(contentType);
        }
        final contentLength =
            streamed.headers['content-length'];
        if (contentLength != null) {
          request.response.headers.contentLength =
              int.tryParse(contentLength) ?? -1;
        }
        request.response.headers
            .set('Accept-Ranges', 'bytes');

        // Stream the response body.
        await for (final chunk in streamed.stream) {
          request.response.add(chunk);
        }
        await request.response.close();
      } finally {
        client.close();
      }
    } catch (e) {
      try {
        request.response.statusCode = 502;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _urlMap.clear();
    await _server?.close(force: true);
    _server = null;
    _rn = 0;
  }
}
