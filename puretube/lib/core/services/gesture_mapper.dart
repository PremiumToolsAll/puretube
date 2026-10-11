import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

part 'gesture_mapper.g.dart';

/// A single gesture -> action mapping.
@collection
class GestureMapping {
  Id id = Isar.autoIncrement;

  /// e.g. "doubleTapLeft", "swipeUpRight", "longPress"
  @Index(unique: true)
  late String gesture;

  /// e.g. "seek:-10", "volume:+10", "brightness:-10", "speed:2.0", "lock"
  late String action;
}

/// Remappable gestures. Defaults match the classic PureTube behavior.
class GestureMapper {
  GestureMapper._();
  static final GestureMapper instance =
      GestureMapper._();

  Isar? _isar;

  static const defaults = {
    'doubleTapLeft': 'seek:-10',
    'doubleTapRight': 'seek:+10',
    'swipeUpLeft': 'brightness:+10',
    'swipeDownLeft': 'brightness:-10',
    'swipeUpRight': 'volume:+10',
    'swipeDownRight': 'volume:-10',
    'longPress': 'lock',
  };

  /// Human-readable action labels for settings.
  static const actionOptions = [
    'seek:-10',
    'seek:+10',
    'seek:-5',
    'seek:+5',
    'seek:-30',
    'seek:+30',
    'volume:+10',
    'volume:-10',
    'brightness:+10',
    'brightness:-10',
    'speed:2.0',
    'lock',
    'none',
  ];

  static String actionLabel(String action) {
    switch (action) {
      case 'seek:-10':
        return 'Seek -10s';
      case 'seek:+10':
        return 'Seek +10s';
      case 'seek:-5':
        return 'Seek -5s';
      case 'seek:+5':
        return 'Seek +5s';
      case 'seek:-30':
        return 'Seek -30s';
      case 'seek:+30':
        return 'Seek +30s';
      case 'volume:+10':
        return 'Volume up';
      case 'volume:-10':
        return 'Volume down';
      case 'brightness:+10':
        return 'Brightness up';
      case 'brightness:-10':
        return 'Brightness down';
      case 'speed:2.0':
        return '2x speed (hold)';
      case 'lock':
        return 'Lock screen';
      default:
        return 'Do nothing';
    }
  }

  Future<Isar> get _db async {
    if (_isar != null) return _isar!;
    final dir =
        await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [GestureMappingSchema],
      directory: dir.path,
      name: 'puretube',
    );
    await _ensureDefaults();
    return _isar!;
  }

  Future<void> _ensureDefaults() async {
    final db = _isar!;
    await db.writeTxn(() async {
      for (final e in defaults.entries) {
        final exists = await db
            .gestureMappings
            .filter()
            .gestureEqualTo(e.key)
            .findFirst();
        if (exists == null) {
          await db.gestureMappings.put(
            GestureMapping()
              ..gesture = e.key
              ..action = e.value,
          );
        }
      }
    });
  }

  /// Get the action for a gesture (e.g. "seek:-10").
  Future<String> getAction(
      String gesture) async {
    try {
      final db = await _db;
      final m = await db.gestureMappings
          .filter()
          .gestureEqualTo(gesture)
          .findFirst();
      return m?.action ??
          defaults[gesture] ??
          'none';
    } catch (_) {
      return defaults[gesture] ?? 'none';
    }
  }

  Future<Map<String, String>> getAll() async {
    final out =
        Map<String, String>.from(defaults);
    try {
      final db = await _db;
      final list = await db.gestureMappings
          .where()
          .findAll();
      for (final m in list) {
        out[m.gesture] = m.action;
      }
    } catch (_) {}
    return out;
  }

  Future<void> setAction(
      String gesture, String action) async {
    try {
      final db = await _db;
      await db.writeTxn(() async {
        final m = await db.gestureMappings
            .filter()
            .gestureEqualTo(gesture)
            .findFirst();
        if (m != null) {
          m.action = action;
          await db.gestureMappings.put(m);
        } else {
          await db.gestureMappings.put(
            GestureMapping()
              ..gesture = gesture
              ..action = action,
          );
        }
      });
    } catch (_) {}
  }

  Future<void> reset() async {
    try {
      final db = await _db;
      await db.writeTxn(() async {
        await db.gestureMappings.clear();
      });
      await _ensureDefaults();
    } catch (_) {}
  }
}
