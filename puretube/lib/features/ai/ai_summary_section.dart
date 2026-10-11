import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_theme.dart';
import 'ai_summary_service.dart';

/// AI summary section below the description.
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

class _AiSummarySectionState
    extends State<AiSummarySection> {
  List<String>? _summary;
  bool _loading = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final points =
          await AiSummaryService.instance
              .summarize(
        title: widget.title,
        author: widget.author,
        description: widget.description,
      );
      if (mounted) {
        setState(() {
          _summary = points;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: AppTheme.primary),
            const SizedBox(width: 6),
            Text('AI Summary',
                style: AppTheme.body.copyWith(
                    fontWeight:
                        FontWeight.bold)),
            const Spacer(),
            if (_summary == null &&
                !_loading)
              TextButton(
                onPressed: _generate,
                child: const Text('Generate',
                    style: TextStyle(
                        color:
                            AppTheme.primary)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          Shimmer.fromColors(
            baseColor: AppTheme.card,
            highlightColor:
                const Color(0xFF2A2A2A),
            child: Column(
              children: List.generate(
                  3,
                  (_) => Container(
                        height: 14,
                        margin:
                            const EdgeInsets
                                .symmetric(
                                vertical: 4),
                        color: Colors.white,
                      )),
            ),
          )
        else if (_error != null)
          Text(_error!,
              style: AppTheme.caption
                  .copyWith(
                      color: AppTheme.error))
        else if (_summary != null)
          ..._summary!.map((p) => Padding(
                padding:
                    const EdgeInsets.symmetric(
                        vertical: 4),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(
                            color: AppTheme
                                .primary,
                            fontWeight:
                                FontWeight
                                    .bold)),
                    Expanded(
                      child: Text(p,
                          style: AppTheme.body
                              .copyWith(
                                  fontSize:
                                      13)),
                    ),
                  ],
                ),
              )),
        if (!AiSummaryService
            .instance.hasApiKey)
          Padding(
            padding:
                const EdgeInsets.only(top: 6),
            child: Text(
                'Tip: add a Gemini API key in Settings for smarter summaries.',
                style:
                    AppTheme.caption.copyWith(
                        color: AppTheme
                            .textSecondary)),
          ),
      ],
    );
  }
}
