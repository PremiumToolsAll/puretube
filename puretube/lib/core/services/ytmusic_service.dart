import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/player/domain/entities/playback_models.dart';

/// YouTube Music (music.youtube.com) InnerTube search, songs filter.
///
/// Unauthenticated — the same public web-client protocol the site uses.
/// Used by the audio home so every song is findable, independent of the
/// youtube.com search path (which shares the same song library anyway).
class YTMusicService {
  YTMusicService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _searchUrl =
      'https://music.youtube.com/youtubei/v1/search?prettyPrint=false';

  /// Base64 protobuf filter: search results limited to songs.
  static const _songsFilterParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  static const _headers = {
    'Content-Type': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    'Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
  };

  static Map<String, dynamic> _contextBody() => {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250101.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
      };

  /// Searches YouTube Music for songs. Returns [VideoDetails] so the
  /// existing player pipeline plays them unchanged (same video IDs as
  /// youtube.com — the libraries are shared).
  ///
  /// The returned page carries a continuation token: pass it to
  /// [loadMoreSongs] for the next batch — effectively endless songs.
  Future<YTMSongPage> searchSongs(String query,
      {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const YTMSongPage(songs: [], continuation: null);
    }
    final body = _contextBody()
      ..['query'] = q
      ..['params'] = _songsFilterParams;
    return _fetchPage(body, limit: limit);
  }

  /// Loads the next batch of songs for a [YTMSongPage.continuation].
  Future<YTMSongPage> loadMoreSongs(String continuation,
      {int limit = 25}) async {
    final body = _contextBody()..['continuation'] = continuation;
    return _fetchPage(body, limit: limit);
  }

  Future<YTMSongPage> _fetchPage(Map<String, dynamic> body,
      {required int limit}) async {
    final resp = await _client
        .post(Uri.parse(_searchUrl),
            headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception(
          'YouTube Music search failed: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body);
    final items = _songItems(json);
    final out = <VideoDetails>[];
    final seen = <String>{};
    for (final it in items) {
      final v = _toVideoDetails(it);
      if (v != null && seen.add(v.id)) out.add(v);
      if (out.length >= limit) break;
    }
    return YTMSongPage(
        songs: out, continuation: _continuationToken(json));
  }

  /// Finds the next-continuation token anywhere in the response.
  static String? _continuationToken(dynamic root) {
    String? found;
    void walk(dynamic o) {
      if (found != null) return;
      if (o is Map<String, dynamic>) {
        final nd = o['nextContinuationData'];
        if (nd is Map<String, dynamic>) {
          final c = nd['continuation']?.toString();
          if (c != null && c.isNotEmpty) {
            found = c;
            return;
          }
        }
        for (final v in o.values) {
          walk(v);
        }
      } else if (o is List) {
        for (final v in o) {
          walk(v);
        }
      }
    }

    walk(root);
    return found;
  }

  /// Collects every musicResponsiveListItemRenderer under song shelves.
  static List<Map<String, dynamic>> _songItems(dynamic root) {
    final out = <Map<String, dynamic>>[];
    void walk(dynamic o) {
      if (o is Map<String, dynamic>) {
        final shelf = o['musicShelfRenderer'];
        if (shelf is Map<String, dynamic>) {
          final contents = shelf['contents'];
          if (contents is List) {
            for (final c in contents) {
              if (c is Map<String, dynamic>) {
                final item =
                    c['musicResponsiveListItemRenderer'];
                if (item is Map<String, dynamic>) {
                  out.add(item);
                }
              }
            }
          }
          return; // don't descend into the shelf twice
        }
        // Continuation responses carry bare musicResponsiveListItemRenderer
        // items (no musicShelfRenderer wrapper) — collect them directly.
        final direct = o['musicResponsiveListItemRenderer'];
        if (direct is Map<String, dynamic>) {
          out.add(direct);
          return;
        }
        for (final v in o.values) {
          walk(v);
        }
      } else if (o is List) {
        for (final v in o) {
          walk(v);
        }
      }
    }

    walk(root);
    return out;
  }

  static String _runsText(dynamic node) {
    if (node is! Map<String, dynamic>) return '';
    final runs = node['runs'];
    if (runs is! List) return node['simpleText']?.toString() ?? '';
    return runs
        .whereType<Map<String, dynamic>>()
        .map((r) => r['text']?.toString() ?? '')
        .join('');
  }

  static Map<String, dynamic>? _flex(
      Map<String, dynamic> item, int index) {
    final cols = item['flexColumns'];
    if (cols is! List || index >= cols.length) return null;
    final c = cols[index];
    if (c is! Map<String, dynamic>) return null;
    final r = c['musicResponsiveListItemFlexColumnRenderer'];
    return r is Map<String, dynamic> ? r : null;
  }

  static Duration? _parseDuration(String s) {
    final parts = s.trim().split(':');
    if (parts.length == 2 || parts.length == 3) {
      final nums = parts.map(int.tryParse).toList();
      if (nums.every((n) => n != null)) {
        if (parts.length == 2) {
          return Duration(
              minutes: nums[0]!, seconds: nums[1]!);
        }
        return Duration(
            hours: nums[0]!,
            minutes: nums[1]!,
            seconds: nums[2]!);
      }
    }
    return null;
  }

  static final _durRe = RegExp(r'^\d{1,3}:\d{2}(:\d{2})?$');

  static VideoDetails? _toVideoDetails(
      Map<String, dynamic> item) {
    // videoId: playlistItemData first, watchEndpoint fallback.
    String? videoId;
    final pid = item['playlistItemData'];
    if (pid is Map<String, dynamic>) {
      videoId = pid['videoId']?.toString();
    }
    final titleFlex = _flex(item, 0);
    final title = _runsText(titleFlex?['text']).trim();
    if ((videoId == null || videoId.isEmpty) &&
        titleFlex != null) {
      final runs = titleFlex['text'] is Map<String, dynamic>
          ? (titleFlex['text']
                  as Map<String, dynamic>)['runs']
          : null;
      if (runs is List && runs.isNotEmpty) {
        final nav = (runs.first
                as Map<String, dynamic>)['navigationEndpoint'];
        if (nav is Map<String, dynamic>) {
          final watch = nav['watchEndpoint'];
          if (watch is Map<String, dynamic>) {
            videoId = watch['videoId']?.toString();
          }
        }
      }
    }
    if (videoId == null ||
        videoId.isEmpty ||
        title.isEmpty) {
      return null;
    }
    // flexColumns[1] runs: [artist, " • ", album, " • ", duration]
    String artist = '';
    Duration? duration;
    final subFlex = _flex(item, 1);
    if (subFlex != null) {
      final text = subFlex['text'];
      if (text is Map<String, dynamic>) {
        final runs = text['runs'];
        if (runs is List && runs.isNotEmpty) {
          artist = (runs.first
                  as Map<String, dynamic>)['text']
                  ?.toString()
                  .trim() ??
              '';
          for (var i = runs.length - 1; i >= 0; i--) {
            final t = (runs[i]
                    as Map<String, dynamic>)['text']
                ?.toString()
                .trim();
            if (t != null && _durRe.hasMatch(t)) {
              duration = _parseDuration(t);
              break;
            }
          }
        }
      }
    }
    // Largest thumbnail.
    String thumb = '';
    final thumbs = item['thumbnail']
        ?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'];
    if (thumbs is List) {
      var bestW = -1;
      for (final t in thumbs) {
        if (t is Map<String, dynamic>) {
          final w = (t['width'] as num?)?.toInt() ?? 0;
          final u = t['url']?.toString() ?? '';
          if (u.isNotEmpty && w >= bestW) {
            bestW = w;
            thumb = u;
          }
        }
      }
    }
    return VideoDetails(
      id: videoId,
      title: title,
      author: artist.isEmpty ? 'YouTube Music' : artist,
      channelId: '',
      duration: duration,
      thumbnailUrl: thumb,
      viewCount: null,
      likeCount: null,
      uploadDate: null,
      description: '',
    );
  }

  void dispose() => _client.close();
}

/// One batch of songs from YouTube Music search, plus the token for
/// the next batch (null when there is nothing more).
class YTMSongPage {
  final List<VideoDetails> songs;
  final String? continuation;

  const YTMSongPage({required this.songs, this.continuation});
}
