import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../player/domain/entities/models.dart';
import '../presentation/providers/player_controller.dart';

/// Full-screen audio player UI (Music Mode).
class MusicModeUI extends StatefulWidget {
  final Player player;
  final VideoItem video;
  final PlayerController notifier;
  final VoidCallback onExit;

  const MusicModeUI({
    super.key,
    required this.player,
    required this.video,
    required this.notifier,
    required this.onExit,
  });

  @override
  State<MusicModeUI> createState() =>
      _MusicModeUIState();
}

class _MusicModeUIState
    extends State<MusicModeUI>
    with SingleTickerProviderStateMixin {
  late final AnimationController _vizCtrl;
  bool _showLyrics = false;
  String? _lyrics;
  bool _lyricsLoading = false;

  @override
  void initState() {
    super.initState();
    _vizCtrl = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _vizCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _showLyrics = true;
      _lyricsLoading = true;
    });
    try {
      // Use auto-generated captions as lyrics.
      final ui = widget.notifier;
      // Trigger subtitle load via controller if needed.
      await Future.delayed(
          const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _lyrics =
              'Lyrics not available for this video.';
          _lyricsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _lyrics = 'Could not load lyrics.';
          _lyricsLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred album art background.
          CachedNetworkImage(
            imageUrl:
                widget.video.thumbnailUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                Container(
                    color: AppTheme.background),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: 30, sigmaY: 30),
            child: Container(
                color: Colors.black
                    .withOpacity(0.6)),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top bar.
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                          Icons
                              .keyboard_arrow_down,
                          color: Colors.white,
                          size: 32),
                      onPressed:
                          widget.onExit,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text('MUSIC MODE',
                              style: AppTheme
                                  .caption
                                  .copyWith(
                                      color: Colors
                                          .white70,
                                      letterSpacing:
                                          2)),
                          Text(
                              widget.video.author,
                              maxLines: 1,
                              overflow: TextOverflow
                                  .ellipsis,
                              style: AppTheme
                                  .caption
                                  .copyWith(
                                      color: Colors
                                          .white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white),
                      onPressed: () {},
                    ),
                  ],
                ),
                const Spacer(),
                // Album art.
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(
                            16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme
                            .primary
                            .withOpacity(0.4),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(
                            16),
                    child: CachedNetworkImage(
                      imageUrl: widget
                          .video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget:
                          (_, __, ___) =>
                              Container(
                        color:
                            AppTheme.card,
                        child: const Icon(
                            Icons
                                .music_note,
                            size: 80,
                            color: Colors
                                .white30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Visualizer.
                _Visualizer(
                    controller: _vizCtrl,
                    player: widget.player),
                const SizedBox(height: 16),
                // Title / artist.
                Padding(
                  padding:
                      const EdgeInsets
                          .symmetric(
                          horizontal: 32),
                  child: Column(
                    children: [
                      Text(widget.video.title,
                          textAlign:
                              TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow
                              .ellipsis,
                          style: AppTheme.title
                              .copyWith(
                                  color: Colors
                                      .white)),
                      const SizedBox(
                          height: 6),
                      Text(
                          widget.video.author,
                          style: AppTheme.body
                              .copyWith(
                                  color: Colors
                                      .white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Seek bar.
                Padding(
                  padding:
                      const EdgeInsets
                          .symmetric(
                          horizontal: 24),
                  child: _MusicSeekBar(
                      player: widget.player),
                ),
                const SizedBox(height: 8),
                // Controls.
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(
                          Icons.skip_previous,
                          color: Colors.white),
                      onPressed: widget
                                  .notifier
                                  .hasPrevious
                          ? widget.notifier
                              .playPrevious
                          : null,
                    ),
                    const SizedBox(
                        width: 16),
                    StreamBuilder<bool>(
                      stream: widget.player
                          .stream.playing,
                      builder: (_, snap) {
                        final playing =
                            snap.data ??
                                false;
                        return Container(
                          decoration:
                              BoxDecoration(
                            shape:
                                BoxShape.circle,
                            gradient: AppTheme
                                .premiumGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme
                                    .primary
                                    .withOpacity(
                                        0.5),
                                blurRadius:
                                    24,
                              ),
                            ],
                          ),
                          child: IconButton(
                            iconSize: 56,
                            icon: Icon(
                                playing
                                    ? Icons.pause
                                    : Icons
                                        .play_arrow,
                                color: Colors
                                    .white),
                            onPressed: widget
                                .notifier
                                .togglePlayPause,
                          ),
                        );
                      },
                    ),
                    const SizedBox(
                        width: 16),
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(
                          Icons.skip_next,
                          color: Colors.white),
                      onPressed: widget
                                  .notifier
                                  .hasNext
                          ? widget.notifier
                              .playNext
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Lyrics button.
                TextButton.icon(
                  icon: const Icon(
                      Icons.lyrics_outlined,
                      color: Colors.white70),
                  label: Text('Lyrics',
                      style: AppTheme.body
                          .copyWith(
                              color: Colors
                                  .white70)),
                  onPressed: _showLyrics
                      ? () => setState(() =>
                          _showLyrics =
                              false)
                      : _loadLyrics,
                ),
                const Spacer(),
              ],
            ),
          ),
          // Lyrics overlay.
          if (_showLyrics)
            Positioned.fill(
              child: Container(
                color: Colors.black
                    .withOpacity(0.85),
                child: SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                                Icons.close,
                                color: Colors
                                    .white),
                            onPressed: () =>
                                setState(() =>
                                    _showLyrics =
                                        false),
                          ),
                          Text('Lyrics',
                              style: AppTheme
                                  .subtitle
                                  .copyWith(
                                      color: Colors
                                          .white)),
                        ],
                      ),
                      Expanded(
                        child: _lyricsLoading
                            ? const Center(
                                child:
                                    CircularProgressIndicator(
                                        color: AppTheme
                                            .primary))
                            : SingleChildScrollView(
                                padding:
                                    const EdgeInsets
                                        .all(
                                        24),
                                child: Text(
                                    _lyrics ??
                                        '',
                                    textAlign:
                                        TextAlign
                                            .center,
                                    style: AppTheme
                                        .body
                                        .copyWith(
                                            color: Colors
                                                .white,
                                            height:
                                                1.8)),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mini audio visualizer (animated bars).
class _Visualizer extends StatelessWidget {
  final AnimationController controller;
  final Player player;

  const _Visualizer({
    required this.controller,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      builder: (_, snap) {
        final playing = snap.data ?? true;
        return SizedBox(
          height: 40,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) => Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children:
                  List.generate(24, (i) {
                final h = playing
                    ? 8 +
                        28 *
                            (0.5 +
                                0.5 *
                                    math.sin(
                                        controller.value *
                                                math.pi *
                                                2 +
                                            i *
                                                0.7))
                    : 8.0;
                return Container(
                  width: 4,
                  height: h,
                  margin:
                      const EdgeInsets.symmetric(
                          horizontal: 2),
                  decoration: BoxDecoration(
                    gradient: AppTheme
                        .premiumGradient,
                    borderRadius:
                        BorderRadius.circular(
                            2),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

class _MusicSeekBar extends StatelessWidget {
  final Player player;

  const _MusicSeekBar(
      {required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (_, ps) =>
          StreamBuilder<Duration>(
        stream: player.stream.duration,
        builder: (_, ds) {
          final pos =
              ps.data ?? Duration.zero;
          final dur =
              ds.data ?? Duration.zero;
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context)
                    .copyWith(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(
                          enabledThumbRadius:
                              8),
                  activeTrackColor:
                      AppTheme.primary,
                  inactiveTrackColor:
                      Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: dur.inMilliseconds >
                          0
                      ? (pos.inMilliseconds /
                              dur.inMilliseconds)
                          .clamp(0.0, 1.0)
                      : 0.0,
                  onChanged: (v) async {
                    try {
                      await player.seek(
                          Duration(
                              milliseconds: (v *
                                      dur.inMilliseconds)
                                  .round()));
                    } catch (_) {}
                  },
                ),
              ),
              Row(
                mainAxisAlignment:
                    MainAxisAlignment
                        .spaceBetween,
                children: [
                  Text(formatDuration(pos),
                      style: AppTheme.caption
                          .copyWith(
                              color: Colors
                                  .white70)),
                  Text(formatDuration(dur),
                      style: AppTheme.caption
                          .copyWith(
                              color: Colors
                                  .white70)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
