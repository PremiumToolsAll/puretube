import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/youtube_service.dart';
import '../../player/domain/entities/models.dart';

class ShortsState {
  final List<VideoItem> shorts;
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
    List<VideoItem>? shorts,
    int? currentIndex,
    bool? loading,
    String? error,
  }) =>
      ShortsState(
        shorts: shorts ?? this.shorts,
        currentIndex:
            currentIndex ?? this.currentIndex,
        loading: loading ?? this.loading,
        error: error,
      );
}

class ShortsController
    extends Notifier<ShortsState> {
  @override
  ShortsState build() {
    Future.microtask(_load);
    return const ShortsState();
  }

  Future<void> _load() async {
    try {
      // Shorts via search (InnerTube has no dedicated shorts feed).
      final videos = await YoutubeService
          .instance
          .search('#shorts', limit: 30);
      final shorts = videos
          .where((v) =>
              v.duration != null &&
              v.duration!.inSeconds <= 90)
          .map(VideoItem.fromVideo)
          .toList();
      // Fallback: use all if filter is too aggressive.
      final list = shorts.isNotEmpty
          ? shorts
          : videos
              .map(VideoItem.fromVideo)
              .toList();
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
    state =
        state.copyWith(currentIndex: i);
    // Pre-load trigger: nothing extra needed —
    // ShortsPlayerWidget pre-caches neighbors.
  }

  Future<void> retry() async {
    state = state.copyWith(
        loading: true, error: null);
    await _load();
  }
}

final shortsControllerProvider = NotifierProvider<
    ShortsController,
    ShortsState>(ShortsController.new);
