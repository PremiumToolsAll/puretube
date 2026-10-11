import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format.dart';

/// Community post types.
enum PostType { text, image, poll }

class CommunityPost {
  final String id;
  final String author;
  final String time;
  final String text;
  final List<String> imageUrls;
  final PostType type;
  final PollData? poll;
  final int likeCount;
  final int commentCount;

  const CommunityPost({
    required this.id,
    required this.author,
    required this.time,
    required this.text,
    this.imageUrls = const [],
    this.type = PostType.text,
    this.poll,
    this.likeCount = 0,
    this.commentCount = 0,
  });
}

class PollData {
  final List<PollOption> options;
  final int totalVotes;

  const PollData({
    required this.options,
    required this.totalVotes,
  });
}

class PollOption {
  final String text;
  final int votes;

  const PollOption({
    required this.text,
    required this.votes,
  });
}

/// Community tab — posts, polls, images.
class CommunityTab extends StatefulWidget {
  final String channelId;

  const CommunityTab(
      {super.key, required this.channelId});

  @override
  State<CommunityTab> createState() =>
      _CommunityTabState();
}

class _CommunityTabState
    extends State<CommunityTab> {
  List<CommunityPost> _posts = [];
  bool _loading = true;
  final Set<String> _votedPolls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // InnerTube community endpoint isn't in youtube_explode_dart.
      // Show empty state gracefully.
      await Future.delayed(
          const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _posts = [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppTheme.primary));
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Column(
                children: [
                  const Icon(
                      Icons
                          .forum_outlined,
                      size: 64,
                      color: AppTheme
                          .textSecondary),
                  const SizedBox(
                      height: 12),
                  Text(
                      'No community posts yet',
                      style: AppTheme.body
                          .copyWith(
                              color: AppTheme
                                  .textSecondary)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _posts.length,
        itemBuilder: (_, i) =>
            _postCard(_posts[i]),
      ),
    );
  }

  Widget _postCard(CommunityPost post) {
    return Card(
      color: AppTheme.card,
      margin: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme
                      .primary
                      .withOpacity(0.3),
                  child: Text(
                      post.author.isNotEmpty
                          ? post.author[0]
                              .toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(post.author,
                        style: AppTheme.body
                            .copyWith(
                                fontWeight:
                                    FontWeight
                                        .w600,
                                fontSize: 13)),
                    Text(post.time,
                        style: AppTheme
                            .caption
                            .copyWith(
                                color: AppTheme
                                    .textSecondary)),
                  ],
                ),
              ],
            ),
            if (post.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(post.text,
                  style: AppTheme.body
                      .copyWith(fontSize: 14)),
            ],
            if (post.type ==
                    PostType.image &&
                post.imageUrls.isNotEmpty)
              _imageCarousel(post.imageUrls),
            if (post.type == PostType.poll &&
                post.poll != null)
              _poll(post),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                    Icons.thumb_up_outlined,
                    size: 16,
                    color:
                        AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                    formatCount(
                        post.likeCount),
                    style: AppTheme.caption
                        .copyWith(
                            color: AppTheme
                                .textSecondary)),
                const SizedBox(width: 16),
                const Icon(
                    Icons.comment_outlined,
                    size: 16,
                    color:
                        AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                    formatCount(
                        post.commentCount),
                    style: AppTheme.caption
                        .copyWith(
                            color: AppTheme
                                .textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageCarousel(
      List<String> urls) {
    return SizedBox(
      height: 200,
      child: PageView.builder(
        itemCount: urls.length,
        itemBuilder: (_, i) => Padding(
          padding:
              const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(8),
            child: Image.network(
              urls[i],
              fit: BoxFit.cover,
              errorBuilder: (_, __,
                      ___) =>
                  Container(
                      color:
                          Colors.white10),
            ),
          ),
        ),
      ),
    );
  }

  Widget _poll(CommunityPost post) {
    final poll = post.poll!;
    final voted =
        _votedPolls.contains(post.id);
    return Padding(
      padding:
          const EdgeInsets.only(top: 8),
      child: Column(
        children: poll.options
            .asMap()
            .entries
            .map((e) {
          final idx = e.key;
          final opt = e.value;
          final pct = poll.totalVotes > 0
              ? opt.votes /
                  poll.totalVotes
              : 0.0;
          return Padding(
            padding:
                const EdgeInsets.symmetric(
                    vertical: 4),
            child: InkWell(
              onTap: voted
                  ? null
                  : () => setState(() =>
                      _votedPolls
                          .add(post.id)),
              child: Stack(
                children: [
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: voted
                          ? AppTheme.primary
                              .withOpacity(
                                  0.15)
                          : Colors.white10,
                      borderRadius:
                          BorderRadius.circular(
                              8),
                    ),
                  ),
                  if (voted)
                    FractionallySizedBox(
                      widthFactor:
                          pct.clamp(0.0, 1.0),
                      child: Container(
                        height: 40,
                        decoration:
                            BoxDecoration(
                          color: AppTheme
                              .primary
                              .withOpacity(
                                  0.4),
                          borderRadius:
                              BorderRadius
                                  .circular(
                                      8),
                        ),
                      ),
                    ),
                  Container(
                    height: 40,
                    padding:
                        const EdgeInsets
                            .symmetric(
                            horizontal:
                                12),
                    alignment: Alignment
                        .centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              opt.text,
                              style: AppTheme
                                  .body
                                  .copyWith(
                                      fontSize:
                                          13)),
                        ),
                        if (voted)
                          Text(
                              '${(pct * 100).toStringAsFixed(0)}%',
                              style: AppTheme
                                  .caption
                                  .copyWith(
                                      color: AppTheme
                                          .textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
