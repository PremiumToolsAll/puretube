import 'package:isar/isar.dart';

part 'search_history.g.dart';

/// A single search history entry.
@collection
class SearchHistoryEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String query;

  late DateTime searchedAt;
}
