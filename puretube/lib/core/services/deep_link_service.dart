import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'share_service.dart';

/// Deep link handling:
/// - puretube://video/VIDEOID
/// - https://youtu.be/VIDEOID, youtube.com/watch?v=, /shorts/
typedef VideoLinkCallback = void Function(
    String videoId);

/// Listens for incoming links and routes to the player.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance =
      DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription? _sub;
  VideoLinkCallback? onVideoLink;

  Future<void> init(
      {VideoLinkCallback? onVideo}) async {
    onVideoLink = onVideo;
    try {
      // Cold start link.
      final initial =
          await _appLinks.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
      // Warm links.
      _sub =
          _appLinks.uriLinkStream.listen(
        _handle,
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _handle(Uri uri) {
    try {
      final videoId =
          ShareService.extractVideoId(
              uri.toString());
      if (videoId != null &&
          videoId.isNotEmpty) {
        onVideoLink?.call(videoId);
      }
    } catch (_) {}
  }

  /// Show a snackbar-style routing helper for MaterialApp.
  static void routeToVideo(
      BuildContext context,
      String videoId,
      Widget Function(String) builder) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => builder(videoId)),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
