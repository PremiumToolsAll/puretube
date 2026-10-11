import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'search_history.dart';

/// Isar database singleton (search history).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Isar? _isar;

  Future<Isar> get isar async {
    if (_isar != null) return _isar!;
    final dir =
        await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [SearchHistoryEntrySchema],
      directory: dir.path,
      name: 'puretube',
    );
    return _isar!;
  }

  Future<List<String>> getHistory(
      {int limit = 20}) async {
    final db = await isar;
    final entries = await db.searchHistoryEntrys
        .where()
        .sortBySearchedAtDesc()
        .limit(limit)
        .findAll();
    return entries.map((e) => e.query).toList();
  }

  Future<void> addQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final db = await isar;
    await db.writeTxn(() async {
      // Replace existing entry to bump it to the top.
      final existing = await db
          .searchHistoryEntrys
          .filter()
          .queryEqualTo(q)
          .findFirst();
      if (existing != null) {
        existing.searchedAt = DateTime.now();
        await db.searchHistoryEntrys
            .put(existing);
      } else {
        await db.searchHistoryEntrys.put(
          SearchHistoryEntry()
            ..query = q
            ..searchedAt = DateTime.now(),
        );
      }
    });
  }

  Future<void> clearHistory() async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.searchHistoryEntrys.clear();
    });
  }

  Future<void> removeQuery(String query) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.searchHistoryEntrys
          .filter()
          .queryEqualTo(query)
          .deleteAll();
    });
  }
}
