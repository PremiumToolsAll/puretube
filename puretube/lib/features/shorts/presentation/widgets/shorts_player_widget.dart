import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puretube_playback/puretube_playback.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/format.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/providers/player_controller.dart';

/// Single full-screen vertical short player (9:16).
///
/// Plays through the shared puretube_playback engine (the same
/// NewPipe/ExoPlayer engine as the main player — mpv is gone).
/// Only the ACTIVE short claims the engine; inactive pages show
/// their thumbnail. Claiming stamps [PureTubeController.ownerTag]
/// so the main PlayerController ignores the engine's events while
/// Shorts owns it, and leaving Shorts releases + invalidates the
/// main player's stale engagement.
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
  Color get _accent => Theme.of(context).colorScheme.primary;
  PureTubeController? _pt;
  int _textureId = -1;
  bool _playing = false;
  bool _muted = false;
  bool _loading = false;
  bool _liked = false;
  bool _claimed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      unawaited(_claim());
    }
  }

  @override
  void didUpdateWidget(covariant ShortsPlayerWidget old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      unawaited(_claim());
    } else if (!widget.isActive && old.isActive) {
      unawaited(_release());
    }
  }

  @override
  void dispose() {
    if (_claimed) {
      // Leaving Shorts entirely: stop the engine and let the
      // main player know its engagement is stale.
      _claimed = false;
      PureTubeController.ownerTag = null;
      final pt = _pt;
      unawaited(() async {
        try {
          await pt?.stop();
        } catch (_) {}
        // detach(), NOT close(): close() invokes the native
        // 'dispose', releasing the ONE shared player for everyone.
        await pt?.detach();
      }());
      ref.read(playerControllerProvider.notifier).invalidateEngine();
    } else {
      unawaited(_pt?.detach() ?? Future.value());
    }
    super.dispose();
  }

  Future<void> _claim() async {
    final pt = _pt ??= PureTubeController();
    pt.addListener(_onEngineChanged);
    PureTubeController.ownerTag = 'shorts';
    _claimed = true;
    if (mounted) setState(() => _loading = true);
    try {
      await pt.load(
        'https://www.youtube.com/watch?v=${widget.video.id}',
        height: 720,
        autoplay: true,
      );
      final id = await pt.textureId;
      if (mounted) {
        setState(() {
          _textureId = id;
          _loading = false;
          _playing = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _release() async {
    if (!_claimed) return;
    _claimed = false;
    final pt = _pt;
    pt?.removeListener(_onEngineChanged);
    try {
      await pt?.pause();
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  void _onEngineChanged() {
    final pt = _pt;
    if (pt == null || !_claimed || !mounted) return;
    // Shorts loop forever.
    if (pt.ended) {
      unawaited(() async {
        try {
          await pt.seek(Duration.zero);
          await pt.play();
        } catch (_) {}
      }());
      return;
    }
    if (pt.isPlaying != _playing) {
      setState(() => _playing = pt.isPlaying);
    }
  }

  Future<void> _togglePlay() async {
    final pt = _pt;
    if (pt == null || !_claimed) return;
    try {
      if (_playing) {
        await pt.pause();
      } else {
        await pt.play();
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    try {
      await _pt?.setMuted(next);
    } catch (_) {}
    if (mounted) setState(() => _muted = next);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video: the engine texture while this short owns the
        // engine; otherwise its thumbnail.
        if (_claimed && _textureId > 0)
          GestureDetector(
            onTap: _togglePlay,
            child: PureTubeVideoView(
              textureId: _textureId,
              aspectRatio: 9 / 16,
              fit: BoxFit.cover,
            ),
          )
        else
          GestureDetector(
            onTap: _togglePlay,
            child: CachedNetworkImage(
              imageUrl: widget.video.thumbnailUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: Colors.black),
            ),
          ),
        if (_loading)
          Center(child: CircularProgressIndicator(color: _accent)),
        // Play icon when paused.
        if (!_playing && !_loading && _claimed)
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
                label: formatCount(widget.video.viewCount),
                color: _liked ? Colors.red : Colors.white,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _accent.withOpacity(0.3),
                    child: Text(
                        widget.video.author.isNotEmpty
                            ? widget.video.author[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.video.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white)),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
