import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/audio_player_service.dart';
import '../../../../core/services/youtube_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../player/domain/entities/models.dart';
import '../../../player/presentation/providers/player_controller.dart'
    as pc;

/// Single full-screen vertical short player (9:16).
class ShortsPlayerWidget extends ConsumerStatefulWidget {
  final VideoItem video;
  final bool isActive;

  const ShortsPlayerWidget({
    super.key,
    required this.video,
    required this.isActive,
  });

  @override
  ConsumerState<ShortsPlayerWidget>
      createState() => _ShortsPlayerWidgetState();
}

class _ShortsPlayerWidgetState
    extends ConsumerState<ShortsPlayerWidget> {
  Player? _player;
  VideoController? _videoController;
  bool _playing = true;
  bool _muted = false;
  bool _loading = true;
  bool _liked = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(
      covariant ShortsPlayerWidget old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      _setActive(widget.isActive);
    }
  }

  @override
  void dispose() {
    try {
      // VideoController has no dispose(); the Player owns the resources.
      _player?.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _player = Player(
          configuration:
              const PlayerConfiguration(
                  title: 'PureTube Shorts'));
      _videoController =
          VideoController(_player!);
      // Load stream.
      final manifest = await YoutubeService
          .instance
          .streams(widget.video.id);
      final muxed = [...manifest.muxed]
        ..sort((a, b) => b.videoResolution.height
            .compareTo(
                a.videoResolution.height));
      if (muxed.isEmpty) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      // Prefer portrait-friendly (lower res is fine for shorts).
      final best = muxed.firstWhere(
        (s) => s.videoResolution.height <= 720,
        orElse: () => muxed.last,
      );
      await _player!
          .open(Media(best.url.toString()));
      if (widget.isActive) {
        await _player!.play();
      } else {
        await _player!.pause();
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _setActive(bool active) async {
    try {
      if (active) {
        await _player?.play();
        if (mounted) {
          setState(() => _playing = true);
        }
      } else {
        await _player?.pause();
        if (mounted) {
          setState(() => _playing = false);
        }
      }
    } catch (_) {}
  }

  Future<void> _togglePlay() async {
    try {
      if (_playing) {
        await _player?.pause();
      } else {
        await _player?.play();
      }
      if (mounted) {
        setState(
            () => _playing = !_playing);
      }
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    try {
      final next = !_muted;
      await _player
          ?.setVolume(next ? 0 : 100);
      if (mounted) {
        setState(() => _muted = next);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video.
        if (_videoController != null)
          GestureDetector(
            onTap: _togglePlay,
            child: Video(
                controller:
                    _videoController!,
                controls: NoVideoControls),
          )
        else
          Container(color: Colors.black),
        if (_loading)
          const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary)),
        // Play icon when paused.
        if (!_playing && !_loading)
          Center(
            child: Container(
              padding:
                  const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black
                    .withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                  Icons.play_arrow,
                  size: 48,
                  color: Colors.white),
            ),
          ),
        // Right action rail.
        Positioned(
          right: 8,
          bottom: 100,
          child: Column(
            children: [
              _action(
                icon: _liked
                    ? Icons.favorite
                    : Icons
                        .favorite_border,
                label: formatCount(
                    _likeCount > 0
                        ? _likeCount
                        : widget.video
                            .viewCount),
                color: _liked
                    ? Colors.red
                    : Colors.white,
                onTap: () => setState(() {
                  _liked = !_liked;
                  _likeCount +=
                      _liked ? 1 : -1;
                }),
              ),
              _action(
                icon: Icons
                    .thumb_down_outlined,
                label: 'Dislike',
                onTap: () {},
              ),
              _action(
                icon:
                    Icons.comment_outlined,
                label: 'Comments',
                onTap: () =>
                    _commentsSheet(),
              ),
              _action(
                icon:
                    Icons.share_outlined,
                label: 'Share',
                onTap: () => Share.share(
                    'https://youtu.be/${widget.video.id}'),
              ),
              _action(
                icon: _muted
                    ? Icons.volume_off
                    : Icons.volume_up,
                label: _muted
                    ? 'Unmute'
                    : 'Mute',
                onTap: _toggleMute,
              ),
            ],
          ),
        ),
        // Bottom info.
        Positioned(
          left: 12,
          right: 80,
          bottom: 24,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme
                        .primary
                        .withOpacity(0.3),
                    child: Text(
                        widget.video.author
                                .isNotEmpty
                            ? widget.video
                                .author[0]
                                .toUpperCase()
                            : '?',
                        style:
                            const TextStyle(
                                color: Colors
                                    .white,
                                fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        widget.video.author,
                        maxLines: 1,
                        overflow: TextOverflow
                            .ellipsis,
                        style: AppTheme.body
                            .copyWith(
                                color: Colors
                                    .white,
                                fontWeight:
                                    FontWeight
                                        .w600)),
                  ),
                  TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      backgroundColor:
                          Colors.white,
                      padding:
                          const EdgeInsets
                              .symmetric(
                                  horizontal:
                                      12,
                                  vertical:
                                      4),
                    ),
                    child: const Text(
                        'Subscribe',
                        style: TextStyle(
                            color: Colors
                                .black,
                            fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.video.title,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(
                      color: Colors.white)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                      Icons.music_note,
                      size: 14,
                      color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        'Original audio • ${widget.video.author}',
                        maxLines: 1,
                        overflow: TextOverflow
                            .ellipsis,
                        style: AppTheme.caption
                            .copyWith(
                                color: Colors
                                    .white70)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon,
                color: color, size: 30),
            const SizedBox(height: 4),
            Text(label,
                style: AppTheme.caption
                    .copyWith(
                        color: Colors.white,
                        fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _commentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, ctrl) => FutureBuilder(
          future: YoutubeService.instance
              .video(widget.video.id)
              .then((v) =>
                  YoutubeService.instance
                      .comments(v)),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Center(
                  child:
                      CircularProgressIndicator());
            }
            final comments = snap.data!;
            if (comments.isEmpty) {
              return const Center(
                  child: Text(
                      'No comments yet.'));
            }
            return ListView.builder(
              controller: ctrl,
              padding:
                  const EdgeInsets.all(16),
              itemCount: comments.length,
              itemBuilder: (_, i) {
                final cm = comments[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppTheme.card,
                    child: Text(
                        cm.author.isNotEmpty
                            ? cm.author[0]
                                .toUpperCase()
                            : '?'),
                  ),
                  title: Text(cm.author,
                      style: AppTheme.caption
                          .copyWith(
                              fontWeight:
                                  FontWeight
                                      .w600)),
                  subtitle: Text(cm.text,
                      style: AppTheme.body
                          .copyWith(
                              fontSize:
                                  13)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
