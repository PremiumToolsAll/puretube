import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class VideoDetails {
  final String id;
  final String title;
  final String author;
  final String channelId;
  final Duration? duration;
  final String thumbnailUrl;
  final int? viewCount;
  final DateTime? uploadDate;
  final String description;

  const VideoDetails({
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

  factory VideoDetails.fromExplode(Video video) => VideoDetails(
        id: video.id.value,
        title: video.title,
        author: video.author,
        channelId: video.channelId.value,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl,
        viewCount: video.engagement.viewCount,
        uploadDate: video.uploadDate,
        description: video.description,
      );
}

class PlaybackStreams {
  /// YouTube-issued stream URLs expire after ~6 hours. We treat them as
  /// stale a little early so refresh happens before a 403 mid-playback.
  static const streamTtl = Duration(hours: 5, minutes: 30);

  final String videoId;
  final String muxedUrl; // audio+video in one URL, up to 720p
  final int muxedHeight;
  final String audioOnlyUrl; // highest-bitrate audio, for background mode
  final int audioBitrate;
  final DateTime fetchedAt;

  const PlaybackStreams({
    required this.videoId,
    required this.muxedUrl,
    required this.muxedHeight,
    required this.audioOnlyUrl,
    required this.audioBitrate,
    required this.fetchedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > streamTtl;
}

class DownloadOption {
  final String label; // "720p", "480p", "Audio"
  final String url;
  final bool audioOnly;
  final int? sizeBytes;

  const DownloadOption({
    required this.label,
    required this.url,
    required this.audioOnly,
    this.sizeBytes,
  });
}
