import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import './tabs/downloads_tab.dart';
import './tabs/history_tab.dart';
import './tabs/playlists_tab.dart';
import './tabs/saved_tab.dart';
import './tabs/subscriptions_tab.dart';

/// Library screen with 5 tabs.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: const Text('Library'),
          bottom: const TabBar(
            indicatorColor: AppTheme.primary,
            isScrollable: true,
            tabs: [
              Tab(text: 'History'),
              Tab(text: 'Playlists'),
              Tab(text: 'Subscriptions'),
              Tab(text: 'Downloads'),
              Tab(text: 'Saved'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            HistoryTab(),
            PlaylistsTab(),
            SubscriptionsTab(),
            DownloadsTab(),
            SavedTab(),
          ],
        ),
      ),
    );
  }
}
