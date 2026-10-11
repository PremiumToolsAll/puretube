import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../player/presentation/providers/player_controller.dart';
import '../providers/search_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/video_card.dart';
import '../../../library/presentation/screens/downloads_screen.dart';
import '../../../library/presentation/screens/history_screen.dart';
import '../../../library/presentation/screens/playlists_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();

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
        player.status == PlayerStatus.ready && player.video != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'PureTube',
          style: TextStyle(
              color: Color(0xFF6200EA),
              fontWeight: FontWeight.bold),
        ),
        actions: [
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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search YouTube…',
                hintStyle:
                    const TextStyle(color: Colors.grey),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.grey),
                suffixIcon: IconButton(
                  icon:
                      const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    ref
                        .read(searchControllerProvider.notifier)
                        .clear();
                  },
                ),
                filled: true,
                fillColor: const Color(0xFF121212),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
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
                backgroundColor: const Color(0xFF1A1A1A),
                side: BorderSide.none,
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
          Expanded(child: _buildResults(search)),
        ],
      ),
      bottomNavigationBar:
          showMini ? const MiniPlayer() : null,
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
            baseColor: const Color(0xFF1A1A1A),
            highlightColor: const Color(0xFF2E2E2E),
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
          padding: const EdgeInsets.all(12),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: s.results.length,
          itemBuilder: (ctx, i) =>
              VideoCard(video: s.results[i]),
        );
    }
  }
}
