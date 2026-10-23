import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/playback_models.dart';

/// Read-only comments viewer, YouTube-style bottom sheet: author,
/// "time · likes" and the comment text. Posting needs a signed-in
/// YouTube account, which this app does not have — viewing only.
class CommentsSheet extends ConsumerStatefulWidget {
  final String videoId;
  const CommentsSheet({super.key, required this.videoId});

  static Future<void> show(BuildContext context, String videoId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CommentsSheet(videoId: videoId),
    );
  }

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  List<VideoComment>? _comments;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list =
          await ref.read(extractorProvider).getComments(widget.videoId);
      if (mounted) setState(() => _comments = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.75;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                const Text('Comments',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                if (_comments != null) ...[
                  const SizedBox(width: 8),
                  Text('${_comments!.length}',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Comments পাওয়া যায়নি',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                setState(() => _error = null);
                _load();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final comments = _comments;
    if (comments == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (comments.isEmpty) {
      return const Center(
        child: Text('কোনো comment নেই', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: comments.length,
      itemBuilder: (_, i) => _CommentTile(comment: comments[i]),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final VideoComment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final initial = comment.author.trim().isNotEmpty
        ? comment.author.trim()[0].toUpperCase()
        : '?';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF272727),
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${comment.author} · ${comment.publishedTime}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(comment.text,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13.5)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.thumb_up_outlined,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 5),
                    Text(formatCount(comment.likeCount),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                    if (comment.replyCount > 0) ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.comment_outlined,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text('${comment.replyCount}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                    if (comment.isHearted) ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.favorite,
                          size: 14, color: Colors.redAccent),
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
