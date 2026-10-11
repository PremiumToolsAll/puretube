import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/format.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/screens/player_screen.dart';

class VideoCard extends StatelessWidget {
  final VideoDetails video;
  const VideoCard({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => PlayerScreen(videoId: video.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: const Color(0xFF1A1A1A)),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF1A1A1A),
                      child: const Icon(Icons.broken_image,
                          color: Colors.grey),
                    ),
                  ),
                ),
                if ((video.duration ?? Duration.zero) >
                    Duration.zero)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatDuration(video.duration),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '${video.author} • ${formatCount(video.viewCount)} views • ${timeAgo(video.uploadDate)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
