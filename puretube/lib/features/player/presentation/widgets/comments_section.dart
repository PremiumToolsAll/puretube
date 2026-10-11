import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../providers/player_controller.dart';

/// Comments section below the video info.
class CommentsSection extends StatelessWidget {
  final PlayerUiState ui;

  const CommentsSection(
      {super.key, required this.ui});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Comments',
                style: AppTheme.subtitle.copyWith(
                    fontWeight:
                        FontWeight.bold)),
            const SizedBox(width: 8),
            Text('${ui.commentCount}',
                style: AppTheme.caption.copyWith(
                    color:
                        AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 12),
        if (ui.comments.isEmpty)
          Text('No comments yet.',
              style: AppTheme.caption.copyWith(
                  color:
                      AppTheme.textSecondary)),
        ...ui.comments
            .take(5)
            .map((c) => _commentTile(c)),
        if (ui.comments.length > 5)
          TextButton(
            onPressed: () =>
                _allComments(context),
            child: const Text(
                'View more comments',
                style: TextStyle(
                    color: AppTheme.primary)),
          ),
      ],
    );
  }

  Widget _commentTile(CommentItem c) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.card,
            child: Text(
                c.author.isNotEmpty
                    ? c.author[0].toUpperCase()
                    : '?',
                style: AppTheme.caption.copyWith(
                    color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(c.author,
                    style:
                        AppTheme.caption.copyWith(
                            fontWeight:
                                FontWeight.w600,
                            color: Colors.white)),
                const SizedBox(height: 2),
                Text(c.text,
                    style: AppTheme.body
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                        Icons.thumb_up_outlined,
                        size: 14,
                        color:
                            AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                        formatCount(c.likeCount),
                        style: AppTheme.caption
                            .copyWith(
                                color: AppTheme
                                    .textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _allComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, ctrl) => ListView.builder(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          itemCount: ui.comments.length,
          itemBuilder: (_, i) =>
              _commentTile(ui.comments[i]),
        ),
      ),
    );
  }
}
