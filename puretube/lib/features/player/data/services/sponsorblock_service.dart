import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/models.dart';

/// SponsorBlock integration (sponsor.ajay.app).
/// Auto-skip sponsors, intros, outros, etc.
class SponsorBlockService {
  static const _base = 'https://sponsor.ajay.app';

  /// Categories to skip by default.
  static const defaultCategories = [
    'sponsor',
    'intro',
    'outro',
    'interaction',
    'selfpromo',
  ];

  final http.Client _client;

  SponsorBlockService([http.Client? client])
      : _client = client ?? http.Client();

  /// Fetch skip segments for [videoId].
  Future<List<SponsorSegment>> getSegments(
    String videoId, {
    List<String> categories = defaultCategories,
  }) async {
    try {
      final uri = Uri.parse(
        '$_base/api/skipSegments'
        '?videoID=$videoId'
        '&categories=${categories.map(Uri.encodeComponent).join(',')}',
      );
      final res = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 404) return [];
      if (res.statusCode != 200) return [];
      final data =
          jsonDecode(res.body) as List<dynamic>;
      return data.map((e) {
        final seg = e['segment'] as List<dynamic>;
        return SponsorSegment(
          start: (seg[0] as num).toDouble(),
          end: (seg[1] as num).toDouble(),
          category: e['category'] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() => _client.close();
}
