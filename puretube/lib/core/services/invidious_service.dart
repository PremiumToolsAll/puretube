import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/player/domain/entities/playback_models.dart';

/// Invidious API fallback — a second, independent proxy network besides
/// Piped. Used when YouTube rate-limits the device IP AND the Piped
/// instances are unreachable from the device's network.
///
/// Only instances verified live are listed (checked 2026-10-16).
class InvidiousService {
  InvidiousService({http.Client? client})
      : _client = client ?? http.Client();

  /// Verified working 2026-10-16 (api.invidious.io lists a single
  /// healthy API instance right now).
  static const List<String> instances = [
    'https://invidious.f5.si',
  ];

  final http.Client _client;

  Future<dynamic> _getJson(String path) =>
      _firstSuccess(instances.map((base) => _fetchInstance(base, path)));

  Future<dynamic> _fetchInstance(String base, String path) async {
    final resp = await _client
        .get(Uri.parse('$base$path'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('Invidious $base: HTTP ${resp.statusCode}');
    }
    return jsonDecode(resp.body);
  }

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
              lastError ?? StateError('No Invidious instances'));
        }
      });
    }
    if (pending == 0) {
      completer.completeError(StateError('No Invidious instances'));
    }
    return completer.future;
  }

  Future<List<VideoDetails>> searchVideos(String query,
      {int limit = 25}) async {
    final json = await _getJson(
        '/api/v1/search?q=${Uri.encodeComponent(query)}&type=video');
    final items = (json as List?) ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_searchItemToDetails)
        .where((v) => v.id.isNotEmpty)
        .take(limit)
        .toList();
  }

  Future<VideoDetails> getVideoDetails(String videoId) async {
    final json =
        await _getJson('/api/v1/videos/$videoId') as Map<String, dynamic>;
    return _videoToDetails(videoId, json);
  }

  /// Playback streams from Invidious' proxied formats, shaped like the
  /// direct extractor's [PlaybackStreams]. formatStreams are muxed
  /// (audio+video); adaptiveFormats hold the separate audio tracks.
  Future<PlaybackStreams> getPlaybackStreams(String videoId,
      {int maxMuxedHeight = 720, bool preferBestAudio = true}) async {
    final json =
        await _getJson('/api/v1/videos/$videoId') as Map<String, dynamic>;

    final muxed = ((json['formatStreams'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .where((s) => _urlOf(s).isNotEmpty)
                .toList() ??
            const [])
      ..sort((a, b) => _heightOf(b).compareTo(_heightOf(a)));
    final muxedPick =
        muxed.where((s) => _heightOf(s) <= maxMuxedHeight).toList();

    final audio = ((json['adaptiveFormats'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .where((s) =>
                    (s['type']?.toString() ?? '')
                        .startsWith('audio/') &&
                    _urlOf(s).isNotEmpty)
                .toList() ??
            const [])
      ..sort((a, b) => _bitrateOf(b).compareTo(_bitrateOf(a)));

    if (muxedPick.isEmpty) {
      throw Exception('Invidious: no playable streams for $videoId');
    }
    final bestMuxed = muxedPick.first;
    final audioPick =
        audio.isEmpty ? null : (preferBestAudio ? audio.first : audio.last);
    return PlaybackStreams(
      videoId: videoId,
      muxedUrl: _urlOf(bestMuxed),
      muxedHeight: _heightOf(bestMuxed),
      audioOnlyUrl:
          audioPick != null ? _urlOf(audioPick) : _urlOf(bestMuxed),
      audioBitrate:
          audioPick != null ? _bitrateOf(audioPick) : 0,
      fetchedAt: DateTime.now(),
    );
  }

  /// Quality menu from Invidious formats: muxed entries plus video-only
  /// adaptive entries paired with the best audio track.
  Future<List<MuxedQuality>> getQualityOptions(String videoId) async {
    final json =
        await _getJson('/api/v1/videos/$videoId') as Map<String, dynamic>;

    final formats = ((json['formatStreams'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .where((s) => _urlOf(s).isNotEmpty)
            .toList() ??
        const [])
      ..sort((a, b) => _heightOf(b).compareTo(_heightOf(a)));
    final adaptive = (json['adaptiveFormats'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .where((s) => _urlOf(s).isNotEmpty)
            .toList() ??
        const [];
    final audio = adaptive
        .where((s) =>
            (s['type']?.toString() ?? '').startsWith('audio/'))
        .toList()
      ..sort((a, b) => _bitrateOf(b).compareTo(_bitrateOf(a)));

    final seen = <String>{};
    final options = <MuxedQuality>[];
    for (final s in formats) {
      final h = _heightOf(s);
      if (h <= 0 || !seen.add('muxed-$h')) continue;
      options.add(MuxedQuality(
        label: 'MPEG-4 ${h}p',
        height: h,
        url: _urlOf(s),
        fps: _fpsOf(s),
        codec: _shortCodec(s['encoding']?.toString()),
      ));
    }
    if (audio.isNotEmpty) {
      final audioUrl = _urlOf(audio.first);
      final videoOnly = adaptive
          .where((s) => (s['type']?.toString() ?? '')
              .startsWith('video/'))
          .toList()
        ..sort((a, b) => _heightOf(b).compareTo(_heightOf(a)));
      for (final s in videoOnly) {
        final h = _heightOf(s);
        if (h <= 0 || !seen.add('dash-$h')) continue;
        options.add(MuxedQuality(
          label: '${h}p · Invidious',
          height: h,
          url: _urlOf(s),
          audioUrl: audioUrl,
          fps: _fpsOf(s),
          codec: _shortCodec(s['encoding']?.toString()),
        ));
      }
    }
    options.sort((a, b) => b.height.compareTo(a.height));
    return options;
  }

  void dispose() => _client.close();

  // --- mapping helpers ---

  static String _urlOf(Map<String, dynamic> s) =>
      s['url']?.toString() ?? '';

  static int _heightOf(Map<String, dynamic> s) {
    final q = s['qualityLabel']?.toString() ??
        s['quality']?.toString() ??
        '';
    final m = RegExp(r'(\d+)p').firstMatch(q);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    final h = s['height'];
    if (h is num) return h.toInt();
    final res = s['resolution']?.toString() ?? '';
    final m2 = RegExp(r'(\d+)p').firstMatch(res);
    if (m2 != null) return int.tryParse(m2.group(1)!) ?? 0;
    return 0;
  }

  static int _bitrateOf(Map<String, dynamic> s) {
    final b = s['bitrate'];
    return b is num ? b.toInt() : 0;
  }

  static int _fpsOf(Map<String, dynamic> s) {
    final f = s['fps'];
    return f is num ? f.toInt() : 0;
  }

  static String _shortCodec(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return raw.split('.').first.toLowerCase();
  }

  static String _bestThumbnail(Object? raw) {
    if (raw is! List) return '';
    var bestW = -1;
    var best = '';
    for (final t in raw.whereType<Map<String, dynamic>>()) {
      final w = (t['width'] as num?)?.toInt() ?? 0;
      final u = t['url']?.toString() ?? '';
      if (u.isNotEmpty && w >= bestW) {
        bestW = w;
        best = u;
      }
    }
    return best;
  }

  static Duration? _secsToDuration(Object? raw) {
    final n = (raw as num?)?.toInt();
    if (n == null || n <= 0) return null;
    return Duration(seconds: n);
  }

  static VideoDetails _searchItemToDetails(
      Map<String, dynamic> item) {
    return VideoDetails(
      id: item['videoId']?.toString() ?? '',
      title: item['title']?.toString() ?? '',
      author: item['author']?.toString() ?? '',
      channelId: item['authorId']?.toString() ?? '',
      duration: _secsToDuration(item['lengthSeconds']),
      thumbnailUrl: _bestThumbnail(item['videoThumbnails']),
      viewCount: (item['viewCount'] as num?)?.toInt(),
      likeCount: null,
      uploadDate: null,
      description: item['description']?.toString() ?? '',
    );
  }

  static VideoDetails _videoToDetails(
      String videoId, Map<String, dynamic> json) {
    DateTime? published;
    final pub = (json['published'] as num?)?.toInt();
    if (pub != null && pub > 0) {
      published =
          DateTime.fromMillisecondsSinceEpoch(pub * 1000);
    }
    return VideoDetails(
      id: videoId,
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      channelId: json['authorId']?.toString() ?? '',
      duration: _secsToDuration(json['lengthSeconds']),
      thumbnailUrl: _bestThumbnail(json['videoThumbnails']),
      viewCount: (json['viewCount'] as num?)?.toInt(),
      likeCount: (json['likeCount'] as num?)?.toInt(),
      uploadDate: published,
      description: json['description']?.toString() ?? '',
    );
  }
}
