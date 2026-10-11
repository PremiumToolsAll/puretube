import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/youtube_service.dart';
import '../../../core/theme/app_theme.dart';

/// Live chat message.
class LiveChatMessage {
  final String author;
  final String text;
  final String avatarUrl;
  final bool isModerator;
  final bool isMember;
  final DateTime timestamp;

  const LiveChatMessage({
    required this.author,
    required this.text,
    this.avatarUrl = '',
    this.isModerator = false,
    this.isMember = false,
    required this.timestamp,
  });
}

/// Live chat widget (toggleable overlay or below video).
class LiveChatWidget extends StatefulWidget {
  final String videoId;
  final bool overlay;

  const LiveChatWidget({
    super.key,
    required this.videoId,
    this.overlay = false,
  });

  @override
  State<LiveChatWidget> createState() =>
      _LiveChatWidgetState();
}

class _LiveChatWidgetState
    extends State<LiveChatWidget> {
  final List<LiveChatMessage> _messages = [];
  final _scrollCtrl = ScrollController();
  Timer? _pollTimer;
  bool _loading = true;
  String? _continuation;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await _fetch();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      // InnerTube live chat via youtube_explode_dart is limited;
      // use the service's fallback chain. If unsupported, show empty.
      final msgs =
          await YoutubeService.instance
              .liveChat(widget.videoId,
                  continuation: _continuation);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _messages.addAll(msgs.messages);
        _continuation =
            msgs.continuation ?? _continuation;
        // Cap at 200 messages.
        if (_messages.length > 200) {
          _messages.removeRange(
              0, _messages.length - 200);
        }
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    Future.delayed(
        const Duration(milliseconds: 100),
        () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl
              .position.maxScrollExtent,
          duration: const Duration(
              milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(
            child: SizedBox(
                width: 24,
                height: 24,
                child:
                    CircularProgressIndicator(
                        strokeWidth: 2)))
        : _messages.isEmpty
            ? Center(
                child: Text(
                    'No live chat messages',
                    style:
                        AppTheme.caption.copyWith(
                            color: AppTheme
                                .textSecondary)),
              )
            : ListView.builder(
                controller: _scrollCtrl,
                padding:
                    const EdgeInsets.all(8),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final m = _messages[i];
                  return Padding(
                    padding:
                        const EdgeInsets
                            .symmetric(
                            vertical: 3),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor:
                              AppTheme.card,
                          backgroundImage: m
                                  .avatarUrl
                                  .isNotEmpty
                              ? NetworkImage(
                                  m.avatarUrl)
                              : null,
                          child: m.avatarUrl
                                  .isEmpty
                              ? Text(
                                  m.author.isNotEmpty
                                      ? m.author[0]
                                          .toUpperCase()
                                      : '?',
                                  style:
                                      const TextStyle(
                                          fontSize:
                                              10))
                              : null,
                        ),
                        const SizedBox(
                            width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                if (m.isModerator)
                                  const WidgetSpan(
                                    child: Icon(
                                        Icons
                                            .shield_outlined,
                                        size:
                                            12,
                                        color: AppTheme
                                            .primary),
                                  ),
                                if (m.isMember)
                                  const WidgetSpan(
                                    child: Icon(
                                        Icons
                                            .star,
                                        size:
                                            12,
                                        color: Colors
                                            .green),
                                  ),
                                TextSpan(
                                  text:
                                      '${m.author}  ',
                                  style: AppTheme
                                      .caption
                                      .copyWith(
                                    color: m.isModerator
                                        ? AppTheme
                                            .primary
                                        : m.isMember
                                            ? Colors.green
                                            : AppTheme.textSecondary,
                                    fontWeight:
                                        FontWeight
                                            .w600,
                                  ),
                                ),
                                TextSpan(
                                  text: m.text,
                                  style: AppTheme
                                      .body
                                      .copyWith(
                                          fontSize:
                                              13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );

    if (widget.overlay) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius:
              BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(
                      Icons.chat_outlined,
                      size: 16,
                      color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Live chat',
                      style: AppTheme.caption
                          .copyWith(
                              color: Colors
                                  .white,
                              fontWeight:
                                  FontWeight
                                      .w600)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                            horizontal: 8,
                            vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius:
                          BorderRadius.circular(
                              4),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Colors
                                .white,
                            fontSize: 10,
                            fontWeight:
                                FontWeight
                                    .bold)),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Live chat',
                style: AppTheme.subtitle
                    .copyWith(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 14)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius:
                    BorderRadius.circular(4),
              ),
              child: const Text('LIVE',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight:
                          FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(height: 300, child: content),
      ],
    );
  }
}

/// Live chat result page.
class LiveChatPage {
  final List<LiveChatMessage> messages;
  final String? continuation;

  const LiveChatPage({
    this.messages = const [],
    this.continuation,
  });
}
