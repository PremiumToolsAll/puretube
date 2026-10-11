import 'package:isar/isar.dart';

part 'download_model.g.dart';

/// Persistent download queue entry (survives app kill).
@collection
class DownloadRecord {
  Id id = Isar.autoIncrement;

  /// flutter_downloader task id (empty until enqueued).
  late String taskId;

  late String videoId;
  late String title;
  late String url;
  late String fileName;
  late String savedDir;
  late String extension;
  late bool isAudio;

  /// queued | downloading | paused | complete | failed | canceled
  late String status;

  late int progress;
  late DateTime createdAt;
  DateTime? completedAt;
}
