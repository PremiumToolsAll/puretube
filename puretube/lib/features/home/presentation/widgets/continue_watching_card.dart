import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../../core/database/hive_setup.dart';
import '../../../../core/utils/format.dart';
import '../../../player/presentation/providers/player_controller.dart';
import '../../../player/presentation/screens/player_screen.dart';

/// "Continue watching" card shown at the top of the home screen when a
/// previously played video was saved to the player_prefs Hive box.
/// Tapping resumes playback from the saved position (loadVideo already
/// seeks to the history position). Like original YouTube.
class ContinueWatchingCard extends ConsumerWidget {
  const ContinueWatchingCard({super.key});

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

        final author =
            box.get(PlayerController.kLastVideoAuthor) as String? ??
                '';
        final thumb =
            box.get(PlayerController.kLastVideoThumb) as String? ??
                '';
        final audioOnly =
            box.get(PlayerController.kLastVideoAudioOnly) as bool? ??
                false;
        final progress =
            durSecs > 0 ? (posSecs / durSecs).clamp(0.0, 1.0) : 0.0;
        final remaining = durSecs > posSecs ? durSecs - posSecs : 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => PlayerScreen(videoId: id)),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF10B981)
                        .withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: thumb,
                          width: 128,
                          height: 72,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 128,
                            height: 72,
                            color: const Color(0xFF1A1A1A),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 128,
                            height: 72,
                            color: const Color(0xFF1A1A1A),
                            child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
                            valueColor:
                                const AlwaysStoppedAnimation(
                                    Color(0xFF10B981)),
                          ),
                        ),
                      ),
                      if (audioOnly)
                        const Positioned(
                          top: 4,
                          left: 4,
                          child: Icon(Icons.headphones,
                              size: 16, color: Colors.white70),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.history,
                                size: 14,
                                color: Color(0xFF10B981)),
                            SizedBox(width: 4),
                            Text(
                              'Continue watching',
                              style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title ?? 'Video',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${author.isEmpty ? '' : '$author • '}'
                          '${formatDuration(Duration(seconds: remaining))} left',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12),
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
