import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/services/lyrics_service.dart';

/// Beautiful WILLOW-themed lyrics bottom sheet.
///
/// Fetches lyrics from the free lyrics.ovh API using the current video's
/// title and channel name. Shows a shimmer loading state, the lyrics in
/// a readable scrollable view, or a friendly "not available" message with
/// a retry button.
class LyricsSheet extends StatefulWidget {
  final String videoTitle;
  final String channelName;
  final String thumbnailUrl;

  const LyricsSheet({
    super.key,
    required this.videoTitle,
    required this.channelName,
    this.thumbnailUrl = '',
  });

  static const _bg = Color(0xFF0C110E);
  static const _card = Color(0xFF16211C);
  static const _accent = Color(0xFF10B981);
  static const _accentLight = Color(0xFF34D399);

  static Future<void> show(
    BuildContext context, {
    required String videoTitle,
    required String channelName,
    String thumbnailUrl = '',
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LyricsSheet(
        videoTitle: videoTitle,
        channelName: channelName,
        thumbnailUrl: thumbnailUrl,
      ),
    );
  }

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  final _service = LyricsService();
  LyricsResult? _result;
  bool _loading = true;
  int _attemptCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    final result = await _service.getLyrics(
      videoTitle: widget.videoTitle,
      channelName: widget.channelName,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  void _retry() {
    HapticFeedback.lightImpact();
    _attemptCount++;
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: LyricsSheet._bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: LyricsSheet._accent, width: 1.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.lyrics_outlined,
                      color: LyricsSheet._accent, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Lyrics',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _result?.title ?? widget.videoTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _result?.artist ?? widget.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LyricsSheet._accentLight,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 16),
            Flexible(child: _buildBody()),
            SizedBox(
                height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildShimmer();
    final result = _result;
    if (result == null) return _buildError();
    if (!result.found || result.lyrics == null) {
      return _buildNotFound();
    }
    return _buildLyrics(result.lyrics!);
  }

  Widget _buildShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFF1C2A23),
        highlightColor: const Color(0xFF2A3F34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(
            14,
            (i) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              height: 14,
              width: i % 3 == 0
                  ? double.infinity
                  : MediaQuery.of(context).size.width *
                      (0.55 + (i % 4) * 0.12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyrics(String lyrics) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: SelectableText(
          lyrics,
          style: const TextStyle(
            color: Color(0xFFE8F0EC),
            fontSize: 15,
            height: 1.8,
          ),
        ),
      ),
    );
  }

  Widget _buildNotFound() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  LyricsSheet._accent.withValues(alpha: 0.12),
              border: Border.all(
                color:
                    LyricsSheet._accent.withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.music_off_outlined,
              color: LyricsSheet._accent,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Lyrics not available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'We couldn\'t find lyrics for this song.\nTry again or check your connection.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh,
                color: LyricsSheet._accent, size: 18),
            label: Text(
              _attemptCount > 0 ? 'Try again' : 'Retry',
              style:
                  const TextStyle(color: LyricsSheet._accent),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color:
                    LyricsSheet._accent.withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return _buildNotFound();
  }
}
