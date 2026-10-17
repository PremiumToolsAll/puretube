import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../features/player/domain/entities/playback_models.dart';
import 'sabr/sabr_client.dart';

/// Direct YouTube access through a real visitor session.
///
/// YouTube's bot protection (HTTP 429) targets anonymous InnerTube API
/// calls, but serves real visitor sessions fine — the same reason the
/// phone's browser keeps working while anonymous API calls get blocked.
/// This service:
///   1. Fetches the mobile homepage (reachable even when flagged) and
///      extracts the `visitorData` token.
///   2. Calls youtubei/v1/player with the ANDROID app client + that
///      visitor token, exactly like a real session.
/// The ANDROID client returns direct (non-ciphered) stream URLs, so no
/// signature deciphering is needed.
///
/// Verified live 2026-10-16 from a 429-flagged IP: playability OK,
/// muxed 360p + 6 audio tracks with direct URLs.
class YoutubeSessionService {
  YoutubeSessionService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _playerUrl =
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';
  static const _searchUrl =
      'https://www.youtube.com/youtubei/v1/search?prettyPrint=false';
  static const _homeUrl = 'https://m.youtube.com/';

  static const _androidUa =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  static final _visitorRe =
      RegExp(r'"visitorData"\s*:\s*"([^"]+)"');
  static final _heightRe = RegExp(r'(\d+)p');
  static final _codecsRe = RegExp(r'codecs="([^"]+)"');

  String? _visitorData;
  DateTime? _visitorFetchedAt;
  DateTime _lastPlayerCall =
      DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> _androidClient(String visitorData) => {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'androidSdkVersion': 30,
        'userAgent': _androidUa,
        'hl': 'en',
        'gl': 'US',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
        'osName': 'Android',
        'osVersion': '11',
        'visitorData': visitorData,
      };

  /// Returns a cached visitor token, refreshing it from the mobile
  /// homepage when missing or older than 6 hours.
  Future<String> _visitorToken() async {
    final vd = _visitorData;
    final at = _visitorFetchedAt;
    if (vd != null &&
        vd.isNotEmpty &&
        at != null &&
        DateTime.now().difference(at).inHours < 6) {
      return vd;
    }
    final resp = await _client
        .get(Uri.parse(_homeUrl),
            headers: {'User-Agent': _mobileUa})
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception(
          'YouTube session: homepage HTTP ${resp.statusCode}');
    }
    final m = _visitorRe.firstMatch(resp.body);
    final token = m?.group(1);
    if (token == null || token.isEmpty) {
      throw Exception('YouTube session: no visitor token');
    }
    _visitorData = token;
    _visitorFetchedAt = DateTime.now();
    return token;
  }

  Future<Map<String, dynamic>> _playerJson(String videoId) async {
    // Gentle throttle: never hammer the player endpoint.
    final since =
        DateTime.now().difference(_lastPlayerCall);
    if (since.inMilliseconds < 1200) {
      await Future.delayed(
          Duration(milliseconds: 1200 - since.inMilliseconds));
    }
    _lastPlayerCall = DateTime.now();

    final vd = await _visitorToken();
    final body = jsonEncode({
      'context': {'client': _androidClient(vd)},
      'videoId': videoId,
    });
    final resp = await _client
        .post(Uri.parse(_playerUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _androidUa,
              'X-Goog-Visitor-Id': vd,
              'Origin': 'https://www.youtube.com',
            },
            body: body)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception(
          'YouTube session: player HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body);
    if (json is! Map<String, dynamic>) {
      throw Exception('YouTube session: bad player response');
    }
    final status = json['playabilityStatus']
        ?['status']
        ?.toString();
    if (status != 'OK') {
      throw Exception('YouTube session: playability $status');
    }
    return json;
  }

  static List<Map<String, dynamic>> _asMaps(Object? raw) =>
      (raw as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList() ??
      const [];

  static String _runsText(Object? node) {
    if (node is! Map<String, dynamic>) return '';
    final runs = node['runs'];
    if (runs is! List) return node['simpleText']?.toString() ?? '';
    return runs
        .whereType<Map<String, dynamic>>()
        .map((r) => r['text']?.toString() ?? '')
        .join('');
  }

  static int _heightOfLabel(String? label) {
    if (label == null) return 0;
    final m = _heightRe.firstMatch(label);
    return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
  }

  static String _codecOf(String? mimeType) {
    if (mimeType == null) return '';
    final m = _codecsRe.firstMatch(mimeType);
    if (m == null) return '';
    return m.group(1)!.split(',').first.split('.').first.trim();
  }

  static int _num(Object? v) {
    if (v is num) return v.toInt();
    // YouTube sometimes sends numbers as strings ("1827060694").
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static Duration? _secs(Object? v) {
    // YouTube sometimes sends these as strings ("213").
    final n = v is num
        ? v.toInt()
        : int.tryParse(v?.toString() ?? '');
    if (n == null || n <= 0) return null;
    return Duration(seconds: n);
  }

  /// Playback streams through the real visitor session. The ANDROID
  /// client returns direct URLs (no signature deciphering).
  Future<PlaybackStreams> getPlaybackStreams(String videoId,
      {int maxMuxedHeight = 720,
      bool preferBestAudio = true}) async {
    final json = await _playerJson(videoId);
    final sd = json['streamingData'];
    if (sd is! Map<String, dynamic>) {
      throw Exception('YouTube session: no streaming data');
    }

    final muxed = _asMaps(sd['formats'])
        .where((s) => (s['url']?.toString() ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) => _heightOfLabel(b['qualityLabel']?.toString())
          .compareTo(
              _heightOfLabel(a['qualityLabel']?.toString())));
    final muxedPick = muxed
        .where((s) =>
            _heightOfLabel(s['qualityLabel']?.toString()) <=
            maxMuxedHeight)
        .toList();

    final audio = _asMaps(sd['adaptiveFormats'])
        .where((s) =>
            (s['mimeType']?.toString() ?? '')
                .startsWith('audio/') &&
            (s['url']?.toString() ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) =>
          _num(b['bitrate']).compareTo(_num(a['bitrate'])));

    if (muxedPick.isEmpty) {
      throw Exception(
          'YouTube session: no playable streams for $videoId');
    }
    final bestMuxed = muxedPick.first;
    final audioPick = audio.isEmpty
        ? null
        : (preferBestAudio ? audio.first : audio.last);
    return PlaybackStreams(
      videoId: videoId,
      muxedUrl: bestMuxed['url'].toString(),
      muxedHeight:
          _heightOfLabel(bestMuxed['qualityLabel']?.toString()),
      audioOnlyUrl: audioPick != null
          ? audioPick['url'].toString()
          : bestMuxed['url'].toString(),
      audioBitrate:
          audioPick != null ? _num(audioPick['bitrate']) : 0,
      fetchedAt: DateTime.now(),
    );
  }

  /// Quality menu through the real visitor session.
  Future<List<MuxedQuality>> getQualityOptions(
      String videoId) async {
    final json = await _playerJson(videoId);
    final sd = json['streamingData'];
    if (sd is! Map<String, dynamic>) {
      throw Exception('YouTube session: no streaming data');
    }

    final seen = <String>{};
    final options = <MuxedQuality>[];

    final muxed = _asMaps(sd['formats'])
        .where((s) => (s['url']?.toString() ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) => _heightOfLabel(b['qualityLabel']?.toString())
          .compareTo(
              _heightOfLabel(a['qualityLabel']?.toString())));
    for (final s in muxed) {
      final h =
          _heightOfLabel(s['qualityLabel']?.toString());
      if (h <= 0 || !seen.add('muxed-$h')) continue;
      options.add(MuxedQuality(
        label: 'MPEG-4 ${h}p',
        height: h,
        url: s['url'].toString(),
        fps: _num(s['fps']),
        codec: _codecOf(s['mimeType']?.toString()),
      ));
    }

    final audio = _asMaps(sd['adaptiveFormats'])
        .where((s) =>
            (s['mimeType']?.toString() ?? '')
                .startsWith('audio/') &&
            (s['url']?.toString() ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) =>
          _num(b['bitrate']).compareTo(_num(a['bitrate'])));
    if (audio.isNotEmpty) {
      final audioUrl = audio.first['url'].toString();
      final videoOnly = _asMaps(sd['adaptiveFormats'])
          .where((s) =>
              (s['mimeType']?.toString() ?? '')
                  .startsWith('video/') &&
              (s['url']?.toString() ?? '').isNotEmpty)
          .toList()
        ..sort((a, b) =>
            _heightOfLabel(b['qualityLabel']?.toString())
                .compareTo(_heightOfLabel(
                    a['qualityLabel']?.toString())));
      for (final s in videoOnly) {
        final h =
            _heightOfLabel(s['qualityLabel']?.toString());
        final codec = _codecOf(s['mimeType']?.toString());
        // Keep every codec variant (avc/vp9/av1) as a separate entry
        // so the quality menu can offer explicit format choice.
        if (h <= 0 || !seen.add('dash-$h-$codec')) continue;
        options.add(MuxedQuality(
          label: '${h}p',
          height: h,
          url: s['url'].toString(),
          audioUrl: audioUrl,
          fps: _num(s['fps']),
          codec: _codecOf(s['mimeType']?.toString()),
        ));
      }
    }

    // Sort: height desc, then AVC first (recommended), then fps desc.
    int codecRank(String c) {
      final lc = c.toLowerCase();
      if (lc.contains('avc')) return 2;
      if (lc.contains('vp9')) return 1;
      return 0;
    }

    options.sort((a, b) {
      final h = b.height.compareTo(a.height);
      if (h != 0) return h;
      final c = codecRank(b.codec).compareTo(codecRank(a.codec));
      if (c != 0) return c;
      return b.fps.compareTo(a.fps);
    });
    return options;
  }

  /// Video details from the player response's videoDetails.
  Future<VideoDetails> getVideoDetails(String videoId) async {
    final json = await _playerJson(videoId);
    final v = json['videoDetails'];
    if (v is! Map<String, dynamic>) {
      throw Exception('YouTube session: no video details');
    }
    final thumbs = _asMaps(v['thumbnail']?['thumbnails']);
    var bestThumb = '';
    var bestW = -1;
    for (final t in thumbs) {
      final w = _num(t['width']);
      final u = t['url']?.toString() ?? '';
      if (u.isNotEmpty && w >= bestW) {
        bestW = w;
        bestThumb = u;
      }
    }
    return VideoDetails(
      id: v['videoId']?.toString() ?? videoId,
      title: v['title']?.toString() ?? '',
      author: v['author']?.toString() ?? '',
      channelId: v['channelId']?.toString() ?? '',
      duration: _secs(v['lengthSeconds']),
      thumbnailUrl: bestThumb,
      viewCount: _num(v['viewCount']) == 0
          ? null
          : _num(v['viewCount']),
      likeCount: null,
      uploadDate: null,
      description:
          v['shortDescription']?.toString() ?? '',
    );
  }

  /// Search through the real visitor session (ANDROID client returns
  /// compactVideoRenderer items).
  Future<List<VideoDetails>> searchVideos(String query,
      {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final vd = await _visitorToken();
    final body = jsonEncode({
      'context': {'client': _androidClient(vd)},
      'query': q,
    });
    final resp = await _client
        .post(Uri.parse(_searchUrl),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _androidUa,
              'X-Goog-Visitor-Id': vd,
            },
            body: body)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception(
          'YouTube session: search HTTP ${resp.statusCode}');
    }
    final out = <VideoDetails>[];
    final seen = <String>{};
    void walk(dynamic o) {
      if (out.length >= limit) return;
      if (o is Map<String, dynamic>) {
        final r = o['compactVideoRenderer'];
        if (r is Map<String, dynamic>) {
          final v = _compactToDetails(r);
          if (v != null && seen.add(v.id)) out.add(v);
          return;
        }
        for (final x in o.values) {
          walk(x);
          if (out.length >= limit) return;
        }
      } else if (o is List) {
        for (final x in o) {
          walk(x);
          if (out.length >= limit) return;
        }
      }
    }

    walk(jsonDecode(resp.body));
    return out;
  }

  static VideoDetails? _compactToDetails(
      Map<String, dynamic> r) {
    final id = r['videoId']?.toString() ?? '';
    if (id.isEmpty) return null;
    final title = _runsText(r['title']).trim();
    if (title.isEmpty) return null;
    String author = '';
    String channelId = '';
    final byline = r['longBylineText'];
    if (byline is Map<String, dynamic>) {
      final runs = byline['runs'];
      if (runs is List && runs.isNotEmpty) {
        final first = runs.first;
        if (first is Map<String, dynamic>) {
          author = first['text']?.toString() ?? '';
          final nav = first['navigationEndpoint'];
          if (nav is Map<String, dynamic>) {
            final browse = nav['browseEndpoint'];
            if (browse is Map<String, dynamic>) {
              channelId =
                  browse['browseId']?.toString() ?? '';
            }
          }
        }
      }
    }
    Duration? dur;
    final lt = r['lengthText'];
    if (lt is Map<String, dynamic>) {
      final t = lt['simpleText']?.toString() ?? '';
      final parts = t.split(':');
      if (parts.length == 2) {
        dur = Duration(
            minutes: int.tryParse(parts[0]) ?? 0,
            seconds: int.tryParse(parts[1]) ?? 0);
      } else if (parts.length == 3) {
        dur = Duration(
            hours: int.tryParse(parts[0]) ?? 0,
            minutes: int.tryParse(parts[1]) ?? 0,
            seconds: int.tryParse(parts[2]) ?? 0);
      }
    }
    final thumbs = _asMaps(r['thumbnail']?['thumbnails']);
    var bestThumb = '';
    var bestW = -1;
    for (final t in thumbs) {
      final w = _num(t['width']);
      final u = t['url']?.toString() ?? '';
      if (u.isNotEmpty && w >= bestW) {
        bestW = w;
        bestThumb = u;
      }
    }
    return VideoDetails(
      id: id,
      title: title,
      author: author,
      channelId: channelId,
      duration: dur,
      thumbnailUrl: bestThumb,
      viewCount: null,
      likeCount: null,
      uploadDate: null,
      description: '',
    );
  }

  /// SABR streaming info from the player response.
  ///
  /// Returns {'serverAbrStreamingUrl': String,
  ///          'ustreamerConfig': Uint8List,
  ///          'formats': List<Map>} where each format has
  /// itag/mimeType/bitrate/lastModified/xtags.
  /// Throws if SABR is not available for this video/client.
  Future<Map<String, dynamic>> getSabrInfo(String videoId) async {
    final json = await _playerJson(videoId);
    final sd = json['streamingData'];
    if (sd is! Map<String, dynamic>) {
      throw Exception('YouTube session: no streaming data');
    }
    final sabrUrl = sd['serverAbrStreamingUrl']?.toString() ?? '';
    if (sabrUrl.isEmpty) {
      throw Exception('YouTube session: no SABR URL');
    }
    // ustreamer config: base64url in playerConfig.
    Uint8List ustreamerConfig = Uint8List(0);
    try {
      final pc = json['playerConfig'];
      final mcc = pc is Map ? pc['mediaCommonConfig'] : null;
      final usrc = mcc is Map ? mcc['mediaUstreamerRequestConfig'] : null;
      final vpu = usrc is Map
          ? usrc['videoPlaybackUstreamerConfig']
          : null;
      if (vpu is String && vpu.isNotEmpty) {
        var s = vpu.replaceAll('-', '+').replaceAll('_', '/');
        while (s.length % 4 != 0) {
          s += '=';
        }
        ustreamerConfig =
            Uint8List.fromList(base64.decode(s));
      }
    } catch (_) {}

    final formats = <Map<String, dynamic>>[];
    for (final s in _asMaps(sd['adaptiveFormats'])) {
      final itag = _num(s['itag']).toInt();
      final mime = s['mimeType']?.toString() ?? '';
      if (itag <= 0 || mime.isEmpty) continue;
      formats.add({
        'itag': itag,
        'mimeType': mime,
        'bitrate': _num(s['bitrate']).toInt(),
        'lastModified': int.tryParse(
                s['lastModified']?.toString() ?? '') ??
            0,
        'xtags': s['xtags']?.toString() ?? '',
        'isAudio': mime.startsWith('audio/'),
        'height': _heightOfLabel(
            s['size']?.toString() ??
                s['qualityLabel']?.toString()),
      });
    }
    return {
      'serverAbrStreamingUrl': sabrUrl,
      'ustreamerConfig': ustreamerConfig,
      'formats': formats,
    };
  }

  /// Downloads video+audio via SABR and saves to temp files.
  ///
  /// Returns {'videoPath': String, 'audioPath': String} with local file
  /// paths suitable for mpv playback. Throws on failure.
  Future<Map<String, String>> downloadViaSabr({
    required String videoId,
    required int videoItag,
    required int audioItag,
    void Function(int downloaded, int? total)? onProgress,
  }) async {
    final info = await getSabrInfo(videoId);
    final formats = info['formats'] as List<Map<String, dynamic>>;

    Map<String, dynamic>? findFormat(int itag) {
      for (final f in formats) {
        if (f['itag'] == itag) return f;
      }
      return null;
    }

    final videoFormat = findFormat(videoItag);
    final audioFormat = findFormat(audioItag);
    if (videoFormat == null || audioFormat == null) {
      throw Exception('SABR: format not found');
    }

    final sabr = SabrClient();
    try {
      final result = await sabr.download(
        serverAbrStreamingUrl:
            info['serverAbrStreamingUrl'] as String,
        ustreamerConfig:
            info['ustreamerConfig'] as Uint8List,
        videoFormat: videoFormat,
        audioFormat: audioFormat,
        onProgress: onProgress,
      );

      final dir = await getTemporaryDirectory();
      // Use correct container extension based on mimeType.
      final videoMime =
          videoFormat['mimeType'] as String? ?? '';
      final audioMime =
          audioFormat['mimeType'] as String? ?? '';
      final videoExt =
          videoMime.contains('webm') ? 'webm' : 'mp4';
      final audioExt =
          audioMime.contains('webm') ? 'webm' : 'm4a';
      final videoPath =
          '${dir.path}/sabr_${videoId}_v.$videoExt';
      final audioPath =
          '${dir.path}/sabr_${videoId}_a.$audioExt';
      await File(videoPath)
          .writeAsBytes(result.video.toBytes());
      await File(audioPath)
          .writeAsBytes(result.audio.toBytes());
      return {'videoPath': videoPath, 'audioPath': audioPath};
    } finally {
      sabr.dispose();
    }
  }

  void dispose() => _client.close();
}
