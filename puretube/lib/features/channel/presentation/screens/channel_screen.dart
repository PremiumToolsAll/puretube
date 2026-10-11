import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../home/presentation/widgets/video_card.dart';

/// Channel page showing channel info and videos.
class ChannelScreen extends ConsumerStatefulWidget {
  final String channelId;

  const ChannelScreen({super.key, required this.channelId});

  @override
  ConsumerState<ChannelScreen> createState() =>
      _ChannelScreenState();
}

class _ChannelScreenState
    extends ConsumerState<ChannelScreen> {
  ChannelInfo? _channel;
  List<VideoDetails>? _videos;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final extractor = ref.read(extractorProvider);
    final results = await Future.wait([
      extractor.getChannelInfo(widget.channelId),
      extractor.getChannelVideos(widget.channelId),
    ]);
    if (mounted) {
      setState(() {
        _channel = results[0] as ChannelInfo?;
        _videos = results[1] as List<VideoDetails>;
        _loading = false;
      });
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
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
              child: CircularProgressIndicator())
          : _channel == null
              ? const Center(
                  child: Text('Channel not found',
                      style:
                          TextStyle(color: Colors.white70)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      // Channel header.
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundImage:
                                  _channel!.logoUrl.isNotEmpty
                                      ? NetworkImage(
                                          _channel!.logoUrl)
                                      : null,
                              backgroundColor: Colors
                                  .purple
                                  .withOpacity(0.3),
                              child: _channel!
                                      .logoUrl.isEmpty
                                  ? Text(
                                      _channel!.title
                                              .isNotEmpty
                                          ? _channel!
                                              .title[0]
                                              .toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                          fontSize: 28,
                                          color: Colors
                                              .white),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(
                                    _channel!.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(
                                      height: 4),
                                  Text(
                                    '${_formatCount(_channel!.subscriberCount)} subscribers',
                                    style: const TextStyle(
                                        color:
                                            Colors.white54,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(
                          color: Colors.white10),
                      // Videos.
                      if (_videos != null &&
                          _videos!.isNotEmpty)
                        ..._videos!.map((v) =>
                            VideoCard(video: v))
                      else
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No videos found.',
                              style: TextStyle(
                                  color:
                                      Colors.white54),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
