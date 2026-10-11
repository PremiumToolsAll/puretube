import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../../core/database/hive_setup.dart';
import '../../domain/entities/library_models.dart';

Map<String, dynamic> _asMap(Object? e) =>
    Map<String, dynamic>.from(e as Map);

class HistoryRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.history);

  Future<void> record(HistoryEntry entry) =>
      _box.put(entry.videoId, entry.toJson());

  Future<void> updatePosition(
      String videoId, int positionSecs) async {
    final raw = _box.get(videoId);
    if (raw == null) return;
    final entry = HistoryEntry.fromJson(_asMap(raw));
    await _box.put(
        videoId,
        entry
            .copyWith(
                positionSecs: positionSecs,
                watchedAt: DateTime.now())
            .toJson());
  }

  List<HistoryEntry> getAll({int limit = 300}) {
    final list = _box.values
        .map((e) => HistoryEntry.fromJson(_asMap(e)))
        .toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return list.take(limit).toList();
  }

  Future<void> remove(String videoId) => _box.delete(videoId);
  Future<void> clear() => _box.clear();
}

class BookmarkRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.bookmarks);

  bool isBookmarked(String videoId) =>
      _box.containsKey(videoId);

  Future<void> toggle(BookmarkEntry entry) async {
    if (isBookmarked(entry.videoId)) {
      await _box.delete(entry.videoId);
    } else {
      await _box.put(entry.videoId, entry.toJson());
    }
  }

  Future<void> remove(String videoId) =>
      _box.delete(videoId);

  List<BookmarkEntry> getAll() {
    final list = _box.values
        .map((e) => BookmarkEntry.fromJson(_asMap(e)))
        .toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return list;
  }
}

class PlaylistRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.playlists);

  List<Playlist> getAll() {
    final list = _box.values
        .map((e) => Playlist.fromJson(_asMap(e)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<Playlist> create(String name) async {
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      createdAt: DateTime.now(),
    );
    await _box.put(playlist.id, playlist.toJson());
    return playlist;
  }

  Future<void> delete(String id) => _box.delete(id);

  /// Returns false when the video is already in the playlist.
  Future<bool> addVideo(
      String playlistId, PlaylistItem item) async {
    final raw = _box.get(playlistId);
    if (raw == null) return false;
    final p = Playlist.fromJson(_asMap(raw));
    if (p.items.any((e) => e.videoId == item.videoId)) {
      return false;
    }
    await _box.put(playlistId,
        p.copyWith(items: [...p.items, item]).toJson());
    return true;
  }

  Future<void> removeVideo(
      String playlistId, String videoId) async {
    final raw = _box.get(playlistId);
    if (raw == null) return;
    final p = Playlist.fromJson(_asMap(raw));
    await _box.put(
        playlistId,
        p
            .copyWith(
                items: p.items
                    .where((e) => e.videoId != videoId)
                    .toList())
            .toJson());
  }
}

class DownloadRepository {
  Box<Map> get _box => Hive.box<Map>(HiveBoxes.downloads);

  Future<void> save(DownloadRecord record) =>
      _box.put(record.id, record.toJson());

  Future<void> delete(String id) => _box.delete(id);

  Map<String, DownloadRecord> getAllAsMap() => {
        for (final e in _box.toMap().entries)
          e.key as String:
              DownloadRecord.fromJson(_asMap(e.value)),
      };
}

class SubscriptionRepository {
  Box<Map> get _box =>
      Hive.box<Map>(HiveBoxes.subscriptions);

  bool isSubscribed(String channelId) =>
      _box.containsKey(channelId);

  Future<void> subscribe(
      {required String channelId,
      required String name,
      int? subscriberCount}) async {
    await _box.put(channelId, {
      'channelId': channelId,
      'name': name,
      'subscriberCount': subscriberCount,
      'subscribedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> unsubscribe(String channelId) =>
      _box.delete(channelId);

  List<Map<String, dynamic>> getAll() => _box.values
      .map((e) => _asMap(e))
      .toList();
}
