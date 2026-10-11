import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';
import '../library/data/library_models.dart';

/// Watch stats dashboard.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() =>
      _StatsScreenState();
}

class _StatsScreenState
    extends State<StatsScreen> {
  bool _loading = true;
  Duration _weekTotal = Duration.zero;
  List<double> _dailyMinutes =
      List.filled(7, 0);
  String _topCategory = '—';
  int _videosWatched = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir =
          await getApplicationDocumentsDirectory();
      final isar = await Isar.open(
        [HistoryEntrySchema],
        directory: dir.path,
        name: 'puretube',
      );
      final now = DateTime.now();
      final weekAgo = now.subtract(
          const Duration(days: 7));
      final entries = await isar
          .historyEntrys
          .filter()
          .watchedAtGreaterThan(weekAgo)
          .findAll();

      var totalSecs = 0;
      final daily = List.filled(7, 0.0);
      final authors = <String, int>{};
      for (final e in entries) {
        totalSecs += e.positionSeconds;
        final dayIdx =
            (now.day - e.watchedAt.day) %
                7;
        final idx =
            (6 - dayIdx).clamp(0, 6);
        daily[idx] +=
            e.positionSeconds / 60.0;
        authors[e.author] =
            (authors[e.author] ?? 0) + 1;
      }
      String top = '—';
      int topCount = 0;
      authors.forEach((k, v) {
        if (v > topCount) {
          topCount = v;
          top = k;
        }
      });
      if (mounted) {
        setState(() {
          _weekTotal = Duration(
              seconds: totalSecs);
          _dailyMinutes = daily;
          _topCategory = top;
          _videosWatched =
              entries.length;
          _loading = false;
        });
      }
      await isar.close();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor:
            AppTheme.background,
        title: const Text('Watch stats'),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(
                      color:
                          AppTheme.primary))
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _load,
              child: ListView(
                padding:
                    const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _statCard(
                              'Watch time',
                              _fmtDuration(
                                  _weekTotal),
                              Icons
                                  .timer_outlined)),
                      const SizedBox(
                          width: 12),
                      Expanded(
                          child: _statCard(
                              'Videos',
                              '$_videosWatched',
                              Icons
                                  .play_circle_outline)),
                    ],
                  ),
                  const SizedBox(
                      height: 12),
                  _statCard(
                      'Top channel',
                      _topCategory,
                      Icons
                          .star_outline),
                  const SizedBox(
                      height: 20),
                  Text('Daily watch time',
                      style: AppTheme.subtitle
                          .copyWith(
                              fontWeight:
                                  FontWeight
                                      .bold)),
                  const SizedBox(
                      height: 12),
                  SizedBox(
                    height: 220,
                    child: Card(
                      color: AppTheme.card,
                      child: Padding(
                        padding:
                            const EdgeInsets
                                .all(16),
                        child: BarChart(
                          BarChartData(
                            gridData:
                                const FlGridData(
                                    show:
                                        false),
                            titlesData:
                                FlTitlesData(
                              bottomTitles:
                                  AxisTitles(
                                sideTitles:
                                    SideTitles(
                                  showTitles:
                                      true,
                                  getTitlesWidget:
                                      (v, _) {
                                    const days = [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S'
                                    ];
                                    final i = v
                                        .toInt();
                                    if (i >=
                                            0 &&
                                        i <
                                            7) {
                                      return Text(
                                          days[
                                              i],
                                          style: AppTheme
                                              .caption
                                              .copyWith(
                                                  color:
                                                      AppTheme.textSecondary));
                                    }
                                    return const Text(
                                        '');
                                  },
                                ),
                              ),
                              leftTitles:
                                  const AxisTitles(
                                      sideTitles:
                                          SideTitles(
                                              showTitles:
                                                  false)),
                              topTitles:
                                  const AxisTitles(
                                      sideTitles:
                                          SideTitles(
                                              showTitles:
                                                  false)),
                              rightTitles:
                                  const AxisTitles(
                                      sideTitles:
                                          SideTitles(
                                              showTitles:
                                                  false)),
                            ),
                            borderData:
                                FlBorderData(
                                    show:
                                        false),
                            barGroups:
                                List.generate(
                                    7, (i) {
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY:
                                        _dailyMinutes[i],
                                    gradient: AppTheme
                                        .premiumGradient,
                                    width: 18,
                                    borderRadius:
                                        BorderRadius.circular(
                                            4),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      'Minutes per day (last 7 days)',
                      textAlign:
                          TextAlign.center,
                      style: AppTheme.caption
                          .copyWith(
                              color: AppTheme
                                  .textSecondary)),
                ],
              ),
            ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon) {
    return Card(
      color: AppTheme.card,
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: AppTheme.primary,
                size: 24),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: AppTheme.title
                    .copyWith(fontSize: 20)),
            const SizedBox(height: 4),
            Text(label,
                style:
                    AppTheme.caption.copyWith(
                        color: AppTheme
                            .textSecondary)),
          ],
        ),
      ),
    );
  }
}
