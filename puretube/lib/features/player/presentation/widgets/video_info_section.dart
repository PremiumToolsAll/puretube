import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../domain/entities/models.dart';
import '../providers/player_controller.dart';
import '../../../downloads/presentation/download_dialog.dart';

/// Video info section below the player:
/// title, channel + subscribe, action pills, description.
class VideoInfoSection extends StatelessWidget {
  final VideoItem video;
  final PlayerUiState ui;
  final PlayerController notifier;

  const VideoInfoSection({
    super.key,
    required this.video,
    required this.ui,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(video.title,
            style: AppTheme.subtitle.copyWith(
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          '${formatCount(video.viewCount)} views • ${timeAgo(video.uploadDate)}',
          style: AppTheme.caption.copyWith(
              color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  AppTheme.primary.withOpacity(0.3),
              child: Text(
                  video.author.isNotEmpty
                      ? video.author[0]
                          .toUpperCase()
                      : '?',
                  style: AppTheme.body.copyWith(
                      color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(video.author,
                  style: AppTheme.body.copyWith(
                      fontWeight:
                          FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(
                        content: Text(
                            'Subscriptions need YouTube sign-in')));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFFFF0000),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                            20)),
              ),
              child: const Text('Subscribe'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _PillAction(
                icon: Icons.thumb_up_outlined,
                label: formatCount(ui.votes.likes ??
                    video.viewCount),
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _PillAction(
                icon: Icons.thumb_down_outlined,
                label:
                    formatCount(ui.votes.dislikes),
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _PillAction(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () => Share.share(
                    'https://youtu.be/${video.id}'),
              ),
              const SizedBox(width: 8),
              _PillAction(
                icon: Icons.download_outlined,
                label: 'Download',
                highlighted: true,
                onTap: () {
                  final s = ui.streams;
                  if (s != null) {
                    DownloadDialog.show(
                        context, video, s);
                  }
                },
              ),
              const SizedBox(width: 8),
              _PillAction(
                icon:
                    Icons.playlist_add_outlined,
                label: 'Save',
                onTap: () {},
              ),
            ],
          ),
        ),
        if (video.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Description',
              style: AppTheme.body.copyWith(
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(video.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                  color:
                      AppTheme.textSecondary)),
        ],
      ],
    );
  }
}

class _PillAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  const _PillAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(20),
          gradient: highlighted
              ? AppTheme.premiumGradient
              : null,
          color:
              highlighted ? null : AppTheme.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(label,
                style: AppTheme.body.copyWith(
                    color: Colors.white,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
