import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

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

/// The single media_kit Player the video UI attaches to.
final mediaKitPlayerProvider =
    Provider<Player>((ref) => ref.watch(audioHandlerProvider).player);
