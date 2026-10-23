import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puretube_playback/puretube_playback.dart';

import '../../../../core/utils/format.dart';
import '../../../player/presentation/providers/player_controller.dart';
import '../../domain/entities/library_models.dart';

/// Plays a downloaded file with the shared puretube_playback
/// engine (loadLocal — the companion audio file of a DASH
/// download is merged natively, the role mpv's audio-file
/// property used to fill). No network, no extractor.
///
/// Opening this screen takes the shared engine over from the
/// main player (ownerTag 'offline'); closing it stops the engine
/// and invalidates the main player's stale engagement, so its
/// play button cleanly re-engages the previous video.
class OfflinePlayerScreen extends ConsumerStatefulWidget {
  final DownloadRecord record;
  const OfflinePlayerScreen({super.key, required this.record});

  @override
  ConsumerState<OfflinePlayerScreen> createState() =>
      _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState
    extends ConsumerState<OfflinePlayerScreen> {
  late final PureTubeController _pt;
  int _textureId = -1;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _pt = PureTubeController();
    unawaited(_start());
  }

  Future<void> _start() async {
    PureTubeController.ownerTag = 'offline';
    ref.read(playerControllerProvider.notifier).invalidateEngine();
    try {
      final audioPath = widget.record.audioFilePath;
      final companion = (audioPath != null &&
              audioPath.isNotEmpty &&
              await File(audioPath).exists())
          ? audioPath
          : null;
      await _pt.loadLocal(
        path: widget.record.filePath,
        audioPath: companion,
        audioOnly: widget.record.audioOnly,
        autoplay: true,
      );
      final id = await _pt.textureId;
      if (mounted) setState(() => _textureId = id);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    PureTubeController.ownerTag = null;
    unawaited(() async {
      try {
        await _pt.stop();
      } catch (_) {}
      await _pt.close();
    }());
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
                : _error
                    ? const Center(
                        child: Icon(Icons.error_outline,
                            size: 48, color: Colors.grey))
                    : _textureId > 0
                        ? PureTubeVideoView(
                            textureId: _textureId,
                            aspectRatio: 16 / 9,
                          )
                        : const Center(
                            child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
              listenable: _pt,
              builder: (context, _) {
                final pos = _pt.position;
                final dur = _pt.duration;
                return Column(
                  children: [
                    Slider(
                      value: dur.inMilliseconds > 0
                          ? (pos.inMilliseconds / dur.inMilliseconds)
                              .clamp(0.0, 1.0)
                          : 0,
                      onChanged: (v) => _pt.seek(Duration(
                          milliseconds:
                              (v * dur.inMilliseconds).round())),
                    ),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatDuration(pos),
                            style:
                                const TextStyle(color: Colors.grey)),
                        Text(formatDuration(dur),
                            style:
                                const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: _pt,
            builder: (context, _) {
              final playing = _pt.isPlaying;
              return IconButton(
                iconSize: 56,
                onPressed: () =>
                    playing ? _pt.pause() : _pt.play(),
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
