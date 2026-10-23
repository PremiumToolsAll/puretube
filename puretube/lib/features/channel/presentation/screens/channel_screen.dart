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

/// Channel page in the original YouTube layout: banner, big avatar
/// with name + subscriber count, a full-width Subscribe pill, then
/// Home / Videos / Shorts / Community tabs. The Videos tab uses
/// YouTube's row list with Latest / Popular / Oldest chips; Shorts
/// uses the 3-column vertical grid.
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
  bool _loading = true;
  bool _subscribed = false;
  String? _error;
  int _videoSort = 0; // 0 latest, 1 popular, 2 oldest

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final extractor = ref.read(extractorProvider);
      final ch = await extractor.getChannel(widget.channelId);
      final uploads =
          await extractor.getChannelUploads(widget.channelId, limit: 40);
      final sub = ref
          .read(subscriptionRepositoryProvider)
          .isSubscribed(widget.channelId);
      if (mounted) {
        setState(() {
          _channel = ch;
          _videos = uploads;
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
            for (final v in rest) _VideoRow(video: v),
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
                    itemCount: list.length,
                    itemBuilder: (_, i) => _VideoRow(video: list[i]),
                  ),
                ),
        ),
      ],
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
            MaterialPageRoute(builder: (_) => PlayerScreen(videoId: v.id)),
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

/// YouTube channel Videos-tab row: 16:9 thumbnail on the left
/// (rounded, duration badge), title + "views · ago" on the right,
/// ⋮ with the same options sheet as the home cards.
class _VideoRow extends ConsumerWidget {
  final VideoDetails video;
  const _VideoRow({required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ago = timeAgo(video.uploadDate);
    final meta = <String>[
      if (video.viewCount != null) '${formatCount(video.viewCount)} views',
      if (ago.isNotEmpty) ago,
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerScreen(videoId: video.id)),
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
                      imageUrl: video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: const Color(0xFF1A1A1A)),
                    ),
                    if ((video.duration ?? Duration.zero) > Duration.zero)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formatDuration(video.duration),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white),
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
                  Text(video.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(meta,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => VideoCard.showOptions(context, ref, video),
            ),
          ],
        ),
      ),
    );
  }
}
