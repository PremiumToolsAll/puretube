import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hidden WebView player using YouTube IFrame Player API.
///
/// The WebView is kept hidden (1x1 pixel); the native Flutter UI
/// provides all controls. Playback uses the browser's media engine,
/// so all qualities work exactly like in Chrome.
class WebViewPlayerService extends ChangeNotifier {
  WebViewController? _controller;
  String? _videoId;
  bool _ready = false;
  bool _playing = false;

  final _readyCompleter = Completer<void>();

  bool get isReady => _ready;
  bool get isPlaying => _playing;
  String? get videoId => _videoId;

  /// Creates the hidden WebView. Call once during app init.
  WebViewController createWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'PureTube',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectPlayer(),
        ),
      )
      ..loadRequest(
        Uri.parse('about:blank'),
      );
    return _controller!;
  }

  void _onJsMessage(JavaScriptMessage message) {
    final data = message.message;
    if (data == 'ready') {
      _ready = true;
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
      notifyListeners();
    } else if (data == 'playing') {
      _playing = true;
      notifyListeners();
    } else if (data == 'paused') {
      _playing = false;
      notifyListeners();
    }
  }

  Future<void> _injectPlayer() async {
    const html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{margin:0;background:#000}</style>
</head>
<body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player;
function onYouTubeIframeAPIReady() {
  PureTube.postMessage('ready');
}
function loadVideo(videoId) {
  if (player) player.destroy();
  player = new YT.Player('player', {
    height: '1', width: '1',
    videoId: videoId,
    playerVars: {autoplay: 1, controls: 0, rel: 0},
    events: {
      onReady: function(e) { e.target.playVideo(); },
      onStateChange: function(e) {
        if (e.data == YT.PlayerState.PLAYING) PureTube.postMessage('playing');
        if (e.data == YT.PlayerState.PAUSED) PureTube.postMessage('paused');
      }
    }
  });
}
</script>
</body>
</html>
''';
    await _controller?.loadHtmlString(html);
  }

  /// Loads and plays a YouTube video by ID.
  Future<void> play(String videoId) async {
    _videoId = videoId;
    _playing = false;
    notifyListeners();

    // Wait for the player to be ready.
    if (!_ready) {
      await _readyCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('WebView player not ready'),
      );
    }

    await _controller?.runJavaScript("loadVideo('$videoId')");
  }

  Future<void> pause() async {
    await _controller?.runJavaScript('player.pauseVideo()');
  }

  Future<void> resume() async {
    await _controller?.runJavaScript('player.playVideo()');
  }

  Future<void> seekTo(int seconds) async {
    await _controller
        ?.runJavaScript('player.seekTo($seconds, true)');
  }

  /// Sets playback quality (e.g., 'hd1080', 'hd720', 'large', 'medium').
  Future<void> setQuality(String quality) async {
    await _controller?.runJavaScript(
        "player.setPlaybackQuality('$quality')");
  }

  Future<int> getDuration() async {
    final result = await _controller
        ?.runJavaScriptReturningResult('player.getDuration()');
    return (num.tryParse(result.toString()) ?? 0).toInt();
  }

  Future<int> getCurrentTime() async {
    final result = await _controller
        ?.runJavaScriptReturningResult(
            'player.getCurrentTime()');
    return (num.tryParse(result.toString()) ?? 0).toInt();
  }

  void disposeController() {
    _controller = null;
    _ready = false;
  }
}
