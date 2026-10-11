import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/services/youtube_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../home/presentation/widgets/video_card.dart';
import '../../../library/data/library_database.dart';
import '../../../player/domain/entities/models.dart';
import '../../../player/presentation/player_screen.dart';
import '../tabs/community_tab.dart';

/// Channel page with tabs.
class ChannelScreen extends ConsumerStatefulWidget {
  final String channelId;

  const ChannelScreen(
      {super.key, required this.channelId});

  @override
  ConsumerState<ChannelScreen> createState() =>
      _ChannelScreenState();
}

class _ChannelScreenState
    extends ConsumerState<ChannelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  Channel? _channel;
  List<VideoItem> _videos = [];
  bool _loading = true;
  bool _subscribed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl =
        TabController(length: 4, vsync: this);
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
      final yt = YoutubeService.instance;
      final ch = await yt
          .channel(widget.channelId);
      final uploads = await yt.channelUploads(
          widget.channelId,
          limit: 30);
      final sub = await LibraryDatabase.instance
          .isSubscribed(widget.channelId);
      if (mounted) {
        setState(() {
          _channel = ch;
          _videos = uploads
              .map(VideoItem.fromVideo)
              .toList();
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
    final db = LibraryDatabase.instance;
    try {
      if (_subscribed) {
        await db
            .unsubscribe(widget.channelId);
      } else {
        await db.subscribe(
          channelId: widget.channelId,
          name: _channel?.title ?? 'Channel',
          subscriberCount:
              _channel?.subscribersCount ?? 0,
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text(_channel?.title ?? 'Channel',
            style: AppTheme.subtitle),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Text('Could not load channel',
                          style: AppTheme.body),
                      const SizedBox(
                          height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        style: ElevatedButton
                            .styleFrom(
                                backgroundColor:
                                    AppTheme
                                        .primary),
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
                      indicatorColor:
                          AppTheme.primary,
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
            backgroundColor: AppTheme.card,
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
                    style: AppTheme.subtitle
                        .copyWith(
                            fontWeight:
                                FontWeight
                                    .bold)),
                const SizedBox(height: 4),
                Text(
                    '${formatCount(ch.subscribersCount)} subscribers',
                    style: AppTheme.caption
                        .copyWith(
                            color: AppTheme
                                .textSecondary)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _toggleSubscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _subscribed
                      ? AppTheme.card
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
                v.duration!.inSeconds <=
                    90)
            .toList()
        : _videos;
    if (list.isEmpty) {
      return Center(
        child: Text(
            shortsOnly
                ? 'No shorts yet'
                : 'No videos yet',
            style: AppTheme.body.copyWith(
                color:
                    AppTheme.textSecondary)),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) =>
            VideoCard(video: list[i]),
      ),
    );
  }

  Widget _aboutTab() {
    // youtube_explode_dart's Channel has no description field;
    // safe fallback so the About tab renders without crashing.
    const description = '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text('About',
              style: AppTheme.subtitle.copyWith(
                  fontWeight:
                      FontWeight.bold)),
          const SizedBox(height: 12),
          if (description.isNotEmpty)
            Text(description,
                style: AppTheme.body.copyWith(
                    color:
                        AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
