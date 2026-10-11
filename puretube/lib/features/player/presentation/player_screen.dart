import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/services/audio_player_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../home/presentation/widgets/video_card.dart';
import '../../home/presentation/providers/search_provider.dart';
import 'providers/player_controller.dart';
import 'widgets/comments_section.dart';
import 'widgets/player_controls.dart';
import 'widgets/quality_speed_sheets.dart';
import 'widgets/sleep_timer_sheet.dart';
import 'widgets/subtitle_widgets.dart';
import 'widgets/video_info_section.dart';

/// PureTube player — full-featured video screen.
/// Assembled from widgets in ./widgets/.
class PlayerScreen extends ConsumerStatefulWidget {
  final String videoId;

  const PlayerScreen({super.key, required this.videoId});

  @override
  ConsumerState<PlayerScreen> createState() =>
      _PlayerScreenState();
}

class _PlayerScreenState
    extends ConsumerState<PlayerScreen> {
  VideoController? _videoController;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isFullscreen = false;
  double _zoom = 1.0;

  String? _flashText;
  IconData? _flashIcon;
  Timer? _flashTimer;

  String? _rippleText;
  bool _rippleLeft = false;
  Timer? _rippleTimer;

  StreamSubscription<String?>? _badgeSub;
  String? _skipBadge;
  Timer? _badgeTimer;

  @override
  void initState() {
    super.initState();
    try {
      final handler =
          ref.read(audioHandlerProvider);
      _videoController =
          VideoController(handler.player);
    } catch (_) {}
    Future.microtask(() {
      try {
        ref
            .read(playerControllerProvider.notifier)
            .loadVideo(widget.videoId);
      } catch (_) {}
    });
    try {
      _badgeSub = ref
          .read(playerControllerProvider.notifier)
          .skipBadgeStream
          .listen((msg) {
        _badgeTimer?.cancel();
        if (mounted) {
          setState(() => _skipBadge = msg);
        }
        if (msg != null) {
          _badgeTimer = Timer(
              const Duration(seconds: 2),
              () => mounted
                  ? setState(
                      () => _skipBadge = null)
                  : null);
        }
      });
    } catch (_) {}
    _restartHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _rippleTimer?.cancel();
    _badgeTimer?.cancel();
    _badgeSub?.cancel();
    try {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge);
    } catch (_) {}
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(
        const Duration(seconds: 3),
        () => mounted
            ? setState(
                () => _showControls = false)
            : null);
  }

  void _toggleControls() {
    if (!mounted) return;
    setState(() => _showControls = !_showControls);
    _restartHideTimer();
  }

  void _flash(String text, IconData icon) {
    _flashTimer?.cancel();
    if (mounted) {
      setState(() {
        _flashText = text;
        _flashIcon = icon;
      });
    }
    _flashTimer = Timer(
        const Duration(milliseconds: 800),
        () => mounted
            ? setState(() => _flashText = null)
            : null);
  }

  void _ripple(String text, bool left) {
    _rippleTimer?.cancel();
    if (mounted) {
      setState(() {
        _rippleText = text;
        _rippleLeft = left;
      });
    }
    _rippleTimer = Timer(
        const Duration(milliseconds: 600),
        () => mounted
            ? setState(() => _rippleText = null)
            : null);
  }

  // ── Gestures ──────────────────────────────────────────────

  Future<void> _doubleTapLeft() async {
    try {
      await ref
          .read(playerControllerProvider.notifier)
          .seekBy(const Duration(seconds: -10));
    } catch (_) {}
    _ripple('-10s', true);
    _restartHideTimer();
  }

  Future<void> _doubleTapRight() async {
    try {
      await ref
          .read(playerControllerProvider.notifier)
          .seekBy(const Duration(seconds: 10));
    } catch (_) {}
    _ripple('+10s', false);
    _restartHideTimer();
  }

  Future<void> _volumeSwipe(double dy) async {
    try {
      final v =
          await VolumeController.instance.getVolume();
      final next =
          (v + (-dy / 280)).clamp(0.0, 1.0);
      await VolumeController.instance
          .setVolume(next);
      _flash('Volume ${(next * 100).round()}%',
          Icons.volume_up);
    } catch (_) {}
  }

  Future<void> _brightnessSwipe(double dy) async {
    try {
      final b =
          await ScreenBrightness().current;
      final next =
          (b + (-dy / 280)).clamp(0.05, 1.0);
      await ScreenBrightness()
          .setScreenBrightness(next);
      _flash(
          'Brightness ${(next * 100).round()}%',
          Icons.brightness_6);
    } catch (_) {}
  }

  void _toggleFullscreen() {
    if (!mounted) return;
    setState(() => _isFullscreen = !_isFullscreen);
    try {
      if (_isFullscreen) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ]);
        SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(playerControllerProvider);
    Player? player;
    try {
      player =
          ref.watch(audioHandlerProvider).player;
    } catch (_) {
      player = null;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _isFullscreen && player != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _videoArea(ui, player),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(
                          Icons.fullscreen_exit,
                          color: Colors.white),
                      onPressed:
                          _toggleFullscreen,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  if (player != null)
                    _videoArea(ui, player),
                  Expanded(
                      child: _belowPlayer(ui)),
                ],
              ),
      ),
    );
  }

  // ── Video area ────────────────────────────────────────────

  Widget _videoArea(PlayerUiState ui, Player player) {
    final ready = ui.status == PlayerStatus.ready;
    final notifier =
        ref.read(playerControllerProvider.notifier);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_videoController != null)
              Transform.scale(
                scale: _zoom,
                child: Video(
                    controller:
                        _videoController!,
                    controls:
                        NoVideoControls),
              ),
            if (ui.status == PlayerStatus.loading)
              const Center(
                  child:
                      CircularProgressIndicator(
                          color:
                              AppTheme.primary)),
            if (ui.status == PlayerStatus.error)
              _error(ui),
            if (ready)
              _gestureLayer(player, ui, notifier),
            if (ready &&
                ui.activeSubtitle != null)
              SubtitleOverlay(
                player: player,
                notifier: notifier,
              ),
            if (ui.sleepTimer.active)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black
                        .withOpacity(0.7),
                    borderRadius:
                        BorderRadius.circular(
                            16),
                  ),
                  child: Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      const Icon(
                          Icons.bedtime_outlined,
                          size: 14,
                          color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        formatDuration(ui
                            .sleepTimer
                            .remaining),
                        style:
                            AppTheme.caption
                                .copyWith(
                                    color: Colors
                                        .white),
                      ),
                    ],
                  ),
                ),
              ),
            if (_skipBadge != null)
              Positioned(
                bottom: 90,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary
                          .withOpacity(0.9),
                      borderRadius:
                          BorderRadius.circular(
                              20),
                    ),
                    child: Text(_skipBadge!,
                        style:
                            AppTheme.caption
                                .copyWith(
                                    color: Colors
                                        .white,
                                    fontWeight:
                                        FontWeight
                                            .w600)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gestureLayer(Player player,
      PlayerUiState ui, PlayerController notifier) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior:
                    HitTestBehavior.translucent,
                onDoubleTap: _doubleTapLeft,
                onTap: _toggleControls,
                onVerticalDragUpdate: (d) =>
                    _brightnessSwipe(
                        d.delta.dy),
                child:
                    Container(color: Colors.transparent),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior:
                    HitTestBehavior.translucent,
                onDoubleTap: _doubleTapRight,
                onTap: _toggleControls,
                onVerticalDragUpdate: (d) =>
                    _volumeSwipe(d.delta.dy),
                child:
                    Container(color: Colors.transparent),
              ),
            ),
          ],
        ),
        GestureDetector(
          onScaleUpdate: (d) {
            if (mounted) {
              setState(() {
                _zoom =
                    d.scale.clamp(0.5, 2.0);
              });
            }
          },
          onScaleEnd: (_) {
            if ((_zoom - 1.0).abs() < 0.1 &&
                mounted) {
              setState(() => _zoom = 1.0);
            }
          },
          child:
              Container(color: Colors.transparent),
        ),
        if (_rippleText != null)
          Positioned(
            left: _rippleLeft ? 40 : null,
            right: _rippleLeft ? null : 40,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white
                      .withOpacity(0.25),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        _rippleLeft
                            ? Icons.replay_10
                            : Icons.forward_10,
                        color: Colors.white,
                        size: 28,
                      ),
                      Text(_rippleText!,
                          style: AppTheme
                              .caption
                              .copyWith(
                                  color: Colors
                                      .white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_flashText != null)
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12),
              decoration: BoxDecoration(
                color:
                    Colors.black.withOpacity(0.7),
                borderRadius:
                    BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_flashIcon,
                      color: Colors.white),
                  const SizedBox(width: 8),
                  Text(_flashText!,
                      style: AppTheme.body
                          .copyWith(
                              color: Colors
                                  .white)),
                ],
              ),
            ),
          ),
        if (_showControls) ...[
          PlayerTopBar(
            ui: ui,
            onBack: () =>
                Navigator.pop(context),
            onPip: () =>
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(
                        content: Text(
                            'PiP: press Home during playback'))),
            onPopup: () =>
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(
                        content: Text(
                            'Popup player coming in Phase 3'))),
            onMore: () => _moreSheet(notifier),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: PlayerBottomBar(
              player: player,
              ui: ui,
              notifier: notifier,
              onFullscreen: _toggleFullscreen,
            ),
          ),
          Center(
              child: PlayerCenterButton(
            player: player,
            onToggle: () {
              try {
                notifier.togglePlayPause();
              } catch (_) {}
              _restartHideTimer();
            },
          )),
        ],
      ],
    );
  }

  Widget _error(PlayerUiState ui) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48,
                color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(ui.error ?? 'Playback failed.',
                textAlign: TextAlign.center,
                style: AppTheme.body.copyWith(
                    color:
                        AppTheme.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                try {
                  ref
                      .read(
                          playerControllerProvider
                              .notifier)
                      .retry();
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      AppTheme.primary),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── ⋮ menu ────────────────────────────────────────────────

  void _moreSheet(PlayerController notifier) {
    final ui = ref.read(playerControllerProvider);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                  Icons.high_quality_outlined),
              title: const Text('Quality'),
              subtitle: Text(
                  ui.currentQualityHeight > 0
                      ? '${ui.currentQualityHeight}p'
                      : 'Auto',
                  style: AppTheme.caption.copyWith(
                      color:
                          AppTheme.textSecondary)),
              onTap: () {
                Navigator.pop(context);
                QualitySheet.show(
                    context, notifier, ui);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.speed_outlined),
              title: const Text('Playback speed'),
              subtitle: Text('${ui.speed}x',
                  style: AppTheme.caption.copyWith(
                      color:
                          AppTheme.textSecondary)),
              onTap: () {
                Navigator.pop(context);
                SpeedSheet.show(
                    context, notifier, ui.speed);
              },
            ),
            ListTile(
              leading: const Icon(
                  Icons.bedtime_outlined),
              title: const Text('Sleep timer'),
              subtitle: Text(
                  ui.sleepTimer.active
                      ? formatDuration(ui
                          .sleepTimer.remaining)
                      : 'Off',
                  style: AppTheme.caption.copyWith(
                      color:
                          AppTheme.textSecondary)),
              onTap: () {
                Navigator.pop(context);
                SleepTimerSheet.show(
                    context, notifier);
              },
            ),
            SwitchListTile(
              secondary: const Icon(
                  Icons.headphones_outlined),
              title: const Text('Audio only'),
              value: ui.audioOnly,
              activeColor: AppTheme.primary,
              onChanged: (_) {
                Navigator.pop(context);
                try {
                  notifier.toggleAudioOnly();
                } catch (_) {}
              },
            ),
            SwitchListTile(
              secondary:
                  const Icon(Icons.cut_outlined),
              title: const Text('Skip sponsors'),
              subtitle:
                  const Text('SponsorBlock'),
              value: ui.skipSponsors,
              activeColor: AppTheme.primary,
              onChanged: (v) {
                try {
                  notifier.toggleSkipSponsors(v);
                } catch (_) {}
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Below player ──────────────────────────────────────────

  Widget _belowPlayer(PlayerUiState ui) {
    final video = ui.video;
    if (video == null) {
      return const SizedBox.shrink();
    }
    final notifier =
        ref.read(playerControllerProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          VideoInfoSection(
              video: video,
              ui: ui,
              notifier: notifier),
          const SizedBox(height: 20),
          CommentsSection(ui: ui),
          if (ui.related.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Up next',
                style: AppTheme.subtitle.copyWith(
                    fontWeight:
                        FontWeight.bold)),
            const SizedBox(height: 8),
            ...ui.related.map((v) =>
                VideoCard(video: v)),
          ],
        ],
      ),
    );
  }
}
