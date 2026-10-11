import 'package:flutter/material.dart';

/// Community tab — graceful empty state.
///
/// youtube_explode_dart has no community-posts endpoint,
/// so this renders an empty state instead of crashing.
class CommunityTab extends StatefulWidget {
  final String channelId;

  const CommunityTab(
      {super.key, required this.channelId});

  @override
  State<CommunityTab> createState() =>
      _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  static const _accent = Color(0xFF6200EA);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await Future.delayed(
        const Duration(milliseconds: 400));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: _accent));
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(Icons.forum_outlined,
                    size: 64,
                    color: Colors.grey),
                SizedBox(height: 12),
                Text('No community posts yet',
                    style: TextStyle(
                        color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
