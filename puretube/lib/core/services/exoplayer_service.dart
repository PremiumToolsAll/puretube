import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

import 'dash_manifest_generator.dart';

/// ExoPlayer-based video service (NewPipe-style).
///
/// Generates DASH manifests from stream URLs and plays them via
/// ExoPlayer (through the video_player plugin). This is how NewPipe
/// plays high-quality YouTube videos.
class ExoPlayerService {
  VideoPlayerController? _controller;
  HttpServer? _manifestServer;

  VideoPlayerController? get controller => _controller;
  bool get isInitialized =>
      _controller?.value.isInitialized ?? false;

  /// Plays video+audio streams via a generated DASH manifest.
  Future<void> play({
    required String videoUrl,
    required String audioUrl,
    required String videoMime,
    required String audioMime,
    required int width,
    required int height,
    required int videoBitrate,
    required int audioBitrate,
    required double durationSec,
  }) async {
    await dispose();

    // Generate DASH manifest.
    final manifest = DashManifestGenerator.generate(
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      videoMime: videoMime,
      audioMime: audioMime,
      videoWidth: width,
      videoHeight: height,
      videoBitrate: videoBitrate,
      audioBitrate: audioBitrate,
      durationSec: durationSec,
    );

    // Serve manifest via local HTTP.
    _manifestServer =
        await HttpServer.bind('127.0.0.1', 0);
    final port = _manifestServer!.port;
    _manifestServer!.listen((request) async {
      request.response.headers.contentType =
          ContentType('application', 'dash+xml');
      request.response.write(manifest);
      await request.response.close();
    });

    final manifestUrl =
        'http://127.0.0.1:$port/manifest.mpd';

    // Play via ExoPlayer.
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(manifestUrl),
    );
    await _controller!.initialize();
    await _controller!.play();
  }

  Future<void> pause() async {
    await _controller?.pause();
  }

  Future<void> resume() async {
    await _controller?.play();
  }

  Future<void> seekTo(Duration position) async {
    await _controller?.seekTo(position);
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    await _manifestServer?.close(force: true);
    _manifestServer = null;
  }
}
