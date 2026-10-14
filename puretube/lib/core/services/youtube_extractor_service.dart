import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../error/exceptions.dart';
import '../../features/player/domain/entities/playback_models.dart';
import 'piped_service.dart';
import 'watch_category_tracker.dart';

/// All YouTube contact goes through here. Everything else in the app
/// talks to [VideoDetails] / [PlaybackStreams] / [DownloadOption], so when
/// YouTube breaks the extractor (and it will, periodically), the fix
/// lands in one file: bump youtube_explode_dart and adjust here.

/// Converts technical extractor errors to user-friendly Bengali messages.
String _friendlyError(Object e) {
  final msg = e.toString();
  final lower = msg.toLowerCase();
  if (lower.contains('login_required') ||
      lower.contains('confirm your age') ||
      lower.contains('age-restricted') ||
      lower.contains('age restricted') ||
      lower.contains('inappropriate for some users')) {
    return 'এই ভিডিওটি 18+ (বয়স যাচাই প্রয়োজন)। চালানোর চেষ্টা করা হয়েছে কিন্তু YouTube অনুমতি দেয়নি।';
  }
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
  //
  // Null when this session came from the Piped fallback, which has no
  // further pages; [fetchMoreSearchResults] then returns an empty list.
  VideoSearchList? _list;

  /// Videos from the first page.
  final List<VideoDetails> firstPage;
}

class YoutubeExtractorService {
  YoutubeExtractorService(
      {YoutubeExplode? client,
      Connectivity? connectivity,
      PipedService? piped})
      : _yt = client ?? YoutubeExplode(),
        _connectivity = connectivity ?? Connectivity(),
        _piped = piped ?? PipedService();

  final YoutubeExplode _yt;
  final Connectivity _connectivity;

  /// Piped proxy fallback used when YouTube rate-limits the device IP.
  final PipedService _piped;

  /// True when [e] looks like YouTube throttling the device IP
  /// (RequestLimitExceededException / HTTP 429). Those failures are worth
  /// retrying through the Piped proxy instead of surfacing an error.
  static bool _isRateLimitError(Object e) {
    if (e is RequestLimitExceededException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('requestlimitexceeded') ||
        msg.contains('rate limit') ||
        msg.contains('ratelimit') ||
        msg.contains('http 429') ||
        msg.contains('too many requests');
  }

  /// Timestamp until which direct YouTube requests are skipped: the last
  /// attempt was rate-limited (HTTP 429), so hammering YouTube again would
  /// only extend the IP block. While blocked, every call goes straight to
  /// the Piped proxy, letting the IP cool down.
  DateTime _youtubeBlockedUntil =
      DateTime.fromMillisecondsSinceEpoch(0);
  static const _blockCooldown = Duration(minutes: 15);

  bool get _youtubeBlocked =>
      DateTime.now().isBefore(_youtubeBlockedUntil);

  void _markYouTubeBlocked() {
    _youtubeBlockedUntil = DateTime.now().add(_blockCooldown);
  }

  /// Piped fallback for video details. Throws a friendly error when the
  /// proxy is unreachable too (instead of leaking the raw exception).
  Future<VideoDetails> _pipedVideoDetails(String videoId) async {
    try {
      return await _piped.getVideoDetails(videoId);
    } catch (_) {
      throw ExtractorException(
          'YouTube সাময়িকভাবে block করেছে আর বিকল্প সার্ভারেও পৌঁছানো যাচ্ছে না। কিছুক্ষণ পরে আবার চেষ্টা করো।');
    }
  }

  /// Piped fallback for playback streams (same friendly-error contract).
  Future<PlaybackStreams> _pipedStreams(String videoId,
      {int maxMuxedHeight = 720, bool preferBestAudio = true}) async {
    try {
      return await _piped.getPlaybackStreams(videoId,
          maxMuxedHeight: maxMuxedHeight,
          preferBestAudio: preferBestAudio);
    } catch (_) {
      throw ExtractorException(
          'YouTube সাময়িকভাবে block করেছে আর বিকল্প সার্ভারেও পৌঁছানো যাচ্ছে না। কিছুক্ষণ পরে আবার চেষ্টা করো।');
    }
  }

  /// Piped fallback for search (same friendly-error contract).
  Future<List<VideoDetails>> _pipedSearch(String query,
      {int limit = 25}) async {
    try {
      return await _piped.searchVideos(query, limit: limit);
    } catch (_) {
      throw ExtractorException(
          'YouTube সাময়িকভাবে block করেছে আর বিকল্প সার্ভারেও পৌঁছানো যাচ্ছে না। কিছুক্ষণ পরে আবার চেষ্টা করো।');
    }
  }

  /// Throttle: minimum delay between YouTube requests to avoid IP blocking.
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minRequestGap = Duration(milliseconds: 800);

  Future<void> _throttle() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequest);
    if (elapsed < _minRequestGap) {
      await Future.delayed(_minRequestGap - elapsed);
    }
    _lastRequest = DateTime.now();
  }

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

  /// Best-effort HDR detection. youtube_explode_dart does not expose
  /// per-stream color metadata, so this only matches an explicit "HDR"
  /// in the stream's quality label. HDR streams still parse and play
  /// through the normal path — nothing in the pipeline assumes SDR,
  /// so there is no HDR-specific crash path.
  static bool _looksHdr(String qualityLabel) =>
      qualityLabel.toLowerCase().contains('hdr');

  Future<void> _requireNetwork() async {
    final results = await _connectivity.checkConnectivity();
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      throw NetworkException();
    }
  }

  /// Fetches the stream manifest, working around YouTube's age gate.
  ///
  /// Age-restricted (18+) videos return LOGIN_REQUIRED for the default
  /// client, so the manifest comes back with no playable streams. The
  /// library retries internally with the TVHTML5 client (which sends
  /// racyCheckOk/contentCheckOk — YouTube's age-gate bypass), but if that
  /// still reports the video unplayable we retry once more explicitly
  /// with the TV client so a stale-version or transient failure on the
  /// first attempt doesn't silently kill playback.
  Future<StreamManifest> _getManifestWithAgeBypass(String videoId) async {
    try {
      await _throttle();
      return await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 30));
    } on VideoUnplayableException {
      await _throttle();
      return await _yt.videos.streamsClient
          .getManifest(videoId, ytClients: [YoutubeApiClient.tv])
          .timeout(const Duration(seconds: 30));
    }
  }

  Future<VideoDetails> getVideoDetails(String videoId) async {
    await _requireNetwork();
    // Circuit breaker: don't hammer a blocked IP — go straight to Piped.
    if (_youtubeBlocked) return _pipedVideoDetails(videoId);
    try {
      await _throttle();
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
      if (_isRateLimitError(e)) {
        _markYouTubeBlocked();
        return _pipedVideoDetails(videoId);
      }
      throw ExtractorException('Could not load video details: ${_friendlyError(e)}');
    }
  }

  /// Returns a muxed (audio+video) URL any player can handle, plus the
  /// best audio-only URL for background mode.
  ///
  /// [maxMuxedHeight] caps the picked muxed stream (closest at-or-below).
  /// [preferBestAudio] picks the highest-bitrate audio track; false picks
  /// the lowest (data-saver).
  Future<PlaybackStreams> getPlaybackStreams(
    String videoId, {
    int maxMuxedHeight = 720,
    bool preferBestAudio = true,
  }) async {
    await _requireNetwork();
    // Circuit breaker: don't hammer a blocked IP — go straight to Piped.
    if (_youtubeBlocked) {
      return _pipedStreams(videoId,
          maxMuxedHeight: maxMuxedHeight,
          preferBestAudio: preferBestAudio);
    }
    try {
      final manifest = await _getManifestWithAgeBypass(videoId);

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
      final audioPick = preferBestAudio ? audio.first : audio.last;

      return PlaybackStreams(
        videoId: videoId,
        muxedUrl: bestMuxed.url.toString(),
        muxedHeight: bestMuxed.videoQuality.height,
        audioOnlyUrl: audioPick.url.toString(),
        audioBitrate: audioPick.bitrate.bitsPerSecond,
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
      if (_isRateLimitError(e)) {
        _markYouTubeBlocked();
        return _pipedStreams(videoId,
            maxMuxedHeight: maxMuxedHeight,
            preferBestAudio: preferBestAudio);
      }
      throw ExtractorException('Could not extract streams: $e');
    }
  }

  /// Lists all muxed (audio+video) quality options for a video plus
  /// DASH video-only options, sorted by height then fps, both
  /// descending. Labels look like "MPEG-4 720p60".
  /// One entry per distinct (height, fps) pair (NewPipe-style): 720p30
  /// and 720p60 stay as separate options instead of collapsing into
  /// one entry the way a height-only key did.
  Future<List<MuxedQuality>> getQualityOptions(
      String videoId) async {
    await _requireNetwork();
    try {
      final manifest = await _getManifestWithAgeBypass(videoId);

      final muxed = [...manifest.muxed]
        ..sort((a, b) => b.videoQuality.height
            .compareTo(a.videoQuality.height));

      if (muxed.isEmpty) {
        throw UnplayableVideoException(videoId,
            'No playable streams for this video.');
      }

      // Dedup key is (height, fps) — shared across muxed and DASH so a
      // DASH (height, fps) already offered as muxed is skipped while
      // other fps variants at that height are kept (e.g. muxed 720p30
      // + DASH 720p60).
      final seen = <String>{};
      final options = <MuxedQuality>[];
      for (final m in muxed) {
        final h = m.videoQuality.height;
        final fps = m.framerate.framesPerSecond.round();
        if (h <= 0 || !seen.add('$h@$fps')) continue;
        final fpsSuffix = fps > 30 ? '$fps' : '';
        options.add(MuxedQuality(
          label: 'MPEG-4 ${h}p$fpsSuffix',
          height: h,
          url: m.url.toString(),
          bitrateKbps: m.bitrate.bitsPerSecond / 1000,
          fps: fps,
          codec: _shortCodec(m.videoCodec),
          isHdr: _looksHdr(m.qualityLabel),
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
          final fps = v.framerate.framesPerSecond.round();
          if (h <= 0 || !seen.add('$h@$fps')) continue;
          final fpsSuffix = fps > 30 ? '$fps' : '';
          final resLabel = h >= 2160
              ? '2160p$fpsSuffix (2K)'
              : h >= 1440
                  ? '1440p$fpsSuffix (1.5K)'
                  : '${h}p$fpsSuffix';
          options.add(MuxedQuality(
            label: '$resLabel · DASH',
            height: h,
            url: v.url.toString(),
            audioUrl: audioUrl,
            bitrateKbps: v.bitrate.bitsPerSecond / 1000,
            fps: fps,
            codec: _shortCodec(v.videoCodec),
            isHdr: _looksHdr(v.qualityLabel),
          ));
        }
      }

      // Height desc, then fps desc (higher fps wins ties — this also
      // makes the auto/default pick prefer 60fps variants), then muxed
      // before DASH on full ties.
      options.sort((a, b) {
        final h = b.height.compareTo(a.height);
        if (h != 0) return h;
        final f = b.fps.compareTo(a.fps);
        if (f != 0) return f;
        if (a.isDash != b.isDash) return a.isDash ? 1 : -1;
        return 0;
      });
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
      final manifest = await _getManifestWithAgeBypass(videoId);

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
    // Circuit breaker: don't hammer a blocked IP — go straight to Piped.
    if (_youtubeBlocked) return _pipedSearch(query, limit: limit);
    try {
      await _throttle();
      final results = await _yt.search
          .search(query)
          .timeout(const Duration(seconds: 25));
      return results
          .whereType<Video>()
          .take(limit)
          .map(VideoDetails.fromExplode)
          .toList();
    } on TimeoutException {
      // A timeout on a slow/rate-limited network never recovers by
      // re-running the same YouTube request — try Piped first, so Retry
      // actually has a chance to load instead of timing out again.
      try {
        return await _piped.searchVideos(query, limit: limit);
      } catch (_) {
        // Fall through to the timeout error below.
      }
      throw ExtractorException('Search timed out. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      if (_isRateLimitError(e)) {
        _markYouTubeBlocked();
        return _pipedSearch(query, limit: limit);
      }
      throw ExtractorException('Search failed: ${_friendlyError(e)}');
    }
  }

  /// Starts a paged search session for infinite scroll.
  /// Returns the first page; call [fetchMoreSearchResults] for more.
  Future<SearchSession> startPagedSearch(String query,
      {int limit = 25}) async {
    await _requireNetwork();
    // Circuit breaker: don't hammer a blocked IP — go straight to Piped.
    if (_youtubeBlocked) {
      final videos = await _pipedSearch(query, limit: limit);
      // Piped has no paging; the session carries a null list and
      // fetchMoreSearchResults returns an empty list for it.
      return SearchSession._(null, videos);
    }
    try {
      await _throttle();
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
      // A timeout on a slow/rate-limited network never recovers by
      // re-running the same YouTube request — try Piped first, so Retry
      // actually has a chance to load instead of timing out again.
      try {
        final pipedVideos =
            await _piped.searchVideos(query, limit: limit);
        // Piped has no paging; the session carries a null list and
        // fetchMoreSearchResults returns an empty list for it.
        return SearchSession._(null, pipedVideos);
      } catch (_) {
        // Fall through to the timeout error below.
      }
      throw ExtractorException('Search timed out. Retry.');
    } on PureTubeException {
      rethrow;
    } catch (e) {
      if (_isRateLimitError(e)) {
        _markYouTubeBlocked();
        final videos = await _pipedSearch(query, limit: limit);
        // Piped has no paging; the session carries a null list and
        // fetchMoreSearchResults returns an empty list for it.
        return SearchSession._(null, videos);
      }
      throw ExtractorException('Search failed: ${_friendlyError(e)}');
    }
  }

  /// Fetches the next page of a [SearchSession]. Returns empty list
  /// when there are no more pages.
  Future<List<VideoDetails>> fetchMoreSearchResults(
      SearchSession session,
      {int limit = 25}) async {
    try {
      // Null when the session came from the Piped fallback: no more pages.
      final list = session._list;
      if (list == null) return const [];
      final next = await list
          .nextPage()
          .timeout(const Duration(seconds: 25));
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

  void dispose() {
    _yt.close();
    _piped.dispose();
  }

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

  /// Downloads the best caption track and returns it as plain
  /// lyrics-style text (no timestamps) — YouTube's own free AI
  /// (auto-generated captions) or manual captions when available.
  ///
  /// Used as the primary source for auto-generated lyrics: for music
  /// videos the transcript IS essentially the lyrics. Prefers manual
  /// tracks (more accurate), then auto-generated ones. Returns null
  /// when the video has no usable captions (never throws).
  Future<String?> getCaptionTranscript(String videoId) async {
    try {
      final manifest = await _yt
          .videos.closedCaptions
          .getManifest(videoId)
          .timeout(const Duration(seconds: 20));
      if (manifest.tracks.isEmpty) return null;
      final sorted = manifest.tracks.toList()
        ..sort((a, b) {
          if (a.isAutoGenerated != b.isAutoGenerated) {
            return a.isAutoGenerated ? 1 : -1;
          }
          return 0;
        });
      for (final info in sorted) {
        try {
          final track = await _yt
              .videos.closedCaptions
              .get(info)
              .timeout(const Duration(seconds: 20));
          final text =
              _formatTranscript(track.captions.map((c) => c.text));
          if (text != null) return text;
        } catch (_) {
          continue;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Joins caption lines into lyrics-style plain text:
  /// - drops sound-effect markers like [Music] / [Applause]
  /// - dedupes consecutive repeated lines (auto-captions repeat)
  /// - returns null when nothing meaningful remains.
  String? _formatTranscript(Iterable<String> lines) {
    final out = <String>[];
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^[\[\(].*[\]\)]$').hasMatch(line)) continue;
      if (out.isNotEmpty && out.last == line) continue;
      out.add(line);
    }
    if (out.isEmpty) return null;
    final text = out.join('\n');
    if (text.length < 30) return null;
    return text;
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
      {int limit = 30,
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
      // Collect extra candidates: aggressive dedupe below shrinks the
      // list, so over-collect to keep Up Next full AND diverse.
      final collectCap = limit * 2;
      for (final query in queries) {
        if (collected.length >= collectCap) break;
        try {
          final results = await _yt.search
              .search(query)
              .timeout(const Duration(seconds: 20));
          for (final v in results.whereType<Video>()) {
            if (seen.add(v.id.value)) {
              collected.add(VideoDetails.fromExplode(v));
              if (collected.length >= collectCap) break;
            }
          }
        } catch (e) {
          debugPrint('getRelatedVideos: search "$query" failed: $e');
        }
      }
      // Near-duplicate removal: the same song/video re-uploaded by other
      // channels (e.g. "Vaaste" appearing 8+ times). Keeps the
      // most-viewed copy of each similar-title group.
      final unique = _dedupeSimilarTitles(collected).take(limit).toList();
      // Category boost: rank results matching the user's frequent
      // categories first (earlier category = stronger boost).
      if (boostCategories.isNotEmpty && unique.length > 1) {
        unique.sort((a, b) => _categoryScore(b.title, boostCategories)
            .compareTo(_categoryScore(a.title, boostCategories)));
      }
      return unique;
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

  /// Noise tokens stripped when normalizing titles for near-duplicate
  /// detection: quality badges, upload-type words, version/re-upload
  /// markers and filler that make "the same song re-uploaded by another
  /// channel" look different.
  static const _dedupeNoiseWords = <String>{
    'official', 'video', 'videos', 'full', 'hd', 'hq', 'sd',
    '4k', '8k', '2k', 'uhd', 'fhd', 'qhd',
    '1080p', '720p', '480p', '360p', '240p', '144p',
    '1440p', '2160p', '4320p',
    'lyrics', 'lyric', 'lyrical', 'audio', 'song', 'songs',
    'music', 'musical', 'visualizer', 'mv', 'mtv',
    'trailer', 'teaser', 'promo', 'clip', 'short', 'shorts',
    'remix', 'remake', 'cover', 'version', 'original',
    // Version/re-upload markers: slowed+reverb, lofi, tiktok etc.
    'slowed', 'slow', 'reverb', 'reverbed', 'sped', 'nightcore',
    'tiktok', 'mashup', 'unplugged', 'acoustic', 'extended',
    'edit', 'bass', 'boosted', '8d', '10d', 'flp',
    '2024', '2025', '2026', '2027',
  };

  /// Splits text into lowercase alphanumeric tokens (unicode-aware,
  /// so Bengali works), dropping tokens shorter than 2 chars.
  static List<String> _wordTokens(String text) {
    final tokens = <String>[];
    for (final w in text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))) {
      if (w.length >= 2 && !tokens.contains(w)) tokens.add(w);
    }
    return tokens;
  }

  /// The "core" of a title: the first few meaningful tokens — the
  /// distinctive song/video name. Noise words and the video's own
  /// author/channel tokens are stripped, so "Artist - Song A" vs
  /// "Artist - Song B" don't look like the same song, while
  /// "Vaaste Remix" vs "Vaaste Lofi" both reduce to "vaaste".
  static String _coreTitle(String title,
      {Set<String> authorTokens = const {}}) {
    final tokens = <String>[];
    for (final w in _wordTokens(title)) {
      if (_dedupeNoiseWords.contains(w)) continue;
      if (authorTokens.contains(w)) continue;
      tokens.add(w);
      if (tokens.length >= 3) break;
    }
    return tokens.join(' ');
  }

  /// Normalizes a title for near-duplicate detection: lowercase, strip
  /// punctuation, drop noise tokens, collapse whitespace. Unicode-aware
  /// so Bengali titles work too.
  static String _normalizeTitle(String title) {
    final tokens = <String>[];
    for (final w in title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))) {
      if (w.length >= 2 &&
          !_dedupeNoiseWords.contains(w) &&
          !tokens.contains(w)) {
        tokens.add(w);
      }
    }
    return tokens.join(' ');
  }

  /// Dice coefficient (0..1) over the token multisets of two normalized
  /// titles. 1.0 means identical token bags.
  static double _titleSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;
    final aTokens = a.split(' ');
    final bTokens = b.split(' ');
    final counts = <String, int>{};
    for (final t in aTokens) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    var intersection = 0;
    final used = <String, int>{};
    for (final t in bTokens) {
      final have = counts[t] ?? 0;
      final taken = used[t] ?? 0;
      if (taken < have) {
        intersection++;
        used[t] = taken + 1;
      }
    }
    return 2 * intersection / (aTokens.length + bTokens.length);
  }

  /// Drops near-duplicate suggestions (same song/video re-uploaded by
  /// other channels): titles more than [threshold] similar, or whose
  /// "core" titles (distinctive song/video name) match, keep only the
  /// highest view-count copy. First-appearance order is preserved.
  /// Aggressive by design: "Vaaste Song" / "Vaaste Remix" / "Vaaste
  /// Lofi" / "Vaaste Official Video" all collapse to one entry so Up
  /// Next stays diverse.
  static List<VideoDetails> _dedupeSimilarTitles(
    List<VideoDetails> videos, {
    double threshold = 0.5,
    double coreThreshold = 0.6,
  }) {
    if (videos.length < 2) return videos;
    final normalized = [for (final v in videos) _normalizeTitle(v.title)];
    final cores = [
      for (final v in videos)
        _coreTitle(v.title,
            authorTokens: _wordTokens(v.author).toSet()),
    ];
    final kept = <int>[];
    for (var i = 0; i < videos.length; i++) {
      var dupOf = -1;
      for (final k in kept) {
        final fullSim = _titleSimilarity(normalized[i], normalized[k]);
        final coreSim = (cores[i].isEmpty || cores[k].isEmpty)
            ? 0.0
            : _titleSimilarity(cores[i], cores[k]);
        if (fullSim > threshold || coreSim > coreThreshold) {
          dupOf = k;
          break;
        }
      }
      if (dupOf == -1) {
        kept.add(i);
      } else {
        // Same song/video: keep the copy with more views.
        final curViews = videos[i].viewCount ?? 0;
        final keptViews = videos[dupOf].viewCount ?? 0;
        if (curViews > keptViews) {
          kept[kept.indexOf(dupOf)] = i;
        }
      }
    }
    return [for (final i in kept) videos[i]];
  }

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
