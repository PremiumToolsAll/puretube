import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/services/exoplayer_service.dart';
import '../../domain/entities/playback_models.dart';

/// Full ExoPlayer-based video player (NewPipe-style).
///
/// Replaces the mpv player for high-quality playback.
/// Uses DASH manifests with ExoPlayer, like NewPipe.
class ExoPlayerScreen extends ConsumerStatefulWidget {
  final String videoId;

  const ExoPlayerScreen({super.key, required this.videoId});

  @override
  ConsumerState<ExoPlayerScreen> createState() =>
      _ExoPlayerScreenState();
}

class _ExoPlayerScreenState
    extends ConsumerState<ExoPlayerScreen> {
  final _exoService = ExoPlayerService();
  VideoDetails? _details;
  List<MuxedQuality> _qualities = [];
  MuxedQuality? _current;
  bool _loading = true;
  String? _error;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final extractor = ref.read(extractorProvider);
      final details =
          await extractor.getVideoDetails(widget.videoId);
      final qualities =
          await extractor.getQualityOptions(widget.videoId);

      if (!mounted) return;
      setState(() {
        _details = details;
        _qualities = qualities;
        _loading = false;
      });

      // Auto-play best quality (prefer 1080p AVC, fallback to highest).
      final best = _pickBest(qualities);
      if (best != null) await _playQuality(best);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  MuxedQuality? _pickBest(List<MuxedQuality> qualities) {
    // Prefer 1080p AVC, then highest AVC, then highest overall.
    MuxedQuality? best;
    for (final q in qualities) {
      if (!q.isDash) continue;
      if (q.height == 1080 &&
          q.codec.toLowerCase().contains('avc')) {
        if (best == null ||
            q.bitrateKbps > best.bitrateKbps) {
          best = q;
        }
      }
    }
    best ??= qualities
        .where((q) =>
            q.isDash &&
            q.codec.toLowerCase().contains('avc'))
        .fold<MuxedQuality?>(null, (b, q) {
      if (b == null || q.height > b.height) return q;
      return b;
    });
    best ??= qualities
        .where((q) => q.isDash)
        .fold<MuxedQuality?>(null, (b, q) {
      if (b == null || q.height > b.height) return q;
      return b;
    });
    return best;
  }

  Future<void> _playQuality(MuxedQuality q) async {
    setState(() {
      _current = q;
      _loading = true;
      _error = null;
    });

    try {
      // Get stream details for DASH manifest.
      // Find video and audio URLs from the quality.
      String? videoUrl = q.url;
      String? audioUrl = q.audioUrl;
      String videoMime = 'video/mp4; codecs="avc1.640028"';
      String audioMime = 'audio/mp4; codecs="mp4a.40.2"';
      int width = 1920;
      int height = q.height;
      int videoBitrate =
          (q.bitrateKbps * 1000).toInt();
      int audioBitrate = 128000;
      double durationSec = 0;

      // Try to get detailed stream info.
      try {
        final ext = ref.read(extractorProvider);
        final details =
            await ext.getVideoDetails(widget.videoId);
        durationSec =
            details.duration?.inSeconds.toDouble() ?? 0;
      } catch (_) {}

      if (videoUrl.isEmpty) {
        throw Exception('No video URL');
      }

      if (audioUrl == null || audioUrl.isEmpty) {
        throw Exception('No audio URL for ${q.label}');
      }

      await _exoService.play(
        videoUrl: videoUrl,
        audioUrl: audioUrl,
        videoMime: videoMime,
        audioMime: audioMime,
        width: width,
        height: height,
        videoBitrate: videoBitrate,
        audioBitrate: audioBitrate,
        durationSec: durationSec > 0 ? durationSec : 3600,
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to play ${q.label}: $e';
        });
      }
    }
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Quality',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _qualities.length,
                itemBuilder: (c, i) {
                  final q = _qualities[i];
                  final selected = q == _current;
                  return ListTile(
                    title: Text(q.label,
                        style: TextStyle(
                            color: selected
                                ? Colors.green
                                : Colors.white)),
                    trailing: selected
                        ? const Icon(Icons.check,
                            color: Colors.green)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _playQuality(q);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _exoService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _exoService.controller;
    final isPlaying =
        controller?.value.isPlaying ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_details?.title ?? 'Loading...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14)),
        actions: [
          if (_qualities.isNotEmpty)
            TextButton(
              onPressed: _showQualityPicker,
              child: Text(_current?.label ?? 'Quality',
                  style: const TextStyle(
                      color: Colors.green)),
            ),
        ],
      ),
      body: _loading && _details == null
          ? const Center(
              child: CircularProgressIndicator())
          : _error != null && _details == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.red)),
                  ),
                )
              : Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // Video.
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        children: [
                          if (controller != null &&
                              controller
                                  .value.isInitialized)
                            GestureDetector(
                              onTap: () => setState(() =>
                                  _showControls =
                                      !_showControls),
                              child: VideoPlayer(
                                  controller),
                            )
                          else
                            const Center(
                              child:
                                  CircularProgressIndicator(),
                            ),
                          if (_showControls &&
                              controller != null)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black26,
                                child: Center(
                                  child: IconButton(
                                    iconSize: 64,
                                    color: Colors.white,
                                    icon: Icon(isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons
                                            .play_circle_filled),
                                    onPressed: () async {
                                      if (isPlaying) {
                                        await _exoService
                                            .pause();
                                      } else {
                                        await _exoService
                                            .resume();
                                      }
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Progress.
                    if (controller != null)
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors:
                            const VideoProgressColors(
                          playedColor: Colors.green,
                        ),
                      ),
                    // Title.
                    Padding(
                      padding:
                          const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            _details?.title ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow:
                                TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_details?.author ?? ''} • ${_current?.label ?? ''}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13),
                          ),
                          if (_error != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(
                                      top: 8),
                              child: Text(_error!,
                                  style:
                                      const TextStyle(
                                          color:
                                              Colors.red,
                                          fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 16),
                      child: Text(
                        'ExoPlayer (NewPipe-style) — all qualities',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
    );
  }
}
