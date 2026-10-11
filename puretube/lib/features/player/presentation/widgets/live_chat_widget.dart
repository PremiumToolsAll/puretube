import 'package:flutter/material.dart';

/// Live chat section.
///
/// youtube_explode_dart has no live-chat endpoint, so for regular
/// videos this shows a graceful "not available" state. Kept as a
/// widget so a real implementation can drop in later.
class LiveChatWidget extends StatelessWidget {
  final String videoId;
  final bool showUnavailable;

  const LiveChatWidget({
    super.key,
    required this.videoId,
    this.showUnavailable = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showUnavailable) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Live chat',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('OFFLINE',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    color: Colors.grey, size: 32),
                SizedBox(height: 8),
                Text('Live chat is not available\nfor this video.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
