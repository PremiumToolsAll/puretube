import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/error/exceptions.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../search/presentation/widgets/search_filter_sheet.dart';

enum SearchStatus { idle, loading, done, error }

class SearchState {
  final SearchStatus status;
  final String query;
  final List<VideoDetails> results;
  final String? errorMessage;
  final SearchFilters filters;

  const SearchState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.errorMessage,
    this.filters = const SearchFilters(),
  });

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<VideoDetails>? results,
    String? errorMessage,
    SearchFilters? filters,
  }) =>
      SearchState(
        status: status ?? this.status,
        query: query ?? this.query,
        results: results ?? this.results,
        errorMessage: errorMessage,
        filters: filters ?? this.filters,
      );
}

/// Applies SearchFilters as post-filtering on extractor results.
List<VideoDetails> _applyFilters(
    List<VideoDetails> videos, SearchFilters f) {
  if (f.isEmpty) return videos;
  final now = DateTime.now();
  return videos.where((v) {
    // Duration filter.
    if (f.duration != null && v.duration != null) {
      final secs = v.duration!.inSeconds;
      switch (f.duration) {
        case 'short':
          if (secs >= 240) return false;
        case 'medium':
          if (secs < 240 || secs > 1200) return false;
        case 'long':
          if (secs <= 1200) return false;
      }
    }
    // Upload date filter.
    if (f.uploadDate != null && v.uploadDate != null) {
      final diff = now.difference(v.uploadDate!);
      switch (f.uploadDate) {
        case 'hour':
          if (diff.inHours >= 1) return false;
        case 'today':
          if (diff.inDays >= 1) return false;
        case 'week':
          if (diff.inDays >= 7) return false;
        case 'month':
          if (diff.inDays >= 30) return false;
        case 'year':
          if (diff.inDays >= 365) return false;
      }
    }
    // Type filter: extractor only returns videos; non-video types
    // yield no results rather than wrong results.
    if (f.type != null && f.type != 'video') return false;
    return true;
  }).toList();
}

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state =
        state.copyWith(status: SearchStatus.loading, query: q);
    try {
      final results =
          await ref.read(extractorProvider).searchVideos(q);
      state = state.copyWith(
          status: SearchStatus.done,
          results:
              _applyFilters(results, state.filters));
    } on PureTubeException catch (e) {
      state = state.copyWith(
          status: SearchStatus.error, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
          status: SearchStatus.error,
          errorMessage: 'Search failed: $e');
    }
  }

  /// Sets filters and re-runs the current query if there is one.
  Future<void> setFilters(SearchFilters filters) async {
    state = state.copyWith(filters: filters);
    if (state.query.isNotEmpty &&
        state.status == SearchStatus.done) {
      await search(state.query);
    }
  }

  void clear() => state = const SearchState();
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(
        SearchController.new);
