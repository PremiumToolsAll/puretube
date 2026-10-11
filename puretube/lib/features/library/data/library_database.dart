import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../../search/data/search_history.dart';
import 'library_models.dart';

/// Library database — history, playlists, subscriptions, saved.
class LibraryDatabase {
  LibraryDatabase._();
  static final LibraryDatabase instance =
      LibraryDatabase._();

  Isar? _isar;

  Future<Isar> get isar async {
    if (_isar != null) return _isar!;
    final dir =
        await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        SearchHistoryEntrySchema,
        HistoryEntrySchema,
        PlaylistSchema,
        SubscriptionSchema,
        SavedVideoSchema,
      ],
      directory: dir.path,
      name: 'puretube',
    );
    await _ensureDefaults();
    return _isar!;
  }

  Future<void> _ensureDefaults() async {
    final db = _isar!;
    await db.writeTxn(() async {
      for (final name in [
        'Watch Later',
        'Favorites',
        'Liked Videos'
      ]) {
        final exists = await db.playlists
            .filter()
            .nameEqualTo(name)
            .findFirst();
        if (exists == null) {
          await db.playlists.put(Playlist()
            ..name = name
            ..description = 'Default playlist'
            ..videoIds = []
            ..createdAt = DateTime.now()
            ..updatedAt = DateTime.now());
        }
      }
    });
  }

  // ── History ───────────────────────────────────────────────

  Future<void> addHistory({
    required String videoId,
    required String title,
    required String author,
    required String thumbnailUrl,
    int positionSeconds = 0,
    int durationSeconds = 0,
  }) async {
    final db = await isar;
    await db.writeTxn(() async {
      final existing = await db.historyEntrys
          .filter()
          .videoIdEqualTo(videoId)
          .findFirst();
      if (existing != null) {
        existing
          ..title = title
          ..author = author
          ..thumbnailUrl = thumbnailUrl
          ..positionSeconds = positionSeconds
          ..durationSeconds = durationSeconds
          ..watchedAt = DateTime.now();
        await db.historyEntrys.put(existing);
      } else {
        await db.historyEntrys.put(HistoryEntry()
          ..videoId = videoId
          ..title = title
          ..author = author
          ..thumbnailUrl = thumbnailUrl
          ..positionSeconds = positionSeconds
          ..durationSeconds = durationSeconds
          ..watchedAt = DateTime.now());
      }
    });
  }

  Future<List<HistoryEntry>> getHistory(
      {String query = ''}) async {
    final db = await isar;
    if (query.trim().isEmpty) {
      return db.historyEntrys
          .where()
          .sortByWatchedAtDesc()
          .findAll();
    }
    final q = query.toLowerCase();
    return db.historyEntrys
        .filter()
        .titleContains(q, caseSensitive: false)
        .or()
        .authorContains(q, caseSensitive: false)
        .sortByWatchedAtDesc()
        .findAll();
  }

  Future<void> removeHistory(String videoId) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.historyEntrys
          .filter()
          .videoIdEqualTo(videoId)
          .deleteAll();
    });
  }

  Future<void> clearHistory() async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.historyEntrys.clear();
    });
  }

  /// Delete entries older than [days].
  Future<int> pruneHistory(int days) async {
    final db = await isar;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days));
    int count = 0;
    await db.writeTxn(() async {
      count = await db.historyEntrys
          .filter()
          .watchedAtLessThan(cutoff)
          .deleteAll();
    });
    return count;
  }

  // ── Playlists ─────────────────────────────────────────────

  Future<List<Playlist>> getPlaylists() async {
    final db = await isar;
    return db.playlists
        .where()
        .sortByUpdatedAtDesc()
        .findAll();
  }

  Future<Playlist> createPlaylist(
      String name, String description) async {
    final db = await isar;
    final p = Playlist()
      ..name = name.trim()
      ..description = description.trim()
      ..videoIds = []
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();
    await db.writeTxn(() async {
      await db.playlists.put(p);
    });
    return p;
  }

  Future<void> renamePlaylist(
      Id id, String name) async {
    final db = await isar;
    await db.writeTxn(() async {
      final p =
          await db.playlists.get(id);
      if (p != null) {
        p.name = name.trim();
        p.updatedAt = DateTime.now();
        await db.playlists.put(p);
      }
    });
  }

  Future<void> deletePlaylist(Id id) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.playlists.delete(id);
    });
  }

  Future<void> addToPlaylist(
      Id playlistId, String videoId) async {
    final db = await isar;
    await db.writeTxn(() async {
      final p =
          await db.playlists.get(playlistId);
      if (p != null &&
          !p.videoIds.contains(videoId)) {
        p.videoIds.add(videoId);
        p.updatedAt = DateTime.now();
        await db.playlists.put(p);
      }
    });
  }

  Future<void> removeFromPlaylist(
      Id playlistId, String videoId) async {
    final db = await isar;
    await db.writeTxn(() async {
      final p =
          await db.playlists.get(playlistId);
      if (p != null) {
        p.videoIds.remove(videoId);
        p.updatedAt = DateTime.now();
        await db.playlists.put(p);
      }
    });
  }

  Future<void> reorderPlaylist(
      Id playlistId, List<String> videoIds) async {
    final db = await isar;
    await db.writeTxn(() async {
      final p =
          await db.playlists.get(playlistId);
      if (p != null) {
        p.videoIds = videoIds;
        p.updatedAt = DateTime.now();
        await db.playlists.put(p);
      }
    });
  }

  // ── Subscriptions ─────────────────────────────────────────

  Future<List<Subscription>> getSubscriptions() async {
    final db = await isar;
    return db.subscriptions
        .where()
        .sortBySubscribedAtDesc()
        .findAll();
  }

  Future<bool> isSubscribed(
      String channelId) async {
    final db = await isar;
    final s = await db.subscriptions
        .filter()
        .channelIdEqualTo(channelId)
        .findFirst();
    return s != null;
  }

  Future<void> subscribe({
    required String channelId,
    required String name,
    String avatarUrl = '',
    int subscriberCount = 0,
    String folder = '',
  }) async {
    final db = await isar;
    await db.writeTxn(() async {
      final existing = await db.subscriptions
          .filter()
          .channelIdEqualTo(channelId)
          .findFirst();
      if (existing == null) {
        await db.subscriptions.put(Subscription()
          ..channelId = channelId
          ..name = name
          ..avatarUrl = avatarUrl
          ..subscriberCount = subscriberCount
          ..folder = folder
          ..notificationsEnabled = false
          ..subscribedAt = DateTime.now());
      }
    });
  }

  Future<void> unsubscribe(
      String channelId) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.subscriptions
          .filter()
          .channelIdEqualTo(channelId)
          .deleteAll();
    });
  }

  Future<void> setSubscriptionFolder(
      String channelId, String folder) async {
    final db = await isar;
    await db.writeTxn(() async {
      final s = await db.subscriptions
          .filter()
          .channelIdEqualTo(channelId)
          .findFirst();
      if (s != null) {
        s.folder = folder;
        await db.subscriptions.put(s);
      }
    });
  }

  // ── Saved ─────────────────────────────────────────────────

  Future<List<SavedVideo>> getSaved() async {
    final db = await isar;
    return db.savedVideos
        .where()
        .sortBySavedAtDesc()
        .findAll();
  }

  Future<bool> isSaved(String videoId) async {
    final db = await isar;
    final s = await db.savedVideos
        .filter()
        .videoIdEqualTo(videoId)
        .findFirst();
    return s != null;
  }

  Future<void> saveVideo({
    required String videoId,
    required String title,
    required String author,
    required String thumbnailUrl,
    String note = '',
  }) async {
    final db = await isar;
    await db.writeTxn(() async {
      final existing = await db.savedVideos
          .filter()
          .videoIdEqualTo(videoId)
          .findFirst();
      if (existing == null) {
        await db.savedVideos.put(SavedVideo()
          ..videoId = videoId
          ..title = title
          ..author = author
          ..thumbnailUrl = thumbnailUrl
          ..note = note
          ..savedAt = DateTime.now());
      }
    });
  }

  Future<void> unsaveVideo(String videoId) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.savedVideos
          .filter()
          .videoIdEqualTo(videoId)
          .deleteAll();
    });
  }

  Future<void> setSavedNote(
      String videoId, String note) async {
    final db = await isar;
    await db.writeTxn(() async {
      final s = await db.savedVideos
          .filter()
          .videoIdEqualTo(videoId)
          .findFirst();
      if (s != null) {
        s.note = note;
        await db.savedVideos.put(s);
      }
    });
  }
}
