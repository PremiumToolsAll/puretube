import 'package:flutter/material.dart'
    hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../downloads/presentation/downloads_screen.dart';
import '../../library/presentation/library_screen.dart';
import '../../player/domain/entities/models.dart';
import '../../search/presentation/search_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shorts/presentation/screens/shorts_screen.dart';
import './providers/search_provider.dart';
import './widgets/shimmer_loading.dart';
import './widgets/video_card.dart';

/// PureTube home — trending feed with category chips.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState
    extends ConsumerState<HomeScreen> {
  static const _categories = [
    'All',
    'Music',
    'Gaming',
    'News',
    'Movies',
    'Sports',
    'Live',
    'Flutter',
    'Comedy',
  ];

  String _activeCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(searchControllerProvider);
    final notifier =
        ref.read(searchControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text(
          'PureTube',
          style: AppTheme.title.copyWith(
              color: AppTheme.primary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () =>
                Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      const SearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(
                Icons.download_outlined),
            onPressed: () =>
                Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      const DownloadsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(
                Icons.bolt_outlined),
            tooltip: 'Shorts',
            onPressed: () =>
                Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      const ShortsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(
                Icons.video_library_outlined),
            onPressed: () =>
                Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      const LibraryScreen()),
            ),
            tooltip: 'Library',
          ),
          IconButton(
            icon: const Icon(
                Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildChips(),
          Expanded(
            child: _buildBody(state, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final active = cat == _activeCategory;
          return Padding(
            padding:
                const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(cat),
              selected: active,
              onSelected: (_) {
                setState(
                    () => _activeCategory = cat);
                final notifier = ref.read(
                    searchControllerProvider
                        .notifier);
                if (cat == 'All') {
                  notifier.retry();
                } else {
                  notifier.search(cat);
                }
              },
              backgroundColor: AppTheme.card,
              selectedColor: AppTheme.primary,
              checkmarkColor: Colors.white,
              labelStyle: AppTheme.body.copyWith(
                color: active
                    ? Colors.white
                    : AppTheme.textSecondary,
                fontWeight: active
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(20),
                side: BorderSide.none,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
      SearchState state, SearchController notifier) {
    switch (state.status) {
      case SearchStatus.loading:
        return const ShimmerFeed();
      case SearchStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48,
                    color: AppTheme.textSecondary),
                const SizedBox(height: 12),
                Text(
                  'Could not load videos',
                  style: AppTheme.subtitle,
                ),
                const SizedBox(height: 6),
                Text(
                  state.error ?? '',
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(
                      color:
                          AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: notifier.retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        AppTheme.primary,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case SearchStatus.done:
        if (state.results.isEmpty) {
          return Center(
            child: Text('No videos found.',
                style: AppTheme.body.copyWith(
                    color:
                        AppTheme.textSecondary)),
          );
        }
        return RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: notifier.retry,
          child: ListView.builder(
            itemCount: state.results.length,
            itemBuilder: (_, i) =>
                VideoCard(video: state.results[i]),
          ),
        );
      case SearchStatus.idle:
        return const ShimmerFeed();
    }
  }
}
