import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/format.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../player/presentation/screens/hidden_webview_player.dart';

/// Video list card, SparkTube/YouTube-app pattern: full-width 16:9
/// thumbnail with a duration badge, then a circle channel avatar
/// beside a 2-line bold title and ONE combined
/// "Channel • views • time" meta line, with a ⋮ options button.
/// (No channel-avatar URLs in our data — the avatar is the channel
/// initial on a themed disc, like YouTube's fallback.)
class VideoCard extends StatelessWidget {
  final VideoDetails video;
  const VideoCard({super.key, required this.video});

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PlayerScreen(videoId: video.id)),
    );
  }

  void _openWebView(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HiddenWebViewPlayer(
          videoId: video.id,
          title: video.title,
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('এখনই চালাও'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _open(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('WebView প্লেয়ারে খুলুন'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openWebView(context);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ago = timeAgo(video.uploadDate);
    final meta = <String>[
      video.author,
      if (video.viewCount != null)
        '${formatCount(video.viewCount)} views',
      if (ago.isNotEmpty) ago,
    ].where((s) => s.isNotEmpty).join(' • ');
    final initial = video.author.trim().isNotEmpty
        ? video.author.trim()[0].toUpperCase()
        : '?';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      // Long-press opens the hidden WebView player
      // (browser engine — all qualities work like Chrome).
      onLongPress: () => _openWebView(context),
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
                    placeholder: (_, __) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainer),
                    errorWidget: (_, __, ___) => Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainer,
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
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                color: scheme.onSurface,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 36, minHeight: 36),
                onPressed: () => _showOptions(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
