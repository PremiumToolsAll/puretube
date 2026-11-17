import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/format.dart';
import '../../../home/presentation/widgets/video_card.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/screens/player_screen.dart';

/// YouTube channel Videos-tab row: 16:9 thumbnail on the left
/// (rounded, duration badge), title + "views · ago" on the right,
/// ⋮ with the same options sheet as the home cards.
class ChannelVideoRow extends ConsumerWidget {
  final VideoDetails video;
  const ChannelVideoRow({super.key, required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ago = timeAgo(video.uploadDate);
    // Original YouTube channel rows: "1.6K · 1d ago" (no "views" word).
    final meta = <String>[
      if (video.viewCount != null) formatCount(video.viewCount),
      if (ago.isNotEmpty) ago,
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) =>
                PlayerScreen(videoId: video.id, initialVideo: video)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 168,
                height: 94,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: const Color(0xFF1A1A1A)),
                    ),
                    if ((video.duration ?? Duration.zero) > Duration.zero)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${video.isMusic ? '♫ ' : ''}${formatDuration(video.duration)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(meta,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => VideoCard.showOptions(context, ref, video),
            ),
          ],
        ),
      ),
    );
  }
}
