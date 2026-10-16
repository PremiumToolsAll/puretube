import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../player/domain/entities/playback_models.dart';

/// ---------------------------------------------------------------------------
/// Audio-home music feed: many songs, paged in as you scroll.
/// ---------------------------------------------------------------------------

class MusicFeedState {
  final List<VideoDetails> songs;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final bool hasMore;

  const MusicFeedState({
    this.songs = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.hasMore = true,
  });

  MusicFeedState copyWith({
    List<VideoDetails>? songs,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool? hasMore,
  }) =>
      MusicFeedState(
        songs: songs ?? this.songs,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
        hasMore: hasMore ?? this.hasMore,
      );
}

class MusicFeedController extends StateNotifier<MusicFeedState> {
  MusicFeedController(this._ref) : super(const MusicFeedState());

  final Ref _ref;

  /// Feed queries — Bangla, Hindi and worldwide. Loaded a few at a time so
  /// the audio home fills with hundreds of songs as you scroll.
  static const _queries = [
    'trending bangla gaan',
    'hindi trending songs 2026',
    'trending english songs',
    'viral songs now',
    'top bangla romantic songs',
    'punjabi hit songs',
    'tamil trending songs',
    'lofi chill songs',
    'bangla folk songs',
    'hindi old is gold songs',
    'english pop hits 2026',
    'top item songs',
  ];

  static const _batchSize = 3; // queries per page
  static const _perQuery = 12; // songs per query

  int _next = 0;
  bool _busy = false;

  Future<List<VideoDetails>> _fetchQuery(String q) async {
    final ytm = _ref.read(ytMusicProvider);
    try {
      final page = await ytm.searchSongs(q, limit: _perQuery);
      if (page.songs.isNotEmpty) return page.songs;
    } catch (_) {}
    // Fallback: regular extractor search (has its own Piped fallback).
    try {
      return await _ref
          .read(extractorProvider)
          .searchVideos(q, limit: _perQuery);
    } catch (_) {
      return const [];
    }
  }

  Future<void> loadInitial() async {
    if (_busy || state.songs.isNotEmpty) return;
    _busy = true;
    state = state.copyWith(loading: true, error: null);
    _next = 0;
    await _loadBatch(isFirst: true);
    _busy = false;
  }

  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.loading) return;
    _busy = true;
    state = state.copyWith(loadingMore: true);
    await _loadBatch();
    state = state.copyWith(loadingMore: false);
    _busy = false;
  }

  Future<void> _loadBatch({bool isFirst = false}) async {
    final out = <VideoDetails>[];
    final seen = state.songs.map((s) => s.id).toSet();
    var taken = 0;
    while (taken < _batchSize && _next < _queries.length) {
      final songs = await _fetchQuery(_queries[_next]);
      _next++;
      taken++;
      for (final s in songs) {
        if (seen.add(s.id)) out.add(s);
      }
      // Progressive: show songs as each query lands.
      if (out.isNotEmpty) {
        state = state.copyWith(
          songs: [...state.songs, ...out],
          loading: false,
        );
        out.clear();
      }
    }
    final hasMore = _next < _queries.length;
    state = state.copyWith(
      loading: false,
      hasMore: hasMore,
      error: state.songs.isEmpty && !hasMore
          ? 'No songs found. Pull to retry.'
          : null,
    );
    if (isFirst && state.songs.isEmpty && !hasMore) {
      state = state.copyWith(
          error: 'No songs found. Pull to retry.');
    }
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    state = const MusicFeedState(loading: true);
    _next = 0;
    await _loadBatch(isFirst: true);
    _busy = false;
  }
}

final musicFeedProvider =
    StateNotifierProvider<MusicFeedController, MusicFeedState>(
        (ref) => MusicFeedController(ref));

/// ---------------------------------------------------------------------------
/// Audio-mode song search: YouTube Music, endless pages via continuations.
/// ---------------------------------------------------------------------------

class AudioSearchState {
  final String query;
  final List<VideoDetails> songs;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final bool hasMore;
  final bool active; // a search was submitted

  const AudioSearchState({
    this.query = '',
    this.songs = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.hasMore = true,
    this.active = false,
  });

  AudioSearchState copyWith({
    String? query,
    List<VideoDetails>? songs,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool? hasMore,
    bool? active,
  }) =>
      AudioSearchState(
        query: query ?? this.query,
        songs: songs ?? this.songs,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
        hasMore: hasMore ?? this.hasMore,
        active: active ?? this.active,
      );
}

class AudioSearchController extends StateNotifier<AudioSearchState> {
  AudioSearchController(this._ref)
      : super(const AudioSearchState());

  final Ref _ref;
  String? _continuation;
  bool _busy = false;
  int _token = 0;

  Future<void> search(String q) async {
    final query = q.trim();
    if (query.isEmpty || _busy) return;
    _busy = true;
    final myToken = ++_token;
    _continuation = null;
    state = AudioSearchState(
        query: query, loading: true, active: true);
    try {
      // Audio search shows songs ONLY (YouTube Music) — no video
      // results mixed in.
      final page =
          await _ref.read(ytMusicProvider).searchSongs(query);
      if (myToken != _token) return;
      _continuation = page.continuation;
      state = state.copyWith(
        songs: page.songs,
        loading: false,
        hasMore: page.continuation != null,
        error: page.songs.isEmpty ? 'No songs found.' : null,
      );
    } catch (_) {
      if (myToken != _token) return;
      state = state.copyWith(
          loading: false, error: 'Search failed. Try again.');
    }
    _busy = false;
  }

  Future<void> loadMore() async {
    final cont = _continuation;
    if (_busy || !state.hasMore || state.loading || cont == null) {
      return;
    }
    _busy = true;
    state = state.copyWith(loadingMore: true);
    try {
      final page =
          await _ref.read(ytMusicProvider).loadMoreSongs(cont);
      _continuation = page.continuation;
      final seen = state.songs.map((s) => s.id).toSet();
      final fresh =
          page.songs.where((s) => seen.add(s.id)).toList();
      state = state.copyWith(
        songs: [...state.songs, ...fresh],
        loadingMore: false,
        hasMore: page.continuation != null,
      );
    } catch (_) {
      // Keep hasMore true so scrolling (or the Load more button)
      // retries — a transient failure must not end pagination.
      state = state.copyWith(loadingMore: false, hasMore: true);
    }
    _busy = false;
  }

  void clear() {
    _token++;
    _continuation = null;
    _busy = false;
    state = const AudioSearchState();
  }
}

final audioSongSearchProvider =
    StateNotifierProvider<AudioSearchController, AudioSearchState>(
        (ref) => AudioSearchController(ref));
