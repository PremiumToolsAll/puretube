import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../../core/database/hive_setup.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/services/watch_category_tracker.dart';
import '../../../../core/services/youtube_extractor_service.dart';
import '../../../library/domain/entities/library_models.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../search/presentation/widgets/search_filter_sheet.dart';

enum SearchStatus { idle, loading, done, error }

class SearchState {
  final SearchStatus status;
  final String query;
  final List<VideoDetails> results;
  final String? errorMessage;
  final SearchFilters filters;
  final bool loadingMore;
  final bool hasMore;

  const SearchState({
    this.status = SearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.errorMessage,
    this.filters = const SearchFilters(),
    this.loadingMore = false,
    this.hasMore = true,
  });

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<VideoDetails>? results,
    String? errorMessage,
    SearchFilters? filters,
    bool? loadingMore,
    bool? hasMore,
  }) =>
      SearchState(
        status: status ?? this.status,
        query: query ?? this.query,
        results: results ?? this.results,
        errorMessage: errorMessage,
        filters: filters ?? this.filters,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
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
  SearchSession? _session;

  /// Rotating trending query variants so each feed refresh surfaces
  /// genuinely different videos instead of the same list.
  static const _feedQueries = [
    'trending videos',
    'popular videos 2026',
    'viral videos now',
    'top music videos',
    'trending now worldwide',
  ];
  int _feedQueryIndex = 0;
  bool _rotatedThisSession = false;

  static const _feedCacheKey = 'home_feed_cache_v1';
  static const _feedIndexKey = 'home_feed_query_index';

  @override
  SearchState build() {
    // Restore the persisted rotation so the feed does not restart
    // from the same query on every app launch.
    try {
      final saved = Hive.box(HiveBoxes.playerPrefs).get(_feedIndexKey);
      if (saved is num) {
        _feedQueryIndex = saved.toInt() % _feedQueries.length;
      }
    } catch (_) {}
    return const SearchState();
  }

  // ---- home-feed cache (instant app open) ----

  List<VideoDetails> _readFeedCache() {
    try {
      final raw = Hive.box(HiveBoxes.playerPrefs).get(_feedCacheKey);
      if (raw is! String || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => _videoFromCache(Map<String, dynamic>.from(e as Map)))
          .where((v) => v.id.isNotEmpty && v.title.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeFeedCache(List<VideoDetails> videos) async {
    try {
      final data = videos.take(30).map(_videoToCache).toList();
      await Hive.box(HiveBoxes.playerPrefs)
          .put(_feedCacheKey, jsonEncode(data));
    } catch (_) {}
  }

  Map<String, dynamic> _videoToCache(VideoDetails v) => {
        'id': v.id,
        'title': v.title,
        'author': v.author,
        'channelId': v.channelId,
        'durationMs': v.duration?.inMilliseconds,
        'thumbnailUrl': v.thumbnailUrl,
        'viewCount': v.viewCount,
        'likeCount': v.likeCount,
        'uploadDate': v.uploadDate?.toIso8601String(),
        'description':
            v.description.length > 200 ? v.description.substring(0, 200) : v.description,
      };

  VideoDetails _videoFromCache(Map<String, dynamic> m) => VideoDetails(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        author: m['author'] as String? ?? '',
        channelId: m['channelId'] as String? ?? '',
        duration: (m['durationMs'] as num?) != null
            ? Duration(milliseconds: (m['durationMs'] as num).toInt())
            : null,
        thumbnailUrl: m['thumbnailUrl'] as String? ?? '',
        viewCount: (m['viewCount'] as num?)?.toInt(),
        likeCount: (m['likeCount'] as num?)?.toInt(),
        uploadDate: m['uploadDate'] != null
            ? DateTime.tryParse(m['uploadDate'] as String)
            : null,
        description: m['description'] as String? ?? '',
      );

  /// Pull-to-refresh / refresh button: reloads the home feed with a
  /// rotated trending query and a shuffled order, so every refresh
  /// shows new videos.
  Future<void> refreshFeed() async {
    _feedQueryIndex =
        (_feedQueryIndex + 1) % _feedQueries.length;
    await _loadTrendingWith(_feedQueries[_feedQueryIndex],
        shuffle: true);
  }

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _session = null;
    state = state.copyWith(
        status: SearchStatus.loading,
        query: q,
        loadingMore: false,
        hasMore: true);
    try {
      final session = await ref
          .read(extractorProvider)
          .startPagedSearch(q, limit: 25);
      _session = session;
      state = state.copyWith(
        status: SearchStatus.done,
        results: _applyFilters(session.firstPage, state.filters),
        hasMore: session.firstPage.isNotEmpty,
      );
    } on PureTubeException catch (e) {
      state = state.copyWith(
          status: SearchStatus.error, errorMessage: e.message);
    } catch (e) {
      state = state.copyWith(
          status: SearchStatus.error,
          errorMessage: 'Search failed: $e');
    }
  }

  /// Loads the next page of results (infinite scroll).
  Future<void> loadMore() async {
    final session = _session;
    if (session == null ||
        state.loadingMore ||
        !state.hasMore ||
        state.status != SearchStatus.done) {
      return;
    }
    state = state.copyWith(loadingMore: true);
    try {
      final more = await ref
          .read(extractorProvider)
          .fetchMoreSearchResults(session, limit: 25);
      final filtered = _applyFilters(more, state.filters);
      // Deduplicate by video id.
      final seen = {for (final v in state.results) v.id};
      final fresh =
          filtered.where((v) => seen.add(v.id)).toList();
      state = state.copyWith(
        results: [...state.results, ...fresh],
        loadingMore: false,
        hasMore: more.isNotEmpty,
      );
    } catch (_) {
      // Silent: keep existing results, allow retry on next scroll.
      state = state.copyWith(loadingMore: false);
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

  /// Loads the default home feed on app startup.
  /// Mixes trending results with personalized suggestions derived from
  /// watch history (Bug 3: smart suggestions).
  ///
  /// The rotation advances once per app session and is persisted, so
  /// every app open starts from a DIFFERENT feed query; the last feed
  /// is shown instantly from cache while fresh results load behind it.
  Future<void> loadTrending() async {
    if (!_rotatedThisSession) {
      _rotatedThisSession = true;
      _feedQueryIndex =
          (_feedQueryIndex + 1) % _feedQueries.length;
      try {
        await Hive.box(HiveBoxes.playerPrefs)
            .put(_feedIndexKey, _feedQueryIndex);
      } catch (_) {}
    }
    await _loadTrendingWith(_feedQueries[_feedQueryIndex],
        shuffle: true, cachedFirst: true);
  }

  /// Shared feed loader. When [shuffle] is true (refresh path), the
  /// mixed results are shuffled so every refresh shows new videos.
  /// When [cachedFirst] is true, the cached feed is displayed
  /// immediately and fresh results replace it when they arrive.
  Future<void> _loadTrendingWith(String feedQuery,
      {bool shuffle = false, bool cachedFirst = false}) async {
    if (state.status == SearchStatus.loading) return;
    _session = null;
    var showedCache = false;
    if (cachedFirst && state.results.isEmpty) {
      final cached = _readFeedCache();
      if (cached.isNotEmpty) {
        showedCache = true;
        state = state.copyWith(
            status: SearchStatus.done,
            query: '',
            results: cached,
            loadingMore: false,
            hasMore: true);
      }
    }
    if (!showedCache) {
      state = state.copyWith(
          status: SearchStatus.loading,
          query: '',
          loadingMore: false,
          hasMore: true);
    }
    try {
      final extractor = ref.read(extractorProvider);
      final session =
          await extractor.startPagedSearch(feedQuery, limit: 25);
      _session = session;
      var results = session.firstPage;

      // Smart suggestions: pull keywords from recent watch history
      // and fetch a few related videos to personalize the feed.
      // Also searches the user's top watch categories (waz, gazal,
      // music, …) so the home feed follows what they actually watch.
      try {
        final history =
            ref.read(historyRepositoryProvider).getAll();
        if (history.isNotEmpty) {
          final keywords = _keywordsFromHistory(history, 3);
          final queries = <String>[...keywords];
          for (final cat in await WatchCategoryTracker.top(2)) {
            final kws =
                WatchCategoryTracker.categoryKeywords[cat];
            if (kws != null && kws.isNotEmpty) {
              queries.add(kws.first);
            }
          }
          // Fetch all personalization queries in PARALLEL — doing
          // them one by one was a big part of the slow home load.
          final personalized = <VideoDetails>[];
          final pages = await Future.wait(queries.take(5).map((kw) async {
            try {
              return await extractor.searchVideos(kw, limit: 6);
            } catch (_) {
              return <VideoDetails>[];
            }
          }));
          for (final vids in pages) {
            personalized.addAll(vids);
          }
          // Interleave: 2 trending, 1 personalized, ...
          if (personalized.isNotEmpty) {
            final seen = {for (final v in results) v.id};
            final fresh =
                personalized.where((v) => seen.add(v.id)).toList();
            final mixed = <VideoDetails>[];
            var pi = 0;
            for (var i = 0; i < results.length; i++) {
              mixed.add(results[i]);
              if (i % 2 == 1 && pi < fresh.length) {
                mixed.add(fresh[pi++]);
              }
            }
            while (pi < fresh.length) {
              mixed.add(fresh[pi++]);
            }
            results = mixed;
          }
        }
      } catch (_) {}

      if (shuffle) {
        results = [...results]..shuffle();
      }

      state = state.copyWith(
        status: SearchStatus.done,
        results: results,
        hasMore: session.firstPage.isNotEmpty,
      );
      // Remember this feed so the next app open shows videos
      // instantly instead of a loading shimmer.
      unawaited(_writeFeedCache(results));
    } on PureTubeException catch (e) {
      // With the cached feed already on screen, a failed refresh
      // keeps the cache instead of replacing it with an error.
      if (!showedCache) {
        state = state.copyWith(
            status: SearchStatus.error, errorMessage: e.message);
      }
    } catch (e) {
      if (!showedCache) {
        state = state.copyWith(
            status: SearchStatus.error,
            errorMessage: 'Could not load home feed: $e');
      }
    }
  }

  /// Extracts up to [max] search keywords from watch-history titles.
  /// Picks the most frequent significant words.
  List<String> _keywordsFromHistory(
      List<HistoryEntry> history, int max) {
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for',
      'with', 'by', 'at', 'from', 'is', 'are', 'was', 'be', 'it',
      'this', 'that', 'vs', '|', '-', '&', 'official', 'video',
      'full', 'new', 'best', 'top', 'hd', '4k',
    };
    final counts = <String, int>{};
    for (final entry in history.take(20)) {
      final words = entry.title
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.length > 2 && !stopWords.contains(w));
      for (final w in words) {
        counts[w] = (counts[w] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(max).map((e) => e.key).toList();
  }

  void clear() {
    _session = null;
    state = const SearchState();
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(
        SearchController.new);
