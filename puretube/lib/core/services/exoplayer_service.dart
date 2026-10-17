import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

import 'dash_manifest_generator.dart';
import 'youtube_proxy_server.dart';

/// ExoPlayer-based video service (NewPipe-style).
///
/// Generates DASH manifests from stream URLs and plays them via
/// ExoPlayer (through the video_player plugin). This is how NewPipe
/// plays high-quality YouTube videos.
///
/// URLs are routed through YoutubeProxyServer (NewPipe trick:
/// Range header → &range= param, incrementing &rn) to avoid
/// throttling, just like 360p plays reliably.
class ExoPlayerService {
  VideoPlayerController? _controller;
  HttpServer? _manifestServer;
  final YoutubeProxyServer _proxy = YoutubeProxyServer();

  VideoPlayerController? get controller => _controller;
  bool get isInitialized =>
      _controller?.value.isInitialized ?? false;

  /// Plays a muxed (progressive) stream directly — like 360p.
  ///
  /// NewPipe plays muxed URLs directly, no manifest needed.
  /// Direct play (no proxy) for fastest loading — muxed streams
  /// are reliable without the proxy overhead.
  Future<void> playMuxed(String url) async {
    await dispose();

    // Direct play for speed — like 360p in the old player.
    // Proxy only needed for DASH throttling, not muxed.
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      // Hint for faster startup.
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
      ),
    );
    await _controller!.initialize();
    await _controller!.play();
  }

  /// Plays video+audio streams via a generated DASH manifest.
  ///
  /// Like 360p (muxed single file), the DASH video+audio are
  /// served through the local proxy so ExoPlayer gets a reliable
  /// stream.
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

    // Route through proxy (NewPipe trick) for reliability.
    await _proxy.start();
    final proxiedVideo = _proxy.proxyUrl(videoUrl);
    final proxiedAudio = _proxy.proxyUrl(audioUrl);

    // Generate DASH manifest with proxied URLs.
    final manifest = DashManifestGenerator.generate(
      videoUrl: proxiedVideo,
      audioUrl: proxiedAudio,
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
    _proxy.clear();
  }
}
