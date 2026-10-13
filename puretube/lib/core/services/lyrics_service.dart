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
///
/// Fallback order (all best-effort):
/// 1. lyrics.ovh (free, no key)
/// 2. Pollinations AI (free, no key)
/// 3. Gemini AI (only when [geminiApiKey] is set in Settings)
class LyricsService {
  LyricsService({http.Client? client, String? geminiApiKey})
      : _client = client ?? http.Client(),
        _geminiApiKey = geminiApiKey;

  static const _base = 'https://api.lyrics.ovh/v1';
  static const _pollinationsBase = 'https://text.pollinations.ai';

  final http.Client _client;
  final String? _geminiApiKey;

  /// Tries several artist/title combinations derived from the YouTube
  /// [videoTitle] and [channelName], returning the first successful
  /// lyrics hit.
  Future<LyricsResult> getLyrics({
    required String videoTitle,
    required String channelName,
  }) async {
    final attempts = _buildAttempts(videoTitle, channelName);

    // 1. lyrics.ovh (free, no key): try all artist/title combinations.
    for (final attempt in attempts) {
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

    // 2 & 3. AI fallbacks: use the most likely artist/title pair.
    if (attempts.isNotEmpty) {
      final best = attempts.first;
      final aiLyrics = await _fetchFromAi(best.artist, best.title);
      if (aiLyrics != null) {
        return LyricsResult(
          lyrics: aiLyrics,
          artist: best.artist,
          title: best.title,
          found: true,
        );
      }
    }

    return LyricsResult.notFound(
      artist: _cleanArtist(channelName),
      title: _cleanTitle(videoTitle),
    );
  }

  /// AI fallback chain: Pollinations (key-free) first, then Gemini
  /// (only when an API key was provided). Returns null when neither
  /// knows the lyrics.
  Future<String?> _fetchFromAi(String artist, String title) async {
    final fromPollinations = await _fetchFromPollinations(artist, title);
    if (fromPollinations != null) return fromPollinations;
    return _fetchFromGemini(artist, title);
  }

  /// Fallback order for the in-player AI Lyrics card (no user tap),
  /// used AFTER YouTube's own captions/transcript (tried first by the
  /// controller — YouTube's free AI is the primary source):
  /// 1. lyrics.ovh (free, no key) — real published lyrics when available.
  /// 2. Pollinations AI (free, no key) — fallback generator.
  /// 3. Gemini AI — advanced, only when an API key is set in Settings.
  ///
  /// Never throws; refusal/copyright responses are filtered to
  /// [LyricsResult.notFound].
  Future<LyricsResult> getLyricsAuto({
    required String videoTitle,
    required String channelName,
  }) async {
    final attempts = _buildAttempts(videoTitle, channelName);
    if (attempts.isEmpty) {
      return LyricsResult.notFound(
        artist: _cleanArtist(channelName),
        title: _cleanTitle(videoTitle),
      );
    }

    // 1. lyrics.ovh across all artist/title combinations.
    for (final attempt in attempts) {
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

    final best = attempts.first;

    // 2. Pollinations fallback.
    final fromPollinations =
        await _fetchFromPollinations(best.artist, best.title);
    if (fromPollinations != null) {
      return LyricsResult(
        lyrics: fromPollinations,
        artist: best.artist,
        title: best.title,
        found: true,
      );
    }

    // 3. Gemini (advanced — only when the user set an API key).
    final fromGemini = await _fetchFromGemini(best.artist, best.title);
    if (fromGemini != null) {
      return LyricsResult(
        lyrics: fromGemini,
        artist: best.artist,
        title: best.title,
        found: true,
      );
    }

    return LyricsResult.notFound(
      artist: _cleanArtist(channelName),
      title: _cleanTitle(videoTitle),
    );
  }

  /// Free, no-API-key AI text generation. Plain-text response.
  Future<String?> _fetchFromPollinations(
      String artist, String title) async {
    if (artist.isEmpty || title.isEmpty) return null;
    final prompt =
        "Provide the full lyrics for the song '$title' by '$artist'. "
        "If you don't know the lyrics, respond with exactly 'NOT_FOUND'.";
    final uri = Uri.parse(
        '$_pollinationsBase/${Uri.encodeComponent(prompt)}');
    try {
      final res =
          await _client.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final text = res.body.trim();
      if (text.isEmpty) return null;
      final upper = text.toUpperCase();
      if (upper.contains('NOT_FOUND')) return null;
      // AI refusal messages for copyrighted lyrics.
      if (upper.contains("I'M SORRY") ||
          upper.contains("I CAN'T PROVIDE") ||
          upper.contains("CANNOT PROVIDE") ||
          upper.contains("COPYRIGHT")) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Gemini AI lyrics generation. Skipped entirely when no API key set.
  Future<String?> _fetchFromGemini(String artist, String title) async {
    final key = _geminiApiKey;
    if (key == null || key.isEmpty) return null;
    if (artist.isEmpty || title.isEmpty) return null;
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent?key=$key');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text':
                  "Provide the full lyrics for the song '$title' by "
                      "'$artist'. If you don't know the lyrics, respond "
                      "with exactly 'NOT_FOUND'."
            }
          ]
        }
      ]
    });
    try {
      final res = await _client
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: body)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final Map<String, dynamic> data =
          jsonDecode(res.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;
      final content =
          (candidates.first as Map<String, dynamic>)['content']
              as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;
      final text =
          ((parts.first as Map<String, dynamic>)['text'] as String?)
              ?.trim();
      if (text == null || text.isEmpty) return null;
      final upper = text.toUpperCase();
      if (upper.contains('NOT_FOUND')) return null;
      if (upper.contains("I'M SORRY") ||
          upper.contains("I CAN'T PROVIDE") ||
          upper.contains("CANNOT PROVIDE") ||
          upper.contains("COPYRIGHT")) return null;
      return text;
    } catch (_) {
      return null;
    }
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
    // Take only the part before " - " or " | " if the rest looks like
    // artist info (e.g. "Kaho Na Kaho - 8K/ | Emraan Hashmi...").
    final dashIdx = t.indexOf(' - ');
    final pipeIdx = t.indexOf(' | ');
    var cutIdx = -1;
    if (dashIdx > 0 && pipeIdx > 0) {
      cutIdx = dashIdx < pipeIdx ? dashIdx : pipeIdx;
    } else if (dashIdx > 0) {
      cutIdx = dashIdx;
    } else if (pipeIdx > 0) {
      cutIdx = pipeIdx;
    }
    if (cutIdx > 3) {
      t = t.substring(0, cutIdx);
    }
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
