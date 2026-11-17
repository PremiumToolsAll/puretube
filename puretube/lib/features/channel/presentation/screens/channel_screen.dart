import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../../../home/presentation/widgets/video_card.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../tabs/community_tab.dart';
import '../widgets/channel_video_row.dart';
import 'playlist_screen.dart';

/// Channel page in the original YouTube layout: banner, big avatar
/// with name + subscriber count, a full-width Subscribe pill, then
/// Home / Videos / Shorts / Playlists / Community tabs. The Videos
/// tab uses YouTube's row list with Latest / Popular / Oldest chips
/// and loads more as you scroll (ALL videos, paged); the Playlists
/// tab lists the channel's playlists (tap one to open its videos).
/// Shorts uses the 3-column vertical grid.
class ChannelScreen extends ConsumerStatefulWidget {
  final String channelId;

  const ChannelScreen({super.key, required this.channelId});

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen>
    with SingleTickerProviderStateMixin {
  Color get _accent => Theme.of(context).colorScheme.primary;
  late final TabController _tabCtrl;
  ChannelInfo? _channel;
  List<VideoDetails> _videos = [];
  String? _nextVideosToken;
  bool _loadingMoreVideos = false;
  final _videosScrollCtrl = ScrollController();
  List<PlaylistInfo> _playlists = [];
  String? _nextPlaylistsToken;
  bool _loadingMorePlaylists = false;
  final _playlistsScrollCtrl = ScrollController();
  bool _loading = true;
  bool _subscribed = false;
  String? _error;
  int _videoSort = 0; // 0 latest, 1 popular, 2 oldest

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _videosScrollCtrl.addListener(_onVideosScroll);
    _playlistsScrollCtrl.addListener(_onPlaylistsScroll);
    _load();
  }

  @override
  void dispose() {
    _videosScrollCtrl.dispose();
    _playlistsScrollCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onVideosScroll() {
    if (_videosScrollCtrl.position.extentAfter < 400) {
      _loadMoreVideos();
    }
  }

  void _onPlaylistsScroll() {
    if (_playlistsScrollCtrl.position.extentAfter < 400) {
      _loadMorePlaylists();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final extractor = ref.read(extractorProvider);
      final ch = await extractor.getChannel(widget.channelId);
      final uploads = await extractor.getChannelVideosPage(
          widget.channelId,
          limit: 30,
          channelTitle: ch.title);
      final playlists = await extractor.getChannelPlaylistsPage(
          widget.channelId,
          limit: 30);
      final sub = ref
          .read(subscriptionRepositoryProvider)
          .isSubscribed(widget.channelId);
      if (mounted) {
        setState(() {
          _channel = ch;
          _videos = uploads.items;
          _nextVideosToken = uploads.nextPageToken;
          _playlists = playlists.items;
          _nextPlaylistsToken = playlists.nextPageToken;
          _subscribed = sub;
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

  /// Loads the next page of channel videos and appends it, so the
  /// Videos tab eventually shows ALL of the channel's videos.
  Future<void> _loadMoreVideos() async {
    final token = _nextVideosToken;
    if (token == null || _loadingMoreVideos || _loading) return;
    setState(() => _loadingMoreVideos = true);
    try {
      final page = await ref.read(extractorProvider).getChannelVideosPage(
          widget.channelId,
          pageToken: token,
          limit: 30,
          channelTitle: _channel?.title ?? '');
      if (!mounted) return;
      setState(() {
        // Skip videos already shown (a page can repeat the last
        // item of the previous one).
        final seen = _videos.map((v) => v.id).toSet();
        _videos.addAll(page.items.where((v) => seen.add(v.id)));
        _nextVideosToken = page.nextPageToken;
        _loadingMoreVideos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreVideos = false);
    }
  }

  /// Loads the next page of channel playlists and appends it.
  Future<void> _loadMorePlaylists() async {
    final token = _nextPlaylistsToken;
    if (token == null || _loadingMorePlaylists || _loading) return;
    setState(() => _loadingMorePlaylists = true);
    try {
      final page = await ref
          .read(extractorProvider)
          .getChannelPlaylistsPage(widget.channelId,
              pageToken: token, limit: 30);
      if (!mounted) return;
      setState(() {
        final seen = _playlists.map((p) => p.id).toSet();
        _playlists.addAll(page.items.where((p) => seen.add(p.id)));
        _nextPlaylistsToken = page.nextPageToken;
        _loadingMorePlaylists = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMorePlaylists = false);
    }
  }

  Future<void> _toggleSubscribe() async {
    final repo = ref.read(subscriptionRepositoryProvider);
    try {
      if (_subscribed) {
        await repo.unsubscribe(widget.channelId);
      } else {
        await repo.subscribe(
          channelId: widget.channelId,
          name: _channel?.title ?? 'Channel',
          subscriberCount: _channel?.subscriberCount,
        );
      }
      if (mounted) {
        setState(() => _subscribed = !_subscribed);
      }
    } catch (_) {}
  }

  List<VideoDetails> get _shorts => _videos
      .where((v) => v.duration != null && v.duration!.inSeconds <= 90)
      .toList();

  List<VideoDetails> get _sortedVideos {
    final list = [..._videos];
    switch (_videoSort) {
      case 1:
        list.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
        break;
      case 2:
        list.sort((a, b) => (a.uploadDate ?? DateTime(2100))
            .compareTo(b.uploadDate ?? DateTime(2100)));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            tooltip: 'Share channel',
            onPressed: () => Share.share(
                'https://www.youtube.com/channel/${widget.channelId}'),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load channel',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        style:
                            ElevatedButton.styleFrom(backgroundColor: _accent),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _header(),
                    TabBar(
                      controller: _tabCtrl,
                      indicatorColor: Colors.white,
                      indicatorWeight: 2,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500),
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Home'),
                        Tab(text: 'Videos'),
                        Tab(text: 'Shorts'),
                        Tab(text: 'Playlists'),
                        Tab(text: 'Community'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _homeTab(),
                          _videosTab(),
                          _shortsTab(),
                          _playlistsTab(),
                          CommunityTab(channelId: widget.channelId),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _header() {
    final ch = _channel!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ch.bannerUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: ch.bannerUrl,
                height: 104,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF1A1A1A),
                backgroundImage:
                    ch.logoUrl.isNotEmpty ? NetworkImage(ch.logoUrl) : null,
                child: ch.logoUrl.isEmpty
                    ? Text(
                        ch.title.isNotEmpty ? ch.title[0].toUpperCase() : '?',
                        style:
                            const TextStyle(fontSize: 30, color: Colors.white))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ch.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Text('${formatCount(ch.subscriberCount)} subscribers',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _toggleSubscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _subscribed ? const Color(0xFF272727) : Colors.white,
                foregroundColor: _subscribed ? Colors.white : Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_subscribed)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.notifications_outlined, size: 18),
                    ),
                  Text(_subscribed ? 'Subscribed' : 'Subscribe',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _homeTab() {
    if (_videos.isEmpty) {
      return const Center(
          child: Text('No videos yet', style: TextStyle(color: Colors.grey)));
    }
    final rest = _videos.skip(1).take(6).toList();
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        children: [
          VideoCard(video: _videos.first),
          if (rest.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Videos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            for (final v in rest) ChannelVideoRow(video: v),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _videosTab() {
    final list = _sortedVideos;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(const ['Latest', 'Popular', 'Oldest'][i]),
                  selected: _videoSort == i,
                  onSelected: (_) => setState(() => _videoSort = i),
                  selectedColor: Colors.white,
                  backgroundColor: const Color(0xFF272727),
                  labelStyle: TextStyle(
                      color: _videoSort == i ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  side: BorderSide.none,
                  showCheckmark: false,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('No videos yet',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: ListView.builder(
                    controller: _videosScrollCtrl,
                    // One trailing slot: a spinner while the next
                    // page loads, so ALL videos keep appearing.
                    itemCount: list.length +
                        (_nextVideosToken != null ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= list.length) {
                        return _loadingMoreVideos
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                    child: CircularProgressIndicator(
                                        color: _accent)),
                              )
                            : const SizedBox(height: 24);
                      }
                      return ChannelVideoRow(video: list[i]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _playlistsTab() {
    if (_playlists.isEmpty) {
      return const Center(
          child: Text('No playlists yet',
              style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView.builder(
        controller: _playlistsScrollCtrl,
        itemCount:
            _playlists.length + (_nextPlaylistsToken != null ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _playlists.length) {
            return _loadingMorePlaylists
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                        child: CircularProgressIndicator(color: _accent)),
                  )
                : const SizedBox(height: 24);
          }
          return _PlaylistRow(
            playlist: _playlists[i],
            channelTitle: _channel?.title ?? '',
          );
        },
      ),
    );
  }

  Widget _shortsTab() {
    final list = _shorts;
    if (list.isEmpty) {
      return const Center(
          child: Text('No shorts yet', style: TextStyle(color: Colors.grey)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 3 / 4.4,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final v = list[i];
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    PlayerScreen(videoId: v.id, initialVideo: v)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: v.thumbnailUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Container(color: const Color(0xFF1A1A1A)),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Text(
                  '${formatCount(v.viewCount)} views',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// YouTube channel Playlists-tab row: 16:9 thumbnail on the left
/// with a dark "▶ N videos" strip at the bottom, title + byline on
/// the right. Tapping opens the playlist's videos.
class _PlaylistRow extends StatelessWidget {
  final PlaylistInfo playlist;
  final String channelTitle;
  const _PlaylistRow({required this.playlist, required this.channelTitle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => PlaylistScreen(
                playlist: playlist, channelTitle: channelTitle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 168,
                height: 94,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: playlist.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: const Color(0xFF1A1A1A)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.75),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.playlist_play,
                                size: 16, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '${playlist.videoCount} videos',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    playlist.byline.isNotEmpty
                        ? playlist.byline
                        : '${playlist.videoCount} videos',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

