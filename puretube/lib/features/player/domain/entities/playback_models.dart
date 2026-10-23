import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Removes unpaired UTF-16 surrogates from remote text.
///
/// YouTube titles/authors occasionally arrive with a broken
/// surrogate pair (an emoji split across response chunks); a
/// lone surrogate makes Flutter's text layout throw
/// "string is not well-formed UTF-16" and crash the frame.
/// Sanitizing at the model boundary kills the whole class.
String sanitizeUtf16(String input) {
  var hasBroken = false;
  final units = input.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        i++;
      } else {
        hasBroken = true;
        break;
      }
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      hasBroken = true;
      break;
    }
  }
  if (!hasBroken) return input;
  final buffer = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        buffer.writeCharCode(u);
        buffer.writeCharCode(units[i + 1]);
        i++;
      }
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      // Lone low surrogate: drop.
    } else {
      buffer.writeCharCode(u);
    }
  }
  return buffer.toString();
}

class VideoDetails {
  final String id;
  final String title;
  final String author;
  final String channelId;
  final Duration? duration;
  final String thumbnailUrl;
  final int? viewCount;
  final int? likeCount;
  final DateTime? uploadDate;
  final String description;

  factory VideoDetails({
    required String id,
    required String title,
    required String author,
    required String channelId,
    required Duration? duration,
    required String thumbnailUrl,
    required int? viewCount,
    required int? likeCount,
    required DateTime? uploadDate,
    required String description,
  }) =>
      VideoDetails._(
        id: id,
        title: sanitizeUtf16(title),
        author: sanitizeUtf16(author),
        channelId: channelId,
        duration: duration,
        thumbnailUrl: thumbnailUrl,
        viewCount: viewCount,
        likeCount: likeCount,
        uploadDate: uploadDate,
        description: sanitizeUtf16(description),
      );

  const VideoDetails._({
    required this.id,
    required this.title,
    required this.author,
    required this.channelId,
    required this.duration,
    required this.thumbnailUrl,
    required this.viewCount,
    required this.likeCount,
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
        likeCount: video.engagement.likeCount,
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

  bool get isExpired => DateTime.now().difference(fetchedAt) > streamTtl;
}

class DownloadOption {
  final String label; // "720p", "480p", "Audio"
  final String url;
  final bool audioOnly;
  final int? sizeBytes;

  /// Video codec string (e.g. "avc1.640028", "vp9") for video options.
  final String? videoCodec;

  /// Audio codec string (e.g. "opus", "mp4a.40.2") for audio options.
  final String? audioCodec;

  /// Video height in px (0 for audio-only options).
  final int height;

  /// Audio bitrate in kbps (0 for video options).
  final int bitrateKbps;

  /// True for video-only DASH streams (no audio track).
  final bool videoOnly;

  /// Frames per second for video options (0 when unknown).
  final int fps;

  /// True for muxed streams (video+audio in one file).
  bool get isMuxed => !audioOnly && !videoOnly;

  /// Premium tier title, e.g. "High quality (1080p)", "Fast (360p)".
  String get tierTitle {
    if (audioOnly) {
      if (bitrateKbps >= 150) return 'Best quality (${bitrateKbps}K)';
      if (bitrateKbps >= 100) return 'High quality (${bitrateKbps}K)';
      if (bitrateKbps >= 60) return 'Balanced (${bitrateKbps}K)';
      return 'Small size (${bitrateKbps}K)';
    }
    if (height >= 1080) return 'High quality (${height}p)';
    if (height >= 720) return 'High quality (${height}p)';
    return 'Fast (${height}p)';
  }

  /// Premium tier description, e.g. "High details for full screen play".
  String get tierDescription {
    if (audioOnly) {
      final c = _shortCodecName(audioCodec);
      if (bitrateKbps >= 150) {
        return '$c, best for music and headphones';
      }
      if (bitrateKbps >= 100) {
        return '$c, best for mobile play';
      }
      return '$c, smaller size, works everywhere';
    }
    final parts = <String>[];
    final c = _shortCodecName(videoCodec);
    if (c.isNotEmpty) parts.add(c);
    if (fps > 0) parts.add('${fps}fps');
    if (bitrateKbps > 0) {
      parts.add(bitrateKbps >= 1000
          ? '${(bitrateKbps / 1000).toStringAsFixed(2)} Mbps'
          : '${bitrateKbps.toStringAsFixed(0)} Kbps');
    }
    if (videoOnly) parts.add('video-only, no audio');
    if (isMuxed) parts.add('with audio');
    final meta = parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
    if (height >= 1080) return 'High details for full screen play$meta';
    if (height >= 720) return 'Clear view and quick play$meta';
    if (height >= 480) return 'Normal quality for quick play$meta';
    if (height >= 240) return 'Low quality for quick play$meta';
    return 'Poor video quality$meta';
  }

  /// Badge text for special tiers ("Low" for tiny video, "Slow" for huge).
  String? get tierBadge {
    if (!audioOnly && height <= 144) return 'Low';
    if (sizeBytes != null && sizeBytes! >= (1 << 30)) return 'Slow';
    return null;
  }

  const DownloadOption({
    required this.label,
    required this.url,
    required this.audioOnly,
    this.sizeBytes,
    this.videoCodec,
    this.audioCodec,
    this.height = 0,
    this.bitrateKbps = 0,
    this.videoOnly = false,
    this.fps = 0,
  });
}

/// Short codec display name: "avc1.640028" -> "avc", "vp9" -> "vp9",
/// "av01.0.08M.08" -> "av1", "mp4a.40.2" -> "mp4a", "opus" -> "opus".
String _shortCodecName(String? codec) {
  if (codec == null || codec.isEmpty) return '';
  final c = codec.toLowerCase();
  if (c.startsWith('avc1') || c.startsWith('avc3')) return 'avc';
  if (c.startsWith('vp9') || c.startsWith('vp09')) return 'vp9';
  if (c.startsWith('av01')) return 'av1';
  if (c.startsWith('mp4a')) return 'mp4a';
  if (c.startsWith('opus')) return 'opus';
  final dot = c.indexOf('.');
  return dot > 0 ? c.substring(0, dot) : c;
}

/// A single stream quality option. Muxed = audio+video in one URL
/// (up to ~1080p). DASH = video-only stream that needs a separate
/// audio track attached (audioUrl != null), e.g. 1440p/2160p.
class MuxedQuality {
  final String label; // "MPEG-4 720p" or "1440p (1.5K) · DASH"
  final int height; // 720
  final String url;
  final String? audioUrl; // set for DASH video-only streams

  /// Bitrate in kbps (e.g. 17990 for 17.99 Mbps). 0 when unknown.
  final double bitrateKbps;

  /// Frames per second (e.g. 24, 30, 60). 0 when unknown.
  final int fps;

  /// Short codec name: "avc", "vp9", "av1". Empty when unknown.
  final String codec;

  /// Full codec string from the stream's mimeType, e.g. "avc1.640028".
  /// Needed by the native HQ (ExoPlayer) player to build a correct DASH
  /// manifest. Empty when unknown (HQ player derives from itag then).
  final String fullCodec;

  /// Full audio codec string for DASH entries, e.g. "mp4a.40.2".
  final String audioFullCodec;

  /// Audio bitrate in bps (DASH entries). 0 when unknown.
  final int audioBitrateBps;

  /// Audio sample rate in Hz (DASH entries), e.g. 44100. 0 when unknown.
  final int audioSampleRate;

  /// Byte ranges for on-demand DASH (SparkTube-style SegmentBase).
  /// From the player response's initRange/indexRange; -1 when unknown.
  final int initStart;
  final int initEnd;
  final int indexStart;
  final int indexEnd;

  /// Audio track's init/index ranges (for the audio AdaptationSet).
  final int audioInitStart;
  final int audioInitEnd;
  final int audioIndexStart;
  final int audioIndexEnd;

  /// True when the stream carries HDR (PQ/HLG) metadata, detected from
  /// the stream's quality label when the extractor exposes it.
  /// youtube_explode_dart does not surface per-stream color info, so
  /// this stays false unless the label names HDR explicitly — HDR
  /// streams still parse and play through the normal path (nothing in
  /// the pipeline assumes SDR, so there is no HDR-specific crash).
  final bool isHdr;

  const MuxedQuality({
    required this.label,
    required this.height,
    required this.url,
    this.audioUrl,
    this.bitrateKbps = 0,
    this.fps = 0,
    this.codec = '',
    this.isHdr = false,
    this.fullCodec = '',
    this.audioFullCodec = '',
    this.audioBitrateBps = 0,
    this.audioSampleRate = 0,
    this.initStart = -1,
    this.initEnd = -1,
    this.indexStart = -1,
    this.indexEnd = -1,
    this.audioInitStart = -1,
    this.audioInitEnd = -1,
    this.audioIndexStart = -1,
    this.audioIndexEnd = -1,
  });

  /// True when this is a video-only DASH stream needing external audio.
  bool get isDash => audioUrl != null;

  /// Premium detail line, e.g. "24fps · 17.99 Mbps · vp9".
  String get detailLine {
    final parts = <String>[];
    if (fps > 0) parts.add('${fps}fps');
    if (bitrateKbps > 0) {
      parts.add(bitrateKbps >= 1000
          ? '${(bitrateKbps / 1000).toStringAsFixed(2)} Mbps'
          : '${bitrateKbps.toStringAsFixed(0)} Kbps');
    }
    if (codec.isNotEmpty) parts.add(codec);
    return parts.join(' · ');
  }

  /// Display resolution, e.g. "2160p60 (2K)", "1440p (1.5K)", "720p",
  /// "720p60". High-frame-rate variants (>30fps) get the fps suffix so
  /// they are visually distinct from their 24/30fps twins at the same
  /// height (YouTube-style "720p60").
  String get resolutionLabel {
    final fpsSuffix = fps > 30 ? '$fps' : '';
    if (height >= 2160) return '2160p$fpsSuffix (2K)';
    if (height >= 1440) return '1440p$fpsSuffix (1.5K)';
    return '${height}p$fpsSuffix';
  }

  @override
  bool operator ==(Object other) =>
      other is MuxedQuality &&
      other.height == height &&
      other.fps == fps &&
      other.url == url &&
      other.audioUrl == audioUrl;

  @override
  int get hashCode => Object.hash(height, fps, url, audioUrl);
}

/// A subtitle/caption track available for a video.
class CaptionTrack {
  final String languageCode; // "en", "bn", ...
  final String language; // "English", "Bengali", ...
  final String url;
  final bool isAutoGenerated;

  const CaptionTrack({
    required this.languageCode,
    required this.language,
    required this.url,
    required this.isAutoGenerated,
  });
}

/// One timed caption line, rendered by the app's own overlay
/// (mpv used to render subtitle tracks; with mpv gone the player
/// draws the current cue itself from the plugin position).
class CaptionCue {
  final Duration start;
  final Duration end;
  final String text;

  const CaptionCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Basic channel info for the channel page.
class ChannelInfo {
  final String id;
  final String title;
  final String logoUrl;
  final String bannerUrl;
  final int? subscriberCount;

  const ChannelInfo({
    required this.id,
    required this.title,
    required this.logoUrl,
    required this.bannerUrl,
    required this.subscriberCount,
  });
}

/// One YouTube comment (read-only viewer data).
class VideoComment {
  final String author;
  final String channelId;
  final String text;
  final int likeCount;
  final String publishedTime; // YouTube's own text, e.g. "2 days ago"
  final int replyCount;
  final bool isHearted;

  const VideoComment({
    required this.author,
    required this.channelId,
    required this.text,
    required this.likeCount,
    required this.publishedTime,
    required this.replyCount,
    required this.isHearted,
  });
}

/// A dubbed audio language track (YouTube's "Audio Track" feature).
class AudioLanguage {
  final String id; // e.g. "b+4"
  final String displayName; // e.g. "Bangla", "English original"
  final bool isDefault;
  final String audioUrl;
  final int bitrateBps;

  const AudioLanguage({
    required this.id,
    required this.displayName,
    required this.isDefault,
    required this.audioUrl,
    required this.bitrateBps,
  });
}
