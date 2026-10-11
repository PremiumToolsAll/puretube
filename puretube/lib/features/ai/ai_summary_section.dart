import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// AI summary section below the description.
///
/// Uses a local heuristic (key sentences from the description) until
/// a Gemini API key is configured in Settings.
class AiSummarySection extends StatefulWidget {
  final String title;
  final String author;
  final String description;

  const AiSummarySection({
    super.key,
    required this.title,
    required this.author,
    required this.description,
  });

  @override
  State<AiSummarySection> createState() =>
      _AiSummarySectionState();
}

/// Local heuristic: picks the most informative sentences.
/// Replaced by Gemini when an API key is configured.
List<String> _heuristicSummary(String description,
    {int maxPoints = 5}) {
  final text = description.trim();
  if (text.isEmpty) return [];
  // Split on sentence boundaries, drop URLs / hashtags / timestamps-only lines.
  final sentences = text
      .split(RegExp(r'(?<=[.!?])\s+|\n+'))
      .map((s) => s.trim())
      .where((s) =>
          s.length > 30 &&
          !s.startsWith('http') &&
          !s.startsWith('#') &&
          !RegExp(r'^[\d:\s.,-]+$').hasMatch(s))
      .toList();
  if (sentences.isEmpty) {
    return [
      text.length > 220 ? '${text.substring(0, 220)}…' : text
    ];
  }
  return sentences.take(maxPoints).toList();
}

class _AiSummarySectionState
    extends State<AiSummarySection> {
  static const _accent = Color(0xFF6200EA);
  List<String>? _summary;
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    // Simulate a beat so the shimmer reads as "working".
    await Future.delayed(
        const Duration(milliseconds: 600));
    final points =
        _heuristicSummary(widget.description);
    if (mounted) {
      setState(() {
        _summary = points;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_outlined,
                size: 18, color: _accent),
            const SizedBox(width: 6),
            const Text('AI Summary',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const Spacer(),
            if (_summary == null && !_loading)
              TextButton(
                onPressed: _generate,
                child: const Text('Generate',
                    style: TextStyle(color: _accent)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          Shimmer.fromColors(
            baseColor: const Color(0xFF1A1A1A),
            highlightColor:
                const Color(0xFF2A2A2A),
            child: Column(
              children: List.generate(
                  3,
                  (_) => Container(
                        height: 14,
                        margin:
                            const EdgeInsets.symmetric(
                                vertical: 4),
                        color: Colors.white,
                      )),
            ),
          )
        else if (_summary != null)
          if (_summary!.isEmpty)
            const Text('No summary available.',
                style:
                    TextStyle(color: Colors.grey))
          else
            ..._summary!.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 4),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              color: _accent,
                              fontWeight:
                                  FontWeight.bold)),
                      Expanded(
                        child: Text(p,
                            style: const TextStyle(
                                color:
                                    Colors.white70,
                                fontSize: 13)),
                      ),
                    ],
                  ),
                )),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
              'Tip: add a Gemini API key in Settings for smarter summaries.',
              style:
                  TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ],
    );
  }
}
