import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/channel_logo_service.dart';
import '../services/pip_service.dart';
import '../services/sponsorblock_service.dart';
import '../services/youtube_extractor_service.dart';
import '../services/ytmusic_service.dart';
import '../../features/player/data/services/audio_player_handler.dart';

final extractorProvider = Provider<YoutubeExtractorService>((ref) {
  final service = YoutubeExtractorService();
  ref.onDispose(service.dispose);
  return service;
});

/// Real channel logos (fetched once per channel, cached in Hive).
final channelLogoProvider =
    StateNotifierProvider<ChannelLogoService, Map<String, String>>(
        (ref) => ChannelLogoService(ref.watch(extractorProvider)));

/// YouTube Music search backend for the audio home.
final ytMusicProvider = Provider<YTMusicService>((ref) {
  final service = YTMusicService();
  ref.onDispose(service.dispose);
  return service;
});

final sponsorBlockProvider =
    Provider<SponsorBlockService>((ref) => SponsorBlockService());

final pipServiceProvider = Provider<PipService>((ref) {
  final service = PipService();
  ref.onDispose(service.dispose);
  return service;
});

/// Overridden in main() with the live handler from AudioService.init.
final audioHandlerProvider = Provider<PureTubeAudioHandler>(
  (ref) => throw StateError(
      'audioHandlerProvider must be overridden in main()'),
);
