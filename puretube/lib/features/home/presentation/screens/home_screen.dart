import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../player/presentation/providers/player_controller.dart';
import '../../../search/presentation/widgets/search_filter_sheet.dart';
import '../../../shorts/presentation/screens/shorts_screen.dart';
import '../providers/search_provider.dart';
import '../../../player/presentation/widgets/mini_player_bar.dart';
import '../widgets/continue_watching_card.dart';
import '../widgets/video_card.dart';
import '../../../player/presentation/widgets/popup_player.dart';
import '../../../library/presentation/screens/downloads_screen.dart';
import '../../../library/presentation/screens/history_screen.dart';
import '../../../library/presentation/screens/playlists_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Auto-load the home feed so videos appear on launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(searchControllerProvider.notifier).loadTrending();
      }
    });
    // Infinite scroll: load more when near the bottom.
    _scrollController.addListener(_onScroll);
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
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _search(String q) {
    FocusScope.of(context).unfocus();
    ref.read(searchControllerProvider.notifier).search(q);
  }

  Future<void> _openFilters() async {
    final current =
        ref.read(searchControllerProvider).filters;
    final picked =
        await SearchFilterSheet.show(context, current);
    if (picked != null && mounted) {
      await ref
          .read(searchControllerProvider.notifier)
          .setFilters(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final showMini =
        player.status == PlayerStatus.ready &&
            player.video != null &&
            !ref.watch(popupVisibleProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F0C),
        title: const Text(
          'PureTube',
          style: TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh feed',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(searchControllerProvider.notifier)
                .refreshFeed(),
          ),
          IconButton(
            tooltip: 'Shorts',
            icon: const Icon(
                Icons.slow_motion_video_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      const ShortsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Downloads',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const DownloadsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Library',
            icon: const Icon(Icons.video_library_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Playlists',
            icon: const Icon(Icons.playlist_play),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const PlaylistsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const SettingsScreen()),
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
                    textInputAction:
                        TextInputAction.search,
                    onSubmitted: _search,
                    style: const TextStyle(
                        color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search YouTube…',
                      hintStyle: const TextStyle(
                          color: Colors.grey),
                      prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(
                                  searchControllerProvider
                                      .notifier)
                              .clear();
                        },
                      ),
                      filled: true,
                      fillColor:
                          const Color(0xFF0E1512),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              vertical: 0),
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                                24),
                        borderSide:
                            BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Consumer(
                  builder: (_, ref, __) {
                    final hasFilters = !ref
                        .watch(
                            searchControllerProvider)
                        .filters
                        .isEmpty;
                    return IconButton(
                      tooltip: 'Search filters',
                      style: IconButton.styleFrom(
                        backgroundColor:
                            hasFilters
                                ? const Color(
                                    0xFF10B981)
                                : const Color(
                                    0xFF0E1512),
                      ),
                      icon: const Icon(
                          Icons.tune,
                          color: Colors.white),
                      onPressed: _openFilters,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const ContinueWatchingCard(),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 8),
              itemBuilder: (ctx, i) => ActionChip(
                backgroundColor: const Color(0xFF0E1512),
                side: const BorderSide(
                    color: Color(0xFF10B981), width: 0.5),
                label: Text(_categories[i],
                    style: const TextStyle(
                        color: Colors.white70)),
                onPressed: () {
                  _searchController.text = _categories[i];
                  _search(_categories[i]);
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF10B981),
              backgroundColor: const Color(0xFF0E1512),
              onRefresh: () => ref
                  .read(searchControllerProvider.notifier)
                  .refreshFeed(),
              child: _buildResults(search),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          showMini ? const MiniPlayerBar() : null,
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
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => Shimmer.fromColors(
            baseColor: const Color(0xFF0E1512),
            highlightColor: const Color(0xFF1E2A22),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                const Icon(Icons.error_outline,
                    size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(s.errorMessage ?? 'Search failed.',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.grey)),
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
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          // Extra item at the end for the loading indicator.
          itemCount:
              s.results.length + (s.loadingMore ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i >= s.results.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      color: Color(0xFF10B981)),
                ),
              );
            }
            return VideoCard(video: s.results[i]);
          },
        );
    }
  }
}
