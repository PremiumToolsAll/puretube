import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/widgets/press_scale.dart';
import '../providers/player_controller.dart';
import '../providers/popup_visibility.dart';
import '../screens/player_screen.dart';
import 'sleep_timer_sheet.dart';
import 'subtitle_sheet.dart';

/// Root-level host for the floating popup player. Mount once above the
/// [Navigator] (e.g. in `MaterialApp.builder`) so the popup floats over
/// every screen while playback continues.
class PopupPlayerHost extends ConsumerWidget {
  const PopupPlayerHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(popupVisibleProvider);
    final uiState = ref.watch(playerControllerProvider);
    final ready = uiState.status == PlayerStatus.ready &&
        uiState.video != null;
    if (!visible || !ready) return const SizedBox.shrink();
    return const _PopupPlayerWindow();
  }
}

/// Draggable floating video window matching the target design:
/// gear (top-left), X (top-right), expand (center),
/// headphone (bottom-left), play/pause (bottom-center),
/// next (bottom-right), minimize chevron below the window.
class _PopupPlayerWindow extends ConsumerStatefulWidget {
  const _PopupPlayerWindow();

  @override
  ConsumerState<_PopupPlayerWindow> createState() =>
      _PopupPlayerWindowState();
}

class _PopupPlayerWindowState
    extends ConsumerState<_PopupPlayerWindow> {
  Color get _gold => Theme.of(context).colorScheme.primary;

  VideoController? _videoController;
  Offset? _offset; // null => centered default

  @override
  void initState() {
    super.initState();
    // Attach a second view onto the SAME shared player instance.
    _videoController =
        VideoController(ref.read(mediaKitPlayerProvider));
  }

  @override
  void dispose() {
    // NOTE: VideoController in this media_kit_video version has no
    // dispose(); PlayerScreen doesn't dispose its controller either.
    // The shared Player itself lives in PureTubeAudioHandler.
    super.dispose();
  }

  void _hide() =>
      ref.read(popupVisibleProvider.notifier).state = false;

  Future<void> _expand() async {
    final videoId =
        ref.read(playerControllerProvider).video?.id;
    _hide();
    if (videoId == null || !mounted) return;
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

  void _playNext() {
    final uiState = ref.read(playerControllerProvider);
    final next = uiState.relatedVideos
        .where((v) => v.id != uiState.videoId)
        .firstOrNull;
    if (next == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No next video found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    // Load inside the popup — no navigation, position starts fresh
    // for the new video while the window stays put.
    ref.read(playerControllerProvider.notifier).loadVideo(next.id);
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(playerControllerProvider);
    final video = uiState.video;
    if (video == null) return const SizedBox.shrink();
    final notifier = ref.read(playerControllerProvider.notifier);
    final player = ref.watch(mediaKitPlayerProvider);

    final size = MediaQuery.of(context).size;
    final winW = (size.width - 48).clamp(200.0, 480.0);
    final winH = winW * 9 / 16;
    final defaultOffset = Offset(
      (size.width - winW) / 2,
      size.height * 0.32,
    );
    final offset = _offset ?? defaultOffset;

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          final next = offset + d.delta;
          setState(() {
            _offset = Offset(
              next.dx.clamp(0.0, size.width - winW),
              next.dy
                  .clamp(0.0, size.height - winH - 120),
            );
          });
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: winW,
              height: winH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video (or album art in audio-only mode).
                    if (uiState.audioOnly)
                      CachedNetworkImage(
                        imageUrl: video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.black),
                      )
                    else if (_videoController != null)
                      Video(
                        controller: _videoController!,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(color: Colors.black),
                    // Readability scrims.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.black54,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.bottomCenter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.black54,
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: SizedBox(
                            width: double.infinity, height: 72),
                      ),
                    ),
                    // Top-left: settings.
                    Positioned(
                      top: 4,
                      left: 4,
                      child: _PopupIconButton(
                        icon: Icons.settings,
                        tooltip: 'Settings',
                        onPressed: () =>
                            _PopupSettingsSheet.show(context),
                      ),
                    ),
                    // Top-right: close.
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _PopupIconButton(
                        icon: Icons.close,
                        tooltip: 'Close',
                        onPressed: _close,
                      ),
                    ),
                    // Center: expand to fullscreen.
                    Center(
                      child: _PopupIconButton(
                        icon: Icons.fullscreen,
                        tooltip: 'Fullscreen',
                        size: 40,
                        onPressed: _expand,
                      ),
                    ),
                    // Bottom-left: audio mode.
                    Positioned(
                      bottom: 6,
                      left: 8,
                      child: _PopupIconButton(
                        icon: Icons.headphones,
                        tooltip: uiState.audioOnly
                            ? 'Video mode'
                            : 'Audio mode',
                        color: uiState.audioOnly
                            ? _gold
                            : Colors.white,
                        onPressed:
                            notifier.toggleAudioOnly,
                      ),
                    ),
                    // Bottom-center: play/pause.
                    Positioned(
                      bottom: 2,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: StreamBuilder<bool>(
                          stream: player.stream.playing,
                          builder: (context, snap) {
                            final playing =
                                snap.data ?? false;
                            return _PopupIconButton(
                              icon: playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              tooltip: playing
                                  ? 'Pause'
                                  : 'Play',
                              size: 44,
                              onPressed:
                                  notifier.togglePlayPause,
                            );
                          },
                        ),
                      ),
                    ),
                    // Bottom-right: next.
                    Positioned(
                      bottom: 6,
                      right: 8,
                      child: _PopupIconButton(
                        icon: Icons.skip_next,
                        tooltip: 'Next',
                        onPressed: _playNext,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Minimize chevron below the window.
            _PopupIconButton(
              icon: Icons.keyboard_arrow_up,
              tooltip: 'Minimize',
              onPressed: _hide,
            ),
          ],
        ),
      ),
    );
  }
}

/// Round translucent icon button used across the popup window,
/// with a 200ms ease-in-out press-scale effect.
class _PopupIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final Color color;

  const _PopupIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 30,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return PressIconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: size),
    );
  }
}

/// Compact settings sheet for the popup: quality, speed, subtitles,
/// sleep timer — all wired to the existing [PlayerController].
class _PopupSettingsSheet extends ConsumerWidget {
  const _PopupSettingsSheet();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(20)),
      ),
      builder: (_) => const _PopupSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(playerControllerProvider);
    final notifier = ref.read(playerControllerProvider.notifier);
    final gold = Theme.of(context).colorScheme.primary;

    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            sectionTitle('QUALITY'),
            ...ui.availableQualities.map((q) {
              final selected =
                  ui.currentQuality?.height == q.height &&
                      ui.currentQuality?.isDash == q.isDash &&
                      ui.currentQuality?.fps == q.fps;
              return ListTile(
                dense: true,
                title: Text(
                  q.isDash
                      ? '${q.resolutionLabel} · DASH'
                      : q.resolutionLabel,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: selected
                    ? Icon(Icons.check,
                        color: gold, size: 20)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  notifier.setQuality(q);
                },
              );
            }),
            if (ui.availableQualities.isEmpty)
              const ListTile(
                dense: true,
                title: Text('Loading qualities…',
                    style:
                        TextStyle(color: Colors.white54)),
              ),
            sectionTitle('SPEED'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((s) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4),
                          child: ChoiceChip(
                            label: Text('${s}x'),
                            selected: ui.speed == s,
                            selectedColor:
                                gold.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              color: ui.speed == s
                                  ? gold
                                  : Colors.white70,
                            ),
                            onSelected: (_) {
                              Navigator.pop(context);
                              notifier.setSpeed(s);
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
            sectionTitle('MORE'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.closed_caption,
                  color: Colors.white70),
              title: const Text('Subtitles',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                ui.activeSubtitle?.language ?? 'Off',
                style:
                    const TextStyle(color: Colors.white54),
              ),
              onTap: () {
                Navigator.pop(context);
                SubtitleSheet.show(context);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.bedtime,
                  color: Colors.white70),
              title: const Text('Sleep timer',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                ui.sleepRemaining != null
                    ? 'Ends in ${ui.sleepRemaining!.inMinutes} min'
                    : 'Off',
                style:
                    const TextStyle(color: Colors.white54),
              ),
              onTap: () {
                Navigator.pop(context);
                _sleepOptions(context);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _sleepOptions(BuildContext context) {
    SleepTimerSheet.show(context);
  }
}
