import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Share video links + handle incoming YouTube URLs.
class ShareService {
  ShareService._();
  static final ShareService instance =
      ShareService._();

  /// Share a video link to other apps.
  Future<void> shareVideo(String videoId,
      {Duration? timestamp}) async {
    var link = 'https://youtu.be/$videoId';
    if (timestamp != null &&
        timestamp > Duration.zero) {
      link += '?t=${timestamp.inSeconds}';
    }
    await Share.share(link);
  }

  /// Share with a human-readable timestamp label.
  Future<void> shareVideoAt(
      String videoId, Duration position) async {
    final label = _formatTimestamp(position);
    await Share.share(
        'Watch from $label - https://youtu.be/$videoId?t=${position.inSeconds}');
  }

  String _formatTimestamp(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Copy link to clipboard.
  Future<void> copyLink(String videoId,
      {Duration? timestamp}) async {
    var link = 'https://youtu.be/$videoId';
    if (timestamp != null &&
        timestamp > Duration.zero) {
      link += '?t=${timestamp.inSeconds}';
    }
    await Clipboard.setData(
        ClipboardData(text: link));
  }

  /// Extract a YouTube video id from a shared URL.
  /// Supports: youtube.com/watch?v=, youtu.be/, youtube.com/shorts/
  static String? extractVideoId(String url) {
    try {
      final uri = Uri.parse(url.trim());
      // youtu.be/VIDEOID
      if (uri.host.contains('youtu.be')) {
        final id = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first
            : '';
        return id.isNotEmpty ? id : null;
      }
      // youtube.com/watch?v=VIDEOID
      if (uri.host.contains('youtube.com')) {
        final v =
            uri.queryParameters['v'];
        if (v != null && v.isNotEmpty) {
          return v;
        }
        // youtube.com/shorts/VIDEOID
        final segs = uri.pathSegments;
        final shortsIdx =
            segs.indexOf('shorts');
        if (shortsIdx >= 0 &&
            shortsIdx + 1 < segs.length) {
          return segs[shortsIdx + 1];
        }
        // youtube.com/embed/VIDEOID
        final embedIdx =
            segs.indexOf('embed');
        if (embedIdx >= 0 &&
            embedIdx + 1 < segs.length) {
          return segs[embedIdx + 1];
        }
      }
      // puretube://video/VIDEOID
      if (uri.scheme == 'puretube' &&
          uri.host == 'video' &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Build a PureTube deep link for a video.
  static String deepLink(String videoId) =>
      'puretube://video/$videoId';
}
