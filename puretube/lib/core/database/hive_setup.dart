import 'package:hive_ce_flutter/hive_flutter.dart';

class HiveBoxes {
  static const history = 'history';
  static const bookmarks = 'bookmarks';
  static const playlists = 'playlists';
  static const downloads = 'downloads';
  static const subscriptions = 'subscriptions';
}

/// Stored as plain JSON maps: no build_runner codegen, readable schema.
Future<void> initHive() async {
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox<Map>(HiveBoxes.history),
    Hive.openBox<Map>(HiveBoxes.bookmarks),
    Hive.openBox<Map>(HiveBoxes.playlists),
    Hive.openBox<Map>(HiveBoxes.downloads),
    Hive.openBox<Map>(HiveBoxes.subscriptions),
  ]);
}
