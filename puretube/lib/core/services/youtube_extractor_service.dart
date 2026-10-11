import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../error/exceptions.dart';
import '../../features/player/domain/entities/playback_models.dart';

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

class YoutubeExtractorService {
  YoutubeExtractorService({YoutubeExplode? client, Connectivity? connectivity})
      : _yt = client ?? YoutubeExplode(),
        _connectivity = connectivity ?? Connectivity();

  final YoutubeExplode _yt;
  final Connectivity _connectivity;

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

      // All muxed qualities for the quality selector (dedupe by height).
      final seenHeights = <int>{};
      final qualities = <QualityOption>[];
      for (final s in muxedPick) {
        final h = s.videoQuality.height;
        if (seenHeights.add(h)) {
          qualities.add(QualityOption(
            label: '${h}p',
            height: h,
            url: s.url.toString(),
          ));
        }
      }
      // Sort by height, best first.
      qualities.sort((a, b) => b.height.compareTo(a.height));

      return PlaybackStreams(
        videoId: videoId,
        muxedUrl: bestMuxed.url.toString(),
        muxedHeight: bestMuxed.videoQuality.height,
        qualities: qualities,
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
      final audio = [...manifest.audioOnly]
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

      final options = <DownloadOption>[
        for (final m in muxed)
          DownloadOption(
            label: m.videoQuality.qualityString,
            url: m.url.toString(),
            audioOnly: false,
            sizeBytes: m.size.totalBytes,
          ),
      ];
      if (audio.isNotEmpty) {
        final a = audio.first;
        options.add(DownloadOption(
          label:
              'Audio ${(a.bitrate.bitsPerSecond / 1000).round()}kbps',
          url: a.url.toString(),
          audioOnly: true,
          sizeBytes: a.size.totalBytes,
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

  /// Returns videos related to [videoId] for the "Up next" section.
  /// Uses search with the video title as query (fallback approach).
  Future<List<VideoDetails>> getRelatedVideos(String videoId,
      {int limit = 15}) async {
    // TODO: Use proper related videos API when available.
    // For now return empty - the section will be hidden.
    return [];
  }

  /// Returns trending/popular videos for the home feed.
  /// Uses a generic popular search since youtube_explode_dart 2.x
  /// has no dedicated trending API.
  Future<List<VideoDetails>> getTrendingVideos({int limit = 25}) async {
    await _requireNetwork();
    try {
      // "trending" search returns popular current videos.
      final results = await _yt.search
          .search('trending')
          .timeout(const Duration(seconds: 25));
      return results
          .whereType<Video>()
          .take(limit)
          .map(VideoDetails.fromExplode)
          .toList();
    } on TimeoutException {
      throw ExtractorException('Trending timed out. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      throw ExtractorException(
          'Could not load trending: ${_friendlyError(e)}');
    }
  }

  void dispose() => _yt.close();
}
