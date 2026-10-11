import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Lightweight video model for UI (decouples UI from explode types).
class VideoItem {
  final String id;
  final String title;
  final String author;
  final String channelId;
  final Duration? duration;
  final String thumbnailUrl;
  final int? viewCount;
  final DateTime? uploadDate;
  final String description;

  const VideoItem({
    required this.id,
    required this.title,
    required this.author,
    required this.channelId,
    required this.duration,
    required this.thumbnailUrl,
    required this.viewCount,
    required this.uploadDate,
    required this.description,
  });

  factory VideoItem.fromVideo(Video v) => VideoItem(
        id: v.id.value,
        title: v.title,
        author: v.author,
        channelId: v.channelId.value,
        duration: v.duration,
        thumbnailUrl: v.thumbnails.highResUrl,
        viewCount: v.engagement.viewCount,
        uploadDate: v.uploadDate,
        description: v.description,
      );
}

/// Playback quality option (muxed or DASH video-only + audio).
class QualityOption {
  final String label;
  final int height;
  final String url;
  final String? audioUrl;

  const QualityOption({
    required this.label,
    required this.height,
    required this.url,
    this.audioUrl,
  });

  bool get isVideoOnly => audioUrl != null;
}

/// Resolved streams for one video.
class PlaybackStreams {
  final String videoId;
  final String muxedUrl;
  final int muxedHeight;
  final List<QualityOption> qualities;
  final String audioOnlyUrl;

  const PlaybackStreams({
    required this.videoId,
    required this.muxedUrl,
    required this.muxedHeight,
    required this.qualities,
    required this.audioOnlyUrl,
  });
}

/// SponsorBlock segment.
class SponsorSegment {
  final double start;
  final double end;
  final String category;

  const SponsorSegment({
    required this.start,
    required this.end,
    required this.category,
  });
}
