import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../player/domain/entities/playback_models.dart';

/// Music feed for the audio-mode home: trending songs fetched through the
/// same extractor (with its Piped fallback), merged from music queries.
final musicFeedProvider =
    FutureProvider<List<VideoDetails>>((ref) async {
  final extractor = ref.watch(extractorProvider);
  const queries = ['trending music', 'top songs 2026'];
  final out = <VideoDetails>[];
  final seen = <String>{};
  for (final q in queries) {
    try {
      final vids = await extractor.searchVideos(q, limit: 12);
      for (final v in vids) {
        if (seen.add(v.id)) out.add(v);
      }
    } catch (_) {}
  }
  if (out.isEmpty) throw Exception('No songs found');
  return out;
});
