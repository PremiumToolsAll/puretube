import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../data/library_database.dart';
import '../data/library_models.dart';

/// Tab 3: Subscriptions (local, no Google account).
class SubscriptionsTab extends StatefulWidget {
  const SubscriptionsTab({super.key});

  @override
  State<SubscriptionsTab> createState() =>
      _SubscriptionsTabState();
}

class _SubscriptionsTabState
    extends State<SubscriptionsTab> {
  List<Subscription> _subs = [];
  bool _loading = true;
  String _sort = 'Latest';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var list = await LibraryDatabase.instance
          .getSubscriptions();
      if (_sort == 'A-Z') {
        list.sort((a, b) =>
            a.name.compareTo(b.name));
      }
      if (mounted) {
        setState(() {
          _subs = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _export() async {
    try {
      final data = {
        'app_name': 'PureTube',
        'app_version': '1.0.0',
        'subscriptions': _subs
            .map((s) => {
                  'service_id': 0,
                  'url':
                      'https://www.youtube.com/channel/${s.channelId}',
                  'name': s.name,
                })
            .toList(),
      };
      final dir =
          await getTemporaryDirectory();
      final file = File(
          '${dir.path}/puretube_subscriptions.json');
      await file.writeAsString(
          jsonEncode(data));
      await Share.shareXFiles(
          [XFile(file.path)],
          text: 'PureTube subscriptions');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
                content: Text(
                    'Export failed: $e')));
      }
    }
  }

  Future<void> _import() async {
    try {
      final result =
          await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null) return;
      final content = await File(
              result.files.single.path!)
          .readAsString();
      final data =
          jsonDecode(content) as Map<String, dynamic>;
      final subs =
          data['subscriptions'] as List<dynamic>? ??
              [];
      int added = 0;
      for (final s in subs) {
        final m = s as Map<String, dynamic>;
        final url =
            (m['url'] as String?) ?? '';
        final name =
            (m['name'] as String?) ?? 'Unknown';
        final match = RegExp(
                r'(?:channel/|@|user/)([^/?]+)')
            .firstMatch(url);
        final channelId =
            match?.group(1) ?? url;
        if (channelId.isNotEmpty) {
          await LibraryDatabase.instance.subscribe(
            channelId: channelId,
            name: name,
          );
          added++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
                content: Text(
                    'Imported $added subscriptions')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
                content: Text(
                    'Import failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DropdownButton<String>(
                value: _sort,
                dropdownColor: AppTheme.surface,
                style: AppTheme.body,
                items: ['Latest', 'A-Z']
                    .map((s) =>
                        DropdownMenuItem(
                            value: s,
                            child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(
                        () => _sort = v);
                    _load();
                  }
                },
              ),
              const Spacer(),
              TextButton.icon(
                icon:
                    const Icon(Icons.upload),
                label:
                    const Text('Export'),
                onPressed:
                    _subs.isEmpty ? null : _export,
              ),
              TextButton.icon(
                icon: const Icon(
                    Icons.download),
                label: const Text('Import'),
                onPressed: _import,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator())
              : _subs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          const Icon(
                              Icons
                                  .subscriptions_outlined,
                              size: 64,
                              color: AppTheme
                                  .textSecondary),
                          const SizedBox(
                              height: 12),
                          Text(
                              'No subscriptions yet',
                              style: AppTheme.body
                                  .copyWith(
                                      color: AppTheme
                                          .textSecondary)),
                          const SizedBox(
                              height: 8),
                          Text(
                              'Subscribe to channels from the player',
                              style: AppTheme.caption
                                  .copyWith(
                                      color: AppTheme
                                          .textSecondary)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color:
                          AppTheme.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount:
                            _subs.length,
                        itemBuilder: (_, i) {
                          final s =
                              _subs[i];
                          return ListTile(
                            leading:
                                CircleAvatar(
                              backgroundColor:
                                  AppTheme.card,
                              backgroundImage: s
                                      .avatarUrl
                                      .isNotEmpty
                                  ? NetworkImage(s
                                      .avatarUrl)
                                  : null,
                              child: s.avatarUrl
                                      .isEmpty
                                  ? Text(
                                      s.name.isNotEmpty
                                          ? s.name[0]
                                              .toUpperCase()
                                          : '?',
                                      style:
                                          AppTheme
                                              .body)
                                  : null,
                            ),
                            title: Text(s.name,
                                style:
                                    AppTheme.body),
                            subtitle: Text(
                                '${formatCount(s.subscriberCount)} subscribers${s.folder.isNotEmpty ? ' • ${s.folder}' : ''}',
                                style: AppTheme
                                    .caption
                                    .copyWith(
                                        color: AppTheme
                                            .textSecondary)),
                            trailing: Row(
                              mainAxisSize:
                                  MainAxisSize
                                      .min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                      s.notificationsEnabled
                                          ? Icons
                                              .notifications_active
                                          : Icons
                                              .notifications_outlined,
                                      size: 20),
                                  onPressed: () {},
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons
                                          .unsubscribe_outlined,
                                      size: 20),
                                  onPressed: () async {
                                    await LibraryDatabase
                                        .instance
                                        .unsubscribe(s
                                            .channelId);
                                    _load();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
