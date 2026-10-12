import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../../../home/presentation/widgets/video_card.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../tabs/community_tab.dart';

/// Channel page with tabs: Videos, Shorts, Community, About.
class ChannelScreen extends ConsumerStatefulWidget {
  final String channelId;

  const ChannelScreen({super.key, required this.channelId});

  @override
  ConsumerState<ChannelScreen> createState() =>
      _ChannelScreenState();
}

class _ChannelScreenState
    extends ConsumerState<ChannelScreen>
    with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF10B981);
  late final TabController _tabCtrl;
  ChannelInfo? _channel;
  List<VideoDetails> _videos = [];
  bool _loading = true;
  bool _subscribed = false;
  String? _error;

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
      final ch =
          await extractor.getChannel(widget.channelId);
      final uploads = await extractor.getChannelUploads(
          widget.channelId,
          limit: 30);
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
    final repo =
        ref.read(subscriptionRepositoryProvider);
    try {
      if (_subscribed) {
        await repo.unsubscribe(widget.channelId);
      } else {
        await repo.subscribe(
          channelId: widget.channelId,
          name: _channel?.title ?? 'Channel',
          subscriberCount:
              _channel?.subscriberCount,
        );
      }
      if (mounted) {
        setState(
            () => _subscribed = !_subscribed);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_channel?.title ?? 'Channel'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: _accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      const Text(
                          'Could not load channel',
                          style: TextStyle(
                              color: Colors.grey)),
                      const SizedBox(
                          height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        style: ElevatedButton
                            .styleFrom(
                                backgroundColor:
                                    _accent),
                        child: const Text(
                            'Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _header(),
                    TabBar(
                      controller: _tabCtrl,
                      indicatorColor: _accent,
                      isScrollable: true,
                      tabs: const [
                        Tab(text: 'Videos'),
                        Tab(text: 'Shorts'),
                        Tab(text: 'Community'),
                        Tab(text: 'About'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _videosTab(false),
                          _videosTab(true),
                          CommunityTab(
                              channelId: widget
                                  .channelId),
                          _aboutTab(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _header() {
    final ch = _channel!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor:
                const Color(0xFF1A1A1A),
            backgroundImage: ch
                    .logoUrl.isNotEmpty
                ? NetworkImage(ch.logoUrl)
                : null,
            child: ch.logoUrl.isEmpty
                ? Text(
                    ch.title.isNotEmpty
                        ? ch.title[0]
                            .toUpperCase()
                        : '?',
                    style: const TextStyle(
                        fontSize: 28))
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(ch.title,
                    style: const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                    '${formatCount(ch.subscriberCount)} subscribers',
                    style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _toggleSubscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor: _subscribed
                  ? const Color(0xFF1A1A1A)
                  : const Color(0xFFFF0000),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                          20)),
            ),
            child: Text(_subscribed
                ? 'Subscribed'
                : 'Subscribe'),
          ),
        ],
      ),
    );
  }

  Widget _videosTab(bool shortsOnly) {
    final list = shortsOnly
        ? _videos
            .where((v) =>
                v.duration != null &&
                v.duration!.inSeconds <= 90)
            .toList()
        : _videos;
    if (list.isEmpty) {
      return Center(
        child: Text(
            shortsOnly
                ? 'No shorts yet'
                : 'No videos yet',
            style:
                const TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) =>
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child:
                  VideoCard(video: list[i]),
            ),
      ),
    );
  }

  Widget _aboutTab() {
    final ch = _channel!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text('About',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white)),
          const SizedBox(height: 12),
          if (ch.bannerUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(12),
              child: Image.network(
                ch.bannerUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 12),
          Text(
              '${formatCount(ch.subscriberCount)} subscribers',
              style: const TextStyle(
                  color: Colors.grey)),
        ],
      ),
    );
  }
}
