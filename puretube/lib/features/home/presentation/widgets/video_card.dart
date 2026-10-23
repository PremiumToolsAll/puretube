import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../../../library/domain/entities/library_models.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/screens/playlists_screen.dart'
    show showSaveToPlaylistSheet;
import '../../../channel/presentation/screens/channel_screen.dart';
import '../../../player/domain/entities/playback_models.dart';
import '../../../player/presentation/screens/player_screen.dart';

/// Video list card, SparkTube/YouTube-app pattern: full-width 16:9
/// thumbnail with a duration badge, then a circle channel avatar
/// beside a 2-line bold title and ONE combined
/// "Channel • views • time" meta line, with a ⋮ options button
/// (Share / Download / Watch Later / Save to playlist).
/// (No channel-avatar URLs in our data — the avatar is the channel
/// initial on a themed disc, like YouTube's fallback.)
class VideoCard extends ConsumerWidget {
  final VideoDetails video;
  const VideoCard({super.key, required this.video});

  /// Opens this card's options sheet for any [video] — shared
  /// with the channel page's video rows so every surface offers
  /// the same Share / Download / Watch Later / Save Playlist.
  static void showOptions(
          BuildContext context, WidgetRef ref, VideoDetails video) =>
      _showOptions(context, ref, video);

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(videoId: video.id)),
    );
  }

  static String _sizeText(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Size unknown';
    if (bytes >= (1 << 30)) {
      return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }

  static Future<void> _download(
      BuildContext context, WidgetRef ref, VideoDetails video) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('ডাউনলোডের অপশন আনা হচ্ছে…'),
      duration: Duration(seconds: 2),
    ));
    List<DownloadOption> options;
    try {
      options = await ref.read(extractorProvider).getDownloadOptions(video.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('অপশন পাওয়া যায়নি: $e')));
      return;
    }
    if (!context.mounted) return;
    final videoOpts = options.where((o) => !o.audioOnly).toList();
    final audioOpts = options.where((o) => o.audioOnly).toList();
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('ডাউনলোড',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final o in videoOpts)
              ListTile(
                leading: const Icon(Icons.video_file_outlined),
                title: Text(o.label),
                subtitle: Text(_sizeText(o.sizeBytes)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  unawaited(ref
                      .read(downloadsControllerProvider.notifier)
                      .startDownload(
                        o,
                        video,
                        audioOption: o.videoOnly && audioOpts.isNotEmpty
                            ? audioOpts.first
                            : null,
                      ));
                  messenger.showSnackBar(
                      const SnackBar(content: Text('ডাউনলোড শুরু হয়েছে')));
                },
              ),
            for (final o in audioOpts)
              ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: Text('Audio • ${o.label}'),
                subtitle: Text(_sizeText(o.sizeBytes)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  unawaited(ref
                      .read(downloadsControllerProvider.notifier)
                      .startDownload(o, video));
                  messenger.showSnackBar(
                      const SnackBar(content: Text('ডাউনলোড শুরু হয়েছে')));
                },
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> _watchLater(
      BuildContext context, WidgetRef ref, VideoDetails video) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(playlistsControllerProvider.notifier);
    var playlists = ref.read(playlistsControllerProvider);
    Playlist? wl;
    for (final p in playlists) {
      if (p.name == 'Watch Later') {
        wl = p;
        break;
      }
    }
    if (wl == null) {
      await notifier.create('Watch Later');
      playlists = ref.read(playlistsControllerProvider);
      for (final p in playlists) {
        if (p.name == 'Watch Later') {
          wl = p;
          break;
        }
      }
    }
    if (wl == null) return;
    final added = await notifier.addVideo(
      wl.id,
      PlaylistItem(
        videoId: video.id,
        title: video.title,
        author: video.author,
        thumbnailUrl: video.thumbnailUrl,
        addedAt: DateTime.now(),
      ),
    );
    messenger.showSnackBar(SnackBar(
      content:
          Text(added ? 'Watch Later-এ সেভ হয়েছে' : 'আগেই Watch Later-এ আছে'),
      duration: const Duration(seconds: 2),
    ));
  }

  static void _showOptions(
      BuildContext context, WidgetRef ref, VideoDetails video) {
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
              leading: const Icon(Icons.share_outlined),
              title: const Text('শেয়ার'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Share.share('https://www.youtube.com/watch?v=${video.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('ডাউনলোড'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_download(context, ref, video));
              },
            ),
            ListTile(
              leading: const Icon(Icons.watch_later_outlined),
              title: const Text('Watch Later'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_watchLater(context, ref, video));
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('প্লেলিস্টে সেভ'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showSaveToPlaylistSheet(context, video);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ago = timeAgo(video.uploadDate);
    final meta = <String>[
      video.author,
      if (video.viewCount != null) '${formatCount(video.viewCount)} views',
      if (ago.isNotEmpty) ago,
    ].where((s) => s.isNotEmpty).join(' · ');
    final initial = video.author.trim().isNotEmpty
        ? video.author.trim()[0].toUpperCase()
        : '?';
    // YouTube-style watched-progress: when this video was partly
    // watched before, a red bar under the thumbnail shows how far.
    final totalSecs = video.duration?.inSeconds ?? 0;
    final watchedSecs =
        ref.read(historyRepositoryProvider).getPosition(video.id);
    final double? watchedFrac =
        (totalSecs > 10 && watchedSecs > 5 && watchedSecs < totalSecs - 10)
            ? watchedSecs / totalSecs
            : null;
    return InkWell(
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: video.thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainer),
                  errorWidget: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
                if ((video.duration ?? Duration.zero) > Duration.zero)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatDuration(video.duration),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
                if (watchedFrac != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3,
                      color: Colors.white24,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: watchedFrac,
                          child: Container(height: 3, color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tapping the channel icon opens the channel page.
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: video.channelId.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ChannelScreen(channelId: video.channelId),
                            ),
                          ),
                  child: Builder(builder: (context) {
                    final logo =
                        ref.watch(channelLogoProvider)[video.channelId];
                    if (logo == null && video.channelId.isNotEmpty) {
                      // Fetch once per channel; cached forever.
                      ref
                          .read(channelLogoProvider.notifier)
                          .ensure(video.channelId);
                    }
                    return CircleAvatar(
                      radius: 18,
                      backgroundColor: scheme.primaryContainer,
                      backgroundImage: logo != null
                          ? CachedNetworkImageProvider(logo)
                          : null,
                      child: logo == null
                          ? Text(
                              initial,
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            )
                          : null,
                    );
                  }),
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
                            color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  color: scheme.onSurface,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => _showOptions(context, ref, video),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
