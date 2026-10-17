import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// True hidden WebView player.
///
/// The WebView runs the YouTube IFrame player with the browser engine.
/// YouTube's own UI is fully suppressed (controls=0, no branding);
/// only the raw video is composited, with 100% native Flutter UI
/// on top. The user never sees a webpage — just video + native UI.
class HiddenWebViewPlayer extends StatefulWidget {
  final String videoId;
  final String title;

  const HiddenWebViewPlayer({
    super.key,
    required this.videoId,
    required this.title,
  });

  @override
  State<HiddenWebViewPlayer> createState() =>
      _HiddenWebViewPlayerState();
}

class _HiddenWebViewPlayerState
    extends State<HiddenWebViewPlayer> {
  late final WebViewController _controller;
  bool _playing = true;
  bool _webViewReady = false;
  double _position = 0;
  double _duration = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      // Prevent the WebView from showing any navigation UI.
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) =>
              NavigationDecision.prevent,
        ),
      )
      ..addJavaScriptChannel(
        'Native',
        onMessageReceived: _onMessage,
      )
      ..loadHtmlString(_html(widget.videoId));
  }

  void _onMessage(JavaScriptMessage msg) {
    final parts = msg.message.split('|');
    if (parts.isEmpty) return;
    switch (parts[0]) {
      case 'ready':
        setState(() => _webViewReady = true);
        break;
      case 'playing':
        setState(() => _playing = true);
        break;
      case 'paused':
        setState(() => _playing = false);
        break;
      case 'time':
        if (parts.length >= 3) {
          setState(() {
            _position =
                double.tryParse(parts[1]) ?? _position;
            _duration =
                double.tryParse(parts[2]) ?? _duration;
          });
        }
        break;
    }
  }

  String _html(String videoId) => '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;padding:0;background:#000;overflow:hidden;height:100%}
#wrap{position:fixed;inset:0}
#player{width:100%;height:100%}
</style>
</head><body>
<div id="wrap"><div id="player"></div></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player=null, timer=null;
function onYouTubeIframeAPIReady(){
  player=new YT.Player('player',{
    videoId:'$videoId',
    playerVars:{autoplay:1,controls:0,disablekb:1,fs:0,iv_load_policy:3,modestbranding:1,playsinline:1,rel:0},
    events:{
      onReady:function(){Native.postMessage('ready');player.playVideo();startTimer();},
      onStateChange:function(e){
        if(e.data==YT.PlayerState.PLAYING)Native.postMessage('playing');
        else if(e.data==YT.PlayerState.PAUSED)Native.postMessage('paused');
      },
      onError:function(e){Native.postMessage('error|'+e.data);}
    }
  });
}
function startTimer(){
  timer=setInterval(function(){
    if(player&&player.getDuration){
      Native.postMessage('time|'+player.getCurrentTime()+'|'+player.getDuration());
    }
  },500);
}
function toggle(){if(player){var s=player.getPlayerState();s==YT.PlayerState.PLAYING?player.pauseVideo():player.playVideo();}}
function seek(sec){if(player)player.seekTo(sec,true);}
</script>
</body></html>
''';

  String _fmt(double sec) {
    final s = sec.toInt();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Video — WebView renders only the raw video frame.
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  // Native tap overlay for play/pause.
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () =>
                          _controller.runJavaScript('toggle()'),
                      child: Container(
                          color: Colors.transparent),
                    ),
                  ),
                ],
              ),
            ),
            // Native controls.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(_fmt(_position),
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _position.clamp(
                            0, _duration > 0 ? _duration : 1),
                        max: _duration > 0 ? _duration : 1,
                        activeColor: Colors.green,
                        inactiveColor: Colors.white24,
                        onChanged: (v) =>
                            setState(() => _position = v),
                        onChangeEnd: (v) => _controller
                            .runJavaScript(
                                'seek(${v.toInt()})'),
                      ),
                    ),
                  ),
                  Text(_fmt(_duration),
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12)),
                ],
              ),
            ),
            // Title.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(height: 4),
            if (!_webViewReady)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: () =>
            _controller.runJavaScript('toggle()'),
        child: Icon(
            _playing ? Icons.pause : Icons.play_arrow,
            color: Colors.black),
      ),
    );
  }
}
