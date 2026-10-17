import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/services/exoplayer_service.dart';

/// Test screen for ExoPlayer playback (NewPipe-style).
///
/// This is the foundation for migrating from mpv to ExoPlayer.
class ExoPlayerTestScreen extends StatefulWidget {
  final String videoUrl;
  final String audioUrl;
  final String videoMime;
  final String audioMime;
  final int width;
  final int height;
  final int videoBitrate;
  final int audioBitrate;
  final double durationSec;
  final String title;

  const ExoPlayerTestScreen({
    super.key,
    required this.videoUrl,
    required this.audioUrl,
    required this.videoMime,
    required this.audioMime,
    required this.width,
    required this.height,
    required this.videoBitrate,
    required this.audioBitrate,
    required this.durationSec,
    required this.title,
  });

  @override
  State<ExoPlayerTestScreen> createState() =>
      _ExoPlayerTestScreenState();
}

class _ExoPlayerTestScreenState
    extends State<ExoPlayerTestScreen> {
  final _service = ExoPlayerService();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _service.play(
        videoUrl: widget.videoUrl,
        audioUrl: widget.audioUrl,
        videoMime: widget.videoMime,
        audioMime: widget.audioMime,
        width: widget.width,
        height: widget.height,
        videoBitrate: widget.videoBitrate,
        audioBitrate: widget.audioBitrate,
        durationSec: widget.durationSec,
      );
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _service.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding:
                              const EdgeInsets.all(16),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.red)),
                        ),
                      )
                    : controller != null
                        ? VideoPlayer(controller)
                        : const SizedBox(),
          ),
          if (!_loading && _error == null)
            VideoProgressIndicator(
              controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.green,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 48,
                  color: Colors.white,
                  icon: Icon(
                    controller?.value.isPlaying ??
                            false
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: () async {
                    if (controller
                            ?.value.isPlaying ??
                        false) {
                      await _service.pause();
                    } else {
                      await _service.resume();
                    }
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16),
            child: Text(widget.title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15),
                maxLines: 2),
          ),
        ],
      ),
    );
  }
}
