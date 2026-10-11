import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../../../player/domain/entities/playback_models.dart';

/// Single full-screen vertical short player (9:16).
class ShortsPlayerWidget extends ConsumerStatefulWidget {
  final VideoDetails video;
  final bool isActive;

  const ShortsPlayerWidget({
    super.key,
    required this.video,
    required this.isActive,
  });

  @override
  ConsumerState<ShortsPlayerWidget> createState() =>
      _ShortsPlayerWidgetState();
}

class _ShortsPlayerWidgetState
    extends ConsumerState<ShortsPlayerWidget> {
  static const _accent = Color(0xFF6200EA);
  Player? _player;
  VideoController? _videoController;
  bool _playing = true;
  bool _muted = false;
  bool _loading = true;
  bool _liked = false;

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
      _player?.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _player = Player(
          configuration: const PlayerConfiguration(
              title: 'PureTube Shorts'));
      _videoController = VideoController(_player!);
      // Load stream via puretube's extractor.
      final streams = await ref
          .read(extractorProvider)
          .getPlaybackStreams(widget.video.id);
      await _player!
          .open(Media(streams.muxedUrl));
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
        if (mounted) setState(() => _playing = true);
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
        setState(() => _playing = !_playing);
      }
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    try {
      final next = !_muted;
      await _player?.setVolume(next ? 0 : 100);
      if (mounted) setState(() => _muted = next);
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
                controller: _videoController!,
                controls: NoVideoControls),
          )
        else
          Container(color: Colors.black),
        if (_loading)
          const Center(
              child: CircularProgressIndicator(
                  color: _accent)),
        // Play icon when paused.
        if (!_playing && !_loading)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow,
                  size: 48, color: Colors.white),
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
                    : Icons.favorite_border,
                label: formatCount(
                    widget.video.viewCount),
                color:
                    _liked ? Colors.red : Colors.white,
                onTap: () => setState(() {
                  _liked = !_liked;
                }),
              ),
              _action(
                icon: Icons.thumb_down_outlined,
                label: 'Dislike',
                onTap: () {},
              ),
              _action(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () => Share.share(
                    'https://youtu.be/${widget.video.id}'),
              ),
              _action(
                icon: _muted
                    ? Icons.volume_off
                    : Icons.volume_up,
                label: _muted ? 'Unmute' : 'Mute',
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
                    backgroundColor:
                        _accent.withOpacity(0.3),
                    child: Text(
                        widget.video.author.isNotEmpty
                            ? widget.video.author[0]
                                .toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.video.author,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight:
                                FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white)),
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
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
