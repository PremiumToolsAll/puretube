import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/player/domain/entities/playback_models.dart';

/// Piped API fallback for when YouTube blocks the device IP directly.
///
/// Piped instances proxy YouTube, so search / details / streams keep
/// working even when youtube_explode_dart hits RequestLimitExceededException.
/// Best-effort only: throws when every known instance is unreachable, in
/// which case callers fall back to their original error handling.
class PipedService {
  PipedService({http.Client? client}) : _client = client ?? http.Client();

  /// Verified working 2026-10-14 (others returned 301/502/526/timeout).
  /// Kept short: [_getJson] races every instance, so dead entries only
  /// waste requests.
  static const List<String> instances = [
    'https://pipedapi.ducks.party',
    'https://api.piped.private.coffee',
  ];

  final http.Client _client;

  /// GETs [path] from the Piped instances, racing them and returning the
  /// first successful JSON object. Throws if every instance fails.
  Future<Map<String, dynamic>> _getJson(String path) =>
      _firstSuccess(instances.map((base) => _fetchInstance(base, path)));

  Future<Map<String, dynamic>> _fetchInstance(
      String base, String path) async {
    final resp = await _client
        .get(Uri.parse('$base$path'))
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception('Piped $base: HTTP ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Piped response');
    }
    return decoded;
  }

  /// Completes with the first future that succeeds; when all fail,
  /// completes with the last error seen.
  static Future<T> _firstSuccess<T>(Iterable<Future<T>> futures) {
    final completer = Completer<T>();
    var pending = 0;
    Object? lastError;
    for (final f in futures) {
      pending++;
      f.then((value) {
        if (!completer.isCompleted) completer.complete(value);
      }).catchError((Object e) {
        lastError = e;
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.completeError(
              lastError ?? StateError('No Piped instances'));
        }
      });
    }
    if (pending == 0) {
      completer.completeError(StateError('No Piped instances'));
    }
    return completer.future;
  }

  Future<List<VideoDetails>> searchVideos(String query,
      {int limit = 25}) async {
    final json = await _getJson(
        '/search?q=${Uri.encodeComponent(query)}&filter=videos');
    final items = (json['items'] as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_searchItemToDetails)
        .where((v) => v.id.isNotEmpty)
        .take(limit)
        .toList();
  }

  Future<VideoDetails> getVideoDetails(String videoId) async {
    final json = await _getJson('/streams/$videoId');
    return _streamsToDetails(videoId, json);
  }

  /// Returns muxed + audio-only URLs from Piped's proxied streams,
  /// shaped exactly like the direct extractor's [PlaybackStreams].
  Future<PlaybackStreams> getPlaybackStreams(String videoId,
      {int maxMuxedHeight = 720, bool preferBestAudio = true}) async {
    final json = await _getJson('/streams/$videoId');

    final videoStreams = (json['videoStreams'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];
    final audioStreams = (json['audioStreams'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];

    final muxed = videoStreams
        .where((s) => s['videoOnly'] != true && _streamUrl(s).isNotEmpty)
        .toList()
      ..sort((a, b) => _heightOf(b).compareTo(_heightOf(a)));
    final muxedPick =
        muxed.where((s) => _heightOf(s) <= maxMuxedHeight).toList();

    final audio = audioStreams
        .where((s) => _streamUrl(s).isNotEmpty)
        .toList()
      ..sort((a, b) => _bitrateOf(b).compareTo(_bitrateOf(a)));

    if (muxedPick.isEmpty || audio.isEmpty) {
      throw Exception('Piped: no playable streams for $videoId');
    }

    final bestMuxed = muxedPick.first;
    final audioPick = preferBestAudio ? audio.first : audio.last;
    return PlaybackStreams(
      videoId: videoId,
      muxedUrl: _streamUrl(bestMuxed),
      muxedHeight: _heightOf(bestMuxed),
      audioOnlyUrl: _streamUrl(audioPick),
      audioBitrate: _bitrateOf(audioPick),
      fetchedAt: DateTime.now(),
    );
  }

  void dispose() => _client.close();

  // --- mapping helpers ---

  static String _streamUrl(Map<String, dynamic> s) =>
      s['url']?.toString() ?? '';

  static int _heightOf(Map<String, dynamic> s) {
    final h = s['height'];
    if (h is num) return h.toInt();
    final q = s['quality']?.toString() ?? '';
    final m = RegExp(r'(\d+)p').firstMatch(q);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    return 0;
  }

  static int _bitrateOf(Map<String, dynamic> s) {
    final b = s['bitrate'];
    return b is num ? b.toInt() : 0;
  }

  static String? _videoIdFromWatchUrl(String url) =>
      Uri.tryParse(url)?.queryParameters['v'];

  static String _channelIdFromUrl(String url) {
    final parts = url.split('/');
    return parts.isNotEmpty ? parts.last : '';
  }

  /// Piped reports durations inconsistently across endpoints
  /// (seconds vs milliseconds); normalize defensively.
  static Duration? _parseDuration(Object? raw) {
    if (raw is! num) return null;
    var seconds = raw.toDouble();
    if (seconds > 100000) seconds /= 1000; // ms -> s
    if (seconds < 0) return null;
    return Duration(seconds: seconds.round());
  }

  /// Piped reports upload dates as relative strings ("7 hours ago",
  /// "Streamed 3 days ago"); convert to an absolute DateTime.
  static DateTime? _parseUploadedDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var s = raw.trim().toLowerCase();
    if (s.startsWith('streamed ')) {
      s = s.substring('streamed '.length).trim();
    }
    final now = DateTime.now();
    if (s == 'just now' || s == 'moments ago') return now;
    final m = RegExp(
            r'(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago')
        .firstMatch(s);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!) ?? 0;
    switch (m.group(2)) {
      case 'second':
        return now.subtract(Duration(seconds: n));
      case 'minute':
        return now.subtract(Duration(minutes: n));
      case 'hour':
        return now.subtract(Duration(hours: n));
      case 'day':
        return now.subtract(Duration(days: n));
      case 'week':
        return now.subtract(Duration(days: n * 7));
      case 'month':
        return now.subtract(Duration(days: n * 30));
      case 'year':
        return now.subtract(Duration(days: n * 365));
    }
    return null;
  }

  static VideoDetails _searchItemToDetails(Map<String, dynamic> item) {
    final id = _videoIdFromWatchUrl(item['url']?.toString() ?? '') ?? '';
    return VideoDetails(
      id: id,
      title: item['title']?.toString() ?? '',
      author: item['uploaderName']?.toString() ?? '',
      channelId: _channelIdFromUrl(item['uploaderUrl']?.toString() ?? ''),
      duration: _parseDuration(item['duration']),
      thumbnailUrl: item['thumbnailUrl']?.toString() ?? '',
      viewCount: (item['views'] as num?)?.toInt(),
      likeCount: null,
      uploadDate: _parseUploadedDate(item['uploadedDate']?.toString()),
      description: '',
    );
  }

  static VideoDetails _streamsToDetails(
      String videoId, Map<String, dynamic> json) {
    DateTime? uploadDate;
    final raw = json['uploadDate']?.toString();
    if (raw != null && raw.isNotEmpty) {
      uploadDate = DateTime.tryParse(raw);
    }
    return VideoDetails(
      id: videoId,
      title: json['title']?.toString() ?? '',
      author: json['uploader']?.toString() ?? '',
      channelId: _channelIdFromUrl(json['uploaderUrl']?.toString() ?? ''),
      duration: _parseDuration(json['duration']),
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
      viewCount: (json['views'] as num?)?.toInt(),
      likeCount: (json['likes'] as num?)?.toInt(),
      uploadDate: uploadDate,
      description: json['description']?.toString() ?? '',
    );
  }
}
