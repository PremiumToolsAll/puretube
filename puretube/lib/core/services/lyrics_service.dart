import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of a lyrics fetch attempt.
class LyricsResult {
  final String? lyrics;
  final String artist;
  final String title;
  final bool found;

  const LyricsResult({
    required this.lyrics,
    required this.artist,
    required this.title,
    required this.found,
  });

  const LyricsResult.notFound({
    required this.artist,
    required this.title,
  })  : lyrics = null,
        found = false;
}

/// Fetches song lyrics from the free lyrics.ovh API.
///
/// Best-effort only: never throws, returns [LyricsResult.notFound] when
/// the API has no lyrics, the network fails, or parsing fails. Must
/// never break playback.
class LyricsService {
  LyricsService({http.Client? client})
      : _client = client ?? http.Client();

  static const _base = 'https://api.lyrics.ovh/v1';

  final http.Client _client;

  /// Tries several artist/title combinations derived from the YouTube
  /// [videoTitle] and [channelName], returning the first successful
  /// lyrics hit.
  Future<LyricsResult> getLyrics({
    required String videoTitle,
    required String channelName,
  }) async {
    for (final attempt in _buildAttempts(videoTitle, channelName)) {
      final lyrics = await _fetch(attempt.artist, attempt.title);
      if (lyrics != null) {
        return LyricsResult(
          lyrics: lyrics,
          artist: attempt.artist,
          title: attempt.title,
          found: true,
        );
      }
    }
    return LyricsResult.notFound(
      artist: _cleanArtist(channelName),
      title: _cleanTitle(videoTitle),
    );
  }

  Future<String?> _fetch(String artist, String title) async {
    if (artist.isEmpty || title.isEmpty) return null;
    final uri = Uri.parse(
        '$_base/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}');
    try {
      final res =
          await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final Map<String, dynamic> data =
          jsonDecode(res.body) as Map<String, dynamic>;
      final lyrics = data['lyrics'] as String?;
      if (lyrics == null || lyrics.trim().isEmpty) return null;
      return lyrics.trim();
    } catch (_) {
      return null;
    }
  }

  /// Candidate (artist, title) pairs, most likely first.
  List<_Attempt> _buildAttempts(String videoTitle, String channelName) {
    final attempts = <_Attempt>[];
    final seen = <String>{};

    void add(String artist, String title) {
      final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
      if (artist.isNotEmpty && title.isNotEmpty && seen.add(key)) {
        attempts.add(_Attempt(artist, title));
      }
    }

    final cleanTitle = _cleanTitle(videoTitle);
    final cleanArtist = _cleanArtist(channelName);

    // 1. Channel name as artist + cleaned video title as song.
    add(cleanArtist, cleanTitle);

    // 2. "Artist - Title" / "Artist – Title" inside the video title.
    for (final sep in [' - ', ' – ', ' — ']) {
      final idx = cleanTitle.indexOf(sep);
      if (idx > 0) {
        add(cleanTitle.substring(0, idx).trim(),
            cleanTitle.substring(idx + sep.length).trim());
      }
    }

    // 3. "Title (feat. X)" style: keep only the part before the feat.
    final featIdx = RegExp(r'\s*\(?feat\.?\s', caseSensitive: false)
        .firstMatch(cleanTitle);
    if (featIdx != null && featIdx.start > 0) {
      add(cleanArtist, cleanTitle.substring(0, featIdx.start).trim());
    }

    return attempts;
  }

  /// Strips common YouTube noise from titles:
  /// (Official Video), [Official Audio], | Artist Name, ft./feat., etc.
  String _cleanTitle(String title) {
    var t = title;
    // Remove bracketed suffixes like (Official Video), [4K], (Lyric Video).
    t = t.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '');
    // Remove trailing "| Channel" / "- Channel" / "• Channel" bits.
    t = t.replaceAll(RegExp(r'\s*[|\-•–—]\s*[^-|•–—]{2,}$'), '');
    // Remove ft./feat. markers (kept as separate attempt too).
    t = t.replaceAll(
        RegExp(r'\s*\(?f(ea)?t\.?\s+[^\)\]]*', caseSensitive: false), '');
    // Collapse whitespace.
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Common filler words that pollute the query.
    for (final noise in [
      'official video',
      'official music video',
      'official audio',
      'official lyric video',
      'lyric video',
      'lyrics video',
      'music video',
      'full video',
      'full song',
      'audio song',
      'video song',
      '4k',
      'hd',
    ]) {
      t = t.replaceAll(
          RegExp('\\b$noise\\b', caseSensitive: false), '');
    }
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Channel names often end with " - Topic", "VEVO", "Official", etc.
  String _cleanArtist(String channel) {
    var c = channel;
    for (final suffix in [
      ' - Topic',
      'VEVO',
      'Official',
      'official',
      'Music',
      'music',
    ]) {
      if (c.endsWith(suffix)) {
        c = c.substring(0, c.length - suffix.length).trim();
      }
    }
    return c.trim();
  }

  void dispose() => _client.close();
}

class _Attempt {
  final String artist;
  final String title;

  _Attempt(this.artist, this.title);
}
