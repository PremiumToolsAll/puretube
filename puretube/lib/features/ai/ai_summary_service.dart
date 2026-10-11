import 'dart:convert';

import 'package:http/http.dart' as http;

/// AI video summary service.
/// Uses Google Gemini API (user provides API key in settings).
/// Falls back to a local heuristic summary when no key is set.
class AiSummaryService {
  AiSummaryService._();
  static final AiSummaryService instance =
      AiSummaryService._();

  String? _apiKey;
  final _client = http.Client();

  void setApiKey(String? key) {
    _apiKey = key?.trim().isEmpty == true
        ? null
        : key?.trim();
  }

  bool get hasApiKey =>
      _apiKey != null && _apiKey!.isNotEmpty;

  /// Generate a 3-bullet summary for a video.
  Future<List<String>> summarize({
    required String title,
    required String author,
    required String description,
    List<String> transcriptLines = const [],
  }) async {
    if (hasApiKey) {
      try {
        return await _geminiSummary(
            title, author, description);
      } catch (_) {
        // Fall through to heuristic.
      }
    }
    return _heuristicSummary(
        title, author, description,
        transcriptLines);
  }

  Future<List<String>> _geminiSummary(
    String title,
    String author,
    String description,
  ) async {
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_apiKey');
    final prompt =
        'Summarize this YouTube video in exactly 3 short bullet points. '
        'Title: $title. Channel: $author. '
        'Description: ${description.length > 2000 ? description.substring(0, 2000) : description}';
    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'maxOutputTokens': 300,
            },
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception(
          'Gemini API error: ${res.statusCode}');
    }
    final data =
        jsonDecode(res.body)
            as Map<String, dynamic>;
    final text =
        ((data['candidates'] as List).first['content']
                ['parts'] as List)
            .first['text'] as String;
    return text
        .split('\n')
        .map((l) => l
            .trim()
            .replaceAll(
                RegExp(r'^[\-\*•\d\.\)\s]+'), ''))
        .where((l) => l.isNotEmpty)
        .take(3)
        .toList();
  }

  /// Local heuristic when no API key: extract key sentences.
  List<String> _heuristicSummary(
    String title,
    String author,
    String description,
    List<String> transcriptLines,
  ) {
    final points = <String>[];
    points.add(
        '"$title" by $author covers the main topic in detail.');
    // First meaningful description lines.
    final descLines = description
        .split('\n')
        .map((l) => l.trim())
        .where((l) =>
            l.length > 40 &&
            !l.startsWith('http') &&
            !l.startsWith('#'))
        .take(2)
        .toList();
    points.addAll(descLines);
    while (points.length < 3) {
      points.add(
          'Watch the full video for complete details and demonstrations.');
    }
    return points.take(3).toList();
  }

  /// Auto-generate chapters from transcript keywords.
  List<AiChapter> suggestChapters(
      List<TranscriptLine> transcript) {
    if (transcript.isEmpty) return [];
    final chapters = <AiChapter>[];
    const keywords = [
      'introduction',
      'intro',
      'overview',
      'getting started',
      'tutorial',
      'demo',
      'example',
      'conclusion',
      'summary',
      'outro',
      'next steps',
      'tips',
      'q&a',
    ];
    AiChapter? current;
    for (final line in transcript) {
      final lower =
          line.text.toLowerCase();
      final hit = keywords.any(
          (k) => lower.contains(k));
      if (hit &&
          (current == null ||
              line.start -
                      current.start >
                  const Duration(
                      minutes: 1))) {
        current = AiChapter(
          title: _titleCase(line.text
              .split(' ')
              .take(5)
              .join(' ')),
          start: line.start,
        );
        chapters.add(current);
        if (chapters.length >= 8) break;
      }
    }
    // Always include start.
    if (chapters.isEmpty ||
        chapters.first.start >
            const Duration(seconds: 5)) {
      chapters.insert(
          0,
          const AiChapter(
              title: 'Start',
              start: Duration.zero));
    }
    return chapters;
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() +
        s.substring(1);
  }

  void dispose() => _client.close();
}

class TranscriptLine {
  final Duration start;
  final String text;

  const TranscriptLine({
    required this.start,
    required this.text,
  });
}

class AiChapter {
  final String title;
  final Duration start;

  const AiChapter({
    required this.title,
    required this.start,
  });
}
