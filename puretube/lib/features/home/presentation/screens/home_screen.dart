import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../player/presentation/providers/player_controller.dart';
import '../../../shorts/presentation/screens/shorts_screen.dart';
import '../providers/home_mode_provider.dart';
import '../providers/search_provider.dart';
import '../../../player/presentation/widgets/mini_player_bar.dart';
import '../widgets/audio_home.dart';
import '../widgets/video_card.dart';
import '../../../player/presentation/providers/popup_visibility.dart';
import '../../../library/presentation/screens/downloads_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);
    final player = ref.watch(playerControllerProvider);
    final showMini =
        player.status == PlayerStatus.ready &&
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
                      hintText: isAudioHome
                          ? 'Search songs…'
                          : 'Search YouTube…',
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
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainer,
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
                // Audio/Video home-mode toggle (sits where the
                // search filter used to be). Tapping switches the
                // whole home between video feed and music-style
                // audio home.
                Consumer(
                  builder: (_, ref, __) {
                    final isAudio =
                        ref.watch(homeModeProvider);
                    return IconButton(
                      tooltip: isAudio
                          ? 'Video mode'
                          : 'Audio mode',
                      style: IconButton.styleFrom(
                        backgroundColor: isAudio
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                      ),
                      icon: Icon(
                          isAudio
                              ? Icons
                                  .videocam_outlined
                              : Icons
                                  .headphones_outlined,
                          color: isAudio
                              ? Colors.black
                              : Colors.white),
                      onPressed: () => ref
                          .read(homeModeProvider
                              .notifier)
                          .toggle(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (!isAudioHome)
            SizedBox(
              height: 42,
              child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final selected =
                    _searchController.text == _categories[i];
                return ActionChip(
                  backgroundColor: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainer,
                  side: BorderSide(
                      color: selected
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                          : Theme.of(context)
                              .colorScheme
                              .outlineVariant,
                      width: selected ? 1.5 : 0.5),
                  label: Text(_categories[i],
                      style: TextStyle(
                          color: selected
                              ? Colors.black
                              : Colors.white70,
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
            child: isAudioHome
                ? const AudioHome()
                : RefreshIndicator(
                    color:
                        Theme.of(context).colorScheme.primary,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainer,
                    onRefresh: () => ref
                        .read(searchControllerProvider
                            .notifier)
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
            baseColor:
                Theme.of(context).colorScheme.surfaceContainer,
            highlightColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHigh,
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
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return VideoCard(video: s.results[i]);
          },
        );
    }
  }
}
