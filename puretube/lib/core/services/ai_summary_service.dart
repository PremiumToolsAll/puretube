import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// AI-generated summary of a YouTube video.
///
/// Best-effort only: never throws, returns null when generation fails.
/// Must never break the player UI.
class AiSummaryService {
  AiSummaryService({http.Client? client, String? geminiApiKey})
      : _client = client ?? http.Client(),
        _geminiApiKey = geminiApiKey;

  static const _pollinationsBase = 'https://text.pollinations.ai';

  final http.Client _client;
  final String? _geminiApiKey;

  /// Summarizes a video in 2-3 sentences.
  ///
  /// Tries Pollinations AI first (free, no key), then Gemini
  /// (only when [geminiApiKey] is set). Returns null on any failure.
  Future<String?> getSummary({
    required String title,
    required String channelName,
    String description = '',
  }) async {
    if (title.trim().isEmpty) return null;
    final desc = description.trim();
    final clippedDesc =
        desc.length > 800 ? '${desc.substring(0, 800)}…' : desc;
    final prompt =
        "Summarize this YouTube video in 2-3 sentences. Title: '$title'. "
        "Channel: '$channelName'. Description: '$clippedDesc'. "
        "Respond in the same language as the title.";

    final fromPollinations = await _summarizeWithPollinations(prompt);
    if (fromPollinations != null) return fromPollinations;
    return _summarizeWithGemini(prompt);
  }

  /// Free, no-API-key AI text generation. Plain-text response.
  Future<String?> _summarizeWithPollinations(String prompt) async {
    final uri = Uri.parse(
        '$_pollinationsBase/${Uri.encodeComponent(prompt)}');
    try {
      final res =
          await _client.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final text = res.body.trim();
      if (text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Gemini AI summarization. Skipped entirely when no API key set.
  Future<String?> _summarizeWithGemini(String prompt) async {
    final key = _geminiApiKey;
    if (key == null || key.isEmpty) return null;
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent?key=$key');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
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
      return text;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
