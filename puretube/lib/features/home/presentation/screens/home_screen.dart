import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import '../../../player/presentation/providers/player_controller.dart';
import '../../../shorts/presentation/screens/shorts_screen.dart';
import '../providers/home_mode_provider.dart';
import '../providers/home_sections_provider.dart';
import '../providers/music_feed_provider.dart';
import '../providers/search_provider.dart';
import '../../../../core/di/providers.dart';
import '../../../player/presentation/widgets/mini_player_bar.dart';
import '../widgets/audio_home.dart';
import '../widgets/video_card.dart';
import '../../../player/presentation/providers/popup_visibility.dart';
import '../../../library/presentation/screens/downloads_screen.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/screens/history_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  // Live search suggestions (SparkTube-style): while typing, a
  // merged list — matching watch-history entries first, then
  // YouTube's suggestions — replaces the feed under the search box.
  Timer? _suggestDebounce;
  List<({String text, bool fromHistory})> _suggestions = const [];
  bool _suggesting = false;
  int _suggestToken = 0;

  void _onSearchChanged(String value) {
    final q = value.trim();
    _suggestDebounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _suggesting = false;
        _suggestions = const [];
      });
      return;
    }
    setState(() {
      _suggesting = true;
      _suggestions = _historyMatches(q);
    });
    final token = ++_suggestToken;
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () async {
      final fetched =
          await ref.read(extractorProvider).getSearchSuggestions(q);
      if (!mounted || token != _suggestToken) return;
      if (_searchController.text.trim() != q) return;
      final merged = <({String text, bool fromHistory})>[
        ..._historyMatches(q),
      ];
      final seen = merged.map((e) => e.text.toLowerCase()).toSet();
      for (final f in fetched) {
        if (seen.add(f.toLowerCase())) {
          merged.add((text: f, fromHistory: false));
        }
      }
      setState(() => _suggestions = merged.take(12).toList());
    });
  }

  /// Watched-video titles containing the query — the local half of
  /// the merged suggestion list (history icon rows).
  List<({String text, bool fromHistory})> _historyMatches(String q) {
    try {
      final entries = ref.read(historyRepositoryProvider).getAll();
      final lower = q.toLowerCase();
      final seen = <String>{};
      final out = <({String text, bool fromHistory})>[];
      for (final e in entries) {
        final t = e.title.trim();
        if (t.isEmpty || !t.toLowerCase().contains(lower)) continue;
        if (seen.add(t.toLowerCase())) {
          out.add((text: t, fromHistory: true));
        }
        if (out.length >= 3) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  void _fillSuggestion(String text) {
    _searchController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _onSearchChanged(text);
  }

  void _runSuggestion(String text) {
    _suggestDebounce?.cancel();
    setState(() => _suggesting = false);
    _searchController.text = text;
    _search(text);
  }

  Widget _buildSuggestionList() {
    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _suggestions.length,
      itemBuilder: (ctx, i) {
        final s = _suggestions[i];
        return ListTile(
          leading: Icon(
            s.fromHistory ? Icons.history : Icons.search,
            color: Colors.grey,
            size: 20,
          ),
          title: Text(
            s.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.north_west, color: Colors.grey, size: 18),
            onPressed: () => _fillSuggestion(s.text),
          ),
          onTap: () => _runSuggestion(s.text),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Auto-load the home feed so videos appear on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(searchControllerProvider.notifier).loadTrending();
        // Preload the audio-mode music feed too, so switching to
        // audio mode shows songs instantly.
        ref.read(musicFeedProvider);
        // Preload the Bengali/Hindi/ghazal/waz rails for both modes.
        ref.read(homeSectionsProvider.notifier).loadVideo();
        ref.read(homeSectionsProvider.notifier).loadAudio();
      }
    });
    // Infinite scroll: load more when near the bottom.
    _scrollController.addListener(_onScroll);
    // If the previous run died with a recorded fatal error, show it
    // once — the text is the diagnostic evidence (key: main.dart's
    // lastFatalKey).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLastFatalIfAny();
    });
  }

  Future<void> _showLastFatalIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fatal = prefs.getString('last_fatal_error');
      if (fatal == null || fatal.isEmpty || !mounted) return;
      await prefs.remove('last_fatal_error');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('আগের crash-এর তথ্য'),
          content: SingleChildScrollView(
            child: SelectableText(fatal, style: const TextStyle(fontSize: 11)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('বন্ধ করো'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    // Trigger when within 400px of the bottom.
    if (max - current < 400) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  static const _categories = [
    'Music',
    'Gaming',
    'News',
    'Flutter',
    'Movies',
    'Sports',
    'Comedy',
    'Podcasts',
  ];

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _search(String q) {
    if (_suggesting) setState(() => _suggesting = false);
    FocusScope.of(context).unfocus();
    if (ref.read(homeModeProvider)) {
      // Audio mode: endless YouTube Music song search.
      ref.read(audioSongSearchProvider.notifier).search(q);
    } else {
      ref.read(searchControllerProvider.notifier).search(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final showMini = player.status == PlayerStatus.ready &&
        player.video != null &&
        !ref.watch(popupVisibleProvider);
    final isAudioHome = ref.watch(homeModeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'PureTube',
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            tooltip: 'Shorts',
            icon: const Icon(Icons.slow_motion_video_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ShortsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Downloads',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DownloadsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Library',
            icon: const Icon(Icons.video_library_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          isAudioHome ? 'Search songs…' : 'Search YouTube…',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _suggesting = false;
                            _suggestions = const [];
                          });
                          ref.read(searchControllerProvider.notifier).clear();
                          ref.read(audioSongSearchProvider.notifier).clear();
                        },
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainer,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Audio/Video home-mode toggle (sits where the
                // search filter used to be). Tapping switches the
                // whole home between video feed and music-style
                // audio home.
                Consumer(
                  builder: (_, ref, __) {
                    final isAudio = ref.watch(homeModeProvider);
                    return IconButton(
                      tooltip: isAudio ? 'Video mode' : 'Audio mode',
                      style: IconButton.styleFrom(
                        backgroundColor: isAudio
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceContainer,
                      ),
                      icon: Icon(
                          isAudio
                              ? Icons.videocam_outlined
                              : Icons.headphones_outlined,
                          color: isAudio ? Colors.black : Colors.white),
                      onPressed: () =>
                          ref.read(homeModeProvider.notifier).toggle(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (!isAudioHome && !_suggesting)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final selected = _searchController.text == _categories[i];
                  return ActionChip(
                    backgroundColor: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainer,
                    side: BorderSide(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: selected ? 1.5 : 0.5),
                    label: Text(_categories[i],
                        style: TextStyle(
                            color: selected ? Colors.black : Colors.white70,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    onPressed: () {
                      setState(() {
                        _searchController.text = _categories[i];
                      });
                      _search(_categories[i]);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _suggesting
                ? _buildSuggestionList()
                : isAudioHome
                ? const AudioHome()
                : RefreshIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainer,
                    onRefresh: () async {
                      await ref
                          .read(homeSectionsProvider.notifier)
                          .refreshVideo();
                      await ref
                          .read(searchControllerProvider.notifier)
                          .refreshFeed();
                    },
                    child: _buildResults(search),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: showMini ? const MiniPlayerBar() : null,
    );
  }

  Widget _buildResults(SearchState s) {
    switch (s.status) {
      case SearchStatus.idle:
        return const Center(
          child: Text(
            'Search for videos,\nor tap a category above.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        );
      case SearchStatus.loading:
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          itemCount: 4,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Shimmer.fromColors(
              baseColor: Theme.of(context).colorScheme.surfaceContainer,
              highlightColor:
                  Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 12,
                    width: 180,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case SearchStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(s.errorMessage ?? 'Search failed.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _search(s.query),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case SearchStatus.done:
        if (s.results.isEmpty) {
          return const Center(
              child: Text('No results found.',
                  style: TextStyle(color: Colors.grey)));
        }
        // YouTube/SparkTube-style home: ONE vertical feed, full-width
        // cards one below another — no horizontal rails, no grid.
        return CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
              sliver: SliverList.builder(
                // Extra item at the end for the loading indicator.
                itemCount: s.results.length + (s.loadingMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= s.results.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: VideoCard(video: s.results[i]),
                  );
                },
              ),
            ),
          ],
        );
    }
  }
}
