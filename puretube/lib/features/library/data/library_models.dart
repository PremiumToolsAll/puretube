import 'package:isar/isar.dart';

part 'library_models.g.dart';

/// Watched video history entry.
@collection
class HistoryEntry {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String videoId;

  late String title;
  late String author;
  late String thumbnailUrl;

  /// Playback position in seconds when last watched.
  late int positionSeconds;

  /// Total duration in seconds (0 if unknown).
  late int durationSeconds;

  late DateTime watchedAt;
}

/// User-created playlist.
@collection
class Playlist {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String name;

  late String description;
  late List<String> videoIds;
  late DateTime createdAt;
  late DateTime updatedAt;
}

/// Local channel subscription (no Google account).
@collection
class Subscription {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String channelId;

  late String name;
  late String avatarUrl;
  late int subscriberCount;
  late String folder;
  late bool notificationsEnabled;
  late DateTime subscribedAt;
}

/// Bookmarked video (not downloaded).
@collection
class SavedVideo {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String videoId;

  late String title;
  late String author;
  late String thumbnailUrl;
  late String note;
  late DateTime savedAt;
}
