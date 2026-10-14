import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../../core/database/hive_setup.dart';
import '../../../../core/utils/format.dart';
import '../../../player/presentation/providers/player_controller.dart';
import '../../../player/presentation/screens/player_screen.dart';

/// "Continue watching" as a floating popup (YouTube-style) at the bottom
/// of the home screen, replacing the old top card.
/// Tapping the popup reopens the fullscreen player and resumes from the
/// saved position. The X button dismisses it.
class ContinueWatchingPopup extends ConsumerWidget {
  const ContinueWatchingPopup({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder(
      valueListenable:
          Hive.box(HiveBoxes.playerPrefs).listenable(keys: _watchKeys),
      builder: (context, Box box, _) {
        final id =
            box.get(PlayerController.kLastVideoId) as String?;
        final title =
            box.get(PlayerController.kLastVideoTitle) as String?;
        if (id == null || id.isEmpty) {
          return const SizedBox.shrink();
        }
        final posSecs =
            box.get(PlayerController.kLastVideoPositionSecs) as int? ??
                0;
        final durSecs =
            box.get(PlayerController.kLastVideoDurationSecs) as int? ??
                0;
        // Skip barely-started or finished videos.
        if (posSecs <= 5) return const SizedBox.shrink();
        if (durSecs > 0 && posSecs >= durSecs - 10) {
          return const SizedBox.shrink();
        }
        // Don't show while the same video is already playing.
        final player = ref.watch(playerControllerProvider);
        if (player.videoId == id &&
            player.status == PlayerStatus.ready) {
          return const SizedBox.shrink();
        }
        // Don't clash with the MiniPlayerBar / popup player: if any
        // video is currently ready, that UI owns the bottom area.
        if (player.status == PlayerStatus.ready &&
            player.video != null) {
          return const SizedBox.shrink();
        }

        final thumb =
            box.get(PlayerController.kLastVideoThumb) as String? ??
                '';
        final progress =
            durSecs > 0 ? (posSecs / durSecs).clamp(0.0, 1.0) : 0.0;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.3),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => PlayerScreen(videoId: id)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: thumb,
                          width: 120,
                          height: 68,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            width: 120,
                            height: 68,
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.play_circle_outline,
                                color: Colors.white70),
                          ),
                        ),
                      ),
                      Container(
                        width: 120,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.white, size: 32),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: Colors.white
                                .withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation(
                                Theme.of(context)
                                    .colorScheme
                                    .primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.history,
                                size: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary),
                            const SizedBox(width: 4),
                            Text(
                              'Continue watching',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title ?? 'Video',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close,
                        size: 18, color: Colors.grey),
                    onPressed: () async {
                      try {
                        await box.deleteAll(_watchKeys);
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
