import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/services/audio_player_service.dart';
import '../../../core/services/youtube_service.dart';
import '../data/services/dislike_service.dart';
import '../data/services/sponsorblock_service.dart';
import '../domain/entities/models.dart';

enum PlayerStatus { idle, loading, ready, error }

class PlayerUiState {
  final PlayerStatus status;
  final String? videoId;
  final VideoItem? video;
  final PlaybackStreams? streams;
  final int currentQualityHeight;
  final double speed;
  final bool audioOnly;
  final bool skipSponsors;
  final List<VideoItem> related;
  final List<CommentItem> comments;
  final int commentCount;
  final DislikeVotes votes;
  final SleepTimerState sleepTimer;
  final String? error;

  const PlayerUiState({
    this.status = PlayerStatus.idle,
    this.videoId,
    this.video,
    this.streams,
    this.currentQualityHeight = 0,
    this.speed = 1.0,
    this.audioOnly = false,
    this.skipSponsors = true,
    this.related = const [],
    this.comments = const [],
    this.commentCount = 0,
    this.votes = const DislikeVotes(),
    this.sleepTimer = const SleepTimerState(),
    this.error,
  });

  PlayerUiState copyWith({
    PlayerStatus? status,
    String? videoId,
    VideoItem? video,
    PlaybackStreams? streams,
    int? currentQualityHeight,
    double? speed,
    bool? audioOnly,
    bool? skipSponsors,
    List<VideoItem>? related,
    List<CommentItem>? comments,
    int? commentCount,
    DislikeVotes? votes,
    SleepTimerState? sleepTimer,
    String? error,
  }) =>
      PlayerUiState(
        status: status ?? this.status,
        videoId: videoId ?? this.videoId,
        video: video ?? this.video,
        streams: streams ?? this.streams,
        currentQualityHeight:
            currentQualityHeight ??
                this.currentQualityHeight,
        speed: speed ?? this.speed,
        audioOnly: audioOnly ?? this.audioOnly,
        skipSponsors:
            skipSponsors ?? this.skipSponsors,
        related: related ?? this.related,
        comments: comments ?? this.comments,
        commentCount:
            commentCount ?? this.commentCount,
        votes: votes ?? this.votes,
        sleepTimer: sleepTimer ?? this.sleepTimer,
        error: error,
      );
}

class SleepTimerState {
  final bool active;
  final Duration remaining;

  const SleepTimerState({
    this.active = false,
    this.remaining = Duration.zero,
  });

  SleepTimerState copyWith({
    bool? active,
    Duration? remaining,
  }) =>
      SleepTimerState(
        active: active ?? this.active,
        remaining: remaining ?? this.remaining,
      );
}

class CommentItem {
  final String author;
  final String text;
  final String time;
  final int likeCount;

  const CommentItem({
    required this.author,
    required this.text,
    required this.time,
    required this.likeCount,
  });
}

class PlayerController
    extends Notifier<PlayerUiState> {
  PureTubeAudioHandler get _handler =>
      ref.read(audioHandlerProvider);
  YoutubeService get _yt =>
      ref.read(youtubeServiceProvider);
  final _sponsorBlock = SponsorBlockService();
  final _dislike = DislikeService();

  StreamSubscription<Duration>? _posSub;
  List<SponsorSegment> _segments = [];
  bool _skipping = false;
  String? _skipBadge;
  Timer? _sleepTimer;
  Timer? _sleepCountdown;

  List<String> _queue = [];
  int _queueIndex = -1;

  /// Stream of skip-badge messages for the UI.
  final _skipBadgeCtrl =
      StreamController<String?>.broadcast();
  Stream<String?> get skipBadgeStream =>
      _skipBadgeCtrl.stream;

  @override
  PlayerUiState build() {
    _posSub = _handler.player.stream.position
        .listen(_maybeSkipSponsor);
    _handler.onSkipNext = playNext;
    _handler.onSkipPrevious = playPrevious;
    ref.onDispose(() {
      _posSub?.cancel();
      _sleepTimer?.cancel();
      _sleepCountdown?.cancel();
      _skipBadgeCtrl.close();
      _sponsorBlock.dispose();
      _dislike.dispose();
    });
    return const PlayerUiState();
  }

  void setQueue(List<String> ids, {int start = 0}) {
    _queue = ids;
    _queueIndex = start.clamp(0, ids.length - 1);
  }

  bool get hasNext =>
      (_queue.isNotEmpty &&
          _queueIndex < _queue.length - 1) ||
      state.related.isNotEmpty;

  bool get hasPrevious =>
      _queue.isNotEmpty && _queueIndex > 0;

  Future<void> playNext() async {
    if (_queue.isNotEmpty &&
        _queueIndex < _queue.length - 1) {
      _queueIndex++;
      await loadVideo(_queue[_queueIndex]);
    } else if (state.related.isNotEmpty) {
      await loadVideo(state.related.first.id);
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isNotEmpty && _queueIndex > 0) {
      _queueIndex--;
      await loadVideo(_queue[_queueIndex]);
    }
  }

  Future<void> loadVideo(String videoId) async {
    cancelSleepTimer();
    state = PlayerUiState(
      status: PlayerStatus.loading,
      videoId: videoId,
      speed: state.speed,
      skipSponsors: state.skipSponsors,
    );
    _segments = [];
    try {
      final results = await Future.wait([
        _yt.video(videoId),
        _yt.streams(videoId),
        _sponsorBlock.getSegments(videoId),
        _dislike.getVotes(videoId),
      ]);
      final video = results[0] as Video;
      final manifest = results[1] as StreamManifest;
      _segments = results[2] as List<SponsorSegment>;
      final votes = results[3] as DislikeVotes;

      final item = VideoItem.fromVideo(video);
      final streams = _pickStreams(videoId, manifest);

      state = state.copyWith(
        status: PlayerStatus.ready,
        video: item,
        streams: streams,
        currentQualityHeight: streams.muxedHeight,
        votes: votes,
      );

      await _handler.loadMedia(
        item: MediaItem(
          id: videoId,
          title: item.title,
          artist: item.author,
          artUri: Uri.tryParse(item.thumbnailUrl),
        ),
        streamUrl: state.audioOnly
            ? streams.audioOnlyUrl
            : streams.muxedUrl,
        speed: state.speed,
      );

      // Related + comments in background.
      _yt.related(video).then((rel) {
        if (state.videoId == videoId) {
          state = state.copyWith(
            related:
                rel.map(VideoItem.fromVideo).toList(),
          );
        }
      });
      _yt.comments(video).then((list) {
        if (state.videoId == videoId) {
          state = state.copyWith(
            comments: list
                .map((c) => CommentItem(
                      author: c.author,
                      text: c.text,
                      time: '',
                      likeCount: c.likeCount,
                    ))
                .toList(),
            commentCount: list.length,
          );
        }
      });
    } catch (e) {
      state = state.copyWith(
        status: PlayerStatus.error,
        error: e.toString(),
      );
    }
  }

  PlaybackStreams _pickStreams(
      String videoId, StreamManifest manifest) {
    final muxed = [...manifest.muxed]
      ..sort((a, b) => b.videoQuality.height
          .compareTo(a.videoQuality.height));
    final audio = [...manifest.audioOnly]
      ..sort(
          (a, b) => b.bitrate.compareTo(a.bitrate));

    if (muxed.isEmpty) {
      throw Exception('No playable streams');
    }

    final best = muxed.first;
    final bestAudio =
        audio.isNotEmpty ? audio.first : null;

    final seen = <int>{};
    final qualities = <QualityOption>[];
    // Standard muxed qualities.
    const standardHeights = [
      2160,
      1440,
      1080,
      720,
      480,
      360,
      240,
      144
    ];
    for (final h in standardHeights) {
      final match = muxed.where(
          (s) => s.videoQuality.height == h);
      if (match.isNotEmpty && seen.add(h)) {
        qualities.add(QualityOption(
          label: h >= 2160 ? '2160p (4K)' : '${h}p',
          height: h,
          url: match.first.url.toString(),
        ));
      }
    }
    // DASH video-only (1080p+) + best audio.
    if (bestAudio != null) {
      final audioUrl = bestAudio.url.toString();
      final videoOnly = [...manifest.videoOnly]
        ..sort((a, b) => b.videoResolution.height
            .compareTo(a.videoResolution.height));
      for (final v in videoOnly) {
        final h = v.videoResolution.height;
        if (h > 720 && seen.add(h)) {
          qualities.add(QualityOption(
            label: h >= 2160
                ? '2160p (4K)'
                : h >= 1440
                    ? '1440p (2K)'
                    : '${h}p',
            height: h,
            url: v.url.toString(),
            audioUrl: audioUrl,
          ));
        }
      }
    }
    qualities
        .sort((a, b) => b.height.compareTo(a.height));

    return PlaybackStreams(
      videoId: videoId,
      muxedUrl: best.url.toString(),
      muxedHeight: best.videoQuality.height,
      qualities: qualities,
      audioOnlyUrl: bestAudio?.url.toString() ?? '',
    );
  }

  void _maybeSkipSponsor(Duration pos) {
    if (!state.skipSponsors ||
        _skipping ||
        _segments.isEmpty) return;
    final sec = pos.inMilliseconds / 1000.0;
    for (final s in _segments) {
      if (sec >= s.start && sec < s.end - 0.3) {
        _skipping = true;
        _handler.player.seek(Duration(
            milliseconds:
                (s.end * 1000).round()));
        final label = _categoryLabel(s.category);
        _skipBadgeCtrl.add('Skipped $label');
        Future.delayed(
            const Duration(seconds: 2),
            () => _skipBadgeCtrl.add(null));
        Future.delayed(
            const Duration(milliseconds: 500),
            () => _skipping = false);
        break;
      }
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'sponsor':
        return 'Sponsor';
      case 'intro':
        return 'Intro';
      case 'outro':
        return 'Outro';
      case 'selfpromo':
        return 'Self Promo';
      case 'interaction':
        return 'Interaction Reminder';
      case 'preview':
        return 'Preview';
      default:
        return 'Segment';
    }
  }

  Future<void> togglePlayPause() async {
    final p = _handler.player;
    if (p.state.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> seekBy(Duration offset) async {
    final player = _handler.player;
    final target = player.state.position + offset;
    final duration = player.state.duration;
    final clamped = target.isNegative
        ? Duration.zero
        : (duration > Duration.zero && target > duration
            ? duration
            : target);
    await player.seek(clamped);
  }

  Future<void> setQuality(QualityOption q) async {
    if (state.status != PlayerStatus.ready ||
        state.audioOnly) return;
    if (q.height == state.currentQualityHeight) return;
    final pos = _handler.player.state.position;
    await _handler.switchStream(
      q.url,
      audioUrl: q.audioUrl,
      resumeAt: pos,
    );
    state = state.copyWith(
        currentQualityHeight: q.height);
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _handler.setSpeed(speed);
  }

  Future<void> toggleAudioOnly() async {
    final s = state.streams;
    if (s == null || s.audioOnlyUrl.isEmpty) return;
    final toAudio = !state.audioOnly;
    final pos = _handler.player.state.position;
    state = state.copyWith(audioOnly: toAudio);
    await _handler.switchStream(
      toAudio ? s.audioOnlyUrl : s.muxedUrl,
      resumeAt: pos,
    );
  }

  void toggleSkipSponsors(bool v) =>
      state = state.copyWith(skipSponsors: v);

  // ── Sleep timer ───────────────────────────────────────────

  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    if (duration == Duration.zero) return;
    state = state.copyWith(
      sleepTimer: SleepTimerState(
          active: true, remaining: duration),
    );
    _sleepCountdown =
        Timer.periodic(const Duration(seconds: 1), (_) {
      final rem =
          state.sleepTimer.remaining - const Duration(seconds: 1);
      if (rem <= Duration.zero) {
        cancelSleepTimer();
        _handler.pause();
      } else {
        state = state.copyWith(
          sleepTimer:
              state.sleepTimer.copyWith(remaining: rem),
        );
      }
    });
  }

  /// Sleep when the current video ends.
  void setSleepTimerEndOfVideo() {
    cancelSleepTimer();
    final duration =
        _handler.player.state.duration -
            _handler.player.state.position;
    if (duration > Duration.zero) {
      setSleepTimer(duration);
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepCountdown?.cancel();
    _sleepTimer = null;
    _sleepCountdown = null;
    if (state.sleepTimer.active) {
      state = state.copyWith(
          sleepTimer: const SleepTimerState());
    }
  }

  Future<void> retry() async {
    final id = state.videoId;
    if (id != null) await loadVideo(id);
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerUiState>(
        PlayerController.new);
