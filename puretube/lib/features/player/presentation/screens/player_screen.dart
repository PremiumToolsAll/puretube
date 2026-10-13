import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/press_scale.dart';
import '../../../../features/library/domain/entities/library_models.dart';
import '../../../../features/library/presentation/providers/library_providers.dart';
import '../../../../features/library/presentation/screens/downloads_screen.dart';
import '../../../../features/library/presentation/screens/playlists_screen.dart'
    show showSaveToPlaylistSheet;
import '../../../ai/ai_summary_section.dart';
import '../widgets/ai_lyrics_card.dart';
import '../../../channel/presentation/screens/channel_screen.dart';
import '../../domain/entities/playback_models.dart';
import '../providers/player_controller.dart';
import '../widgets/live_chat_widget.dart';
import '../widgets/lyrics_sheet.dart';
import '../widgets/popup_player.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/subtitle_sheet.dart';
import '../../../../features/settings/presentation/screens/settings_screen.dart'
    show doubleTapSecondsProvider, geminiApiKeyProvider;
import '../../../../core/services/ai_summary_service.dart';

enum _GaugeKind { volume, brightness, info }

class _Gauge {
  final IconData icon;
  final String label;
  final double value; // 0..1
  final _GaugeKind kind;
  const _Gauge(
      {required this.icon,
      required this.label,
      required this.value,
      this.kind = _GaugeKind.info});
}

/// iPhone-style slim vertical pill indicator, premium edition.
///
/// 48dp wide × 132dp tall. Dark translucent (#1C1C1E @ 90%) background with
/// a subtle gold border and soft drop shadow, white fill rising from the
/// bottom proportional to [value] (0..1), with the kind icon (headphones /
/// sun) centered in dark grey. Fill height animates smoothly on value
/// changes.
///
/// The pill is tappable: tapping the upper half calls [onIncrease], the
/// lower half calls [onDecrease] (iPhone-style nudging). The current
/// percentage (0–100%) is shown below the pill in gold.
class _IosPill extends StatelessWidget {
  final double value;
  final _GaugeKind kind;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  /// Key used to translate a tap position into upper/lower half.
  final GlobalKey _pillKey = GlobalKey();

  _IosPill({
    required this.value,
    required this.kind,
    this.onIncrease,
    this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    const width = 48.0;
    const height = 132.0;
    const radius = 14.0;
    final gold = Theme.of(context).colorScheme.primary;
    final clamped = value.clamp(0.0, 1.0);
    final icon = kind == _GaugeKind.volume
        ? Icons.headphones
        : Icons.wb_sunny;
    // Muted state: show the muted icon variant.
    final showMuted =
        kind == _GaugeKind.volume && clamped <= 0.0;
    final percent = (clamped * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final box = _pillKey.currentContext
                ?.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.globalPosition);
            if (local.dy < box.size.height / 2) {
              onIncrease?.call();
            } else {
              onDecrease?.call();
            }
          },
          child: Container(
            key: _pillKey,
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0x1C1C1E).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: gold.withValues(alpha: 0.45),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: [
                  // White fill from the bottom.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      height: height * clamped,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.white,
                            Color(0xFFF5E6C8)
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Centered icon in dark grey.
                  Center(
                    child: Icon(
                      showMuted ? Icons.volume_off : icon,
                      size: 26,
                      color: const Color(0xFF3A3A3C),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Percentage readout in gold.
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: gold.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            '$percent%',
            style: TextStyle(
              color: gold,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// YouTube-original channel row shown directly below the video title:
/// [avatar] [channel name + subscriber count] [Subscribe button].
/// Tapping the avatar/name opens the channel page.
class _ChannelRow extends ConsumerStatefulWidget {
  final VideoDetails video;
  const _ChannelRow({required this.video});

  @override
  ConsumerState<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends ConsumerState<_ChannelRow> {
  ChannelInfo? _channel;
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _subscribed = ref
        .read(subscriptionRepositoryProvider)
        .isSubscribed(widget.video.channelId);
    _loadChannel();
  }

  @override
  void didUpdateWidget(covariant _ChannelRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.channelId != widget.video.channelId) {
      _channel = null;
      _subscribed = ref
          .read(subscriptionRepositoryProvider)
          .isSubscribed(widget.video.channelId);
      _loadChannel();
    }
  }

  Future<void> _loadChannel() async {
    final id = widget.video.channelId;
    if (id.isEmpty) return;
    try {
      final ch =
          await ref.read(extractorProvider).getChannel(id);
      if (!mounted) return;
      setState(() {
        _channel = ch;
        _subscribed = ref
            .read(subscriptionRepositoryProvider)
            .isSubscribed(id);
      });
    } catch (_) {}
  }

  Future<void> _toggleSubscribe() async {
    final repo = ref.read(subscriptionRepositoryProvider);
    final id = widget.video.channelId;
    try {
      if (_subscribed) {
        await repo.unsubscribe(id);
      } else {
        await repo.subscribe(
          channelId: id,
          name: _channel?.title ?? widget.video.author,
          subscriberCount: _channel?.subscriberCount,
        );
      }
      if (mounted) setState(() => _subscribed = !_subscribed);
    } catch (_) {}
  }

  void _openChannel() {
    if (widget.video.channelId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChannelScreen(channelId: widget.video.channelId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return Row(
      children: [
        GestureDetector(
          onTap: _openChannel,
          // WILLOW: circular avatar with an emerald ring.
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF3F3F3F),
              backgroundImage: _channel?.logoUrl != null
                  ? CachedNetworkImageProvider(
                      _channel!.logoUrl)
                  : null,
              child: _channel?.logoUrl == null
                  ? Text(
                      video.author.isNotEmpty
                          ? video.author[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _openChannel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _channel?.title ?? video.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  _channel?.subscriberCount != null
                      ? '${formatCount(_channel!.subscriberCount)} subscribers'
                      : 'Channel',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _toggleSubscribe,
          style: ElevatedButton.styleFrom(
            // WILLOW: solid emerald pill; subscribed = dark pill, emerald text.
            backgroundColor: _subscribed
                ? Theme.of(context).colorScheme.surfaceContainer
                : Theme.of(context).colorScheme.primary,
            foregroundColor: _subscribed
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).scaffoldBackgroundColor,
            side: _subscribed
                ? BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.6))
                : BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            _subscribed ? 'Subscribed' : 'Subscribe',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class PlayerScreen extends ConsumerStatefulWidget {
  final String videoId;
  final Duration? initialPosition;
  const PlayerScreen(
      {super.key, required this.videoId, this.initialPosition});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

/// Expandable "AI Summary" card below the video/channel info.
///
/// Generates a 2-3 sentence summary via Pollinations AI (free, no key)
/// with Gemini as an optional fallback when the API key is set in
/// Settings. Collapsible; never throws; never breaks the player UI.
class _AiSummaryCard extends ConsumerStatefulWidget {
  final String videoId;
  final String title;
  final String channelName;
  final String description;

  const _AiSummaryCard({
    super.key,
    required this.videoId,
    required this.title,
    required this.channelName,
    required this.description,
  });

  @override
  ConsumerState<_AiSummaryCard> createState() => _AiSummaryCardState();
}

class _AiSummaryCardState extends ConsumerState<_AiSummaryCard> {
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _card => Theme.of(context).colorScheme.surfaceContainer;

  AiSummaryService? _service;
  String? _summary;
  bool _loading = true;
  bool _expanded = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AiSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _summary = null;
    });
    _service?.dispose();
    _service =
        AiSummaryService(geminiApiKey: ref.read(geminiApiKeyProvider));
    try {
      final summary = await _service!.getSummary(
        title: widget.title,
        channelName: widget.channelName,
        description: widget.description,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
        if (summary == null) _error = 'unavailable';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      color: _accent, size: 18),
                  const SizedBox(width: 8),
                  const Text('AI Summary',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Powered by AI',
                        style: TextStyle(
                            color: _accent, fontSize: 10)),
                  ),
                  const Spacer(),
                  Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Colors.white10),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildBody(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < 3; i++)
            Container(
              margin: EdgeInsets.only(
                  bottom: 8, right: i == 2 ? 80 : 0),
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
        ],
      );
    }
    if (_summary != null) {
      return Text(_summary!,
          style: const TextStyle(
              color: Color(0xFFE8F0EC),
              fontSize: 13,
              height: 1.6));
    }
    return Row(
      children: [
        const Expanded(
          child: Text('Summary not available.',
              style:
                  TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        TextButton.icon(
          onPressed: _load,
          icon: Icon(Icons.refresh,
              color: _accent, size: 16),
          label: Text('Retry',
              style: TextStyle(color: _accent)),
        ),
      ],
    );
  }
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  Color get _accent => Theme.of(context).colorScheme.primary;

  /// WILLOW emerald theme for video mode: glowing controls, seekbar,
  /// outlined chips, avatar rings and the autoplay toggle.
  /// Follows the selected theme accent.
  Color get _emerald => Theme.of(context).colorScheme.primary;
  Color get _emeraldLight =>
      Theme.of(context).colorScheme.secondary;

  /// Dark green-black scaffold background for video mode (WILLOW).
  /// Follows the selected theme background.
  Color get _willowBg =>
      Theme.of(context).scaffoldBackgroundColor;

  /// Spotify-style gold/tan accent used by the audio (music) mode.
  /// Follows the selected theme accent so the whole app converts.
  Color get _gold => Theme.of(context).colorScheme.primary;

  VideoController? _videoController;
  bool _showControls = true;
  Timer? _hideTimer;

  // fullscreen (landscape)
  bool _isFullscreen = false;
  bool _screenLocked = false;

  // audio (music) mode state
  bool _liked = false;
  bool _disliked = false;
  bool _shuffle = false;
  int _repeatMode = 0; // 0=off, 1=all, 2=one
  // Artwork swipe direction for the track-change crossfade:
  // -1 = next track (slides in from the right), +1 = previous (from left).
  double _artworkSlideDir = -1;

  // double-tap
  Offset? _doubleTapPos;
  String? _seekFlash;
  bool _seekFlashLeft = true;
  Timer? _seekFlashTimer;

  // stats for nerds overlay
  bool _showStats = false;

  // volume / brightness / scrub overlay
  _Gauge? _gauge;
  Timer? _gaugeTimer;

  // vertical-drag gesture state
  bool _dragOnRightSide = true;
  double? _dragStartVolume; // 0..100
  double? _dragStartBrightness; // 0..1
  double _lastVolume = 50; // restored by mute toggle

  // video fit mode (fullscreen defaults to cover: fills the display)
  BoxFit _videoFit = BoxFit.contain;

  // horizontal scrub state
  Duration? _scrubStartPosition;
  Duration? _scrubPreview;

  // long-press 2x
  double _prevSpeed = 1.0;

  // resume-from-history
  bool _didInitialSeek = false;
  ProviderSubscription<PlayerStatus>? _statusSub;
  ProviderSubscription<VideoDetails?>? _videoSub;
  ProviderSubscription<String?>? _errorMsgSub;

  @override
  void initState() {
    super.initState();
    _videoController = VideoController(ref.read(mediaKitPlayerProvider));
    // Fullscreen player takes over: hide the floating popup window.
    ref.read(popupVisibleProvider.notifier).state = false;
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
    // Surface non-fatal errors (e.g. quality-switch rollback) as a
    // snackbar while playback continues. Fatal errors (status == error)
    // are rendered by the full error screen instead.
    _errorMsgSub = ref.listenManual(
      playerControllerProvider.select((s) => s.errorMessage),
      (prev, next) {
        if (next == null || next == prev || !mounted) return;
        final st = ref.read(playerControllerProvider);
        if (st.status != PlayerStatus.ready) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(playerControllerProvider.notifier).clearError();
      },
    );
    _restartHideTimer();
  }

  @override
  void dispose() {
    _videoSub?.close();
    _statusSub?.close();
    _errorMsgSub?.close();
    // Persist resume position for history (creates entry if needed).
    final uiState = ref.read(playerControllerProvider);
    if (uiState.videoId != null) {
      final v = uiState.video;
      ref.read(historyRepositoryProvider).saveResumePosition(
            videoId: uiState.videoId!,
            positionSecs: ref
                .read(mediaKitPlayerProvider)
                .state
                .position
                .inSeconds,
            title: v?.title ?? '',
            author: v?.author ?? '',
            thumbnailUrl: v?.thumbnailUrl ?? '',
            durationSecs: v?.duration?.inSeconds,
          );
    }
    _hideTimer?.cancel();
    _seekFlashTimer?.cancel();
    _gaugeTimer?.cancel();
    // Restore portrait + system UI if the user left while fullscreen.
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  // ---------------- controls visibility ----------------

  void _restartHideTimer() {
    _hideTimer?.cancel();
    // In fullscreen the exit button must stay reachable: no auto-hide,
    // the user toggles controls manually by tapping the video.
    if (_isFullscreen) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _restartHideTimer();
  }

  // ---------------- fullscreen ----------------

  Future<void> _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
      // Entering fullscreen: make sure the controls (incl. the exit
      // button) are visible, since auto-hide is disabled there.
      // Fullscreen fills the display (cover); normal mode contains.
      if (_isFullscreen) {
        _showControls = true;
        _videoFit = BoxFit.cover;
      } else {
        _videoFit = BoxFit.contain;
      }
    });
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
    }
    // Apply the fullscreen / no-fullscreen quality preference.
    try {
      ref
          .read(playerControllerProvider.notifier)
          .applyFullscreenQuality(_isFullscreen);
    } catch (_) {}
    _restartHideTimer();
  }

  /// Cycle video fit: contain -> cover -> fill -> contain.
  void _cycleVideoFit() {
    setState(() {
      _videoFit = _videoFit == BoxFit.contain
          ? BoxFit.cover
          : _videoFit == BoxFit.cover
              ? BoxFit.fill
              : BoxFit.contain;
    });
    _restartHideTimer();
  }

  // ---------------- prev / next ----------------

  /// Previous: restart the current video when past 3s, otherwise go to
  /// the previously played video (Spotify/YouTube behavior).
  Future<void> _playPrevious() async {
    if (mounted) setState(() => _artworkSlideDir = 1);
    await ref
        .read(playerControllerProvider.notifier)
        .playPrevious();
    _restartHideTimer();
  }

  /// Next: load the first video from the Up Next list in-place
  /// (no route push — preserves fullscreen/rotation state).
  /// If Up Next is empty, fetches it (with a last-resort search
  /// fallback) while showing progress, so Next almost always
  /// finds a video instead of just saying "not found".
  Future<void> _playNext() async {
    if (mounted) setState(() => _artworkSlideDir = -1);
    final notifier = ref.read(playerControllerProvider.notifier);
    final related =
        ref.read(playerControllerProvider).relatedVideos;
    if (related.isNotEmpty) {
      // Load in the same screen: keeps fullscreen, fit mode, controls.
      notifier.loadVideo(related.first.id);
      _restartHideTimer();
      return;
    }
    // Up Next came back empty — fetch it now with progress shown.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Finding next video…'),
        duration: Duration(seconds: 10),
      ),
    );
    final nextId = await notifier.ensureNextVideoId();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (nextId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No next video found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    notifier.loadVideo(nextId);
    _restartHideTimer();
  }

  // ---------------- double-tap: -10s / +10s / play-pause ----------------

  void _onDoubleTap() {
    final pos = _doubleTapPos;
    if (pos == null) return;
    final width = MediaQuery.of(context).size.width;
    final notifier = ref.read(playerControllerProvider.notifier);
    // User-configurable double-tap seek interval (Settings → Double-tap to seek).
    int secs = 10;
    try {
      secs = ref.read(doubleTapSecondsProvider);
    } catch (_) {}
    if (pos.dx < width * 0.35) {
      notifier.seekBy(Duration(seconds: -secs));
      _flashSeek('-${secs}s', left: true);
    } else if (pos.dx > width * 0.65) {
      notifier.seekBy(Duration(seconds: secs));
      _flashSeek('+${secs}s', left: false);
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
      if (v > 0) _lastVolume = v;
      // 0-10% zone shows the mute icon (MX Player style).
      _showGauge(_Gauge(
        icon: v <= 10
            ? Icons.volume_off
            : (v <= 50 ? Icons.volume_down : Icons.volume_up),
        label: v == 0 ? 'Muted' : 'Volume ${v.round()}%',
        value: v / 100,
        kind: _GaugeKind.volume,
      ));
      _hideGaugeSoon();
    } else if (!_dragOnRightSide &&
        _dragStartBrightness != null) {
      final b = (_dragStartBrightness! + delta).clamp(0.05, 1.0);
      try {
        ScreenBrightness().setScreenBrightness(b);
      } catch (_) {}
      _showGauge(_Gauge(
        icon: b <= 0.15 ? Icons.brightness_low : Icons.brightness_6,
        label: 'Brightness ${(b * 100).round()}%',
        value: b,
        kind: _GaugeKind.brightness,
      ));
      _hideGaugeSoon();
    }
  }

  /// Set volume from the gauge's mute / full buttons.
  Future<void> _setVolumeGauge(double v) async {
    v = v.clamp(0.0, 100.0);
    await ref.read(mediaKitPlayerProvider).setVolume(v);
    if (v > 0) _lastVolume = v;
    _showGauge(_Gauge(
      icon: v <= 10
          ? Icons.volume_off
          : (v <= 50 ? Icons.volume_down : Icons.volume_up),
      label: v == 0 ? 'Muted' : 'Volume ${v.round()}%',
      value: v / 100,
      kind: _GaugeKind.volume,
    ));
    _hideGaugeSoon();
  }

  /// Mute toggle: 0 <-> last non-zero volume.
  Future<void> _toggleMute() async {
    final current =
        ref.read(mediaKitPlayerProvider).state.volume;
    if (current > 0) {
      _lastVolume = current;
      await _setVolumeGauge(0);
    } else {
      await _setVolumeGauge(
          _lastVolume > 0 ? _lastVolume : 50);
    }
  }

  /// Set brightness from the gauge's min / max buttons.
  Future<void> _setBrightnessGauge(double b) async {
    b = b.clamp(0.05, 1.0);
    try {
      await ScreenBrightness().setScreenBrightness(b);
    } catch (_) {}
    _showGauge(_Gauge(
      icon: b <= 0.15 ? Icons.brightness_low : Icons.brightness_6,
      label: 'Brightness ${(b * 100).round()}%',
      value: b,
      kind: _GaugeKind.brightness,
    ));
    _hideGaugeSoon();
  }

  // ---------------- horizontal drag: scrub ----------------

  void _onScrubStart(DragStartDetails d) {
    // Ignore scrub gestures that start on the bottom controls (seekbar
    // area). The seekbar has its own Listener-based drag handling; letting
    // the video-area scrub also fire causes a conflict (double-seek,
    // wrong position). Bottom controls are ~120px tall.
    final screenHeight = MediaQuery.of(context).size.height;
    if (d.globalPosition.dy > screenHeight - 140) return;
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

  /// iPhone-style vertical pill indicator for volume/brightness.
  ///
  /// The volume pill is anchored to the RIGHT edge of the screen and the
  /// brightness pill to the LEFT edge (matching the swipe side, not the
  /// center). Tapping the pill's upper / lower half nudges the value up /
  /// down, iPhone-style. The scrub-preview ("info") kind keeps the old
  /// centered box style.
  Widget _buildGauge() {
    final g = _gauge!;
    if (g.kind == _GaugeKind.volume) {
      final v = g.value * 100;
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 28),
          child: _IosPill(
            value: g.value,
            kind: g.kind,
            onIncrease: () => _setVolumeGauge(v + 5),
            onDecrease: () => _setVolumeGauge(v - 5),
          ),
        ),
      );
    }
    if (g.kind == _GaugeKind.brightness) {
      final b = g.value;
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 28),
          child: _IosPill(
            value: g.value,
            kind: g.kind,
            onIncrease: () => _setBrightnessGauge(b + 0.05),
            onDecrease: () => _setBrightnessGauge(b - 0.05),
          ),
        ),
      );
    }
    // Scrub preview keeps the compact box style.
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(g.icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                value: g.value,
                backgroundColor: Colors.white24,
                color: _accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(g.label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _showGauge(_Gauge gauge) {
    _gaugeTimer?.cancel();
    setState(() => _gauge = gauge);
  }

  void _hideGaugeSoon() {
    _gaugeTimer?.cancel();
    _gaugeTimer = Timer(const Duration(milliseconds: 1500), () {
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                    title: Text('Playback speed',
                        style:
                            TextStyle(fontWeight: FontWeight.bold))),
            for (final s in [
              0.25,
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              1.75,
              2.0,
              2.5,
              3.0,
              4.0
            ])
              ListTile(
                title: Text('${s}x'),
                trailing: s == current
                    ? Icon(Icons.check, color: _accent)
                    : null,
                onTap: () {
                  notifier.setSpeed(s);
                  Navigator.pop(ctx);
                },
              ),
          ],
            ),
          ),
        ),
      ),
    );
  }

  /// Premium bottom-sheet quality picker (VLC/Seal style): each row shows
  /// resolution + fps + bitrate + codec with a radio indicator, DASH
  /// streams get an accent badge.
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text('Quality',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Select playback quality',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: qualities.length,
                itemBuilder: (ctx, i) {
                  final q = qualities[i];
                  final selected = current != null &&
                      current.height == q.height &&
                      current.isDash == q.isDash;
                  final detail = q.detailLine;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (mounted) notifier.setQuality(q);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        children: [
                          // Radio indicator.
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? _accent
                                    : Colors.white38,
                                width: 2,
                              ),
                              color: selected
                                  ? _accent
                                  : Colors.transparent,
                            ),
                            child: selected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 14)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(q.resolutionLabel,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight:
                                                  FontWeight.w600)),
                                    ),
                                    if (q.isDash) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                                horizontal: 8,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _accent.withValues(
                                              alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(
                                                  4),
                                        ),
                                        child: Text('DASH',
                                            style: TextStyle(
                                                color: _accent,
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                                if (detail.isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 2),
                                    child: Text(detail,
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showSleepSheet() {
    SleepTimerSheet.show(context);
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: SingleChildScrollView(
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
                SwitchListTile(
                  secondary: const Icon(Icons.analytics_outlined),
                  title: const Text('Stats for nerds'),
                  subtitle: const Text(
                      'Show playback debug overlay'),
                  value: _showStats,
                  activeColor: _accent,
                  onChanged: (v) {
                    Navigator.pop(ctx);
                    setState(() => _showStats = v);
                  },
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
                  leading: const Icon(
                      Icons.picture_in_picture_outlined),
                  title: const Text('Popup player'),
                  subtitle: const Text(
                      'Floating window over the app'),
                  onTap: () {
                    Navigator.pop(ctx); // close the sheet
                    Navigator.pop(
                        context); // leave fullscreen player
                    ref
                        .read(popupVisibleProvider.notifier)
                        .state = true;
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bedtime),
                  title: const Text('Sleep timer'),
                  subtitle: Text(ui.sleepRemaining != null
                      ? 'Ends in ${formatDuration(ui.sleepRemaining)}'
                      : 'Stop playback after a while'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSleepSheet();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('Playback speed'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${ui.speed}x',
                          style:
                              const TextStyle(color: Colors.grey)),
                      const Icon(Icons.chevron_right,
                          color: Colors.grey),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSpeedSheet();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.closed_caption),
                  title: const Text('Captions'),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.grey),
                  onTap: () {
                    Navigator.pop(ctx);
                    SubtitleSheet.show(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Lock screen'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _screenLocked = true);
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
              ),
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
    final allOptions = options;
    final fetchError = error;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        if (fetchError != null || allOptions == null) {
          return SafeArea(
            child: ListTile(
              leading: const Icon(Icons.error_outline,
                  color: Colors.red),
              title:
                  const Text('Could not list qualities.'),
              subtitle: Text(fetchError ?? '',
                  style:
                      const TextStyle(color: Colors.grey)),
            ),
          );
        }
        final videoOpts =
            allOptions.where((o) => !o.audioOnly).toList();
        final audioOpts =
            allOptions.where((o) => o.audioOnly).toList();
        // Default: best muxed video (has audio), else best video-only;
        // best audio track.
        DownloadOption? selVideo = videoOpts.isEmpty
            ? null
            : videoOpts.firstWhere(
                (o) => o.isMuxed,
                orElse: () => videoOpts.first,
              );
        DownloadOption? selAudio =
            audioOpts.isEmpty ? null : audioOpts.first;
        String size(int? b) => b == null
            ? 'Size unknown'
            : b >= (1 << 30)
                ? '${(b / (1 << 30)).toStringAsFixed(1)} GB'
                : '${(b / (1 << 20)).toStringAsFixed(1)} MB';

        /// Premium Seal-style radio row.
        Widget optionRow({
          required IconData icon,
          required String title,
          required String subtitle,
          required String? badge,
          required String sizeText,
          required bool selected,
          required VoidCallback onTap,
        }) {
          return InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white54, size: 26),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500)),
                            ),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                                child: Text(badge,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(sizeText,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 14)),
                  const SizedBox(width: 12),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            selected ? _gold : Colors.white38,
                        width: 2,
                      ),
                      color: selected
                          ? _gold
                          : Colors.transparent,
                    ),
                    child: selected
                        ? const Icon(Icons.check,
                            color: Colors.black, size: 16)
                        : null,
                  ),
                ],
              ),
            ),
          );
        }

        Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(
                  top: 12, bottom: 4, left: 4),
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            );

        return StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text('Download',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13)),
                  sectionLabel('Video'),
                  optionRow(
                    icon: Icons.ondemand_video,
                    title: 'No video',
                    subtitle: 'Audio only',
                    badge: null,
                    sizeText: '',
                    selected: selVideo == null,
                    onTap: () =>
                        setSheetState(() => selVideo = null),
                  ),
                  for (final o in videoOpts)
                    optionRow(
                      icon: Icons.play_circle_outline,
                      title: o.tierTitle,
                      subtitle: o.tierDescription,
                      badge: o.tierBadge,
                      sizeText: size(o.sizeBytes),
                      selected: selVideo == o,
                      onTap: () =>
                          setSheetState(() => selVideo = o),
                    ),
                  sectionLabel('Audio'),
                  optionRow(
                    icon: Icons.music_note,
                    title: 'No audio',
                    subtitle: 'Video only',
                    badge: null,
                    sizeText: '',
                    selected: selAudio == null,
                    onTap: () =>
                        setSheetState(() => selAudio = null),
                  ),
                  for (final o in audioOpts)
                    optionRow(
                      icon: Icons.music_note_outlined,
                      title: o.tierTitle,
                      subtitle: o.tierDescription,
                      badge: o.tierBadge,
                      sizeText: size(o.sizeBytes),
                      selected: selAudio == o,
                      onTap: () =>
                          setSheetState(() => selAudio = o),
                    ),
                  if (selVideo != null && selVideo!.videoOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        selAudio == null
                            ? 'Video-only has no audio track.'
                            : 'Audio track downloads too — attached automatically at playback.',
                        style: TextStyle(
                            color: selAudio == null
                                ? Colors.orange
                                : Colors.grey,
                            fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                    onPressed:
                        (selVideo == null && selAudio == null)
                            ? null
                            : () {
                                final v = selVideo;
                                final a = selAudio;
                                Navigator.pop(ctx);
                                if (v != null && v.isMuxed) {
                                  // Muxed already contains audio.
                                  notifier.startDownload(v, video);
                                  _showDownloadStartedSnack(
                                      'Download started (${v.label})');
                                } else if (v != null && v.videoOnly) {
                                  // DASH video-only: also fetch the chosen
                                  // audio track so the video plays WITH
                                  // audio (attached at playback, no
                                  // FFmpeg merge needed).
                                  notifier.startDownload(v, video,
                                      audioOption: a);
                                  _showDownloadStartedSnack(
                                      a == null
                                          ? 'Video-only download started (${v.label})'
                                          : 'Download started (${v.label} + audio)');
                                } else if (v != null) {
                                  notifier.startDownload(v, video);
                                  _showDownloadStartedSnack(
                                      'Video-only download started (${v.label})');
                                } else if (a != null) {
                                  notifier.startDownload(a, video);
                                  _showDownloadStartedSnack(
                                      'Audio download started (${a.label})');
                                }
                              },
                    icon: const Icon(Icons.download),
                    label: const Text('Download',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                  const Divider(height: 24),
                  ListTile(
                    leading: const Icon(
                        Icons.download_done,
                        color: Colors.white70),
                    title: const Text('View downloads'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const DownloadsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDownloadStartedSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'View',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DownloadsScreen(),
            ),
          );
        },
      ),
    ));
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

    // Fullscreen: video fills the whole landscape screen with the same
    // clean controls; tap still toggles their visibility. The system back
    // button/gesture exits fullscreen instead of closing the player, so
    // the user always has a way out.
    if (_isFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleFullscreen();
        },
        child: Scaffold(
          backgroundColor: _willowBg,
          body: _buildVideoArea(uiState, player, fillScreen: true),
        ),
      );
    }

    // Audio (music) mode: Spotify-style player with the gold theme.
    // Playback is owned by PureTubeAudioHandler (audio_service), so it
    // keeps playing in the background even if this screen is popped.
    if (uiState.audioOnly && uiState.video != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
            child:
                _buildAudioMode(uiState, player, notifier)),
      );
    }

    return Scaffold(
      backgroundColor: _willowBg,
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

  // ---------------- Audio (music) mode ----------------
  //
  // Spotify-style player shown when audio-only is on. Playback is owned by
  // PureTubeAudioHandler (audio_service foreground service), so it keeps
  // playing even if the user pops this screen or turns the display off.

  Widget _buildAudioMode(
      PlayerUiState uiState, Player player, PlayerController notifier) {
    final video = uiState.video!;
    return Stack(
      children: [
        // Blurred album-art backdrop — Spotify premium look.
        // Crossfades when the track changes.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: CachedNetworkImage(
              key: ValueKey('bg-${video.id}'),
              imageUrl: video.thumbnailUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Container(color: const Color(0xFF0A0A0F)),
            ),
          ),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.60),
                    Colors.black.withOpacity(0.88),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Foreground content.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SONORA-style header: chevron | centered brand column | menu.
            // The video-mode toggle lives in the more sheet ("Audio only").
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.center,
                children: [
                  PressIconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white, size: 32),
                    // Audio keeps playing in the background.
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.graphic_eq,
                            color: _gold, size: 18),
                        const SizedBox(height: 4),
                        const Text('PURE TUBE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                letterSpacing: 6,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        const Text('PLAYING FROM',
                            style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                letterSpacing: 1.6)),
                        const SizedBox(height: 2),
                        const Text('Queue',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ],
                    ),
                  ),
                  _buildModeToggle(uiState),
                  PressIconButton(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white),
                    onPressed: _showMoreSheet,
                  ),
                ],
              ),
            ),
            // Sleep timer countdown badge — visible only while a timer is
            // active. Tapping opens the sleep timer sheet.
            if (uiState.sleepRemaining != null)
              Center(
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 6, bottom: 2),
                  child: PressScale(
                    onTap: _showSleepSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(20),
                        color:
                            _gold.withValues(alpha: 0.12),
                        border: Border.all(
                          color:
                              _gold.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined,
                              color: _gold, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '${formatDuration(uiState.sleepRemaining)} left',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // SONORA: large album art, 24px rounded corners, strong shadow.
            // Swipe left/right on the artwork to change tracks
            // (YouTube Music style) — only the artwork/title crossfade,
            // the controls stay visible and responsive.
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(40, 18, 40, 0),
              child: AspectRatio(
                aspectRatio: 1,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v < -250) {
                      HapticFeedback.lightImpact();
                      _playNext(); // swipe left → next track
                    } else if (v > 250) {
                      HapticFeedback.lightImpact();
                      _playPrevious(); // swipe right → previous track
                    }
                  },
                  child: Stack(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) {
                          final curved = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          );
                          return FadeTransition(
                            opacity: curved,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: Offset(
                                    0.28 * _artworkSlideDir, 0),
                                end: Offset.zero,
                              ).animate(curved),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          key: ValueKey(video.id),
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withOpacity(0.65),
                                blurRadius: 48,
                                spreadRadius: 4,
                                offset: const Offset(0, 18),
                              ),
                              BoxShadow(
                                color: _gold.withOpacity(0.12),
                                blurRadius: 60,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(24),
                            child: CachedNetworkImage(
                              imageUrl: video.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  Container(
                                color:
                                    const Color(0xFF1A1A1A),
                                child: const Icon(
                                    Icons.music_note,
                                    size: 80,
                                    color: Colors.white24),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Small loading indicator on the artwork while the
                      // next track loads — no full-screen spinner.
                      if (uiState.status ==
                          PlayerStatus.loading)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius:
                                  BorderRadius.circular(24),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 34,
                                height: 34,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Title (28px w600, centered) + artist (grey).
            // Crossfades on track change — no jarring swap.
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(36, 20, 36, 0),
              child: Center(
                child: AnimatedSwitcher(
                  duration:
                      const Duration(milliseconds: 300),
                  child: _MarqueeText(
                    key: ValueKey('title-${video.id}'),
                    text: video.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 28,
                        letterSpacing: 0.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(video.author,
                  key: ValueKey('artist-${video.id}'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 15)),
            ),
            // SONORA: heart + download as circular outline buttons.
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _outlineCircleButton(
                    tooltip: 'Download',
                    icon: Icons.download_outlined,
                    iconColor: _gold,
                    onPressed: () => _showDownloadSheet(video),
                  ),
                  const SizedBox(width: 24),
                  _outlineCircleButton(
                    tooltip: _liked ? 'Liked' : 'Like',
                    icon: _liked
                        ? Icons.favorite
                        : Icons.favorite_border,
                    iconColor:
                        _liked ? _gold : Colors.white70,
                    filled: _liked,
                    onPressed: () {
                      setState(() => _liked = !_liked);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(
                        content: Text(_liked
                            ? 'Added to Liked'
                            : 'Removed from Liked'),
                        duration: const Duration(seconds: 1),
                      ));
                    },
                  ),
                ],
              ),
            ),
            // Seekbar + times.
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _AudioSeekBar(player: player),
            ),
            // Controls: shuffle | prev | WHITE 72 play | next | repeat
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                children: [
                  PressIconButton(
                    tooltip: 'Shuffle',
                    icon: Icon(Icons.shuffle,
                        color: _shuffle
                            ? _gold
                            : Colors.white70),
                    onPressed: () {
                      setState(() => _shuffle = !_shuffle);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(
                        content: Text(_shuffle
                            ? 'Shuffle on'
                            : 'Shuffle off'),
                        duration: const Duration(seconds: 1),
                      ));
                    },
                  ),
                  PressIconButton(
                    tooltip: 'Previous',
                    iconSize: 44,
                    icon: const Icon(Icons.skip_previous,
                        color: Colors.white),
                    onPressed: _playPrevious,
                  ),
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (context, snap) {
                      final playing = snap.data ?? false;
                      return PressScale(
                        onTap: notifier.togglePlayPause,
                        child: Semantics(
                          button: true,
                          label: playing ? 'Pause' : 'Play',
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white
                                  .withValues(alpha: 0.06),
                              border: Border.all(
                                color: _gold.withValues(
                                    alpha: 0.85),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _gold.withValues(
                                      alpha: 0.35),
                                  blurRadius: 32,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(
                                  milliseconds: 200),
                              child: Icon(
                                playing
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                key: ValueKey<bool>(playing),
                                color: _gold,
                                size: 44,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  PressIconButton(
                    tooltip: 'Next',
                    iconSize: 44,
                    icon: const Icon(Icons.skip_next,
                        color: Colors.white),
                    onPressed: _playNext,
                  ),
                  PressIconButton(
                    tooltip: 'Repeat',
                    icon: Icon(
                        _repeatMode == 2
                            ? Icons.repeat_one
                            : Icons.repeat,
                        color: _repeatMode == 0
                            ? Colors.white70
                            : _gold),
                    onPressed: _cycleRepeatMode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // AI Lyrics card (audio mode): expandable lyrics below the
            // controls, scrollable so long lyrics never overflow.
            // Auto-fetched by the controller when the track loads.
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: AiLyricsCard(),
              ),
            ),
            // Bottom tabs: QUEUE | LYRICS | TIMER
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                children: [
                  _audioTab(
                      Icons.queue_music, 'QUEUE', _showQueueSheet),
                  _audioTab(Icons.lyrics_outlined, 'LYRICS', () {
                    final video =
                        ref.read(playerControllerProvider).video;
                    if (video == null) return;
                    LyricsSheet.show(
                      context,
                      videoTitle: video.title,
                      channelName: video.author,
                      thumbnailUrl: video.thumbnailUrl,
                    );
                  }),
                  _sleepTimerAudioTab(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// SONORA: circular outline button (transparent bg, 1px gold/white
  /// border) used for the audio-mode like/download row.
  Widget _outlineCircleButton({
    required String tooltip,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    return PressScale(
      onTap: onPressed,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? _gold.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border.all(
              color: _gold.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
      ),
    );
  }

  /// SONORA: QUEUE / LYRICS / TIMER as pill outline buttons with
  /// gold-tinted borders.
  Widget _audioTab(
      IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: _gold.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _gold, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color:
                        Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  /// TIMER pill that shows the live sleep-timer countdown (e.g. "44:47")
  /// when a timer is set, and "TIMER" otherwise. Tapping still opens the
  /// sleep-timer sheet. The countdown uses the active theme color.
  Widget _sleepTimerAudioTab() {
    return InkWell(
      onTap: _showSleepSheet,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: _gold.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, color: _gold, size: 20),
            const SizedBox(width: 8),
            Consumer(
              builder: (context, ref, _) {
                final remaining = ref.watch(
                  playerControllerProvider
                      .select((s) => s.sleepRemaining),
                );
                if (remaining == null) {
                  return Text('TIMER',
                      style: TextStyle(
                          color:
                              Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w600));
                }
                return Text(
                  _formatSleepRemaining(remaining),
                  style: TextStyle(
                      color: _emerald,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Formats a sleep-timer countdown as m:ss (or h:mm:ss past an hour).
  String _formatSleepRemaining(Duration d) {
    final total = d.inSeconds.clamp(0, 99 * 3600 + 59 * 60 + 59);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _cycleRepeatMode() {
    final player = ref.read(mediaKitPlayerProvider);
    setState(() => _repeatMode = (_repeatMode + 1) % 3);
    // Real behavior via media_kit playlist modes.
    player.setPlaylistMode(_repeatMode == 2
        ? PlaylistMode.single
        : _repeatMode == 1
            ? PlaylistMode.loop
            : PlaylistMode.none);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_repeatMode == 2
          ? 'Repeat one'
          : _repeatMode == 1
              ? 'Repeat all'
              : 'Repeat off'),
      duration: const Duration(seconds: 1),
    ));
  }

  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer(
              builder: (context, ref, _) {
                final autoplay = ref.watch(
                    playerControllerProvider
                        .select((s) => s.autoplay));
                return ListTile(
                  title: const Text('Queue',
                      style: TextStyle(
                          fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Autoplay',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13)),
                      const SizedBox(width: 6),
                      Switch(
                        value: autoplay,
                        activeThumbColor: Colors.white,
                        activeTrackColor: _accent,
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.white24,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) => ref
                            .read(playerControllerProvider
                                .notifier)
                            .setAutoplay(v),
                      ),
                    ],
                  ),
                );
              },
            ),
            Flexible(
              child: Consumer(
                builder: (context, ref, _) {
                  final videos = ref
                      .watch(playerControllerProvider)
                      .relatedVideos;
                  if (videos.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Queue is empty',
                          style:
                              TextStyle(color: Colors.grey)),
                    );
                  }
                  return ReorderableListView.builder(
                    shrinkWrap: true,
                    itemCount: videos.length,
                    onReorderItem: (oldIndex, newIndex) {
                      ref
                          .read(playerControllerProvider
                              .notifier)
                          .reorderQueue(oldIndex, newIndex);
                    },
                    itemBuilder: (c, i) {
                      final v = videos[i];
                      return ListTile(
                        key: ValueKey(v.id),
                        leading: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: v.thumbnailUrl,
                            width: 72,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(v.title,
                            maxLines: 2,
                            overflow:
                                TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13)),
                        subtitle: Text(v.author,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11)),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: Icon(
                            Icons.drag_handle,
                            color: _accent.withValues(
                                alpha: 0.8),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.of(context)
                              .pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                  videoId: v.id),
                            ),
                          );
                        },
                      );
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

  Widget _buildVideoArea(PlayerUiState uiState, Player player,
      {bool fillScreen = false}) {
    final isReady = uiState.status == PlayerStatus.ready;
    final content = Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (uiState.audioOnly && uiState.video != null)
              _buildAudioArt(uiState)
            else if (_videoController != null)
              Video(
                  controller: _videoController!,
                  controls: NoVideoControls,
                  fit: _videoFit),
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
              Center(
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
            if (_gauge != null) _buildGauge(),
            if (_screenLocked)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _screenLocked = false),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: _emerald, width: 1),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock,
                                  color: Colors.white, size: 32),
                              SizedBox(height: 8),
                              Text('Screen locked',
                                  style: TextStyle(
                                      color: Colors.white)),
                              SizedBox(height: 4),
                              Text('Tap to unlock',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showStats && isReady)
              Positioned(
                top: 8,
                left: 8,
                child: IgnorePointer(
                  child: _StatsOverlay(
                    uiState: uiState,
                    player: player,
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
              Center(child: _buildCenterControls()),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomControls(player, uiState),
              ),
            ],
          ],
        ),
    );
    // Fullscreen (landscape): the video fills the whole screen; the same
    // clean controls render on top and tap still toggles them.
    if (fillScreen) return SizedBox.expand(child: content);
    return AspectRatio(aspectRatio: 16 / 9, child: content);
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
                  backgroundColor: _accent,
                  foregroundColor: Colors.black),
              onPressed: notifier.retry,
              icon: const Icon(Icons.refresh,
                  color: Colors.black),
              label: const Text('Retry',
                  style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold)),
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
          PressIconButton(
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
            PressScale(
              onTap: _showSleepSheet,
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _accent.withValues(alpha: 0.14),
                  border: Border.all(
                    color: _accent.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined,
                        color: _accent, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      formatDuration(uiState.sleepRemaining),
                      style: TextStyle(
                          color: _accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          PressIconButton(
            tooltip: 'Subtitles',
            onPressed: () => SubtitleSheet.show(context),
            icon: Icon(Icons.closed_caption_outlined,
                color: uiState.activeSubtitle != null
                    ? _accent
                    : Colors.white),
          ),
          Builder(
            builder: (btnCtx) => PressScale(
              onTap: () => _showQualityMenu(btnCtx),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8),
                child: Text(qualityLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
          ),
          PressScale(
            onTap: _showSpeedSheet,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${uiState.speed}x',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ),
          _buildModeToggle(uiState),
          PressIconButton(
            onPressed: _showMoreSheet,
            icon:
                const Icon(Icons.more_vert, color: Colors.white),
          ),
          // Fullscreen only: cycle video fit (contain/cover/fill).
          if (_isFullscreen)
            PressIconButton(
              tooltip: 'Video fit: ${_videoFit.name}',
              onPressed: _cycleVideoFit,
              icon: const Icon(Icons.aspect_ratio,
                  color: Colors.white),
            ),
        ],
      ),
    );
  }

  /// Switch-style audio/video mode toggle (like the Autoplay switch):
  /// a track with headphone | video icons and a sliding emerald thumb
  /// that animates to the active side. Tap anywhere to flip modes.
  Widget _buildModeToggle(PlayerUiState uiState) {
    final notifier = ref.read(playerControllerProvider.notifier);
    final audioOnly = uiState.audioOnly;
    return Tooltip(
      message: audioOnly ? 'Switch to video mode' : 'Switch to audio mode',
      child: GestureDetector(
        onTap: () => notifier.setAudioOnly(!audioOnly),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 74,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withOpacity(0.12), width: 1),
          ),
          child: Stack(
            children: [
              // Static icons on the track.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.headphones,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.45)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.play_arrow,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.45)),
                  ),
                ],
              ),
              // Sliding thumb with the active icon.
              AnimatedAlign(
                alignment: audioOnly
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _emerald,
                    boxShadow: [
                      BoxShadow(
                        color: _emerald.withValues(alpha: 0.45),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Icon(
                    audioOnly ? Icons.headphones : Icons.play_arrow,
                    size: 16,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// YouTube-style centered transport controls:
  /// previous | play/pause | next.
  Widget _buildCenterControls() {
    final notifier = ref.read(playerControllerProvider.notifier);
    final player = ref.read(mediaKitPlayerProvider);
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PressIconButton(
              tooltip: 'Previous',
              iconSize: 48,
              onPressed: _playPrevious,
              icon: const Icon(Icons.skip_previous,
                  color: Colors.white),
            ),
            const SizedBox(width: 24),
            // WILLOW-style glowing emerald transport button.
            PressScale(
              onTap: notifier.togglePlayPause,
              child: Semantics(
                button: true,
                label: playing ? 'Pause' : 'Play',
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _emerald.withValues(alpha: 0.92),
                    border: Border.all(
                      color:
                          _emeraldLight.withValues(alpha: 0.55),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            _emerald.withValues(alpha: 0.40),
                        blurRadius: 24,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            PressIconButton(
              tooltip: 'Next',
              iconSize: 48,
              onPressed: _playNext,
              icon: const Icon(Icons.skip_next,
                  color: Colors.white),
            ),
          ],
        );
      },
    );
  }

  /// Bottom controls: one compact row —
  /// current time | seekbar | total time | fullscreen.
  Widget _buildBottomControls(
      Player player, PlayerUiState uiState) {
    // Absorb taps on the control bar: without this, a tap on the seekbar
    // also reaches the video-area GestureDetector behind it, whose onTap
    // toggles (hides) the controls — hiding the bar mid-gesture and
    // disposing the seekbar State. The empty onTap wins the arena over the
    // behind detector; inner buttons still win over this wrapper.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 0, 6),
          child: Row(
            children: [
              _TimeLabel(
                  player: player,
                  current: true,
                  color: _emeraldLight),
              Expanded(
                  child: _PlayerSeekBar(
                      player: player,
                      activeColor: _emerald)),
              _TimeLabel(
                  player: player,
                  current: false,
                  color: _emeraldLight),
              PressIconButton(
                tooltip: _isFullscreen
                    ? 'Exit fullscreen'
                    : 'Fullscreen',
                onPressed: _toggleFullscreen,
                icon: Icon(
                  _isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
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
          InkWell(
            onTap: () => _DescriptionSheet.show(context, video),
            borderRadius: BorderRadius.circular(4),
            child: Text(video.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
          ),
          // WILLOW-style subtitle: quality • duration in emerald-grey.
          if (uiState.currentQuality?.label != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${uiState.currentQuality!.label} • ${_clock(video.duration ?? Duration.zero)}',
                style: TextStyle(
                    color:
                        _emeraldLight.withValues(alpha: 0.7),
                    fontSize: 13),
              ),
            ),
          const SizedBox(height: 10),
          // YouTube original: channel row directly below the title.
          _ChannelRow(video: video),
          const SizedBox(height: 12),
          _buildActionRow(uiState, notifier),
          const SizedBox(height: 12),
          if (video.description.isNotEmpty) ...[
            InkWell(
              onTap: () => _DescriptionSheet.show(context, video),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _emerald.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text('Description',
                        style: TextStyle(
                            color: _emeraldLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      '${formatCount(video.viewCount)} views • ${timeAgo(video.uploadDate)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    const Text('...more',
                        style: TextStyle(
                            color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
          if (video.id.isNotEmpty)
            const _UpNextSection(),
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
  /// YouTube-style action chips below the channel row:
  /// Like|Dislike segmented pill, Share, Download, Save (Add To),
  /// Background (audio mode), Popup (PiP). Horizontal scroll.
  Widget _buildActionRow(
      PlayerUiState uiState, PlayerController notifier) {
    final video = uiState.video;

    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
    }) {
      // WILLOW: transparent pill with a 1px emerald outline.
      final color = active ? _emerald : Colors.white;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? _emerald.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? _emerald
                  : _emerald.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(color: color, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    void toggleLike() {
      setState(() {
        _liked = !_liked;
        if (_liked) _disliked = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _liked ? 'Added to Liked' : 'Removed from Liked'),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    void toggleDislike() {
      setState(() {
        _disliked = !_disliked;
        if (_disliked) _liked = false;
      });
    }

    final likeLabel = video?.likeCount != null
        ? formatCount(video!.likeCount)
        : 'Like';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Like | Dislike segmented pill, like YouTube —
          // WILLOW: emerald outline style with a tinted divider.
          Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _emerald.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: toggleLike,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _liked
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          color:
                              _liked ? _emerald : Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(likeLabel,
                            style: TextStyle(
                                color: _liked
                                    ? _emerald
                                    : Colors.white,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                Container(
                    width: 1,
                    height: 20,
                    color:
                        _emerald.withValues(alpha: 0.4)),
                InkWell(
                  onTap: toggleDislike,
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Icon(
                      _disliked
                          ? Icons.thumb_down
                          : Icons.thumb_down_outlined,
                      color:
                          _disliked ? _emerald : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          chip(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: () {
              if (video != null) {
                Share.share(
                    'https://www.youtube.com/watch?v=${video.id}');
              }
            },
          ),
          const SizedBox(width: 8),
          chip(
            icon: Icons.download_outlined,
            label: 'Download',
            onTap: () {
              if (video != null) _showDownloadSheet(video);
            },
          ),
          const SizedBox(width: 8),
          chip(
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
        ],
      ),
    );
  }
}

/// "Up Next" suggestions below the player. Reads the already-loaded
/// related videos from the player controller (same list the Next button
/// plays from) — no extra fetch. Shimmer while loading, retry on error.
/// The Autoplay toggle is wired to the player controller: when ON, a
/// completed video automatically starts the next Up Next item.
class _UpNextSection extends ConsumerStatefulWidget {
  const _UpNextSection();

  @override
  ConsumerState<_UpNextSection> createState() =>
      _UpNextSectionState();
}

class _UpNextSectionState
    extends ConsumerState<_UpNextSection> {
  Color get _emerald => Theme.of(context).colorScheme.primary;

  /// Header row: "Up Next" + Autoplay label with an emerald switch.
  Widget _header() {
    final autoplay = ref.watch(
        playerControllerProvider.select((s) => s.autoplay));
    return Row(
      children: [
        const Expanded(
          child: Text('Up Next',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white)),
        ),
        const Text('Autoplay',
            style: TextStyle(
                color: Colors.white70, fontSize: 13)),
        const SizedBox(width: 6),
        Switch(
          value: autoplay,
          activeThumbColor: Colors.white,
          activeTrackColor: _emerald,
          inactiveThumbColor: Colors.grey,
          inactiveTrackColor: Colors.white24,
          materialTapTargetSize:
              MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) => ref
              .read(playerControllerProvider.notifier)
              .setAutoplay(v),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(playerControllerProvider);
    final videos = uiState.relatedVideos;
    if (videos.isEmpty && !uiState.relatedFailed) {
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
              padding: const EdgeInsets.only(bottom: 10),
              child: Shimmer.fromColors(
                baseColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainer,
                highlightColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                child: Row(
                  children: [
                    Container(
                      width: 120,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
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
    if (videos.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _header()),
              PressScale(
                onTap: () => ref
                    .read(playerControllerProvider.notifier)
                    .retryRelated(),
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Retry',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 8),
        for (final v in videos)
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(videoId: v.id),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: v.thumbnailUrl,
                      width: 120,
                      height: 68,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 120,
                        height: 68,
                        color: const Color(0xFF1A1A1A),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 120,
                        height: 68,
                        color: const Color(0xFF1A1A1A),
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey, size: 20),
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
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(
                          '${v.author}'
                          '${v.viewCount != null ? ' • ${formatCount(v.viewCount)} views' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
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
  }
}

/// YouTube-style description bottom sheet: opened by tapping the video
/// title or the collapsed description box. Dark theme (#0F0F0F / #212121).
class _DescriptionSheet extends ConsumerStatefulWidget {
  final VideoDetails video;
  const _DescriptionSheet({required this.video});

  static void show(BuildContext context, VideoDetails video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DescriptionSheet(video: video),
    );
  }

  @override
  ConsumerState<_DescriptionSheet> createState() =>
      _DescriptionSheetState();
}

class _DescriptionSheetState
    extends ConsumerState<_DescriptionSheet> {
  bool _descExpanded = false;
  ChannelInfo? _channel;
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _subscribed = ref
        .read(subscriptionRepositoryProvider)
        .isSubscribed(widget.video.channelId);
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    final id = widget.video.channelId;
    if (id.isEmpty) return;
    try {
      final ch =
          await ref.read(extractorProvider).getChannel(id);
      if (!mounted) return;
      setState(() {
        _channel = ch;
        _subscribed = ref
            .read(subscriptionRepositoryProvider)
            .isSubscribed(id);
      });
    } catch (_) {}
  }

  Future<void> _toggleSubscribe() async {
    final repo = ref.read(subscriptionRepositoryProvider);
    final id = widget.video.channelId;
    try {
      if (_subscribed) {
        await repo.unsubscribe(id);
      } else {
        await repo.subscribe(
          channelId: id,
          name: _channel?.title ?? widget.video.author,
          subscriberCount: _channel?.subscriberCount,
        );
      }
      if (mounted) setState(() => _subscribed = !_subscribed);
    } catch (_) {}
  }

  String _fullDate(DateTime? dt) {
    if (dt == null) return '–';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _statCard(IconData icon, String value) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF212121),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Description',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                  PressIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close,
                        color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(video.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statCard(
                      Icons.thumb_up,
                      video.likeCount != null
                          ? formatCount(video.likeCount)
                          : '–'),
                  const SizedBox(width: 8),
                  _statCard(Icons.remove_red_eye,
                      formatCount(video.viewCount)),
                  const SizedBox(width: 8),
                  _statCard(Icons.calendar_today,
                      _fullDate(video.uploadDate)),
                ],
              ),
              const SizedBox(height: 12),
              if (video.description.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF212121),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.description,
                        maxLines: _descExpanded ? null : 4,
                        overflow: _descExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(
                            () => _descExpanded = !_descExpanded),
                        child: Text(
                          _descExpanded
                              ? 'Show less'
                              : 'See more',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              const Text('Transcript',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Follow along using the transcript.',
                  style:
                      TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Transcript not available'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                      color: Color(0xFF3F3F3F)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Show transcript',
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        const Color(0xFF3F3F3F),
                    backgroundImage: _channel?.logoUrl != null
                        ? CachedNetworkImageProvider(
                            _channel!.logoUrl)
                        : null,
                    child: _channel?.logoUrl == null
                        ? Text(
                            video.author.isNotEmpty
                                ? video.author[0]
                                    .toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          _channel?.title ?? video.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _channel?.subscriberCount != null
                              ? '${formatCount(_channel!.subscriberCount)} subscribers'
                              : 'Channel',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _toggleSubscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _subscribed
                          ? const Color(0xFF3F3F3F)
                          : Colors.white,
                      foregroundColor: _subscribed
                          ? Colors.white
                          : Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(_subscribed
                        ? 'Subscribed'
                        : 'Subscribe'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AiSummaryCard(
                videoId: video.id,
                title: video.title,
                channelName: video.author,
                description: video.description,
              ),
              const SizedBox(height: 16),
              // AI Lyrics (video mode): auto-generated when the video
              // loads; shares the controller's lyrics cache with audio
              // mode.
              const AiLyricsCard(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (video.channelId.isNotEmpty) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChannelScreen(
                                  channelId:
                                      video.channelId),
                            ),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFF3F3F3F)),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('Videos',
                          style:
                              TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final name =
                            _channel?.title ?? video.author;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          SnackBar(
                            content: Text('About: $name'),
                            duration:
                                const Duration(seconds: 2),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFF3F3F3F)),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('About',
                          style:
                              TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}


/// Combined "0:02 / 45:56" time label, bottom-left of the video.
/// Clock-style mm:ss (or h:mm:ss) used by the bottom time labels.
String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Bottom-row time label: current position on the left, total on the right.
class _TimeLabel extends StatelessWidget {
  final Player player;
  final bool current;

  /// Tint for the label; defaults to white (video fullscreen overlays).
  final Color color;
  const _TimeLabel(
      {required this.player, required this.current, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    // initialData from the synchronous player state: media_kit's streams
    // are broadcast without replay, so a fresh subscription (e.g. after
    // the fullscreen rebuild) would otherwise show 00:00 until the next
    // mpv event.
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            return Text(
              _clock(current ? position : duration),
              style: TextStyle(color: color, fontSize: 13),
            );
          },
        );
      },
    );
  }
}

/// Custom seek bar: buffered track + played track + knob, tap & drag to seek.
class _PlayerSeekBar extends ConsumerStatefulWidget {
  final Player player;

  /// Color of the played track and knob. Defaults to amber.
  final Color activeColor;
  const _PlayerSeekBar(
      {required this.player, this.activeColor = Colors.amber});

  @override
  ConsumerState<_PlayerSeekBar> createState() =>
      _PlayerSeekBarState();
}

class _PlayerSeekBarState extends ConsumerState<_PlayerSeekBar> {
  bool _dragging = false;
  double _dragFrac = 0;
  final _barKey = GlobalKey();

  double _fracFromGlobal(Offset globalPos) {
    final box =
        _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final local = box.globalToLocal(globalPos);
    final width = box.size.width;
    if (width <= 0) return 0;
    // Account for the 12dp horizontal padding.
    return ((local.dx - 12) / (width - 24)).clamp(0.0, 1.0);
  }

  /// Total duration, preferring the synchronous player state over the
  /// stream snapshot (which can lag or still hold zero during rebuilds).
  Duration _totalDuration(Duration streamDuration) {
    final stateDuration = widget.player.state.duration;
    if (stateDuration > Duration.zero) return stateDuration;
    return streamDuration;
  }

  Future<void> _seekToFrac(double frac, Duration streamDuration) async {
    final total = _totalDuration(streamDuration);
    if (total <= Duration.zero) return;
    var target = Duration(
        milliseconds: (frac.clamp(0.0, 1.0) * total.inMilliseconds).round());
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    // Route through the controller so seeking shares the same path as
    // scrub gestures, double-tap ±10s, and notification seeks.
    await ref
        .read(playerControllerProvider.notifier)
        .seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    // initialData from the synchronous player state: media_kit's streams
    // are broadcast without replay, so a fresh subscription (e.g. after
    // the fullscreen rebuild, which recreates this whole subtree) would
    // otherwise show an empty track and 00:00 until mpv emits again.
    return StreamBuilder<Duration>(
      stream: widget.player.stream.duration,
      initialData: widget.player.state.duration,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: widget.player.stream.buffer,
          initialData: widget.player.state.buffer,
          builder: (context, bufSnap) {
            final buffered = bufSnap.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: widget.player.stream.position,
              initialData: widget.player.state.position,
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
                // Listener (raw pointer events) instead of GestureDetector:
                // bypasses the gesture arena so horizontal drags on the
                // seekbar can't be stolen by the video-area scrub/volume
                // recognizers behind it. Works in both portrait and
                // landscape: _fracFromGlobal uses the live RenderBox size.
                return LayoutBuilder(
                  builder: (context, constraints) {
                    // Drag tooltip: exact time above the thumb while dragging.
                    final dragTime = _clock(Duration(
                        milliseconds:
                            (_dragFrac * duration.inMilliseconds)
                                .round()));
                    // Tooltip x position, clamped so it stays on-screen.
                    final tipX =
                        (12 + _dragFrac * (constraints.maxWidth - 24))
                            .clamp(28.0, constraints.maxWidth - 28);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (e) {
                            setState(() {
                              _dragging = true;
                              _dragFrac =
                                  _fracFromGlobal(e.position);
                            });
                          },
                          onPointerMove: (e) {
                            if (!_dragging) return;
                            setState(() => _dragFrac =
                                _fracFromGlobal(e.position));
                          },
                          onPointerUp: (_) async {
                            final f = _dragFrac;
                            setState(() => _dragging = false);
                            await _seekToFrac(f, duration);
                          },
                          onPointerCancel: (_) =>
                              setState(() => _dragging = false),
                          child: Container(
                            key: _barKey,
                            height: 36,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            color: Colors.transparent,
                            child: CustomPaint(
                              size: const Size(double.infinity, 36),
                              painter: _SeekBarPainter(
                                playedFrac: frac,
                                bufferedFrac: bufferedFrac,
                                activeColor: widget.activeColor,
                                dragging: _dragging,
                              ),
                            ),
                          ),
                        ),
                        if (_dragging)
                          Positioned(
                            left: tipX - 28,
                            top: -34,
                            child: Container(
                              width: 56,
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius:
                                    BorderRadius.circular(6),
                                border: Border.all(
                                    color: widget.activeColor
                                        .withOpacity(0.5)),
                              ),
                              child: Text(
                                dragTime,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight:
                                        FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
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
  final Color activeColor;
  final bool dragging;

  _SeekBarPainter(
      {required this.playedFrac,
      required this.bufferedFrac,
      this.activeColor = Colors.amber,
      this.dragging = false});

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
      ..color = activeColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawLine(
        Offset(0, y), Offset(w * playedFrac, y), played);
    // Thumb grows while dragging (7 -> 11).
    final radius = dragging ? 11.0 : 7.0;
    canvas.drawCircle(Offset(w * playedFrac, y), radius,
        Paint()..color = activeColor);
    canvas.drawCircle(
        Offset(w * playedFrac, y),
        radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SeekBarPainter old) =>
      old.playedFrac != playedFrac ||
      old.bufferedFrac != bufferedFrac ||
      old.activeColor != activeColor ||
      old.dragging != dragging;
}

/// "Stats for nerds" debug overlay (YouTube parity): monospace readout of
/// video ID, quality, codec/fps/bitrate, position/duration/buffer.
class _StatsOverlay extends StatelessWidget {
  final PlayerUiState uiState;
  final Player player;

  const _StatsOverlay({required this.uiState, required this.player});

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final q = uiState.currentQuality;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (context, posSnap) {
          return StreamBuilder<Duration>(
            stream: player.stream.buffer,
            initialData: player.state.buffer,
            builder: (context, bufSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final buf = bufSnap.data ?? Duration.zero;
              final dur =
                  uiState.video?.duration ?? Duration.zero;
              final lines = [
                'id: ${uiState.videoId ?? '-'}',
                'quality: ${q?.label ?? '-'}',
                'codec: ${(q?.codec.isNotEmpty ?? false) ? q!.codec : 'n/a'}'
                    ' / ${(q?.fps ?? 0) > 0 ? '${q!.fps}fps' : 'n/a'}'
                    ' / ${(q?.bitrateKbps ?? 0) > 0 ? '${(q!.bitrateKbps / 1000).toStringAsFixed(1)}Mbps' : 'n/a'}',
                'pos: ${_fmt(pos)} / ${_fmt(dur)}'
                    '  buf: ${_fmt(buf)}',
                'speed: ${uiState.speed}x',
              ];
              return Text(
                lines.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['Courier'],
                  fontSize: 11,
                  height: 1.4,
                  color: Colors.white,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Seek bar for the audio (music) mode: gold track with time labels.
class _AudioSeekBar extends StatelessWidget {
  final Player player;

  const _AudioSeekBar({required this.player});

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // initialData from the synchronous player state (broadcast streams
    // don't replay for fresh subscriptions).
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PlayerSeekBar(
                    player: player,
                    activeColor:
                        Theme.of(context).colorScheme.primary),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(position),
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12)),
                      Text(_fmt(duration),
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Auto-scrolling title text (marquee) for long titles in audio mode.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText(
      {super.key, required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _ctrl = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeScroll());
  }

  @override
  void didUpdateWidget(covariant _MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _timer?.cancel();
      if (_ctrl.hasClients) _ctrl.jumpTo(0);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeScroll());
    }
  }

  void _maybeScroll() {
    if (!mounted || !_ctrl.hasClients) return;
    final max = _ctrl.position.maxScrollExtent;
    if (max <= 0) return;
    // Pause, scroll to end, pause, scroll back — forever.
    _timer =
        Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || !_ctrl.hasClients) return;
      final curMax = _ctrl.position.maxScrollExtent;
      if (curMax <= 0) return;
      final target =
          _ctrl.offset >= curMax - 1 ? 0.0 : curMax;
      await _ctrl.animateTo(target,
          duration: Duration(
              milliseconds:
                  (curMax * 18).round().clamp(800, 6000)),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      child: Text(widget.text, style: widget.style),
    );
  }
}
