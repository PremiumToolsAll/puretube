import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../widgets/channel_video_row.dart';

/// One playlist's videos, opened from the channel's Playlists tab:
/// playlist title + count + Play all, then the same YouTube-style
/// rows as the channel Videos tab, loading more as you scroll.
class PlaylistScreen extends ConsumerStatefulWidget {
  final PlaylistInfo playlist;
  final String channelTitle;

  const PlaylistScreen(
      {super.key, required this.playlist, required this.channelTitle});

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  Color get _accent => Theme.of(context).colorScheme.primary;
  List<VideoDetails> _videos = [];
  String? _nextToken;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.extentAfter < 400) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(extractorProvider)
          .getPlaylistVideosPage(widget.playlist.id,
              limit: 30, channelTitle: widget.channelTitle);
      if (mounted) {
        setState(() {
          _videos = page.items;
          _nextToken = page.nextPageToken;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final token = _nextToken;
    if (token == null || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(extractorProvider)
          .getPlaylistVideosPage(widget.playlist.id,
              pageToken: token,
              limit: 30,
              channelTitle: widget.channelTitle);
      if (!mounted) return;
      setState(() {
        final seen = _videos.map((v) => v.id).toSet();
        _videos.addAll(page.items.where((v) => seen.add(v.id)));
        _nextToken = page.nextPageToken;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _playAll() {
    if (_videos.isEmpty) return;
    final first = _videos.first;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            PlayerScreen(videoId: first.id, initialVideo: first)));
  }

  @override
  Widget build(BuildContext context) {
    final pl = widget.playlist;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(pl.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load playlist',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _accent),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: pl.thumbnailUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: const Color(0xFF1A1A1A)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(pl.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Text(
                        '${pl.videoCount} videos · ${widget.channelTitle}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _videos.isEmpty ? null : _playAll,
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: const Text('Play all',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding:
                                const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _videos.isEmpty
                          ? const Center(
                              child: Text('No videos in this playlist',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              controller: _scrollCtrl,
                              itemCount: _videos.length +
                                  (_nextToken != null ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i >= _videos.length) {
                                  return _loadingMore
                                      ? Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                          child: Center(
                                              child:
                                                  CircularProgressIndicator(
                                                      color: _accent)),
                                        )
                                      : const SizedBox(height: 24);
                                }
                                return ChannelVideoRow(video: _videos[i]);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
