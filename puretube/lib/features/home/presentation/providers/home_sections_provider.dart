import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../player/domain/entities/playback_models.dart';

/// One home-feed section: a Bengali header plus its items.
class HomeSection {
  final String header;
  final List<VideoDetails> items;
  final bool loading;

  const HomeSection({
    required this.header,
    this.items = const [],
    this.loading = false,
  });

  HomeSection copyWith({List<VideoDetails>? items, bool? loading}) =>
      HomeSection(
        header: header,
        items: items ?? this.items,
        loading: loading ?? this.loading,
      );
}

class HomeSectionsState {
  final List<HomeSection> audio;
  final List<HomeSection> video;

  const HomeSectionsState({
    this.audio = const [],
    this.video = const [],
  });

  HomeSectionsState copyWith({
    List<HomeSection>? audio,
    List<HomeSection>? video,
  }) =>
      HomeSectionsState(
        audio: audio ?? this.audio,
        video: video ?? this.video,
      );
}

/// Section definitions: Bengali header + per-mode search query.
///
/// Audio mode uses YouTube Music song search — except waz, which isn't on
/// YouTube Music: those come from regular YouTube search and play through
/// the existing video-ID audio path (playAudioOnly).
/// Video mode uses regular YouTube search for all four.
class _SectionDef {
  final String header;
  final String audioQuery;
  final bool audioViaYtm;
  final String videoQuery;

  const _SectionDef({
    required this.header,
    required this.audioQuery,
    required this.videoQuery,
    this.audioViaYtm = true,
  });
}

const _defs = <_SectionDef>[
  _SectionDef(
    header: 'বাংলা গান',
    audioQuery: 'bangla gaan',
    videoQuery: 'bangla gaan',
  ),
  _SectionDef(
    header: 'হিন্দি গান',
    audioQuery: 'hindi songs',
    videoQuery: 'hindi video songs',
  ),
  _SectionDef(
    header: 'গজল',
    audioQuery: 'ghazal',
    videoQuery: 'ghazal songs',
  ),
  _SectionDef(
    header: 'ওয়াজ',
    audioQuery: 'bangla waz',
    audioViaYtm: false,
    videoQuery: 'bangla waz mahfil',
  ),
];

class HomeSectionsController
    extends StateNotifier<HomeSectionsState> {
  HomeSectionsController(this._ref)
      : super(HomeSectionsState(
          audio: _defs
              .map((d) =>
                  HomeSection(header: d.header, loading: true))
              .toList(),
          video: _defs
              .map((d) =>
                  HomeSection(header: d.header, loading: true))
              .toList(),
        ));

  final Ref _ref;
  bool _audioBusy = false;
  bool _videoBusy = false;
  bool _audioDone = false;
  bool _videoDone = false;

  static const _perSection = 12;

  Future<List<VideoDetails>> _fetchAudio(_SectionDef def) async {
    if (def.audioViaYtm) {
      try {
        final page = await _ref
            .read(ytMusicProvider)
            .searchSongs(def.audioQuery, limit: _perSection);
        if (page.songs.isNotEmpty) return page.songs;
      } catch (_) {}
    }
    // Fallback — and the waz path: regular YouTube search. Results
    // carry plain YouTube video IDs, so the audio home plays them
    // through the existing playAudioOnly(videoId) path.
    try {
      return await _ref
          .read(extractorProvider)
          .searchVideos(def.audioQuery, limit: _perSection);
    } catch (_) {
      return const [];
    }
  }

  Future<List<VideoDetails>> _fetchVideo(_SectionDef def) async {
    try {
      return await _ref
          .read(extractorProvider)
          .searchVideos(def.videoQuery, limit: _perSection);
    } catch (_) {
      return const [];
    }
  }

  /// Loads the four audio-mode sections once; each section appears as
  /// its query lands (progressive, like the music feed batches).
  Future<void> loadAudio() async {
    if (_audioDone || _audioBusy) return;
    _audioBusy = true;
    final out = state.audio.toList();
    for (var i = 0; i < _defs.length; i++) {
      final items = await _fetchAudio(_defs[i]);
      out[i] = out[i].copyWith(items: items, loading: false);
      state = state.copyWith(audio: List.of(out));
    }
    _audioDone = true;
    _audioBusy = false;
  }

  /// Loads the four video-mode sections once; progressive like audio.
  Future<void> loadVideo() async {
    if (_videoDone || _videoBusy) return;
    _videoBusy = true;
    final out = state.video.toList();
    for (var i = 0; i < _defs.length; i++) {
      final items = await _fetchVideo(_defs[i]);
      out[i] = out[i].copyWith(items: items, loading: false);
      state = state.copyWith(video: List.of(out));
    }
    _videoDone = true;
    _videoBusy = false;
  }

  /// Force-reloads the audio sections (pull-to-refresh in audio home).
  Future<void> refreshAudio() async {
    _audioDone = false;
    if (_audioBusy) return;
    await loadAudio();
  }

  /// Force-reloads the video sections (pull-to-refresh in video home).
  Future<void> refreshVideo() async {
    _videoDone = false;
    if (_videoBusy) return;
    await loadVideo();
  }
}

final homeSectionsProvider = StateNotifierProvider<
    HomeSectionsController, HomeSectionsState>(
  (ref) => HomeSectionsController(ref),
);
