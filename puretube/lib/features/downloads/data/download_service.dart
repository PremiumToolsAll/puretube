import 'dart:async';
import 'dart:io';

import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/file_utils.dart';
import '../../../core/utils/permission_utils.dart';
import 'download_model.dart';

/// PureTube download service:
/// - flutter_downloader for background transfers
/// - Isar-persisted queue (survives app kill, resumes on restart)
/// - flutter_local_notifications for progress + completion
class DownloadService {
  DownloadService._();
  static final DownloadService instance =
      DownloadService._();

  bool _initialized = false;
  Isar? _isar;

  final _notifications =
      FlutterLocalNotificationsPlugin();

  final _queueCtrl = StreamController<
      List<DownloadRecord>>.broadcast();
  Stream<List<DownloadRecord>> get queueStream =>
      _queueCtrl.stream;

  Future<Isar> get _db async {
    if (_isar != null) return _isar!;
    final dir =
        await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [DownloadRecordSchema],
      directory: dir.path,
      name: 'puretube_downloads',
    );
    return _isar!;
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      await FlutterDownloader.initialize(
          debug: false, ignoreSsl: false);
      FlutterDownloader.registerCallback(
          _downloadCallback,
          step: 1);
    } catch (_) {}
    try {
      const settings =
          InitializationSettings(
        android: AndroidInitializationSettings(
            '@mipmap/ic_launcher'),
      );
      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse:
            _onNotificationTap,
      );
      const channel =
          AndroidNotificationChannel(
        'puretube_downloads',
        'Downloads',
        description:
            'Download progress notifications',
        importance: Importance.low,
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (_) {}
    _initialized = true;
    // Resume interrupted downloads.
    await _resumeInterrupted();
  }

  @pragma('vm:entry-point')
  static void _downloadCallback(
      String id, int status, int progress) {}

  void _onNotificationTap(
      NotificationResponse r) {}

  // ── Queue persistence ─────────────────────────────────────

  Future<List<DownloadRecord>> getQueue() async {
    final db = await _db;
    return db.downloadRecords
        .where()
        .sortByCreatedAtDesc()
        .findAll();
  }

  Future<void> _emit() async {
    try {
      _queueCtrl.add(await getQueue());
    } catch (_) {}
  }

  /// Re-enqueue downloads that were active when the app died.
  Future<void> _resumeInterrupted() async {
    try {
      final db = await _db;
      final stuck = await db.downloadRecords
          .filter()
          .statusEqualTo('downloading')
          .findAll();
      await db.writeTxn(() async {
        for (final r in stuck) {
          r.status = 'queued';
          await db.downloadRecords.put(r);
        }
      });
      await _emit();
      // Kick the queue.
      _pumpQueue();
    } catch (_) {}
  }

  // ── Enqueue ───────────────────────────────────────────────

  /// Add a download. [startNow]=false just queues it.
  Future<DownloadRecord?> enqueue({
    required String videoId,
    required String title,
    required String url,
    required bool isAudio,
    required String extension,
    String? qualityLabel,
    String folder = 'Videos',
    bool startNow = true,
  }) async {
    try {
      await init();
      if (!await PermissionUtils
          .ensureStorage()) {
        return null;
      }

      final dir = isAudio
          ? await FileUtils.audioDir()
          : (folder == 'Music'
              ? await FileUtils.audioDir()
              : folder == 'Custom'
                  ? await FileUtils.customDir(
                      'Downloads')
                  : await FileUtils.videoDir());

      final safeTitle =
          FileUtils.safeName(title);
      final fileName =
          '$safeTitle${qualityLabel != null ? ' [$qualityLabel]' : ''}.$extension';

      final db = await _db;
      final record = DownloadRecord()
        ..taskId = ''
        ..videoId = videoId
        ..title = title
        ..url = url
        ..fileName = fileName
        ..savedDir = dir.path
        ..extension = extension
        ..isAudio = isAudio
        ..status =
            startNow ? 'queued' : 'paused'
        ..progress = 0
        ..createdAt = DateTime.now();

      await db.writeTxn(() async {
        await db.downloadRecords.put(record);
      });
      await _emit();
      if (startNow) _pumpQueue();
      return record;
    } catch (_) {
      return null;
    }
  }

  /// Start up to 3 queued downloads.
  Future<void> _pumpQueue() async {
    try {
      final db = await _db;
      final active = await db.downloadRecords
          .filter()
          .statusEqualTo('downloading')
          .count();
      if (active >= 3) return;

      final next = await db.downloadRecords
          .filter()
          .statusEqualTo('queued')
          .sortByCreatedAt()
          .limit(3 - active)
          .findAll();

      for (final r in next) {
        await _startTask(r);
      }
      await _emit();
    } catch (_) {}
  }

  Future<void> _startTask(
      DownloadRecord r) async {
    final db = await _db;
    try {
      final taskId =
          await FlutterDownloader.enqueue(
        url: r.url,
        savedDir: r.savedDir,
        fileName: r.fileName,
        showNotification: true,
        openFileFromNotification: true,
      );
      if (taskId == null) {
        await db.writeTxn(() async {
          r.status = 'failed';
          await db.downloadRecords.put(r);
        });
        return;
      }
      await db.writeTxn(() async {
        r.taskId = taskId;
        r.status = 'downloading';
        await db.downloadRecords.put(r);
      });
      _watchTask(r.id, taskId);
    } catch (_) {
      await db.writeTxn(() async {
        r.status = 'failed';
        await db.downloadRecords.put(r);
      });
    }
  }

  /// Poll native task state and mirror into Isar + notification.
  void _watchTask(int recordId, String taskId) {
    Timer.periodic(
        const Duration(seconds: 2),
        (timer) async {
      try {
        final tasks =
            await FlutterDownloader.loadTasksWithRawQuery(
          query:
              "SELECT * FROM task WHERE task_id='$taskId'",
        );
        if (tasks == null || tasks.isEmpty) {
          timer.cancel();
          return;
        }
        final t = tasks.first;
        final db = await _db;
        final r =
            await db.downloadRecords.get(recordId);
        if (r == null) {
          timer.cancel();
          return;
        }
        await db.writeTxn(() async {
          r.progress = t.progress;
          switch (t.status) {
            case DownloadTaskStatus.complete:
              r.status = 'complete';
              r.completedAt = DateTime.now();
              break;
            case DownloadTaskStatus.failed:
              r.status = 'failed';
              break;
            case DownloadTaskStatus.canceled:
              r.status = 'canceled';
              break;
            case DownloadTaskStatus.paused:
              r.status = 'paused';
              break;
            default:
              r.status = 'downloading';
          }
          await db.downloadRecords.put(r);
        });
        await _emit();
        await _notifyProgress(r);

        if (t.status ==
                DownloadTaskStatus.complete ||
            t.status ==
                DownloadTaskStatus.failed ||
            t.status ==
                DownloadTaskStatus.canceled) {
          timer.cancel();
          if (t.status ==
              DownloadTaskStatus.complete) {
            await _notifyComplete(r);
          }
          _pumpQueue();
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  // ── Controls ──────────────────────────────────────────────

  Future<void> pauseDownload(int recordId) async {
    try {
      final db = await _db;
      final r =
          await db.downloadRecords.get(recordId);
      if (r == null || r.taskId.isEmpty) {
        // Not started yet — just mark paused.
        if (r != null) {
          await db.writeTxn(() async {
            r.status = 'paused';
            await db.downloadRecords.put(r);
          });
          await _emit();
        }
        return;
      }
      await FlutterDownloader.pause(
          taskId: r.taskId);
      await db.writeTxn(() async {
        r.status = 'paused';
        await db.downloadRecords.put(r);
      });
      await _emit();
    } catch (_) {}
  }

  Future<void> resumeDownload(int recordId) async {
    try {
      final db = await _db;
      final r =
          await db.downloadRecords.get(recordId);
      if (r == null) return;
      if (r.taskId.isEmpty) {
        // Never started — queue it.
        await db.writeTxn(() async {
          r.status = 'queued';
          await db.downloadRecords.put(r);
        });
        await _emit();
        _pumpQueue();
        return;
      }
      final newId =
          await FlutterDownloader.resume(
              taskId: r.taskId);
      await db.writeTxn(() async {
        if (newId != null) r.taskId = newId;
        r.status = 'downloading';
        await db.downloadRecords.put(r);
      });
      await _emit();
      if (newId != null) {
        _watchTask(r.id, newId);
      }
    } catch (_) {}
  }

  Future<void> cancelDownload(int recordId) async {
    try {
      final db = await _db;
      final r =
          await db.downloadRecords.get(recordId);
      if (r == null) return;
      if (r.taskId.isNotEmpty) {
        await FlutterDownloader.cancel(
            taskId: r.taskId);
      }
      await db.writeTxn(() async {
        r.status = 'canceled';
        await db.downloadRecords.put(r);
      });
      await _emit();
      _pumpQueue();
    } catch (_) {}
  }

  Future<void> retryDownload(int recordId) async {
    try {
      final db = await _db;
      final r =
          await db.downloadRecords.get(recordId);
      if (r == null) return;
      await db.writeTxn(() async {
        r.status = 'queued';
        r.progress = 0;
        r.taskId = '';
        await db.downloadRecords.put(r);
      });
      await _emit();
      _pumpQueue();
    } catch (_) {}
  }

  Future<void> removeRecord(int recordId,
      {bool deleteFile = false}) async {
    try {
      final db = await _db;
      final r =
          await db.downloadRecords.get(recordId);
      if (r == null) return;
      if (r.taskId.isNotEmpty) {
        await FlutterDownloader.remove(
          taskId: r.taskId,
          shouldDeleteContent: deleteFile,
        );
      }
      if (deleteFile) {
        try {
          final f = File(
              '${r.savedDir}/${r.fileName}');
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
      await db.writeTxn(() async {
        await db.downloadRecords
            .delete(recordId);
      });
      await _emit();
    } catch (_) {}
  }

  // ── Notifications ─────────────────────────────────────────

  Future<void> _notifyProgress(
      DownloadRecord r) async {
    try {
      await _notifications.show(
        r.id,
        'Downloading',
        '${r.title} — ${r.progress}%',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'puretube_downloads',
            'Downloads',
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: r.progress,
            onlyAlertOnce: true,
            ongoing: true,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _notifyComplete(
      DownloadRecord r) async {
    try {
      await _notifications.cancel(r.id);
      await _notifications.show(
        r.id + 100000,
        'Download complete',
        r.fileName,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'puretube_downloads',
            'Downloads',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        payload: '${r.savedDir}/${r.fileName}',
      );
    } catch (_) {}
  }

  // ── Downloaded files ──────────────────────────────────────

  Future<List<DownloadedFile>> listDownloaded(
      bool audio) async {
    try {
      final dir = audio
          ? await FileUtils.audioDir()
          : await FileUtils.videoDir();
      if (!await dir.exists()) return [];
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final out = <DownloadedFile>[];
      for (final f in files) {
        try {
          final stat = await f.stat();
          out.add(DownloadedFile(
            path: f.path,
            name: FileUtils.basename(f.path),
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {}
      }
      out.sort((a, b) =>
          b.modified.compareTo(a.modified));
      return out;
    } catch (_) {
      return [];
    }
  }

  void dispose() => _queueCtrl.close();
}

class DownloadedFile {
  final String path;
  final String name;
  final int size;
  final DateTime modified;

  const DownloadedFile({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  String get sizeLabel =>
      FileUtils.sizeLabel(size);
}
