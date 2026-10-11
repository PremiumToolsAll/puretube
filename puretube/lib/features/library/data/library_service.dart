import 'library_database.dart';
import 'library_models.dart';

export 'library_models.dart';

/// Unified library service — facade over [LibraryDatabase].
/// All data persists in Isar across app restarts.
class LibraryService {
  LibraryService._();
  static final LibraryService instance =
      LibraryService._();

  final _db = LibraryDatabase.instance;

  // ── History ───────────────────────────────────────────────
  Future<void> addHistory({
    required String videoId,
    required String title,
    required String author,
    required String thumbnailUrl,
    int positionSeconds = 0,
    int durationSeconds = 0,
  }) =>
      _db.addHistory(
        videoId: videoId,
        title: title,
        author: author,
        thumbnailUrl: thumbnailUrl,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
      );

  Future<List<HistoryEntry>> getHistory(
          {String query = ''}) =>
      _db.getHistory(query: query);

  Future<void> removeHistory(String videoId) =>
      _db.removeHistory(videoId);

  Future<void> clearHistory() =>
      _db.clearHistory();

  Future<int> pruneHistory(int days) =>
      _db.pruneHistory(days);

  // ── Playlists ─────────────────────────────────────────────
  Future<List<Playlist>> getPlaylists() =>
      _db.getPlaylists();

  Future<Playlist> createPlaylist(
          String name, String description) =>
      _db.createPlaylist(name, description);

  Future<void> renamePlaylist(
          int id, String name) =>
      _db.renamePlaylist(id, name);

  Future<void> deletePlaylist(int id) =>
      _db.deletePlaylist(id);

  Future<void> addToPlaylist(
          int playlistId, String videoId) =>
      _db.addToPlaylist(playlistId, videoId);

  Future<void> removeFromPlaylist(
          int playlistId, String videoId) =>
      _db.removeFromPlaylist(
          playlistId, videoId);

  Future<void> reorderPlaylist(
          int playlistId, List<String> videoIds) =>
      _db.reorderPlaylist(playlistId, videoIds);

  // ── Subscriptions ─────────────────────────────────────────
  Future<List<Subscription>> getSubscriptions() =>
      _db.getSubscriptions();

  Future<bool> isSubscribed(
          String channelId) =>
      _db.isSubscribed(channelId);

  Future<void> subscribe({
    required String channelId,
    required String name,
    String avatarUrl = '',
    int subscriberCount = 0,
    String folder = '',
  }) =>
      _db.subscribe(
        channelId: channelId,
        name: name,
        avatarUrl: avatarUrl,
        subscriberCount: subscriberCount,
        folder: folder,
      );

  Future<void> unsubscribe(
          String channelId) =>
      _db.unsubscribe(channelId);

  // ── Saved ─────────────────────────────────────────────────
  Future<List<SavedVideo>> getSaved() =>
      _db.getSaved();

  Future<bool> isSaved(String videoId) =>
      _db.isSaved(videoId);

  Future<void> saveVideo({
    required String videoId,
    required String title,
    required String author,
    required String thumbnailUrl,
    String note = '',
  }) =>
      _db.saveVideo(
        videoId: videoId,
        title: title,
        author: author,
        thumbnailUrl: thumbnailUrl,
        note: note,
      );

  Future<void> unsaveVideo(String videoId) =>
      _db.unsaveVideo(videoId);
}
