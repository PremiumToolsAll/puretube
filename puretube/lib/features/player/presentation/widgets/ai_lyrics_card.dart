import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_controller.dart';

/// Expandable "AI Lyrics" card, styled like the "AI Summary" card.
///
/// Display-only: lyrics are auto-fetched by [PlayerController] when a
/// video loads (no user tap needed) and cached per video id, shared
/// between video and audio mode. This card just renders the loading,
/// lyrics, or "not available" state from the controller.
///
/// AI refusal/copyright responses are filtered (by the service and
/// defensively here) and shown as "Lyrics not available" instead.
class AiLyricsCard extends ConsumerStatefulWidget {
  const AiLyricsCard({super.key});

  @override
  ConsumerState<AiLyricsCard> createState() => _AiLyricsCardState();
}

class _AiLyricsCardState extends ConsumerState<AiLyricsCard> {
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _card => Theme.of(context).colorScheme.surfaceContainer;

  bool _expanded = true;

  /// Defensive filter: reject AI refusal / copyright / placeholder
  /// responses even if the service let one through. Handles
  /// straight/curly apostrophes.
  bool _isRefusal(String text) {
    var norm = text.toUpperCase();
    norm = norm.replaceAll('\u2019', "'"); // ’ -> '
    norm = norm.replaceAll('\u2018', "'"); // ‘ -> '
    norm = norm.replaceAll(RegExp(r'\s+'), ' ');
    if (norm.contains('NOT_FOUND')) return true;
    if (norm.contains('SORRY') && norm.contains('PROVIDE')) return true;
    if (norm.contains('CANNOT PROVIDE')) return true;
    if (norm.contains('UNABLE TO PROVIDE')) return true;
    if (norm.contains('COPYRIGHT')) return true;
    if (norm.contains('AS AN AI')) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(
        playerControllerProvider.select((s) => s.lyricsLoading));
    final result = ref.watch(
        playerControllerProvider.select((s) => s.lyricsResult));
    final rawLyrics =
        (result != null && result.found) ? result.lyrics : null;
    final lyrics = (rawLyrics != null &&
            rawLyrics.trim().isNotEmpty &&
            !_isRefusal(rawLyrics))
        ? rawLyrics.trim()
        : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.lyrics_outlined,
                      color: _accent, size: 18),
                  const SizedBox(width: 8),
                  const Text('AI Lyrics',
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
                        style:
                            TextStyle(color: _accent, fontSize: 10)),
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
              child: _buildBody(loading, lyrics),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(bool loading, String? lyrics) {
    if (loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < 4; i++)
            Container(
              margin:
                  EdgeInsets.only(bottom: 8, right: i == 3 ? 120 : 0),
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
        ],
      );
    }
    if (lyrics != null) {
      return Text(lyrics,
          style: const TextStyle(
              color: Color(0xFFE8F0EC), fontSize: 13, height: 1.7));
    }
    return Row(
      children: [
        const Expanded(
          child: Text('Lyrics not available.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        TextButton.icon(
          onPressed: () => ref
              .read(playerControllerProvider.notifier)
              .retryLyrics(),
          icon: Icon(Icons.refresh, color: _accent, size: 16),
          label: Text('Retry', style: TextStyle(color: _accent)),
        ),
      ],
    );
  }
}
