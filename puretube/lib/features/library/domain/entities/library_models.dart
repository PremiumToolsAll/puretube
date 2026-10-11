class HistoryEntry {
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final int? durationSecs;
  final int positionSecs;
  final DateTime watchedAt;

  const HistoryEntry({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    this.durationSecs,
    this.positionSecs = 0,
    required this.watchedAt,
  });

  HistoryEntry copyWith({int? positionSecs, DateTime? watchedAt}) =>
      HistoryEntry(
        videoId: videoId,
        title: title,
        author: author,
        thumbnailUrl: thumbnailUrl,
        durationSecs: durationSecs,
        positionSecs: positionSecs ?? this.positionSecs,
        watchedAt: watchedAt ?? this.watchedAt,
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'durationSecs': durationSecs,
        'positionSecs': positionSecs,
        'watchedAt': watchedAt.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) =>
      HistoryEntry(
        videoId: j['videoId'] as String,
        title: j['title'] as String? ?? '',
        author: j['author'] as String? ?? '',
        thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
        durationSecs: j['durationSecs'] as int?,
        positionSecs: j['positionSecs'] as int? ?? 0,
        watchedAt:
            DateTime.tryParse(j['watchedAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

class BookmarkEntry {
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final DateTime savedAt;

  const BookmarkEntry({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'savedAt': savedAt.toIso8601String(),
      };

  factory BookmarkEntry.fromJson(Map<String, dynamic> j) =>
      BookmarkEntry(
        videoId: j['videoId'] as String,
        title: j['title'] as String? ?? '',
        author: j['author'] as String? ?? '',
        thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
        savedAt: DateTime.tryParse(
                j['savedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class PlaylistItem {
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final DateTime addedAt;

  const PlaylistItem({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'addedAt': addedAt.toIso8601String(),
      };

  factory PlaylistItem.fromJson(Map<String, dynamic> j) =>
      PlaylistItem(
        videoId: j['videoId'] as String,
        title: j['title'] as String? ?? '',
        author: j['author'] as String? ?? '',
        thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
        addedAt: DateTime.tryParse(
                j['addedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class Playlist {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<PlaylistItem> items;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.items = const [],
  });

  Playlist copyWith({String? name, List<PlaylistItem>? items}) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        items: items ?? this.items,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Playlist',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                DateTime.now(),
        items: ((j['items'] as List?) ?? [])
            .map((e) => PlaylistItem.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  canceled
}

class DownloadRecord {
  final String id;
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String qualityLabel;
  final bool audioOnly;
  final String filePath;
  final int? totalBytes;
  final DownloadStatus status;
  final double progress;
  final String? error;
  final DateTime createdAt;

  const DownloadRecord({
    required this.id,
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.qualityLabel,
    required this.audioOnly,
    required this.filePath,
    this.totalBytes,
    required this.status,
    this.progress = 0,
    this.error,
    required this.createdAt,
  });

  DownloadRecord copyWith({
    DownloadStatus? status,
    double? progress,
    String? error,
    int? totalBytes,
  }) =>
      DownloadRecord(
        id: id,
        videoId: videoId,
        title: title,
        author: author,
        thumbnailUrl: thumbnailUrl,
        qualityLabel: qualityLabel,
        audioOnly: audioOnly,
        filePath: filePath,
        totalBytes: totalBytes ?? this.totalBytes,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        error: error,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'videoId': videoId,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'qualityLabel': qualityLabel,
        'audioOnly': audioOnly,
        'filePath': filePath,
        'totalBytes': totalBytes,
        'status': status.name,
        'progress': progress,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> j) {
    DownloadStatus status;
    try {
      status = DownloadStatus.values.byName(j['status'] as String);
    } catch (_) {
      status = DownloadStatus.failed;
    }
    return DownloadRecord(
      id: j['id'] as String,
      videoId: j['videoId'] as String,
      title: j['title'] as String? ?? '',
      author: j['author'] as String? ?? '',
      thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
      qualityLabel: j['qualityLabel'] as String? ?? '',
      audioOnly: j['audioOnly'] as bool? ?? false,
      filePath: j['filePath'] as String? ?? '',
      totalBytes: j['totalBytes'] as int?,
      status: status,
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}
