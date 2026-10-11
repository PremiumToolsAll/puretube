import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../../../../features/library/domain/entities/library_models.dart';
import '../../../../features/library/presentation/providers/library_providers.dart';
import '../../../../features/library/presentation/screens/playlists_screen.dart'
    show showSaveToPlaylistSheet;
import '../../../ai/ai_summary_section.dart';
import '../../../channel/presentation/screens/channel_screen.dart';
import '../../domain/entities/playback_models.dart';
import '../providers/player_controller.dart';
import '../widgets/live_chat_widget.dart';
import '../widgets/subtitle_sheet.dart';

class _Gauge {
  final IconData icon;
  final String label;
  final double value; // 0..1
  const _Gauge(
      {required this.icon, required this.label, required this.value});
}

class PlayerScreen extends ConsumerStatefulWidget {
  final String videoId;
  final Duration? initialPosition;
  const PlayerScreen(
      {super.key, required this.videoId, this.initialPosition});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _accent = Color(0xFF6200EA);

  VideoController? _videoController;
  bool _showControls = true;
  Timer? _hideTimer;

  // double-tap
  Offset? _doubleTapPos;
  String? _seekFlash;
  bool _seekFlashLeft = true;
  Timer? _seekFlashTimer;

  // volume / brightness / scrub overlay
  _Gauge? _gauge;
  Timer? _gaugeTimer;

  // vertical-drag gesture state
  bool _dragOnRightSide = true;
  double? _dragStartVolume; // 0..100
  double? _dragStartBrightness; // 0..1

  // horizontal scrub state
  Duration? _scrubStartPosition;
  Duration? _scrubPreview;

  // long-press 2x
  double _prevSpeed = 1.0;

  // resume-from-history
  bool _didInitialSeek = false;
  ProviderSubscription<PlayerStatus>? _statusSub;
  ProviderSubscription<VideoDetails?>? _videoSub;

  @override
  void initState() {
    super.initState();
    _videoController = VideoController(ref.read(mediaKitPlayerProvider));
    final st = ref.read(playerControllerProvider);
    if (st.videoId != widget.videoId ||
        st.status != PlayerStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(playerControllerProvider.notifier)
              .loadVideo(widget.videoId);
        }
      });
    }
    // Record watch history when metadata arrives.
    _videoSub = ref.listenManual(
      playerControllerProvider.select((s) => s.video),
      (prev, next) {
        if (next != null && prev?.id != next.id) {
          ref.read(historyRepositoryProvider).record(
                HistoryEntry(
                  videoId: next.id,
                  title: next.title,
                  author: next.author,
                  thumbnailUrl: next.thumbnailUrl,
                  durationSecs: next.duration?.inSeconds,
                  watchedAt: DateTime.now(),
                ),
              );
          ref.read(historyControllerProvider.notifier).refresh();
        }
      },
    );
    // Resume from history/bookmark position, once, when ready.
    _statusSub = ref.listenManual(
      playerControllerProvider.select((s) => s.status),
      (prev, status) {
        if (status == PlayerStatus.ready &&
            !_didInitialSeek &&
            widget.initialPosition != null) {
          _didInitialSeek = true;
          ref
              .read(playerControllerProvider.notifier)
              .seekTo(widget.initialPosition!);
        }
      },
    );
    _restartHideTimer();
  }

  @override
  void dispose() {
    _videoSub?.close();
    _statusSub?.close();
    // Persist resume position for history.
    final uiState = ref.read(playerControllerProvider);
    if (uiState.videoId != null) {
      ref.read(historyRepositoryProvider).updatePosition(
            uiState.videoId!,
            ref
                .read(mediaKitPlayerProvider)
                .state
                .position
                .inSeconds,
          );
    }
    _hideTimer?.cancel();
    _seekFlashTimer?.cancel();
    _gaugeTimer?.cancel();
    super.dispose();
  }

  // ---------------- controls visibility ----------------

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _restartHideTimer();
  }

  // ---------------- double-tap: -10s / +10s / play-pause ----------------

  void _onDoubleTap() {
    final pos = _doubleTapPos;
    if (pos == null) return;
    final width = MediaQuery.of(context).size.width;
    final notifier = ref.read(playerControllerProvider.notifier);
    if (pos.dx < width * 0.35) {
      notifier.seekBy(const Duration(seconds: -10));
      _flashSeek('-10s', left: true);
    } else if (pos.dx > width * 0.65) {
      notifier.seekBy(const Duration(seconds: 10));
      _flashSeek('+10s', left: false);
    } else {
      notifier.togglePlayPause();
    }
    _restartHideTimer();
  }

  void _flashSeek(String label, {required bool left}) {
    _seekFlashTimer?.cancel();
    setState(() {
      _seekFlash = label;
      _seekFlashLeft = left;
    });
    _seekFlashTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  // ---------------- long-press: 2x speed ----------------

  Future<void> _onLongPressStart() async {
    final notifier = ref.read(playerControllerProvider.notifier);
    _prevSpeed = ref.read(playerControllerProvider).speed;
    await notifier.setSpeed(2.0);
    _showGauge(const _Gauge(
        icon: Icons.fast_forward, label: '2x speed', value: 1.0));
  }

  Future<void> _onLongPressEnd() async {
    await ref
        .read(playerControllerProvider.notifier)
        .setSpeed(_prevSpeed);
    _hideGaugeSoon();
  }

  // ---------------- vertical drag: right = volume, left = brightness ----------------

  Future<void> _onVerticalDragStart(DragStartDetails d) async {
    final width = MediaQuery.of(context).size.width;
    _dragOnRightSide = d.globalPosition.dx > width / 2;
    if (_dragOnRightSide) {
      _dragStartVolume =
          ref.read(mediaKitPlayerProvider).state.volume;
    } else {
      try {
        _dragStartBrightness = await ScreenBrightness().current;
      } catch (_) {
        _dragStartBrightness = null;
      }
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final player = ref.read(mediaKitPlayerProvider);
    final delta = -d.delta.dy / 280; // ~280px swipe covers the full range
    if (_dragOnRightSide && _dragStartVolume != null) {
      final v =
          (_dragStartVolume! + delta * 100).clamp(0.0, 100.0);
      player.setVolume(v);
      _showGauge(_Gauge(
        icon: v == 0 ? Icons.volume_off : Icons.volume_up,
        label: 'Volume ${v.round()}%',
        value: v / 100,
      ));
    } else if (!_dragOnRightSide &&
        _dragStartBrightness != null) {
      final b = (_dragStartBrightness! + delta).clamp(0.05, 1.0);
      try {
        ScreenBrightness().setScreenBrightness(b);
      } catch (_) {}
      _showGauge(_Gauge(
        icon: Icons.brightness_6,
        label: 'Brightness ${(b * 100).round()}%',
        value: b,
      ));
    }
  }

  // ---------------- horizontal drag: scrub ----------------

  void _onScrubStart(DragStartDetails d) {
    _scrubStartPosition =
        ref.read(mediaKitPlayerProvider).state.position;
    _scrubPreview = _scrubStartPosition;
  }

  void _onScrubUpdate(DragUpdateDetails d) {
    final player = ref.read(mediaKitPlayerProvider);
    final start = _scrubStartPosition;
    if (start == null) return;
    final width = MediaQuery.of(context).size.width;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    // A full-width swipe scrubs across half the video: fine control.
    final delta = Duration(
      milliseconds:
          (d.delta.dx / width * duration.inMilliseconds / 2).round(),
    );
    var preview = _scrubPreview! + delta;
    if (preview < Duration.zero) preview = Duration.zero;
    if (preview > duration) preview = duration;
    final diff = preview - start;
    final sign = diff.isNegative ? '−' : '+';
    setState(() => _scrubPreview = preview);
    _showGauge(_Gauge(
      icon: Icons.fast_forward,
      label:
          '$sign${formatDuration(diff.abs())}  •  ${formatDuration(preview)}',
      value: preview.inMilliseconds / duration.inMilliseconds,
    ));
  }

  Future<void> _onScrubEnd() async {
    final preview = _scrubPreview;
    _scrubStartPosition = null;
    _scrubPreview = null;
    _hideGaugeSoon();
    if (preview != null) {
      await ref
          .read(playerControllerProvider.notifier)
          .seekTo(preview);
    }
  }

  // ---------------- gauge overlay ----------------

  void _showGauge(_Gauge gauge) {
    _gaugeTimer?.cancel();
    setState(() => _gauge = gauge);
  }

  void _hideGaugeSoon() {
    _gaugeTimer?.cancel();
    _gaugeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gauge = null);
    });
  }

  // ---------------- sheets ----------------

  void _showSpeedSheet() {
    final notifier = ref.read(playerControllerProvider.notifier);
    final current = ref.read(playerControllerProvider).speed;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Playback speed',
                    style:
                        TextStyle(fontWeight: FontWeight.bold))),
            for (final s in [
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              1.75,
              2.0
            ])
              ListTile(
                title: Text('${s}x'),
                trailing: s == current
                    ? const Icon(Icons.check, color: _accent)
                    : null,
                onTap: () {
                  notifier.setSpeed(s);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showQualityMenu(BuildContext buttonContext) {
    final notifier = ref.read(playerControllerProvider.notifier);
    final uiState = ref.read(playerControllerProvider);
    final qualities = uiState.availableQualities;
    if (qualities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading qualities…'),
          duration: Duration(seconds: 2),
        ),
      );
      // Retry the background fetch in case it failed earlier.
      unawaited(notifier.loadQualities());
      return;
    }
    final current = uiState.currentQuality;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? Size.zero;
    final position = RelativeRect.fromLTRB(
      pos.dx,
      pos.dy + size.height + 4,
      pos.dx + 200,
      pos.dy + size.height + 4 + qualities.length * 48.0,
    );
    showMenu<MuxedQuality>(
      context: context,
      position: position,
      color: const Color(0xFF232323),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8)),
      items: [
        for (final q in qualities)
          PopupMenuItem<MuxedQuality>(
            value: q,
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(q.label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
                ),
                if (current?.height == q.height)
                  const Icon(Icons.check,
                      color: _accent, size: 18),
              ],
            ),
          ),
      ],
    ).then((selected) {
      if (selected != null && mounted) {
        notifier.setQuality(selected);
      }
    });
  }

  void _showSleepSheet() {
    final notifier = ref.read(playerControllerProvider.notifier);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Sleep timer',
                    style:
                        TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              title: const Text('Off'),
              onTap: () {
                notifier.cancelSleepTimer();
                Navigator.pop(ctx);
              },
            ),
            for (final m in [5, 10, 15, 30, 45, 60])
              ListTile(
                title: Text('$m minutes'),
                onTap: () {
                  notifier
                      .startSleepTimer(Duration(minutes: m));
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showMoreSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final ui = ref.watch(playerControllerProvider);
          final notifier =
              ref.read(playerControllerProvider.notifier);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.headphones),
                  title: const Text('Audio only'),
                  subtitle: const Text(
                      'Background audio, screen can go off'),
                  value: ui.audioOnly,
                  activeColor: _accent,
                  onChanged: (_) => notifier.toggleAudioOnly(),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.cut),
                  title: const Text('Skip sponsors'),
                  subtitle: const Text(
                      'Auto-skip SponsorBlock segments'),
                  value: ui.skipSponsors,
                  activeColor: _accent,
                  onChanged: notifier.toggleSkipSponsors,
                ),
                ListTile(
                  leading: Icon(
                    ref
                            .read(bookmarkControllerProvider
                                .notifier)
                            .isBookmarked(ui.videoId ?? '')
                        ? Icons.bookmark
                        : Icons.bookmark_add_outlined,
                  ),
                  title: const Text('Bookmark'),
                  onTap: () {
                    final v = ui.video;
                    Navigator.pop(ctx);
                    if (v == null) return;
                    ref
                        .read(bookmarkControllerProvider.notifier)
                        .toggle(
                          BookmarkEntry(
                            videoId: v.id,
                            title: v.title,
                            author: v.author,
                            thumbnailUrl: v.thumbnailUrl,
                            savedAt: DateTime.now(),
                          ),
                        );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: const Text('Save to playlist'),
                  onTap: () {
                    final v = ui.video;
                    Navigator.pop(ctx);
                    if (v != null) {
                      showSaveToPlaylistSheet(context, v);
                    }
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.download_outlined),
                  title: const Text('Download'),
                  onTap: () {
                    final v = ui.video;
                    Navigator.pop(ctx);
                    if (v != null) _showDownloadSheet(v);
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.picture_in_picture_alt),
                  title: const Text('Picture in picture'),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.enterPip();
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.share_outlined),
                  title: const Text('Share'),
                  onTap: () {
                    final v = ui.video;
                    Navigator.pop(ctx);
                    if (v != null) {
                      Share.share(
                          'https://www.youtube.com/watch?v=${v.id}');
                    }
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.open_in_browser),
                  title: const Text('Open in browser'),
                  onTap: () {
                    final v = ui.video;
                    Navigator.pop(ctx);
                    if (v != null) {
                      launchUrl(
                        Uri.parse(
                            'https://www.youtube.com/watch?v=${v.id}'),
                        mode:
                            LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.stop,
                      color: Colors.red),
                  title: const Text('Stop playback',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.stop();
                    if (mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDownloadSheet(VideoDetails video) async {
    final extractor = ref.read(extractorProvider);
    final notifier =
        ref.read(downloadsControllerProvider.notifier);
    List<DownloadOption>? options;
    String? error;
    try {
      options = await extractor.getDownloadOptions(video.id);
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        if (error != null || options == null) {
          return SafeArea(
            child: ListTile(
              leading: const Icon(Icons.error_outline,
                  color: Colors.red),
              title:
                  const Text('Could not list qualities.'),
              subtitle: Text(error ?? '',
                  style:
                      const TextStyle(color: Colors.grey)),
            ),
          );
        }
        String size(int? b) => b == null
            ? 'Size unknown'
            : '${(b / (1 << 20)).toStringAsFixed(1)} MB';
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                  title: Text('Download',
                      style: TextStyle(
                          fontWeight: FontWeight.bold))),
              for (final o in options)
                ListTile(
                  leading: Icon(o.audioOnly
                      ? Icons.audio_file
                      : Icons.video_file),
                  title: Text(o.label),
                  subtitle: Text(size(o.sizeBytes)),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.startDownload(o, video);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(
                      content: Text('Download started'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(playerControllerProvider);

    // PiP mode: render the bare video only. The system owns the window.
    if (uiState.isInPip && _videoController != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Video(
              controller: _videoController!,
              controls: NoVideoControls),
        ),
      );
    }

    final player = ref.watch(mediaKitPlayerProvider);
    final notifier = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildVideoArea(uiState, player),
            Expanded(child: _buildMeta(uiState, notifier)),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea(PlayerUiState uiState, Player player) {
    final isReady = uiState.status == PlayerStatus.ready;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (uiState.audioOnly && uiState.video != null)
              _buildAudioArt(uiState)
            else if (_videoController != null)
              Video(
                  controller: _videoController!,
                  controls: NoVideoControls),
            if (isReady)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                onDoubleTapDown: (d) =>
                    _doubleTapPos = d.globalPosition,
                onDoubleTap: _onDoubleTap,
                onLongPressStart: (_) => _onLongPressStart(),
                onLongPressEnd: (_) => _onLongPressEnd(),
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: (_) => _hideGaugeSoon(),
                onHorizontalDragStart: (d) =>
                    _onScrubStart(d),
                onHorizontalDragUpdate: (d) =>
                    _onScrubUpdate(d),
                onHorizontalDragEnd: (_) => _onScrubEnd(),
              ),
            if (uiState.status == PlayerStatus.loading)
              const Center(
                  child: CircularProgressIndicator(
                      color: _accent)),
            if (uiState.status == PlayerStatus.error)
              _buildError(uiState),
            if (_seekFlash != null)
              Align(
                alignment: _seekFlashLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 44),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _seekFlashLeft
                                ? Icons.replay_10
                                : Icons.forward_10,
                            color: Colors.white,
                            size: 28),
                        Text(_seekFlash!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            if (_gauge != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius:
                          BorderRadius.circular(12)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_gauge!.icon,
                          color: Colors.white, size: 28),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 150,
                        child: LinearProgressIndicator(
                          value: _gauge!.value,
                          backgroundColor: Colors.white24,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(_gauge!.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ),
            if (_showControls && isReady) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(uiState),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomControls(player, uiState),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioArt(PlayerUiState uiState) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: uiState.video!.thumbnailUrl,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              Container(color: Colors.black),
        ),
        Container(color: Colors.black54),
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headphones,
                  size: 56, color: Colors.white70),
              SizedBox(height: 8),
              Text('Audio only',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError(PlayerUiState uiState) {
    final notifier = ref.read(playerControllerProvider.notifier);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              uiState.errorMessage ?? 'Playback failed.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _accent),
              onPressed: notifier.retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(PlayerUiState uiState) {
    final qualityLabel = uiState.currentQuality != null
        ? '${uiState.currentQuality!.height}p'
        : (uiState.streams != null
            ? '${uiState.streams!.muxedHeight}p'
            : 'Auto');
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            // Back keeps audio playing in the background (mini player).
            onPressed: () => Navigator.pop(context),
            icon:
                const Icon(Icons.close, color: Colors.white),
          ),
          Expanded(
            child: Text(
              uiState.video?.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          if (uiState.sleepRemaining != null)
            TextButton(
              onPressed: _showSleepSheet,
              child: Text(
                '⏾ ${formatDuration(uiState.sleepRemaining)}',
                style: const TextStyle(
                    color: _accent, fontSize: 12),
              ),
            ),
          IconButton(
            tooltip: 'Subtitles',
            onPressed: () => SubtitleSheet.show(context),
            icon: Icon(Icons.closed_caption_outlined,
                color: uiState.activeSubtitle != null
                    ? _accent
                    : Colors.white),
          ),
          Builder(
            builder: (btnCtx) => TextButton(
              onPressed: () => _showQualityMenu(btnCtx),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(qualityLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ),
          TextButton(
            onPressed: _showSpeedSheet,
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize:
                  MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('${uiState.speed}x',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          IconButton(
            tooltip: 'Save to playlist',
            onPressed: () {
              final v = uiState.video;
              if (v != null) {
                showSaveToPlaylistSheet(context, v);
              }
            },
            icon: const Icon(Icons.playlist_add,
                color: Colors.white),
          ),
          IconButton(
            onPressed: _showMoreSheet,
            icon:
                const Icon(Icons.more_vert, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(
      Player player, PlayerUiState uiState) {
    final notifier = ref.read(playerControllerProvider.notifier);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayerSeekBar(player: player),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                _TimeLabel(player: player, current: true),
                const Spacer(),
                TextButton(
                  onPressed: _showSpeedSheet,
                  child: Text('${uiState.speed}x',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  builder: (context, snap) {
                    final playing = snap.data ?? false;
                    return IconButton(
                      iconSize: 40,
                      onPressed: notifier.togglePlayPause,
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Sleep timer',
                  onPressed: _showSleepSheet,
                  icon: Icon(Icons.bedtime,
                      color: uiState.sleepRemaining != null
                          ? _accent
                          : Colors.white),
                ),
                const Spacer(),
                _TimeLabel(player: player, current: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta(
      PlayerUiState uiState, PlayerController notifier) {
    final video = uiState.video;
    if (video == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(video.title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              if (video.channelId.isNotEmpty) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChannelScreen(
                        channelId: video.channelId),
                  ),
                );
              }
            },
            child: Text(
              '${video.author}  •  ${formatCount(video.viewCount)} views  •  ${timeAgo(video.uploadDate)}',
              style: const TextStyle(
                  color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 14),
          _buildActionRow(uiState, notifier),
          const SizedBox(height: 16),
          if (video.id.isNotEmpty)
            _UpNextSection(videoId: video.id),
          if (video.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Description',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(video.description,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          AiSummarySection(
            title: video.title,
            author: video.author,
            description: video.description,
          ),
          const SizedBox(height: 16),
          const LiveChatWidget(
              videoId: '', showUnavailable: true),
        ],
      ),
    );
  }
  /// Icon-above-label action row under the video, matching the
  /// reference design: Add To | Background | Popup | Download.
  Widget _buildActionRow(
      PlayerUiState uiState, PlayerController notifier) {
    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
    }) {
      final color = active ? _accent : Colors.white70;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    final video = uiState.video;
    return Row(
      children: [
        item(
          icon: Icons.playlist_add,
          label: 'Add To',
          onTap: () {
            if (video != null) {
              showSaveToPlaylistSheet(context, video);
            }
          },
        ),
        item(
          icon: Icons.headphones,
          label: 'Background',
          active: uiState.audioOnly,
          onTap: notifier.toggleAudioOnly,
        ),
        item(
          icon: Icons.picture_in_picture_alt,
          label: 'Popup',
          onTap: () {
            if (uiState.pipSupported) {
              notifier.enterPip();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Picture-in-picture is not supported on this device.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
        item(
          icon: Icons.download_outlined,
          label: 'Download',
          onTap: () {
            if (video != null) _showDownloadSheet(video);
          },
        ),
      ],
    );
  }
}

/// "Up Next" suggestions below the player, loaded from the
/// extractor's related-videos search. Shimmer while loading,
/// retry button on empty/error.
class _UpNextSection extends ConsumerStatefulWidget {
  final String videoId;
  const _UpNextSection({required this.videoId});

  @override
  ConsumerState<_UpNextSection> createState() =>
      _UpNextSectionState();
}

class _UpNextSectionState extends ConsumerState<_UpNextSection> {
  Future<List<VideoDetails>>? _future;

  @override
  void initState() {
    super.initState();
    _future =
        ref.read(extractorProvider).getRelatedVideos(widget.videoId);
  }

  @override
  void didUpdateWidget(covariant _UpNextSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      setState(() {
        _future = ref
            .read(extractorProvider)
            .getRelatedVideos(widget.videoId);
      });
    }
  }

  void _retry() {
    setState(() {
      _future =
          ref.read(extractorProvider).getRelatedVideos(widget.videoId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VideoDetails>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Up Next',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white)),
              const SizedBox(height: 8),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 10),
                  child: Shimmer.fromColors(
                    baseColor: const Color(0xFF1A1A1A),
                    highlightColor: const Color(0xFF2E2E2E),
                    child: Row(
                      children: [
                        Container(
                          width: 120,
                          height: 68,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }
        final videos = snap.data ?? [];
        if (videos.isEmpty) {
          return Row(
            children: [
              const Expanded(
                child: Text('Up Next',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white)),
              ),
              TextButton(
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Up Next',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white)),
            const SizedBox(height: 8),
            for (final v in videos)
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PlayerScreen(videoId: v.id),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: v.thumbnailUrl,
                          width: 120,
                          height: 68,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 120,
                            height: 68,
                            color:
                                const Color(0xFF1A1A1A),
                          ),
                          errorWidget: (_, __, ___) =>
                              Container(
                            width: 120,
                            height: 68,
                            color:
                                const Color(0xFF1A1A1A),
                            child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                                size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(v.title,
                                maxLines: 2,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(
                              '${v.author}'
                              '${v.viewCount != null ? ' • ${formatCount(v.viewCount)} views' : ''}',
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final Player player;
  final bool current;
  const _TimeLabel(
      {required this.player, required this.current});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream:
          current ? player.stream.position : player.stream.duration,
      builder: (context, snap) => Text(
        formatDuration(snap.data),
        style:
            const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

/// Custom seek bar: buffered track + played track + knob, tap & drag to seek.
class _PlayerSeekBar extends StatefulWidget {
  final Player player;
  const _PlayerSeekBar({required this.player});

  @override
  State<_PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<_PlayerSeekBar> {
  bool _dragging = false;
  double _dragFrac = 0;

  double _fracFromDx(double dx) {
    final width = context.size?.width ?? 1;
    return ((dx - 12) / (width - 24)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: widget.player.stream.buffer,
          builder: (context, bufSnap) {
            final buffered = bufSnap.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              builder: (context, posSnap) {
                final position = posSnap.data ?? Duration.zero;
                final total = duration.inMilliseconds;
                final playedFrac = total > 0
                    ? (position.inMilliseconds / total)
                        .clamp(0.0, 1.0)
                    : 0.0;
                final bufferedFrac = total > 0
                    ? (buffered.inMilliseconds / total)
                        .clamp(0.0, 1.0)
                    : 0.0;
                final frac =
                    _dragging ? _dragFrac : playedFrac;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (d) => setState(() {
                    _dragging = true;
                    _dragFrac =
                        _fracFromDx(d.localPosition.dx);
                  }),
                  onHorizontalDragUpdate: (d) => setState(() =>
                      _dragFrac =
                          _fracFromDx(d.localPosition.dx)),
                  onHorizontalDragEnd: (_) async {
                    final target = Duration(
                        milliseconds:
                            (_dragFrac * total).round());
                    setState(() => _dragging = false);
                    await widget.player.seek(target);
                  },
                  onTapDown: (d) async {
                    final frac =
                        _fracFromDx(d.localPosition.dx);
                    await widget.player.seek(Duration(
                        milliseconds:
                            (frac * total).round()));
                  },
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12),
                    child: CustomPaint(
                      painter: _SeekBarPainter(
                        playedFrac: frac,
                        bufferedFrac: bufferedFrac,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SeekBarPainter extends CustomPainter {
  final double playedFrac;
  final double bufferedFrac;
  static const _accent = Color(0xFF6200EA);

  _SeekBarPainter(
      {required this.playedFrac, required this.bufferedFrac});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;
    final track = Paint()
      ..color = Colors.white24
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawLine(Offset(0, y), Offset(w, y), track);
    final buf = Paint()
      ..color = Colors.white38
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawLine(
        Offset(0, y), Offset(w * bufferedFrac, y), buf);
    final played = Paint()
      ..color = _accent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawLine(
        Offset(0, y), Offset(w * playedFrac, y), played);
    canvas.drawCircle(
        Offset(w * playedFrac, y), 7, Paint()..color = _accent);
    canvas.drawCircle(
        Offset(w * playedFrac, y),
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SeekBarPainter old) =>
      old.playedFrac != playedFrac ||
      old.bufferedFrac != bufferedFrac;
}
