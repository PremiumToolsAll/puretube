import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/exceptions.dart';
import '../../../player/domain/entities/playback_models.dart';

enum SearchStatus { idle, loading, done, error }

class SearchState {
  final SearchStatus status;
  final String query;
  final List<VideoDetails> results;
  final String? errorMessage;

  const SearchState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.errorMessage,
  });

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<VideoDetails>? results,
    String? errorMessage,
  }) =>
      SearchState(
        status: status ?? this.status,
        query: query ?? this.query,
        results: results ?? this.results,
        errorMessage: errorMessage,
      );
}

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() {
    // Auto-load trending on startup.
    Future.microtask(() => loadTrending());
    return const SearchState();
  }

  /// Get search suggestions for autocomplete.
  Future<List<String>> getSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      return await ref
          .read(extractorProvider)
          .getSearchSuggestions(q);
    } catch (_) {
      return [];
    }
  }

  Future<void> loadTrending() async {
    state = state.copyWith(status: SearchStatus.loading, query: '');
    try {
      final results =
          await ref.read(extractorProvider).getTrendingVideos();
      state = state.copyWith(
          status: SearchStatus.done, results: results);
    } on PureTubeException catch (e) {
      state = state.copyWith(
          status: SearchStatus.error, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
          status: SearchStatus.error,
          errorMessage: 'Failed to load: $e');
    }
  }

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state =
        state.copyWith(status: SearchStatus.loading, query: q);
    try {
      final results =
          await ref.read(extractorProvider).searchVideos(q);
      state = state.copyWith(
          status: SearchStatus.done, results: results);
    } on PureTubeException catch (e) {
      state = state.copyWith(
          status: SearchStatus.error, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
          status: SearchStatus.error,
          errorMessage: 'Search failed: $e');
    }
  }

  void clear() => state = const SearchState();
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(
        SearchController.new);
