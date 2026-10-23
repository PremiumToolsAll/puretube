import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:puretube_playback/puretube_playback.dart';

import '../../../../core/database/hive_setup.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/widgets/press_scale.dart';
import '../providers/player_controller.dart';
import '../providers/popup_visibility.dart';
import '../screens/player_screen.dart';

/// Unified tiny corner mini player (YouTube-style).
///
/// ONE widget, bottom corner, two states — nothing else:
/// * **Live**: Back during playback shrinks the video here (small, bottom
///   corner). Tap expands back to the fullscreen player without
///   restarting; the X stops playback.
/// * **Continue watching**: when nothing is playing but a saved resume
///   position exists, the same corner window shows the thumbnail +
///   progress. Tap resumes from the exact saved position.
///
/// Mount once above the [Navigator] (e.g. in `MaterialApp.builder`) so it
/// floats over every screen. Hidden while the fullscreen [PlayerScreen] is
/// open.
class PopupPlayerHost extends ConsumerWidget {
  const PopupPlayerHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(fullPlayerOpenProvider)) {
      return const SizedBox.shrink();
    }
    final uiState = ref.watch(playerControllerProvider);
    // Never show the popup in audio mode — audio keeps playing in the
    // background without any floating window, including on track Next.
    if (uiState.audioOnly) {
      return const SizedBox.shrink();
    }
    final live = ref.watch(popupVisibleProvider) &&
        uiState.status == PlayerStatus.ready &&
        uiState.video != null;
    if (live) return const _LiveCornerPlayer();
    return const _ResumeCornerPlayer();
  }
}

/// Shared geometry for the corner window.
class _Corner {
  static const double width = 200;
  static const double height = width * 9 / 16; // 112.5
  static const double margin = 12;

  static Offset defaultOffset(Size size) => Offset(
        size.width - width - margin,
        // Parked above the bottom nav bar.
        size.height - height - 96,
      );

  static Offset clampOffset(Offset o, Size size) => Offset(
        o.dx.clamp(0.0, size.width - width),
        o.dy.clamp(0.0, size.height - height - 40),
      );
}

/// Small floating window with the live video while playback continues
/// after Back. Draggable; tap expands; X stops.
class _LiveCornerPlayer extends ConsumerStatefulWidget {
  const _LiveCornerPlayer();

  @override
  ConsumerState<_LiveCornerPlayer> createState() =>
      _LiveCornerPlayerState();
}

class _LiveCornerPlayerState
    extends ConsumerState<_LiveCornerPlayer> {
  // Drag offset via ValueNotifier so panning only rebuilds the
  // Positioned wrapper — the Video widget itself is built once and
  // never rebuilt mid-drag (that's what made dragging janky).
  final ValueNotifier<Offset?> _offsetNotifier =
      ValueNotifier<Offset?>(null);

  @override
  void dispose() {
    _offsetNotifier.dispose();
    super.dispose();
  }

  void _hide() =>
      ref.read(popupVisibleProvider.notifier).state = false;

  Future<void> _expand() async {
    final videoId =
        ref.read(playerControllerProvider).video?.id;
    _hide();
    if (videoId == null || !mounted) return;
    // If paused, resume so tapping the popup always plays. Ask the
    // ENGINE THAT IS ACTUALLY PLAYING: when the plugin owns playback
    // mpv sits paused, and reading mpv's state here would toggle the
    // playing plugin video OFF.
    final ui = ref.read(playerControllerProvider);
    final notifier = ref.read(playerControllerProvider.notifier);
    final playing = notifier.hqIsPlaying;
    if (!playing) {
      notifier.togglePlayPause();
    }
    // PlayerScreen skips loadVideo when the id is unchanged,
    // so playback position is preserved.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(videoId: videoId),
      ),
    );
  }

  void _close() {
    ref.read(playerControllerProvider.notifier).stop();
    _hide();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(playerControllerProvider);
    final video = uiState.video;
    if (video == null) return const SizedBox.shrink();
    final notifier = ref.read(playerControllerProvider.notifier);

    final size = MediaQuery.of(context).size;

    return ValueListenableBuilder<Offset?>(
      valueListenable: _offsetNotifier,
      builder: (context, offsetValue, child) {
        final offset = _Corner.clampOffset(
            offsetValue ?? _Corner.defaultOffset(size), size);
        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: GestureDetector(
            // Immediate drag response: update the notifier directly so
            // the window tracks the finger 1:1 like YouTube's mini player.
            onPanUpdate: (d) {
              _offsetNotifier.value =
                  _Corner.clampOffset(offset + d.delta, size);
            },
            onTap: _expand,
            child: child!,
          ),
        );
      },
      child: Container(
          width: _Corner.width,
          height: _Corner.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (uiState.audioOnly)
                  CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.black),
                  )
                else if (uiState.hqTextureId != null)
                  // Plugin engine: the SAME engine-owned texture the
                  // full player shows. Mounting/unmounting this
                  // render target never pauses, restarts or blacks
                  // out the video (the old PlatformView's surface
                  // was destroyed on every popup transition).
                  PureTubeVideoView(
                    textureId: uiState.hqTextureId!,
                    aspectRatio: uiState.hqAspectRatio,
                    fit: BoxFit.cover,
                  )
                else
                  Container(color: Colors.black),
                // Readability scrim.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Colors.black45, Colors.transparent],
                    ),
                  ),
                ),
                // Center transport: previous | play/pause | next —
                // the mini player can change videos too (wired to
                // the same controller paths as every other surface).
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PressIconButton(
                        tooltip: 'Previous',
                        onPressed: () => notifier.playPrevious(),
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      StreamBuilder<bool>(
                        stream: notifier.hqPlayingStream,
                        initialData: notifier.hqIsPlaying,
                        builder: (context, snap) {
                          final playing = snap.data ?? false;
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: PressIconButton(
                              tooltip: playing ? 'Pause' : 'Play',
                              onPressed: notifier.togglePlayPause,
                              icon: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          );
                        },
                      ),
                      PressIconButton(
                        tooltip: 'Next',
                        onPressed: () => notifier.playNext(),
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
                // Top-right close.
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: PressIconButton(
                      tooltip: 'Close',
                      onPressed: _close,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                // Live progress line at the bottom.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: const _LiveProgressLine(),
                ),
              ],
            ),
          ),
      ),
    );
  }
}

/// The same corner window for "continue watching": saved thumbnail +
/// progress. Tap resumes from the exact saved position.
class _ResumeCornerPlayer extends ConsumerStatefulWidget {
  const _ResumeCornerPlayer();

  @override
  ConsumerState<_ResumeCornerPlayer> createState() =>
      _ResumeCornerPlayerState();
}

class _ResumeCornerPlayerState
    extends ConsumerState<_ResumeCornerPlayer> {
  static const _watchKeys = [
    PlayerController.kLastVideoId,
    PlayerController.kLastVideoTitle,
    PlayerController.kLastVideoAuthor,
    PlayerController.kLastVideoThumb,
    PlayerController.kLastVideoDurationSecs,
    PlayerController.kLastVideoPositionSecs,
    PlayerController.kLastVideoAudioOnly,
    PlayerController.kLastVideoUpdatedAt,
  ];

  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable:
          Hive.box(HiveBoxes.playerPrefs).listenable(keys: _watchKeys),
      builder: (context, Box box, _) {
        final id = box.get(PlayerController.kLastVideoId) as String?;
        if (id == null || id.isEmpty) {
          return const SizedBox.shrink();
        }
        final posSecs =
            box.get(PlayerController.kLastVideoPositionSecs) as int? ?? 0;
        final durSecs =
            box.get(PlayerController.kLastVideoDurationSecs) as int? ?? 0;
        // Skip barely-started or finished videos.
        if (posSecs <= 5) return const SizedBox.shrink();
        if (durSecs > 0 && posSecs >= durSecs - 10) {
          return const SizedBox.shrink();
        }
        final player = ref.watch(playerControllerProvider);
        // Don't show while this video is the active one.
        if (player.videoId == id &&
            (player.status == PlayerStatus.ready ||
                player.status == PlayerStatus.loading)) {
          return const SizedBox.shrink();
        }
        // Don't clash with the live mini player.
        if (player.status == PlayerStatus.ready && player.video != null) {
          return const SizedBox.shrink();
        }

        final thumb =
            box.get(PlayerController.kLastVideoThumb) as String? ?? '';
        final progress =
            durSecs > 0 ? (posSecs / durSecs).clamp(0.0, 1.0) : 0.0;
        final size = MediaQuery.of(context).size;
        final offset = _Corner.clampOffset(
            _offset ?? _Corner.defaultOffset(size), size);

        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() {
              _offset = _Corner.clampOffset(offset + d.delta, size);
            }),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  videoId: id,
                  initialPosition: Duration(seconds: posSecs),
                ),
              ),
            ),
            child: Container(
              width: _Corner.width,
              height: _Corner.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.35),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF1E1E1E),
                      ),
                    ),
                    Container(color: Colors.black38),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: PressIconButton(
                          tooltip: 'Dismiss',
                          onPressed: () async {
                            try {
                              await box.deleteAll(_watchKeys);
                            } catch (_) {}
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(
                            Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Thin live progress line for the corner player.
class _LiveProgressLine extends ConsumerWidget {
  const _LiveProgressLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerControllerProvider.notifier);
    return StreamBuilder<Duration>(
      stream:
          notifier.hqDurationStream,
      builder: (context, durSnap) {
        final total = durSnap.data?.inMilliseconds ?? 0;
        return StreamBuilder<Duration>(
          stream: notifier.hqPositionStream,
          builder: (context, posSnap) {
            final pos = posSnap.data?.inMilliseconds ?? 0;
            return LinearProgressIndicator(
              value:
                  total > 0 ? (pos / total).clamp(0.0, 1.0) : 0,
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
