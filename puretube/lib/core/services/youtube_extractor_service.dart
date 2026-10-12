import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../error/exceptions.dart';
import '../../features/player/domain/entities/playback_models.dart';
import 'watch_category_tracker.dart';

/// All YouTube contact goes through here. Everything else in the app
/// talks to [VideoDetails] / [PlaybackStreams] / [DownloadOption], so when
/// YouTube breaks the extractor (and it will, periodically), the fix
/// lands in one file: bump youtube_explode_dart and adjust here.

/// Converts technical extractor errors to user-friendly Bengali messages.
String _friendlyError(Object e) {
  final msg = e.toString();
  if (msg.contains('RequestLimitExceededException') ||
      msg.contains('rate limiting')) {
    return 'YouTube সাময়িকভাবে block করেছে (অনেক request)। ১-২ ঘণ্টা পরে আবার চেষ্টা করো, অথবা WiFi/mobile data বদলে দেখো।';
  }
  if (msg.contains('FormatException')) {
    return 'YouTube data পড়তে সমস্যা হয়েছে। Retry চাপো।';
  }
  return msg;
}

/// Height in pixels for a [VideoQuality] (youtube_explode_dart 2.5.3 made it a plain enum).
extension VideoQualityHeight on VideoQuality {
  int get height => switch (this) {
        VideoQuality.low144 => 144,
        VideoQuality.low240 => 240,
        VideoQuality.medium360 => 360,
        VideoQuality.medium480 => 480,
        VideoQuality.high720 => 720,
        VideoQuality.high1080 => 1080,
        VideoQuality.high1440 => 1440,
        VideoQuality.high2160 => 2160,
        VideoQuality.high2880 => 2880,
        VideoQuality.high3072 => 3072,
        VideoQuality.high4320 => 4320,
        VideoQuality.unknown => 0,
      };
}

/// Holds a paged YouTube search for infinite scroll.
/// Created by [YoutubeExtractorService.startPagedSearch]; fetch more
/// with [YoutubeExtractorService.fetchMoreSearchResults].
class SearchSession {
  SearchSession._(this._list, this.firstPage);

  // ignore: prefer_final_fields - reassigned on each nextPage()
  VideoSearchList _list;

  /// Videos from the first page.
  final List<VideoDetails> firstPage;
}

class YoutubeExtractorService {
  YoutubeExtractorService({YoutubeExplode? client, Connectivity? connectivity})
      : _yt = client ?? YoutubeExplode(),
        _connectivity = connectivity ?? Connectivity();

  final YoutubeExplode _yt;
  final Connectivity _connectivity;

  /// Short codec display name: "avc1.640028" -> "avc", "av01.0.08M.08"
  /// -> "av1", "mp4a.40.2" -> "mp4a".
  static String _shortCodec(String codec) {
    final c = codec.toLowerCase();
    if (c.startsWith('avc1') || c.startsWith('avc3')) return 'avc';
    if (c.startsWith('vp9') || c.startsWith('vp09')) return 'vp9';
    if (c.startsWith('av01')) return 'av1';
    if (c.startsWith('mp4a')) return 'mp4a';
    if (c.startsWith('opus')) return 'opus';
    final dot = c.indexOf('.');
    return dot > 0 ? c.substring(0, dot) : c;
  }

  Future<void> _requireNetwork() async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      throw NetworkException();
    }
  }

  Future<VideoDetails> getVideoDetails(String videoId) async {
    await _requireNetwork();
    try {
      final video =
          await _yt.videos.get(videoId).timeout(const Duration(seconds: 25));
      return VideoDetails.fromExplode(video);
    } on TimeoutException {
      throw ExtractorException(
          'YouTube is taking too long to respond. Retry.');
    } on VideoUnplayableException catch (e) {
      throw UnplayableVideoException(videoId, e.message);
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException('Could not load video details: ${_friendlyError(e)}');
    }
  }

  /// Returns a muxed (audio+video) URL any player can handle, plus the
  /// best audio-only URL for background mode.
  Future<PlaybackStreams> getPlaybackStreams(
    String videoId, {
    int maxMuxedHeight = 720,
  }) async {
    await _requireNetwork();
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 30));

      final muxed = [...manifest.muxed]
        ..sort((a, b) =>
            b.videoQuality.height.compareTo(a.videoQuality.height));
      final muxedPick =
          muxed.where((s) => s.videoQuality.height <= maxMuxedHeight);

      final audio = [...manifest.audioOnly]
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

      if (muxedPick.isEmpty || audio.isEmpty) {
        throw UnplayableVideoException(videoId,
            'No playable streams for this video (it may be live, age-restricted, or rental-only).');
      }

      final bestMuxed = muxedPick.first;
      final bestAudio = audio.first;

      return PlaybackStreams(
        videoId: videoId,
        muxedUrl: bestMuxed.url.toString(),
        muxedHeight: bestMuxed.videoQuality.height,
        audioOnlyUrl: bestAudio.url.toString(),
        audioBitrate: bestAudio.bitrate.bitsPerSecond,
        fetchedAt: DateTime.now(),
      );
    } on TimeoutException {
      throw ExtractorException(
          'Timed out fetching streams. Check your connection and retry.');
    } on VideoUnplayableException catch (e) {
      throw UnplayableVideoException(videoId, e.message);
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException('Could not extract streams: $e');
    }
  }

  /// Lists all muxed (audio+video) quality options for a video,
  /// sorted by height descending. Labels look like "MPEG-4 720p".
  /// One entry per distinct height (duplicates by codec are dropped).
  Future<List<MuxedQuality>> getQualityOptions(
      String videoId) async {
    await _requireNetwork();
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 30));

      final muxed = [...manifest.muxed]
        ..sort((a, b) => b.videoQuality.height
            .compareTo(a.videoQuality.height));

      if (muxed.isEmpty) {
        throw UnplayableVideoException(videoId,
            'No playable streams for this video.');
      }

      final seenHeights = <int>{};
      final options = <MuxedQuality>[];
      for (final m in muxed) {
        final h = m.videoQuality.height;
        if (h <= 0 || !seenHeights.add(h)) continue;
        options.add(MuxedQuality(
          label: 'MPEG-4 ${h}p',
          height: h,
          url: m.url.toString(),
          bitrateKbps: m.bitrate.bitsPerSecond / 1000,
          fps: m.framerate.framesPerSecond.round(),
          codec: _shortCodec(m.videoCodec),
        ));
      }

      // DASH video-only streams (1080p/1440p/2160p+) + best separate
      // audio track. mpv plays these by attaching the audio URL via the
      // 'audio-file' property (see PureTubeAudioHandler.switchStream).
      final audioOnly = [...manifest.audioOnly]
        ..sort((a, b) =>
            b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      if (audioOnly.isNotEmpty) {
        final audioUrl = audioOnly.first.url.toString();
        final videoOnly = [...manifest.videoOnly]
          ..sort((a, b) => b.videoResolution.height
              .compareTo(a.videoResolution.height));
        for (final v in videoOnly) {
          final h = v.videoResolution.height;
          if (h <= 720 || !seenHeights.add(h)) continue;
          final resLabel = h >= 2160
              ? '2160p (2K)'
              : h >= 1440
                  ? '1440p (1.5K)'
                  : '${h}p';
          options.add(MuxedQuality(
            label: '$resLabel · DASH',
            height: h,
            url: v.url.toString(),
            audioUrl: audioUrl,
            bitrateKbps: v.bitrate.bitsPerSecond / 1000,
            fps: v.framerate.framesPerSecond.round(),
            codec: _shortCodec(v.videoCodec),
          ));
        }
      }

      options.sort((a, b) => b.height.compareTo(a.height));
      if (options.isEmpty) {
        throw UnplayableVideoException(videoId,
            'No playable streams for this video.');
      }
      return options;
    } on TimeoutException {
      throw ExtractorException(
          'Timed out fetching qualities. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException('Could not list qualities: $e');
    }
  }

  /// Lists every downloadable stream: all muxed qualities + best audio.
  Future<List<DownloadOption>> getDownloadOptions(
      String videoId) async {
    await _requireNetwork();
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 30));

      final muxed = [...manifest.muxed]
        ..sort((a, b) => b.videoQuality.height
            .compareTo(a.videoQuality.height));
      final videoOnly = [...manifest.videoOnly]
        ..sort((a, b) => b.videoResolution.height
            .compareTo(a.videoResolution.height));
      final audio = [...manifest.audioOnly]
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

      final options = <DownloadOption>[];
      final seenVideo = <String>{};
      for (final m in muxed) {
        final h = m.videoQuality.height;
        if (h <= 0 || !seenVideo.add('muxed-$h')) continue;
        options.add(DownloadOption(
          label: '${h}p',
          url: m.url.toString(),
          audioOnly: false,
          sizeBytes: m.size.totalBytes,
          videoCodec: m.videoCodec,
          audioCodec: m.audioCodec,
          height: h,
          bitrateKbps: (m.bitrate.bitsPerSecond / 1000).round(),
          fps: m.framerate.framesPerSecond.round(),
        ));
      }
      for (final v in videoOnly) {
        final h = v.videoResolution.height;
        if (h <= 0 || !seenVideo.add('vo-$h-${v.videoCodec}')) continue;
        options.add(DownloadOption(
          label: '${h}p ${v.videoCodec}',
          url: v.url.toString(),
          audioOnly: false,
          sizeBytes: v.size.totalBytes,
          videoCodec: v.videoCodec,
          height: h,
          videoOnly: true,
          bitrateKbps: (v.bitrate.bitsPerSecond / 1000).round(),
          fps: v.framerate.framesPerSecond.round(),
        ));
      }
      final seenAudio = <int>{};
      for (final a in audio) {
        final kbps = (a.bitrate.bitsPerSecond / 1000).round();
        if (!seenAudio.add(kbps)) continue;
        options.add(DownloadOption(
          label: '$kbps kbps ${a.audioCodec}',
          url: a.url.toString(),
          audioOnly: true,
          sizeBytes: a.size.totalBytes,
          audioCodec: a.audioCodec,
          bitrateKbps: kbps,
        ));
      }
      if (options.isEmpty) {
        throw UnplayableVideoException(videoId,
            'No downloadable streams for this video.');
      }
      return options;
    } on TimeoutException {
      throw ExtractorException('Timed out. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException('Could not list downloads: $e');
    }
  }

  Future<List<VideoDetails>> searchVideos(String query,
      {int limit = 25}) async {
    await _requireNetwork();
    try {
      final results = await _yt.search
          .search(query)
          .timeout(const Duration(seconds: 25));
      return results
          .whereType<Video>()
          .take(limit)
          .map(VideoDetails.fromExplode)
          .toList();
    } on TimeoutException {
      throw ExtractorException('Search timed out. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException('Search failed: ${_friendlyError(e)}');
    }
  }

  /// Starts a paged search session for infinite scroll.
  /// Returns the first page; call [fetchMoreSearchResults] for more.
  Future<SearchSession> startPagedSearch(String query,
      {int limit = 25}) async {
    await _requireNetwork();
    try {
      final results = await _yt.search
          .search(query)
          .timeout(const Duration(seconds: 25));
      final videos = results
          .whereType<Video>()
          .take(limit)
          .map(VideoDetails.fromExplode)
          .toList();
      return SearchSession._(results, videos);
    } on TimeoutException {
      throw ExtractorException('Search timed out. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException('Search failed: ${_friendlyError(e)}');
    }
  }

  /// Fetches the next page of a [SearchSession]. Returns empty list
  /// when there are no more pages.
  Future<List<VideoDetails>> fetchMoreSearchResults(
      SearchSession session,
      {int limit = 25}) async {
    try {
      final next = await session._list
          .nextPage()
          ?.timeout(const Duration(seconds: 25));
      if (next == null) return const [];
      session._list = next;
      return next
          .whereType<Video>()
          .take(limit)
          .map(VideoDetails.fromExplode)
          .toList();
    } on TimeoutException {
      throw ExtractorException('Timed out loading more. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException('Could not load more: ${_friendlyError(e)}');
    }
  }

  void dispose() => _yt.close();

  /// Lists subtitle/caption tracks for a video. Returns empty list
  /// when the video has no captions (never throws).
  Future<List<CaptionTrack>> getCaptionTracks(
      String videoId) async {
    try {
      final manifest = await _yt
          .videos.closedCaptions
          .getManifest(videoId)
          .timeout(const Duration(seconds: 20));
      return manifest.tracks
          .map((t) => CaptionTrack(
                languageCode: t.language.code,
                language: t.language.name,
                url: t.url.toString(),
                isAutoGenerated: t.isAutoGenerated,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches basic channel info for the channel page.
  Future<ChannelInfo> getChannel(String channelId) async {
    await _requireNetwork();
    try {
      final ch = await _yt.channels
          .get(channelId)
          .timeout(const Duration(seconds: 25));
      return ChannelInfo(
        id: ch.id.value,
        title: ch.title,
        logoUrl: ch.logoUrl,
        bannerUrl: ch.bannerUrl,
        subscriberCount: ch.subscribersCount,
      );
    } on TimeoutException {
      throw ExtractorException('Channel timed out. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException(
          'Could not load channel: ${_friendlyError(e)}');
    }
  }

  /// Lists recent uploads from a channel. Tries the uploads-page API
  /// first (most reliable), falling back to the UU-playlist method.
  Future<List<VideoDetails>> getChannelUploads(
      String channelId,
      {int limit = 30}) async {
    await _requireNetwork();
    try {
      final page = await _yt.channels
          .getUploadsFromPage(channelId)
          .timeout(const Duration(seconds: 30));
      final videos = page.take(limit).toList();
      if (videos.isNotEmpty) {
        return videos
            .map(VideoDetails.fromExplode)
            .toList();
      }
    } catch (_) {
      // Fall through to the UU-playlist method below.
    }
    try {
      final uploads = await _yt.channels
          .getUploads(channelId)
          .take(limit)
          .toList()
          .timeout(const Duration(seconds: 30));
      return uploads
          .map(VideoDetails.fromExplode)
          .toList();
    } on TimeoutException {
      throw ExtractorException('Channel videos timed out.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException(
          'Could not load uploads: ${_friendlyError(e)}');
    }
  }

  /// Fetches "Up Next" suggestions for a video. youtube_explode_dart 3.x
  /// exposes no public related-videos API, so we search using the
  /// video's author + title and exclude the video itself.
  ///
  /// Uses a multi-strategy fallback so the section rarely comes back
  /// empty:
  ///   1. author + title (most relevant — e.g. same song/artist)
  ///   2. title keywords (meaningful words only, stop-words removed)
  ///   3. author only (more videos from the same channel)
  ///   4. short title keywords (broader net)
  ///
  /// [titleHint]/[authorHint] let callers that already loaded the video
  /// details skip the extra `videos.get` network call.
  /// [boostCategories] (most important first) re-ranks results so videos
  /// matching the user's frequent categories surface at the top.
  /// Returns an empty list (never throws) only if every strategy fails.
  Future<List<VideoDetails>> getRelatedVideos(String videoId,
      {int limit = 12,
      String? titleHint,
      String? authorHint,
      List<String> boostCategories = const []}) async {
    try {
      await _requireNetwork();

      String title = titleHint ?? '';
      String author = authorHint ?? '';
      if (title.isEmpty || author.isEmpty) {
        try {
          final video = await _yt.videos
              .get(videoId)
              .timeout(const Duration(seconds: 20));
          if (title.isEmpty) title = video.title;
          if (author.isEmpty) author = video.author;
        } catch (e) {
          debugPrint('getRelatedVideos: videos.get failed: $e');
        }
      }

      final queries = <String>[];
      final authorTitle = '$author $title'.trim();
      if (authorTitle.isNotEmpty) queries.add(authorTitle);

      final keywords = _titleKeywords(title);
      if (keywords.isNotEmpty) {
        queries.add(keywords.join(' '));
      }
      if (author.trim().isNotEmpty) {
        queries.add(author.trim());
      }
      // Broadest net: first few keywords only.
      if (keywords.length > 2) {
        queries.add(keywords.take(3).join(' '));
      }

      final seen = <String>{videoId};
      final collected = <VideoDetails>[];
      for (final query in queries) {
        if (collected.length >= limit) break;
        try {
          final results = await _yt.search
              .search(query)
              .timeout(const Duration(seconds: 20));
          for (final v in results.whereType<Video>()) {
            if (seen.add(v.id.value)) {
              collected.add(VideoDetails.fromExplode(v));
              if (collected.length >= limit) break;
            }
          }
        } catch (e) {
          debugPrint('getRelatedVideos: search "$query" failed: $e');
        }
      }
      // Category boost: rank results matching the user's frequent
      // categories first (earlier category = stronger boost).
      if (boostCategories.isNotEmpty && collected.length > 1) {
        collected.sort((a, b) => _categoryScore(b.title, boostCategories)
            .compareTo(_categoryScore(a.title, boostCategories)));
      }
      return collected;
    } catch (e) {
      debugPrint('getRelatedVideos: fatal failure for $videoId: $e');
      return [];
    }
  }

  /// Scores how well a title matches the boosted categories.
  /// Earlier categories in the list score higher.
  static int _categoryScore(String title, List<String> categories) {
    final t = title.toLowerCase();
    var score = 0;
    for (var i = 0; i < categories.length; i++) {
      final kws = WatchCategoryTracker.categoryKeywords[categories[i]];
      if (kws == null) continue;
      for (final kw in kws) {
        if (t.contains(kw)) {
          score += (categories.length - i) * 2;
          break;
        }
      }
    }
    return score;
  }

  /// Words that carry no signal for "more like this" searches.
  static const _relatedStopWords = <String>{
    'the', 'and', 'for', 'with', 'from', 'this', 'that', 'you',
    'your', 'are', 'was', 'were', 'has', 'have', 'had', 'will',
    'would', 'can', 'not', 'but', 'all', 'any', 'out', 'new',
    'official', 'video', 'full', 'part', 'episode', 'ep', 'hd',
    '4k', '8k', 'lyrics', 'lyric', 'audio', 'song', 'songs',
    'music', 'movie', 'film', 'trailer', 'teaser', 'promo',
    '2024', '2025', '2026', '2027',
  };

  /// Extracts the most meaningful search keywords from a video title:
  /// drops punctuation, stop-words and tiny tokens, keeps order,
  /// caps at 6 words so the query stays focused.
  static List<String> _titleKeywords(String title) {
    final words = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_relatedStopWords.contains(w))
        .toList();
    // De-dupe while preserving order.
    final unique = <String>[];
    for (final w in words) {
      if (!unique.contains(w)) unique.add(w);
    }
    return unique.take(6).toList();
  }
}
