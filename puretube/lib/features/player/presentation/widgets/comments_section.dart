import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../domain/entities/playback_models.dart';
import '../providers/player_controller.dart';

/// Comments section below the video player.
class CommentsSection extends ConsumerStatefulWidget {
  const CommentsSection({super.key});

  @override
  ConsumerState<CommentsSection> createState() =>
      _CommentsSectionState();
}

class _CommentsSectionState
    extends ConsumerState<CommentsSection> {
  List<CommentInfo>? _comments;
  bool _loading = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    final videoId =
        ref.read(playerControllerProvider).videoId;
    if (videoId == null) return;
    setState(() => _loading = true);
    try {
      final comments = await ref
          .read(extractorProvider)
          .getComments(videoId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Comments ${_comments?.length ?? ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.white70,
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  ),
                )
              else if (_comments != null &&
                  _comments!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildComment(_comments!.first),
                if (_expanded)
                  ..._comments!
                      .skip(1)
                      .map(_buildComment),
              ] else if (!_loading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'No comments yet.',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComment(CommentInfo comment) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                Colors.purple.withOpacity(0.3),
            child: Text(
              comment.author.isNotEmpty
                  ? comment.author[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.author,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        overflow:
                            TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      comment.publishedTime,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.text,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13),
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded
                      ? null
                      : TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.thumb_up_outlined,
                        size: 14,
                        color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.likeCount}',
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11),
                    ),
                    if (comment.replyCount > 0) ...[
                      const SizedBox(width: 12),
                      Text(
                        '${comment.replyCount} replies',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
