import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hidden WebView player screen.
///
/// Uses YouTube IFrame Player API in a Chromeless WebView.
/// Playback runs on the browser engine, so all qualities work
/// exactly like in Chrome. Native Flutter UI overlays on top.
class WebViewPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;

  const WebViewPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
  });

  @override
  State<WebViewPlayerScreen> createState() =>
      _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState
    extends State<WebViewPlayerScreen> {
  late final WebViewController _controller;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'PureTube',
        onMessageReceived: (msg) {
          if (msg.message == 'playing') {
            setState(() => _playing = true);
          } else if (msg.message == 'paused') {
            setState(() => _playing = false);
          }
        },
      )
      ..loadHtmlString(_buildHtml(widget.videoId));
  }

  String _buildHtml(String videoId) {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
#player{position:absolute;top:0;left:0;width:100%;height:100%}
</style>
</head>
<body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player;
function onYouTubeIframeAPIReady() {
  player = new YT.Player('player', {
    videoId: '$videoId',
    playerVars: {
      autoplay: 1,
      controls: 0,
      rel: 0,
      fs: 0,
      modestbranding: 1,
      playsinline: 1
    },
    events: {
      onStateChange: function(e) {
        if (e.data == YT.PlayerState.PLAYING)
          PureTube.postMessage('playing');
        if (e.data == YT.PlayerState.PAUSED)
          PureTube.postMessage('paused');
      }
    }
  });
}
function togglePlay() {
  if (!player) return;
  var s = player.getPlayerState();
  if (s == YT.PlayerState.PLAYING) player.pauseVideo();
  else player.playVideo();
}
</script>
</body>
</html>
''';
  }

  void _togglePlay() {
    _controller.runJavaScript('togglePlay()');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Column(
        children: [
          // Video area (16:9).
          AspectRatio(
            aspectRatio: 16 / 9,
            child: WebViewWidget(controller: _controller),
          ),
          // Native controls.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 56,
                  color: Colors.white,
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: _togglePlay,
                ),
              ],
            ),
          ),
          // Title.
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Playing via browser engine — all qualities supported',
              style:
                  TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
