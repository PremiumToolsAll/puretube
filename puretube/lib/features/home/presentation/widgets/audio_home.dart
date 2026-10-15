import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/presentation/providers/library_providers.dart';
import '../../../player/presentation/providers/player_controller.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../providers/music_feed_provider.dart';
import '../providers/search_provider.dart';

/// Music-style home for audio mode: trending songs, recently played,
/// and song-style search results. Tapping a song plays it audio-only.
class AudioHome extends ConsumerWidget {
  const AudioHome({super.key});

  Future<void> _playSong(
      WidgetRef ref, BuildContext context, String videoId) async {
    await ref
        .read(playerControllerProvider.notifier)
        .playAudioOnly(videoId);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerScreen(videoId: videoId)));
    }
  }

  static String _fmtDur(Duration? d) {
    if (d == null) return '';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(searchControllerProvider);
    // An active search shows song-style results instead of the sections.
    if (search.query.isNotEmpty) {
      return _buildSearchResults(context, ref, search);
    }
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      backgroundColor:
          Theme.of(context).colorScheme.surfaceContainer,
      onRefresh: () => ref.refresh(musicFeedProvider.future),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _sectionTitle(context, 'Trending songs'),
          _trendingRow(context, ref),
          _sectionTitle(context, 'Recently played'),
          _recentlyPlayed(context, ref),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold),
        ),
      );

  Widget _trendingRow(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(musicFeedProvider);
    return feed.when(
      loading: () => const SizedBox(
        height: 170,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Could not load songs. Pull to retry.',
            style: TextStyle(color: Colors.grey[500])),
      ),
      data: (songs) => SizedBox(
        height: 178,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: songs.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: 12),
          itemBuilder: (ctx, i) {
            final v = songs[i];
            return GestureDetector(
              onTap: () => _playSong(ref, context, v.id),
              child: SizedBox(
                width: 128,
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: v.thumbnailUrl,
                        width: 128,
                        height: 128,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(
                          width: 128,
                          height: 128,
                          color:
                              const Color(0xFF1E1E1E),
                          child: const Icon(
                              Icons.music_note,
                              color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      v.title,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight:
                              FontWeight.w600,
                          fontSize: 13),
                    ),
                    Text(
                      v.author,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _recentlyPlayed(
      BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyControllerProvider);
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('Songs you play will show up here.',
            style: TextStyle(color: Colors.grey[500])),
      );
    }
    return Column(
      children: [
        for (final h in history.take(20))
          _songRow(
            context,
            ref,
            videoId: h.videoId,
            title: h.title,
            subtitle: h.author,
            thumbUrl: h.thumbnailUrl,
            duration: h.durationSecs != null
                ? _fmtDur(
                    Duration(seconds: h.durationSecs!))
                : '',
          ),
      ],
    );
  }

  Widget _buildSearchResults(
      BuildContext context, WidgetRef ref, SearchState s) {
    switch (s.status) {
      case SearchStatus.loading:
        return const Center(
            child: CircularProgressIndicator());
      case SearchStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(s.errorMessage ?? 'Search failed.',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.grey)),
          ),
        );
      case SearchStatus.done:
        if (s.results.isEmpty) {
          return const Center(
              child: Text('No songs found.',
                  style:
                      TextStyle(color: Colors.grey)));
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final v in s.results)
              _songRow(
                context,
                ref,
                videoId: v.id,
                title: v.title,
                subtitle: v.author,
                thumbUrl: v.thumbnailUrl,
                duration: _fmtDur(v.duration),
              ),
          ],
        );
      case SearchStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _songRow(
    BuildContext context,
    WidgetRef ref, {
    required String videoId,
    required String title,
    required String subtitle,
    required String thumbUrl,
    required String duration,
  }) =>
      ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: thumbUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: 56,
              height: 56,
              color: const Color(0xFF1E1E1E),
              child: const Icon(Icons.music_note,
                  color: Colors.grey),
            ),
          ),
        ),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.grey)),
        trailing: duration.isEmpty
            ? null
            : Text(duration,
                style:
                    const TextStyle(color: Colors.grey)),
        onTap: () => _playSong(ref, context, videoId),
      );
}
