import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../providers/player_controller.dart';
import 'seek_bar.dart';

/// Top overlay bar: back, title, PiP, popup, more.
class PlayerTopBar extends StatelessWidget {
  final PlayerUiState ui;
  final VoidCallback onBack;
  final VoidCallback onPip;
  final VoidCallback onPopup;
  final VoidCallback onMore;

  const PlayerTopBar({
    super.key,
    required this.ui,
    required this.onBack,
    required this.onPip,
    required this.onPopup,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black87,
            Colors.transparent
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back,
                color: Colors.white),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(ui.video?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body.copyWith(
                    color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(
                Icons
                    .picture_in_picture_outlined,
                color: Colors.white),
            tooltip: 'Picture in picture',
            onPressed: onPip,
          ),
          IconButton(
            icon: const Icon(
                Icons.open_in_new_outlined,
                color: Colors.white),
            tooltip: 'Popup player',
            onPressed: onPopup,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert,
                color: Colors.white),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

/// Center play/pause button with glow.
class PlayerCenterButton extends StatelessWidget {
  final Player player;
  final VoidCallback onToggle;

  const PlayerCenterButton({
    super.key,
    required this.player,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      builder: (_, snap) {
        final playing = snap.data ?? false;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary
                    .withOpacity(0.5),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: IconButton(
            iconSize: 64,
            onPressed: onToggle,
            icon: Icon(
              playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

/// Bottom control bar: seek, time, prev/play/next, fullscreen.
class PlayerBottomBar extends StatelessWidget {
  final Player player;
  final PlayerUiState ui;
  final PlayerController notifier;
  final VoidCallback onFullscreen;

  const PlayerBottomBar({
    super.key,
    required this.player,
    required this.ui,
    required this.notifier,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black87,
            Colors.transparent
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerSeekBar(player: player),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                StreamBuilder<Duration>(
                  stream: player.stream.position,
                  builder: (_, ps) =>
                      StreamBuilder<Duration>(
                    stream:
                        player.stream.duration,
                    builder: (_, ds) => Text(
                      '${formatDuration(ps.data)} / ${formatDuration(ds.data)}',
                      style: AppTheme.caption
                          .copyWith(
                              color: Colors
                                  .white70),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Previous',
                  onPressed:
                      notifier.hasPrevious
                          ? notifier.playPrevious
                          : null,
                  icon: Icon(Icons.skip_previous,
                      color: notifier.hasPrevious
                          ? Colors.white
                          : Colors.white30),
                ),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  builder: (_, snap) {
                    final playing =
                        snap.data ?? false;
                    return IconButton(
                      iconSize: 42,
                      onPressed:
                          notifier.togglePlayPause,
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: notifier.hasNext
                      ? notifier.playNext
                      : null,
                  icon: Icon(Icons.skip_next,
                      color: notifier.hasNext
                          ? Colors.white
                          : Colors.white30),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Fullscreen',
                  onPressed: onFullscreen,
                  icon: const Icon(
                      Icons.fullscreen,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
