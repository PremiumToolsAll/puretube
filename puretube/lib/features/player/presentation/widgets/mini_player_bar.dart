import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/widgets/press_scale.dart';
import '../providers/player_controller.dart';
import '../screens/player_screen.dart';

/// In-app mini player bar shown (e.g. on Home) while audio/video keeps
/// playing after leaving the fullscreen player.
///
/// Gold-accented, slides up when playback becomes ready, and reopens the
/// fullscreen [PlayerScreen] on tap without restarting the video
/// (PlayerScreen skips `loadVideo` when the video id is unchanged).
class MiniPlayerBar extends ConsumerStatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  ConsumerState<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends ConsumerState<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  Color get _gold => Theme.of(context).colorScheme.primary;

  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    // Start hidden; the first frame decides visibility.
    _slideController.value = 0;
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(playerControllerProvider);
    final video = uiState.video;
    final visible =
        uiState.status == PlayerStatus.ready && video != null;

    // Drive the slide animation from visibility changes.
    if (visible && _slideController.status != AnimationStatus.completed) {
      _slideController.forward();
    } else if (!visible &&
        _slideController.status != AnimationStatus.dismissed) {
      _slideController.reverse();
    }

    if (!visible && _slideController.value == 0) {
      return const SizedBox.shrink();
    }

    final notifier = ref.read(playerControllerProvider.notifier);
    final player = ref.watch(mediaKitPlayerProvider);

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          border: Border(
            top: BorderSide(color: Color(0x33D4A574), width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProgressLine(player: player),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(videoId: video!.id),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: video!.thumbnailUrl,
                          width: 72,
                          height: 40,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: Colors.black),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Marquee(
                              text: video.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              video.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        builder: (context, snap) {
                          final playing = snap.data ?? false;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PressIconButton(
                                tooltip: 'Rewind 10s',
                                icon: const Icon(
                                    Icons.replay_10_rounded,
                                    size: 24,
                                    color: Colors.white70),
                                onPressed: () => notifier.seekBy(
                                    const Duration(seconds: -10)),
                              ),
                              PressIconButton(
                                tooltip:
                                    playing ? 'Pause' : 'Play',
                                icon: AnimatedSwitcher(
                                  duration: const Duration(
                                      milliseconds: 200),
                                  transitionBuilder:
                                      (child, animation) =>
                                          ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                                  child: Icon(
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    key: ValueKey(playing),
                                    color: _gold,
                                    size: 30,
                                  ),
                                ),
                                onPressed:
                                    notifier.togglePlayPause,
                              ),
                              PressIconButton(
                                tooltip: 'Forward 10s',
                                icon: const Icon(
                                    Icons.forward_10_rounded,
                                    size: 24,
                                    color: Colors.white70),
                                onPressed: () => notifier.seekBy(
                                    const Duration(seconds: 10)),
                              ),
                            ],
                          );
                        },
                      ),
                      PressIconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded,
                            size: 22, color: Colors.white70),
                        onPressed: notifier.stop,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin gold progress line pinned to the top of the mini player bar.
class _ProgressLine extends StatelessWidget {
  final Player player;
  const _ProgressLine({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      builder: (context, durSnap) {
        final total = durSnap.data?.inMilliseconds ?? 0;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          builder: (context, posSnap) {
            final pos = posSnap.data?.inMilliseconds ?? 0;
            return LinearProgressIndicator(
              value: total > 0
                  ? (pos / total).clamp(0.0, 1.0)
                  : 0,
              minHeight: 2,
              backgroundColor: Colors.white12,
              color: Theme.of(context).colorScheme.primary,
            );
          },
        );
      },
    );
  }
}

/// Auto-scrolling marquee for long titles. Static when the text fits.
class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _Marquee({required this.text, required this.style});

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollLoop());
  }

  Future<void> _scrollLoop() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      await _scrollController.animateTo(
        max,
        duration: Duration(milliseconds: (max * 18).round()),
        curve: Curves.linear,
      );
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_scrollController.hasClients) return;
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(widget.text, style: widget.style),
      ),
    );
  }
}
