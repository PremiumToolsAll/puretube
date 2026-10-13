import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../player/domain/entities/playback_models.dart';

class ShortsState {
  final List<VideoDetails> shorts;
  final int currentIndex;
  final bool loading;
  final String? error;

  const ShortsState({
    this.shorts = const [],
    this.currentIndex = 0,
    this.loading = true,
    this.error,
  });

  ShortsState copyWith({
    List<VideoDetails>? shorts,
    int? currentIndex,
    bool? loading,
    String? error,
  }) =>
      ShortsState(
        shorts: shorts ?? this.shorts,
        currentIndex: currentIndex ?? this.currentIndex,
        loading: loading ?? this.loading,
        error: error,
      );
}

class ShortsController extends Notifier<ShortsState> {
  @override
  ShortsState build() {
    Future.microtask(_load);
    return const ShortsState();
  }

  Future<void> _load() async {
    try {
      // Shorts via search (no dedicated shorts feed in the extractor).
      // Try multiple queries as fallback for rate limiting.
      List<VideoDetails> videos = [];
      for (final q in ['#shorts', 'shorts', 'short videos']) {
        try {
          videos = await ref
              .read(extractorProvider)
              .searchVideos(q, limit: 30);
          if (videos.isNotEmpty) break;
        } catch (_) {
          continue;
        }
      }
      if (videos.isEmpty) {
        throw Exception('No shorts found');
      }
      final shorts = videos
          .where((v) =>
              v.duration != null &&
              v.duration!.inSeconds <= 90)
          .toList();
      // Fallback: use all if filter is too aggressive.
      final list =
          shorts.isNotEmpty ? shorts : videos;
      state = state.copyWith(
        shorts: list,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString(),
      );
    }
  }

  void setIndex(int i) {
    if (i < 0 || i >= state.shorts.length) return;
    state = state.copyWith(currentIndex: i);
  }

  Future<void> retry() async {
    state =
        state.copyWith(loading: true, error: null);
    await _load();
  }
}

final shortsControllerProvider =
    NotifierProvider<ShortsController, ShortsState>(
        ShortsController.new);
