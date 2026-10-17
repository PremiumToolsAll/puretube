/// Generates DASH MPD manifests from YouTube stream URLs.
///
/// Based on NewPipe's YoutubeProgressiveDashManifestCreator approach:
/// wraps progressive stream URLs in a DASH manifest so ExoPlayer
/// can play them with adaptive streaming support.
class DashManifestGenerator {
  /// Generates a DASH MPD XML for video+audio streams.
  ///
  /// [videoUrl]: Direct video stream URL
  /// [audioUrl]: Direct audio stream URL
  /// [videoMime]: e.g. 'video/mp4; codecs="avc1.640028"'
  /// [audioMime]: e.g. 'audio/mp4; codecs="mp4a.40.2"'
  /// [videoWidth], [videoHeight]: Video dimensions
  /// [videoBitrate], [audioBitrate]: Bitrates in bits/sec
  /// [durationSec]: Video duration in seconds
  static String generate({
    required String videoUrl,
    required String audioUrl,
    required String videoMime,
    required String audioMime,
    required int videoWidth,
    required int videoHeight,
    required int videoBitrate,
    required int audioBitrate,
    required double durationSec,
  }) {
    final videoCodec = _extractCodec(videoMime);
    final audioCodec = _extractCodec(audioMime);
    final videoContainer = videoMime.contains('webm')
        ? 'video/webm'
        : 'video/mp4';
    final audioContainer = audioMime.contains('webm')
        ? 'audio/webm'
        : 'audio/mp4';

    // Escape URLs for XML.
    final vUrl = _xmlEscape(videoUrl);
    final aUrl = _xmlEscape(audioUrl);

    return '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
     profiles="urn:mpeg:dash:profile:isoff-on-demand:2011"
     type="static"
     mediaPresentationDuration="PT${durationSec.toStringAsFixed(2)}S"
     minBufferTime="PT1.5S">
  <Period duration="PT${durationSec.toStringAsFixed(2)}S">
    <AdaptationSet mimeType="$videoContainer"
                   codecs="$videoCodec"
                   contentType="video">
      <Representation id="v1"
                      bandwidth="$videoBitrate"
                      width="$videoWidth"
                      height="$videoHeight">
        <BaseURL>$vUrl</BaseURL>
        <SegmentBase indexRange="0-0">
          <Initialization range="0-0"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
    <AdaptationSet mimeType="$audioContainer"
                   codecs="$audioCodec"
                   contentType="audio">
      <Representation id="a1"
                      bandwidth="$audioBitrate">
        <BaseURL>$aUrl</BaseURL>
        <SegmentBase indexRange="0-0">
          <Initialization range="0-0"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';
  }

  static String _extractCodec(String mime) {
    final match =
        RegExp(r'codecs="([^"]+)"').firstMatch(mime);
    return match?.group(1) ?? '';
  }

  static String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
