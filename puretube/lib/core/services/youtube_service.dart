import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../features/player/widgets/live_chat_widget.dart';

/// Thrown when all InnerTube clients fail for an operation.
class PureTubeException implements Exception {
  final String message;
  final Object? cause;
  const PureTubeException(this.message, [this.cause]);

  @override
  String toString() => 'PureTubeException: $message'
}

/// YouTube data layer — talks DIRECTLY to YouTube's InnerTube API via
/// [youtube_explode_dart]. No Piped, no Invidious, no Data API.
///
/// ## Client Fallback System
/// YouTube serves different InnerTube "clients" (WEB, ANDROID, IOS, TV).
/// Any single client can start throwing [TransientFailureException] when
/// YouTube changes its player responses. To stay resilient, every public
/// method tries clients in order:
///
///   1. ANDROID  (most reliable for streams)
///   2. WEB      (best for search/trending metadata)
///   3. TV       (fallback, rarely blocked)
///   4. IOS      (last resort)
///
/// The first client that succeeds wins; if all fail a [PureTubeException]
/// is thrown with the last error attached.
class YoutubeService {
  YoutubeService._();
  static final YoutubeService instance = YoutubeService._();

  // One YoutubeExplode per client — created lazily and reused.
  final Map<YoutubeApiClient, YoutubeExplode> _clients = {};

  YoutubeExplode _client(YoutubeApiClient apiClient) =>
      _clients.putIfAbsent(
        apiClient,
        () => YoutubeExplode(YoutubeHttpClient(), apiClient),
      );

  /// Runs [action] against each client in fallback order.
  Future<T> _withFallback<T>(
    String operation,
    Future<T> Function(YoutubeExplode yt) action,
  ) async {
    Object? lastError;
    StackTrace? lastStack;
    for (final apiClient in _fallbackOrder) {
      try {
        return await action(_client(apiClient))
            .timeout(const Duration(seconds: 30));
      } on TimeoutException catch (e, st) {
        lastError = e;
        lastStack = st;
      } on TransientFailureException catch (e, st) {
        // YouTube changed something for this client — try next.
        lastError = e;
        lastStack = st;
      } on FatalFailureException {
        // Fatal = request itself is bad (e.g. video removed).
        // Retrying other clients won't help.
        rethrow;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
      }
    }
    Error.throwWithStackTrace(
      PureTubeException(
        'All InnerTube clients failed for "$operation". '
        'Check your connection and retry.',
        lastError,
      ),
      lastStack ?? StackTrace.current,
    );
  }

  static const List<YoutubeApiClient> _fallbackOrder = [
    YoutubeApiClient.android,
    YoutubeApiClient.web,
    YoutubeApiClient.tv,
    YoutubeApiClient.ios,
  ];

  // ── Search ──────────────────────────────────────────────────

  /// Search YouTube. Returns video results only.
  Future<List<Video>> search(
    String query, {
    int limit = 25,
  }) =>
      _withFallback('search', (yt) async {
        final results = await yt.search.search(query);
        final videos = <Video>[];
        await for (final batch in results.nextBatch(limit)) {
          for (final e in batch) {
            if (e is Video) videos.add(e);
            if (videos.length >= limit) break;
          }
          if (videos.length >= limit) break;
        }
        return videos;
      });

  /// Autocomplete suggestions for a partial query.
  Future<List<String>> searchSuggestions(String query) =>
      _withFallback('searchSuggestions', (yt) async {
        if (query.trim().isEmpty) return <String>[];
        return yt.search.getQuerySuggestions(query.trim());
      });

  // ── Trending ────────────────────────────────────────────────

  /// Trending feed. Implemented as high-signal searches because
  /// InnerTube has no stable global "trending" endpoint across clients.
  Future<List<Video>> trending({int limit = 25}) =>
      _withFallback('trending', (yt) async {
        const queries = [
          'trending now',
          'viral videos today',
          'popular music videos',
        ];
        final seen = <String>{};
        final out = <Video>[];
        for (final q in queries) {
          if (out.length >= limit) break;
          try {
            final results = await yt.search.search(q);
            await for (final batch
                in results.nextBatch(limit)) {
              for (final e in batch) {
                if (e is Video &&
                    seen.add(e.id.value)) {
                  out.add(e);
                  if (out.length >= limit) break;
                }
              }
              if (out.length >= limit) break;
            }
          } catch (_) {
            // One trending query failing must not kill the feed.
            continue;
          }
        }
        if (out.isEmpty) {
          throw const TransientFailureException(
              'Empty trending response');
        }
        return out;
      });

  // ── Videos ──────────────────────────────────────────────────

  Future<Video> video(String videoId) =>
      _withFallback(
          'video', (yt) => yt.videos.get(videoId));

  /// Full stream manifest (muxed + adaptive + audio-only).
  Future<StreamManifest> streams(String videoId) =>
      _withFallback('streams',
          (yt) => yt.videos.streamsClient.getManifest(videoId));

  /// Related / "up next" videos.
  Future<List<Video>> related(Video video,
      {int limit = 15}) =>
      _withFallback('related', (yt) async {
        final related = await yt.videos
            .getRelatedVideos(video)
            .timeout(const Duration(seconds: 20));
        return related
            .take(limit)
            .toList(growable: false);
      });

  /// Comments (first page).
  Future<List<Comment>> comments(Video video,
      {int limit = 30}) =>
      _withFallback('comments', (yt) async {
        final list = await yt.videos.commentsClient
            .getComments(video);
        if (list == null) return <Comment>[];
        return list.take(limit).toList(growable: false);
      });

  // ── Channels ────────────────────────────────────────────────

  Future<Channel> channel(String channelId) =>
      _withFallback('channel',
          (yt) => yt.channels.get(ChannelId(channelId)));

  Future<List<Video>> channelUploads(
    String channelId, {
    int limit = 30,
  }) =>
      _withFallback('channelUploads', (yt) async {
        final stream =
            yt.channels.getUploads(ChannelId(channelId));
        return stream.take(limit).toList();
      });

  // ── Captions ────────────────────────────────────────────────

  Future<List<ClosedCaptionTrackInfo>> captionTracks(
          String videoId) =>
      _withFallback('captionTracks', (yt) async {
        final manifest = await yt.videos.closedCaptionsClient
            .getManifest(videoId);
        return manifest.tracks.toList(growable: false);
      });

  Future<List<ClosedCaption>> captions(
    ClosedCaptionTrackInfo track,
  ) =>
      _withFallback(
          'captions',
          (yt) => yt.videos.closedCaptionsClient
              .get(track)
              .then((c) => c.captions.toList()));

  // ── Live chat ───────────────────────────────────────────────
  // NOTE: youtube_explode_dart does not expose the live-chat
  // endpoint directly. We return an empty page so the UI degrades
  // gracefully; a future Dio-based InnerTube call can fill this in.

  Future<LiveChatPage> liveChat(
    String videoId, {
    String? continuation,
  }) async {
    // Placeholder for real InnerTube live_chat implementation.
    // Returns empty so polling simply shows "no messages".
    return const LiveChatPage();
  }

  // ── Shorts helpers ──────────────────────────────────────────

  /// Heuristic: video is a Short if <= 90s.
  bool isShort(Video v) =>
      v.duration != null &&
      v.duration!.inSeconds <= 90;

  /// Release all HTTP clients (call on app shutdown / logout).
  void dispose() {
    for (final c in _clients.values) {
      c.close();
    }
    _clients.clear();
  }
}
