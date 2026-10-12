import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/utils/format.dart';
import '../../domain/entities/library_models.dart';

/// Plays a downloaded file with media_kit. No network, no extractor.
class OfflinePlayerScreen extends StatefulWidget {
  final DownloadRecord record;
  const OfflinePlayerScreen({super.key, required this.record});

  @override
  State<OfflinePlayerScreen> createState() =>
      _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState
    extends State<OfflinePlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _attachCompanionAudio().then((_) {
      if (mounted) {
        _player.open(Media('file://${widget.record.filePath}'));
      }
    });
  }

  /// DASH video-only downloads ship a companion audio file. Attach it
  /// via mpv's `audio-file` (same mechanism as DASH streaming) so the
  /// video plays WITH audio — no FFmpeg merge required.
  Future<void> _attachCompanionAudio() async {
    final audioPath = widget.record.audioFilePath;
    if (audioPath == null || audioPath.isEmpty) return;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('audio-file', audioPath);
      } catch (_) {
        // Video still plays; just without the companion audio.
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.record.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: widget.record.audioOnly
                ? const Center(
                    child: Icon(Icons.audio_file,
                        size: 64, color: Colors.grey))
                : Video(
                    controller: _controller,
                    controls: NoVideoControls,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<Duration>(
              stream: _player.stream.position,
              builder: (context, posSnap) {
                return StreamBuilder<Duration>(
                  stream: _player.stream.duration,
                  builder: (context, durSnap) {
                    final pos =
                        posSnap.data ?? Duration.zero;
                    final dur =
                        durSnap.data ?? Duration.zero;
                    return Column(
                      children: [
                        Slider(
                          value: dur.inMilliseconds > 0
                              ? (pos.inMilliseconds /
                                      dur.inMilliseconds)
                                  .clamp(0.0, 1.0)
                              : 0,
                          onChanged: (v) => _player.seek(
                              Duration(
                                  milliseconds:
                                      (v * dur.inMilliseconds)
                                          .round())),
                        ),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(formatDuration(pos),
                                style: const TextStyle(
                                    color: Colors.grey)),
                            Text(formatDuration(dur),
                                style: const TextStyle(
                                    color: Colors.grey)),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            builder: (context, snap) {
              final playing = snap.data ?? false;
              return IconButton(
                iconSize: 56,
                onPressed: () =>
                    playing ? _player.pause() : _player.play(),
                icon: Icon(playing
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
              );
            },
          ),
        ],
      ),
    );
  }
}
