import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/services/audio_player_service.dart';
import '../../../core/theme/app_theme.dart';
import 'popup_player_service.dart';

/// Floating popup player widget (in-app mini player).
/// Shown as a draggable overlay inside the app; the system
/// overlay window is managed by [PopupPlayerService].
class PopupPlayerWidget extends ConsumerStatefulWidget {
  final String videoId;
  final VoidCallback onClose;
  final VoidCallback onExpand;

  const PopupPlayerWidget({
    super.key,
    required this.videoId,
    required this.onClose,
    required this.onExpand,
  });

  @override
  ConsumerState<PopupPlayerWidget>
      createState() => _PopupPlayerWidgetState();
}

class _PopupPlayerWidgetState
    extends ConsumerState<PopupPlayerWidget> {
  VideoController? _videoController;
  Offset _position = const Offset(16, 120);
  double _width = 300;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    try {
      _videoController = VideoController(
          ref.read(audioHandlerProvider).player);
    } catch (_) {}
    _restartHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    try {
      _videoController?.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(
        const Duration(seconds: 2),
        () => mounted
            ? setState(
                () => _showControls = false)
            : null);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final height = _width * 9 / 16 + 48;
    final x = _position.dx
        .clamp(0.0, screen.width - _width);
    final y = _position.dy
        .clamp(0.0, screen.height - height);

    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _position += d.delta;
            // Snap to edges.
            final sx =
                MediaQuery.of(context).size.width;
            if (_position.dx < 24) {
              _position =
                  Offset(8, _position.dy);
            } else if (_position.dx >
                sx - _width - 24) {
              _position = Offset(
                  sx - _width - 8,
                  _position.dy);
            }
          });
        },
        onScaleUpdate: (d) {
          setState(() {
            _width = (300 * d.scale)
                .clamp(150.0, 400.0);
          });
        },
        onTap: () {
          setState(
              () => _showControls = !_showControls);
          _restartHideTimer();
        },
        onDoubleTap: widget.onExpand,
        child: Material(
          elevation: 12,
          borderRadius:
              BorderRadius.circular(12),
          color: Colors.black,
          child: Container(
            width: _width,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withOpacity(0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(
                              top: Radius.circular(
                                  12)),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _videoController !=
                                null
                            ? Video(
                                controller:
                                    _videoController!,
                                controls:
                                    NoVideoControls)
                            : Container(
                                color:
                                    Colors.black),
                      ),
                    ),
                    if (_showControls)
                      Positioned.fill(
                        child: Container(
                          decoration:
                              BoxDecoration(
                            color: Colors.black
                                .withOpacity(0.35),
                            borderRadius:
                                const BorderRadius
                                    .vertical(
                                    top: Radius
                                        .circular(
                                            12)),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .center,
                            children: [
                              _miniBtn(
                                  Icons
                                      .replay_10,
                                  () {}),
                              const SizedBox(
                                  width: 8),
                              _playPauseBtn(),
                              const SizedBox(
                                  width: 8),
                              _miniBtn(
                                  Icons
                                      .forward_10,
                                  () {}),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: widget.onClose,
                        child: Container(
                          padding:
                              const EdgeInsets
                                  .all(4),
                          decoration:
                              const BoxDecoration(
                            color: Colors
                                .black54,
                            shape:
                                BoxShape.circle,
                          ),
                          child: const Icon(
                              Icons.close,
                              size: 16,
                              color:
                                  Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Now playing',
                          maxLines: 1,
                          overflow: TextOverflow
                              .ellipsis,
                          style: AppTheme
                              .caption
                              .copyWith(
                                  color: Colors
                                      .white70),
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onExpand,
                        child: const Icon(
                            Icons
                                .open_in_full_outlined,
                            size: 18,
                            color: Colors
                                .white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniBtn(
      IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      onPressed: () {
        onTap();
        _restartHideTimer();
      },
    );
  }

  Widget _playPauseBtn() {
    Player? player;
    try {
      player =
          ref.read(audioHandlerProvider).player;
    } catch (_) {}
    if (player == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      builder: (_, snap) {
        final playing = snap.data ?? false;
        return IconButton(
          iconSize: 36,
          icon: Icon(
              playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: Colors.white),
          onPressed: () {
            try {
              if (playing) {
                ref
                    .read(audioHandlerProvider)
                    .pause();
              } else {
                ref
                    .read(audioHandlerProvider)
                    .play();
              }
            } catch (_) {}
            _restartHideTimer();
          },
        );
      },
    );
  }
}
