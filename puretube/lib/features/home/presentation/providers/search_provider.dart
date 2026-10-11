import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/services/audio_player_service.dart';
import '../../../../core/services/youtube_service.dart';
import '../../../player/domain/entities/models.dart';

/// Singleton audio handler (initialized in main).
final audioHandlerProvider =
    Provider<PureTubeAudioHandler>((_) {
  throw UnimplementedError(
      'audioHandlerProvider must be overridden in main()');
});

final youtubeServiceProvider =
    Provider<YoutubeService>((_) => YoutubeService.instance);

enum SearchStatus { idle, loading, done, error }

class SearchState {
  final SearchStatus status;
  final String query;
  final List<VideoItem> results;
  final String? error;

  const SearchState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.error,
  });

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<VideoItem>? results,
    String? error,
  }) =>
      SearchState(
        status: status ?? this.status,
        query: query ?? this.query,
        results: results ?? this.results,
        error: error,
      );
}

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() {
    Future.microtask(_loadTrending);
    return const SearchState();
  }

  YoutubeService get _yt =>
      ref.read(youtubeServiceProvider);

  Future<void> _loadTrending() async {
    state = state.copyWith(status: SearchStatus.loading);
    try {
      final videos = await _yt.trending(limit: 30);
      state = state.copyWith(
        status: SearchStatus.done,
        results:
            videos.map(VideoItem.fromVideo).toList(),
      );
    } catch (e) {
      state = state.copyWith(
        status: SearchStatus.error,
        error: e.toString(),
      );
    }
  }

  Future<void> retry() => _loadTrending();

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state = state.copyWith(
        status: SearchStatus.loading, query: q);
    try {
      final videos = await _yt.search(q, limit: 30);
      state = state.copyWith(
        status: SearchStatus.done,
        results:
            videos.map(VideoItem.fromVideo).toList(),
      );
    } catch (e) {
      state = state.copyWith(
        status: SearchStatus.error,
        error: e.toString(),
      );
    }
  }

  Future<List<String>> suggestions(String query) =>
      _yt.searchSuggestions(query);

  void clear() => state = const SearchState();
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(
        SearchController.new);
