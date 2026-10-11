import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';
import '../../../player/domain/entities/models.dart';
import '../../../player/presentation/player_screen.dart';

/// YouTube-like video card.
class VideoCard extends StatelessWidget {
  final VideoItem video;

  const VideoCard({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration:
              const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) =>
              PlayerScreen(videoId: video.id),
          transitionsBuilder:
              (_, anim, __, child) =>
                  FadeTransition(
                      opacity: anim,
                      child: child),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: video.thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      color: AppTheme.card),
                  errorWidget: (_, __, ___) =>
                      Container(
                    color: AppTheme.card,
                    child: const Icon(
                        Icons.broken_image,
                        color: Colors.white30),
                  ),
                ),
              ),
              if (video.duration != null &&
                  video.duration! > Duration.zero)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black
                          .withOpacity(0.85),
                      borderRadius:
                          BorderRadius.circular(4),
                    ),
                    child: Text(
                      formatDuration(video.duration),
                      style: AppTheme.caption.copyWith(
                          color: Colors.white,
                          fontWeight:
                              FontWeight.w500),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                12, 10, 12, 14),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.card,
                  child: Text(
                    video.author.isNotEmpty
                        ? video.author[0]
                            .toUpperCase()
                        : '?',
                    style: AppTheme.body.copyWith(
                        color:
                            AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(
                            fontWeight:
                                FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${video.author} • '
                        '${formatCount(video.viewCount)} views • '
                        '${timeAgo(video.uploadDate)}',
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: AppTheme.caption
                            .copyWith(
                                color: AppTheme
                                    .textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                      Icons.more_vert,
                      size: 20),
                  color: AppTheme.textSecondary,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
