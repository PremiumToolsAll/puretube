import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File helpers: safe names, PureTube folders, open, size labels.
class FileUtils {
  FileUtils._();

  /// Remove characters illegal in file names.
  static String safeName(String title) {
    return title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String extension(String path) =>
      p.extension(path).replaceFirst('.', '');

  static String basename(String path) =>
      p.basename(path);

  /// Public PureTube/Videos folder (falls back to app dir).
  static Future<Directory> videoDir() async {
    return _dir('Videos');
  }

  static Future<Directory> audioDir() async {
    return _dir('Music');
  }

  static Future<Directory> customDir(
      String name) async {
    return _dir(name);
  }

  static Future<Directory> _dir(
      String sub) async {
    try {
      final dir = Directory(
          '/storage/emulated/0/PureTube/$sub');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      final base =
          await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory();
      final dir =
          Directory('${base.path}/PureTube/$sub');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
  }

  /// Open a file with the system handler.
  static Future<void> open(String path) async {
    try {
      await OpenFile.open(path);
    } catch (_) {}
  }

  static String sizeLabel(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  static bool isVideoFile(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.mp4') ||
        n.endsWith('.mkv') ||
        n.endsWith('.webm') ||
        n.endsWith('.3gp');
  }

  static bool isAudioFile(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.mp3') ||
        n.endsWith('.m4a') ||
        n.endsWith('.opus') ||
        n.endsWith('.ogg') ||
        n.endsWith('.wav');
  }
}
