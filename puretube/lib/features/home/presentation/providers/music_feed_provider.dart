import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../player/domain/entities/playback_models.dart';

/// Music feed for the audio-mode home: trending songs fetched through the
/// same extractor (with its Piped fallback). Bangla + Hindi + worldwide
/// queries are merged so the audio home auto-loads a familiar mix.
final musicFeedProvider =
    FutureProvider<List<VideoDetails>>((ref) async {
  final extractor = ref.watch(extractorProvider);
  const queries = [
    'trending bangla gaan',
    'hindi trending songs 2026',
    'trending music 2026',
    'viral songs now',
  ];
  final out = <VideoDetails>[];
  final seen = <String>{};
  for (final q in queries) {
    if (out.length >= 24) break;
    try {
      final vids = await extractor.searchVideos(q, limit: 8);
      for (final v in vids) {
        if (seen.add(v.id)) out.add(v);
        if (out.length >= 24) break;
      }
    } catch (_) {}
  }
  if (out.isEmpty) throw Exception('No songs found');
  return out;
});
