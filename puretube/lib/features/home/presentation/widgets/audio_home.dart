import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/providers/player_controller.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../providers/music_feed_provider.dart';

/// Audio-mode home: endless songs (YouTube Music), trending rail on top,
/// everything else in one scrollable song list. Tap a song → audio-only.
class AudioHome extends ConsumerStatefulWidget {
  const AudioHome({super.key});

  @override
  ConsumerState<AudioHome> createState() => _AudioHomeState();
}

class _AudioHomeState extends ConsumerState<AudioHome> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(musicFeedProvider.notifier).loadInitial();
      }
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    if (max - current < 600) {
      final searching = ref.read(audioSongSearchProvider).active;
      if (searching) {
        ref.read(audioSongSearchProvider.notifier).loadMore();
      } else {
        ref.read(musicFeedProvider.notifier).loadMore();
      }
    }
  }

  Future<void> _playSong(String videoId) async {
    await ref
        .read(playerControllerProvider.notifier)
        .playAudioOnly(videoId);
    if (mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerScreen(videoId: videoId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final search = ref.watch(audioSongSearchProvider);

    if (search.active) return _buildSearchResults(theme, search);

    final feed = ref.watch(musicFeedProvider);
    if (feed.loading && feed.songs.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ));
    }
    if (feed.error != null && feed.songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_off_outlined, size: 56),
              const SizedBox(height: 12),
              Text(feed.error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(musicFeedProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final songs = feed.songs;
    final trending = songs.take(15).toList();
    final rest = songs.skip(15).toList();

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(musicFeedProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (trending.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                  title: 'Trending songs', theme: theme),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 196,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: trending.length,
                  itemBuilder: (c, i) => _ArtworkCard(
                    song: trending[i],
                    onTap: () => _playSong(trending[i].id),
                  ),
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'All songs', theme: theme),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (c, i) => _SongRow(
                song: rest[i],
                onTap: () => _playSong(rest[i].id),
              ),
              childCount: rest.length,
            ),
          ),
          if (feed.loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child:
                    Center(child: CircularProgressIndicator()),
              ),
            )
          else
            const SliverToBoxAdapter(
                child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
      ThemeData theme, AudioSearchState search) {
    if (search.loading) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ));
    }
    if (search.error != null && search.songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_outlined, size: 56),
              const SizedBox(height: 12),
              Text(search.error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }
    final songs = search.songs;
    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('${songs.length} songs',
                style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurfaceVariant)),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (c, i) => _SongRow(
              song: songs[i],
              onTap: () => _playSong(songs[i].id),
            ),
            childCount: songs.length,
          ),
        ),
        if (search.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child:
                  Center(child: CircularProgressIndicator()),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader(
      {required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _ArtworkCard extends StatelessWidget {
  final VideoDetails song;
  final VoidCallback onTap;

  const _ArtworkCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 128,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: song.thumbnailUrl.isNotEmpty
                    ? Image.network(song.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _artFallback(theme))
                    : _artFallback(theme),
              ),
            ),
            const SizedBox(height: 6),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(song.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _artFallback(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.music_note,
            size: 40, color: theme.colorScheme.primary),
      );
}

class _SongRow extends StatelessWidget {
  final VideoDetails song;
  final VoidCallback onTap;

  const _SongRow({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: song.thumbnailUrl.isNotEmpty
              ? Image.network(song.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _thumbFallback(theme))
              : _thumbFallback(theme),
        ),
      ),
      title: Text(song.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          song.author,
          if (song.duration != null) _fmt(song.duration!),
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          Icon(Icons.play_arrow, color: AppTheme.primary),
    );
  }

  Widget _thumbFallback(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child:
            Icon(Icons.music_note, color: theme.colorScheme.primary),
      );

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
