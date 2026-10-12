import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Simple category detection + tracking for personalized suggestions.
///
/// Detects a category from a video title (waz, gazal, music, movie, …),
/// records watch counts in SharedPreferences, and exposes the user's
/// top categories so Up Next and the home feed can boost them.
class WatchCategoryTracker {
  static const _prefsKey = 'watch_categories_v1';
  static const _maxCount = 200;

  /// Category -> trigger keywords, matched against the lowercased title.
  /// Insertion order is the detection priority (most specific first).
  static const Map<String, List<String>> categoryKeywords = {
    'waz': ['waz', 'ওয়াজ', 'waaz', 'mahfil', 'মাহফিল', 'khutba'],
    'gazal': ['gazal', 'গজল', 'gojol', 'ghazal', 'naat', 'নাত', 'hamd'],
    'music': [
      'song',
      'গান',
      'music',
      'gaan',
      'sangeet',
      'মিউজিক',
      'lyrical',
      'cover song'
    ],
    'movie': [
      'movie',
      'film',
      'natok',
      'নাটক',
      'drama',
      'cinema',
      'trailer',
      'web series'
    ],
    'news': ['news', 'সংবাদ', 'খবর', 'headline'],
    'sports': [
      'cricket',
      'football',
      'sports',
      'খেলা',
      'highlights',
      'match'
    ],
    'comedy': ['comedy', 'funny', 'কমেডি', 'funny video'],
    'cooking': ['recipe', 'cooking', 'রান্না', 'food'],
    'tech': ['tech', 'review', 'unboxing', 'tutorial', 'gadget'],
  };

  /// Returns the first matching category for [title], or null.
  static String? detect(String title) {
    final t = title.toLowerCase();
    for (final entry in categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (t.contains(kw)) return entry.key;
      }
    }
    return null;
  }

  /// Records one watch of a video titled [title]. Safe to fire-and-forget.
  static Future<void> record(String title) async {
    final cat = detect(title);
    if (cat == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _read(prefs);
      map[cat] = ((map[cat] ?? 0) + 1).clamp(0, _maxCount);
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {}
  }

  /// Top [n] categories by watch count, most-watched first.
  static Future<List<String>> top(int n) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _read(prefs);
      final sorted = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(n).map((e) => e.key).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, int> _read(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }
}
