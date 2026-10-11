import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/youtube_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/presentation/providers/search_provider.dart';
import '../../home/presentation/widgets/video_card.dart';
import '../../player/domain/entities/models.dart';
import '../data/app_database.dart';

/// Search screen — history, filters, paginated results.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() =>
      _SearchScreenState();
}

class _SearchScreenState
    extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  List<String> _history = [];
  List<String> _suggestions = [];
  String _filter = 'Videos';
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h =
        await AppDatabase.instance.getHistory();
    if (mounted) setState(() => _history = h);
  }

  Future<void> _doSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await AppDatabase.instance.addQuery(q);
    await _loadHistory();
    setState(() {
      _suggestions = [];
      _searched = true;
    });
    if (mounted) {
      await ref
          .read(searchControllerProvider.notifier)
          .search(q);
    }
    if (mounted) {
      Navigator.of(context).pop();
      // Results are shown on home; push a results view instead.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              _SearchResultsScreen(query: q),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: AppTheme.body,
          decoration: InputDecoration(
            hintText: 'Search YouTube…',
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon:
                        const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() =>
                          _suggestions = []);
                    },
                  )
                : null,
          ),
          onChanged: (v) async {
            setState(() {});
            if (v.trim().isEmpty) {
              setState(() => _suggestions = []);
              return;
            }
            final s = await YoutubeService
                .instance
                .searchSuggestions(v);
            if (mounted) {
              setState(() => _suggestions = s);
            }
          },
          onSubmitted: _doSearch,
        ),
      ),
      body: Column(
        children: [
          // Filter chips.
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8),
              children: [
                'Videos',
                'Channels',
                'Playlists',
                'Live'
              ]
                  .map((f) => Padding(
                        padding:
                            const EdgeInsets.only(
                                right: 8),
                        child: FilterChip(
                          label: Text(f),
                          selected:
                              _filter == f,
                          onSelected: (_) =>
                              setState(() =>
                                  _filter = f),
                          backgroundColor:
                              AppTheme.card,
                          selectedColor:
                              AppTheme.primary,
                          labelStyle: AppTheme
                              .body
                              .copyWith(
                            color:
                                _filter == f
                                    ? Colors.white
                                    : AppTheme
                                        .textSecondary,
                          ),
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius
                                    .circular(20),
                            side:
                                BorderSide.none,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: _suggestions.isNotEmpty
                ? ListView.builder(
                    itemCount:
                        _suggestions.length,
                    itemBuilder: (_, i) =>
                        ListTile(
                      leading: const Icon(
                          Icons.search,
                          size: 20),
                      title: Text(
                          _suggestions[i],
                          style: AppTheme.body),
                      onTap: () => _doSearch(
                          _suggestions[i]),
                    ),
                  )
                : _buildHistory(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          'Search for videos, channels, and more',
          style: AppTheme.body.copyWith(
              color: AppTheme.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              16, 8, 16, 4),
          child: Row(
            children: [
              Text('Recent searches',
                  style: AppTheme.subtitle
                      .copyWith(fontSize: 14)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await AppDatabase.instance
                      .clearHistory();
                  _loadHistory();
                },
                child: const Text('Clear all',
                    style: TextStyle(
                        color:
                            AppTheme.primary)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _history.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(
                  Icons.history,
                  size: 20),
              title: Text(_history[i],
                  style: AppTheme.body),
              trailing: IconButton(
                icon: const Icon(Icons.close,
                    size: 18),
                onPressed: () async {
                  await AppDatabase.instance
                      .removeQuery(_history[i]);
                  _loadHistory();
                },
              ),
              onTap: () =>
                  _doSearch(_history[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Results page for a search query.
class _SearchResultsScreen
    extends ConsumerStatefulWidget {
  final String query;
  const _SearchResultsScreen(
      {required this.query});

  @override
  ConsumerState<_SearchResultsScreen>
      createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState
    extends ConsumerState<_SearchResultsScreen> {
  List<VideoItem> _results = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final videos = await YoutubeService.instance
          .search(widget.query, limit: 30);
      if (mounted) {
        setState(() {
          _results = videos
              .map(VideoItem.fromVideo)
              .toList();
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: Text(widget.query,
            style: AppTheme.subtitle),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Text('Search failed',
                          style: AppTheme
                              .subtitle),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _run,
                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor:
                              AppTheme.primary,
                        ),
                        child:
                            const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _results.isEmpty
                  ? Center(
                      child: Text(
                          'No results for "${widget.query}"',
                          style: AppTheme.body
                              .copyWith(
                                  color: AppTheme
                                      .textSecondary)),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _run,
                      child: ListView.builder(
                        itemCount:
                            _results.length,
                        itemBuilder: (_, i) =>
                            VideoCard(
                                video:
                                    _results[i]),
                      ),
                    ),
    );
  }
}
