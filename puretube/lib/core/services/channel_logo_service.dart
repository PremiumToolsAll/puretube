import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../database/hive_setup.dart';
import 'youtube_extractor_service.dart';

/// Real channel logos for cards and rows.
///
/// Video/search results carry only the channel id + name — no
/// avatar — so logos are fetched once per channel through the
/// extractor's channel call and cached forever (memory + Hive):
/// a channel's logo effectively never changes, so repeat feeds
/// cost zero network. Cards show the letter avatar until the
/// logo lands, then swap in the real image.
class ChannelLogoService extends StateNotifier<Map<String, String>> {
  ChannelLogoService(this._extractor) : super(const {}) {
    _restore();
  }

  final YoutubeExtractorService _extractor;
  final Set<String> _inFlight = {};
  static const _key = 'channel_logos_v1';

  Box get _box => Hive.box(HiveBoxes.playerPrefs);

  void _restore() {
    try {
      final raw = _box.get(_key);
      if (raw is Map) {
        state = raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
  }

  String? logoFor(String channelId) => state[channelId];

  /// Fetches (once) and caches the logo for [channelId].
  /// Safe to call from build methods: in-flight and cached ids
  /// return immediately, and state only changes asynchronously.
  Future<void> ensure(String channelId) async {
    if (channelId.isEmpty ||
        state.containsKey(channelId) ||
        !_inFlight.add(channelId)) {
      return;
    }
    try {
      final info = await _extractor.getChannel(channelId);
      if (info.logoUrl.isNotEmpty) {
        state = {...state, channelId: info.logoUrl};
        try {
          await _box.put(_key, state);
        } catch (_) {}
      }
    } catch (_) {
      // Offline / rate-limited: the letter avatar stays; a
      // later build call retries.
    } finally {
      _inFlight.remove(channelId);
    }
  }

  void ensureAll(Iterable<String> channelIds) {
    for (final id in channelIds) {
      unawaited(ensure(id));
    }
  }
}
