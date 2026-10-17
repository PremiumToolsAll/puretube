/// SABR (Server-side Adaptive BitRate) client for YouTube.
/// Streams video+audio directly from YouTube's CDN using their native
/// protocol — the same one the official YouTube app uses.
///
/// Flow:
///   1. InnerTube /player → serverAbrStreamingUrl + ustreamer config
///   2. POST protobuf VideoPlaybackAbrRequest → UMP response
///   3. Parse UMP parts, collect media bytes per format
///   4. Repeat with buffered-range updates until complete
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'sabr_proto.dart';
import 'ump_parser.dart';

/// A downloaded media segment for one format.
/// Supports progressive file writing for true streaming.
class SabrFormatStream {
  final int itag;
  final String mimeType;
  final BytesBuilder initSegment = BytesBuilder();
  final BytesBuilder media = BytesBuilder();
  int maxSequenceNumber = -1;
  int endSegmentNumber = -1;
  bool initReceived = false;

  /// Optional file sink for progressive writing.
  /// When set, media bytes are appended to the file as they arrive.
  IOSink? fileSink;
  bool _initWritten = false;

  SabrFormatStream({required this.itag, required this.mimeType});

  /// Appends payload to the stream (and file if sink is set).
  void addMedia(List<int> payload, {required bool isInit}) {
    if (isInit) {
      initSegment.add(payload);
      initReceived = true;
      // Write init to file first.
      fileSink?.add(initSegment.toBytes());
      _initWritten = true;
    } else {
      // Ensure init is written before media.
      if (!_initWritten && initReceived) {
        fileSink?.add(initSegment.toBytes());
        _initWritten = true;
      }
      media.add(payload);
      fileSink?.add(payload);
    }
  }

  Uint8List toBytes() {
    final out = BytesBuilder();
    out.add(initSegment.toBytes());
    out.add(media.toBytes());
    return out.toBytes();
  }

  Future<void> closeFile() async {
    await fileSink?.flush();
    await fileSink?.close();
    fileSink = null;
  }
}

/// Result of a SABR download: video + audio streams.
class SabrResult {
  final SabrFormatStream video;
  final SabrFormatStream audio;
  SabrResult({required this.video, required this.audio});
}

class SabrClient {
  final HttpClient _client;
  SabrClient({HttpClient? client}) : _client = client ?? HttpClient();

  void dispose() => _client.close(force: true);

  /// Downloads video+audio for [videoId] via SABR.
  ///
  /// [serverAbrStreamingUrl], [ustreamerConfig], and [formats] come from
  /// the InnerTube player response (see YoutubeSessionService).
  /// Each format: {'itag': int, 'mimeType': String, 'bitrate': int,
  ///   'lastModified': int, 'xtags': String}.
  ///
  /// [onProgress] reports (downloadedBytes, totalBytesEstimate).
  Future<SabrResult> download({
    required String serverAbrStreamingUrl,
    required Uint8List ustreamerConfig,
    required Map<String, dynamic> videoFormat,
    required Map<String, dynamic> audioFormat,
    void Function(int downloaded, int? total)? onProgress,
    String? videoFilePath,
    String? audioFilePath,
    void Function()? onReadyToPlay,
    int readyThresholdBytes = 2 * 1024 * 1024,
  }) async {
    final videoItag = videoFormat['itag'] as int;
    final audioItag = audioFormat['itag'] as int;

    final videoStream = SabrFormatStream(
      itag: videoItag,
      mimeType: videoFormat['mimeType'] as String? ?? '',
    );
    final audioStream = SabrFormatStream(
      itag: audioItag,
      mimeType: audioFormat['mimeType'] as String? ?? '',
    );
    final streams = {videoItag: videoStream, audioItag: audioStream};

    // Set up progressive file writing if paths are provided.
    if (videoFilePath != null) {
      videoStream.fileSink =
          File(videoFilePath).openWrite();
    }
    if (audioFilePath != null) {
      audioStream.fileSink =
          File(audioFilePath).openWrite();
    }
    var readyFired = false;

    // header_id -> itag mapping from MEDIA_HEADER parts.
    final headerToItag = <int, int>{};
    // itag -> FormatId bytes for buffered-range reporting.
    Uint8List formatIdOf(Map<String, dynamic> f) => encodeFormatId(
          itag: f['itag'] as int,
          lastModified: (f['lastModified'] as int?) ?? 0,
          xtags: f['xtags'] as String? ?? '',
        );
    final videoFormatId = formatIdOf(videoFormat);
    final audioFormatId = formatIdOf(audioFormat);

    var sabrUrl = serverAbrStreamingUrl;
    var rn = 0;
    Uint8List playbackCookie = Uint8List(0);
    final sabrContexts = <MapEntry<int, Uint8List>>[];
    var backoffMs = 0;
    var downloaded = 0;

    // Track init segments separately: header_id -> isInit.
    final headerIsInit = <int, bool>{};
    final headerSeq = <int, int>{};

    bool isDone() {
      for (final s in streams.values) {
        if (s.endSegmentNumber < 0) return false;
        if (s.maxSequenceNumber < s.endSegmentNumber) return false;
      }
      return true;
    }

    // Safety: max 200 requests, or stop if no new data for 10 requests.
    var noProgressCount = 0;
    var lastDownloaded = 0;
    while (rn < 200 && !isDone()) {
      if (backoffMs > 0) {
        await Future.delayed(Duration(milliseconds: backoffMs));
        backoffMs = 0;
      }

      // Build buffered ranges for formats with progress.
      final ranges = <Uint8List>[];
      for (final entry in streams.entries) {
        final s = entry.value;
        final mediaLen = s.media.length;
        if (mediaLen > 0 || s.initReceived) {
          // Estimate duration: use a rough ms from bytes.
          // Refined via FormatInitializationMetadata when available.
          ranges.add(encodeBufferedRange(
            formatId:
                entry.key == videoItag ? videoFormatId : audioFormatId,
            startTimeMs: 0,
            durationMs: 60000, // placeholder; server corrects us
            startSegmentIndex: 0,
            endSegmentIndex:
                s.maxSequenceNumber >= 0 ? s.maxSequenceNumber : 0,
          ));
        }
      }

      final request = encodeAbrRequest(
        clientAbrState: encodeClientAbrState(),
        selectedFormatIds: [videoFormatId, audioFormatId],
        bufferedRanges: ranges,
        videoPlaybackUstreamerConfig: ustreamerConfig,
        preferredAudioFormatIds: [audioFormatId],
        preferredVideoFormatIds: [videoFormatId],
        streamerContext: encodeStreamerContext(
          clientInfo: encodeClientInfo(),
          playbackCookie: playbackCookie,
          sabrContexts: sabrContexts,
        ),
      );

      final uri = Uri.parse('$sabrUrl${sabrUrl.contains('?') ? '&' : '?'}rn=$rn');
      final req = await _client.postUrl(uri);
      req.headers.set('Content-Type', 'application/x-protobuf');
      req.headers.set('Accept', 'application/vnd.yt-ump');
      req.headers.set('User-Agent',
          'com.google.android.youtube/19.44.38 (Linux; U; Android 14; en_US; Pixel 8; Build/UP1A.231005.007; Cronet/118.0.5993.65)');
      req.add(request);
      final resp = await req.close().timeout(
          const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        throw StateError(
            'SABR request failed: HTTP ${resp.statusCode}');
      }

      final parser = UmpParser();
      await for (final chunk in resp.timeout(
          const Duration(seconds: 30))) {
        parser.addChunk(chunk);
      }
      for (final part in parser.drainParts()) {
        switch (part.type) {
          case UmpPartType.mediaHeader:
            _handleMediaHeader(
                part.data, headerToItag, headerIsInit, headerSeq);
            break;
          case UmpPartType.media:
            final headerId = part.data[0];
            final itag = headerToItag[headerId];
            if (itag != null) {
              final s = streams[itag]!;
              final payload = part.data.sublist(1);
              final isInit = headerIsInit[headerId] == true;
              s.addMedia(payload, isInit: isInit);
              if (!isInit) downloaded += payload.length;
              final seq = headerSeq[headerId];
              if (seq != null && seq > s.maxSequenceNumber) {
                s.maxSequenceNumber = seq;
              }
            }
            break;
          case UmpPartType.mediaEnd:
            break; // segment complete marker; nothing to do
          case UmpPartType.nextRequestPolicy:
            final policy = _parseNextRequestPolicy(part.data);
            playbackCookie = policy.cookie;
            backoffMs = policy.backoffMs;
            break;
          case UmpPartType.formatInitializationMetadata:
            _handleFormatInit(part.data, streams);
            break;
          case UmpPartType.sabrRedirect:
            final newUrl = _parseSabrRedirect(part.data);
            if (newUrl.isNotEmpty) sabrUrl = newUrl;
            break;
          case UmpPartType.sabrError:
            throw StateError(
                'SABR error: ${_parseSabrError(part.data)}');
          case UmpPartType.sabrContextUpdate:
            _handleContextUpdate(part.data, sabrContexts);
            break;
          case UmpPartType.streamProtectionStatus:
          case UmpPartType.sabrContextSendingPolicy:
            break; // informational; ignore for now
        }
      }

      onProgress?.call(downloaded, null);
      rn++;

      // Fire onReadyToPlay once we have enough video data for mpv
      // to start (init segment + threshold bytes).
      if (!readyFired &&
          onReadyToPlay != null &&
          videoStream.initReceived &&
          videoStream.media.length >= readyThresholdBytes) {
        readyFired = true;
        // Flush files so mpv sees the data.
        await videoStream.fileSink?.flush();
        await audioStream.fileSink?.flush();
        onReadyToPlay();
      }

      // Stop if no new data for 10 consecutive requests.
      if (downloaded == lastDownloaded) {
        noProgressCount++;
        if (noProgressCount >= 10) break;
      } else {
        noProgressCount = 0;
        lastDownloaded = downloaded;
      }
    }

    // Accept partial download if we got substantial data.
    final videoBytes = videoStream.media.length;
    final audioBytes = audioStream.media.length;
    if (videoBytes < 1024 * 100 || audioBytes < 1024 * 10) {
      throw StateError(
          'SABR download incomplete: only ${videoBytes}v/${audioBytes}a bytes after $rn requests');
    }
    // Close file sinks.
    await videoStream.closeFile();
    await audioStream.closeFile();
    return SabrResult(video: videoStream, audio: audioStream);
  }

  void _handleMediaHeader(
    Uint8List data,
    Map<int, int> headerToItag,
    Map<int, bool> headerIsInit,
    Map<int, int> headerSeq,
  ) {
    final r = ProtoReader(data);
    int? headerId, itag, seq;
    bool isInit = false;
    while (!r.isDone) {
      final (field, wire) = r.readField();
      switch (field) {
        case 1:
          headerId = r.readVarint();
          break;
        case 3:
          itag = r.readVarint();
          break;
        case 8:
          isInit = r.readVarint() != 0;
          break;
        case 9:
          seq = r.readVarint();
          break;
        default:
          r.skipField(wire);
      }
    }
    if (headerId != null && itag != null) {
      headerToItag[headerId] = itag;
      headerIsInit[headerId] = isInit;
      if (seq != null) headerSeq[headerId] = seq;
    }
  }

  void _handleFormatInit(
      Uint8List data, Map<int, SabrFormatStream> streams) {
    // FormatInitializationMetadata doesn't carry itag directly in all
    // versions; apply end info to all streams lacking it.
    final r = ProtoReader(data);
    int? endSeg;
    while (!r.isDone) {
      final (field, wire) = r.readField();
      switch (field) {
        case 4:
          endSeg = r.readVarint();
          break;
        default:
          r.skipField(wire);
      }
    }
    if (endSeg != null) {
      for (final s in streams.values) {
        if (s.endSegmentNumber < 0) s.endSegmentNumber = endSeg;
      }
    }
  }

  ({Uint8List cookie, int backoffMs}) _parseNextRequestPolicy(
      Uint8List data) {
    final r = ProtoReader(data);
    var backoff = 0;
    var cookie = Uint8List(0);
    while (!r.isDone) {
      final (field, wire) = r.readField();
      switch (field) {
        case 4:
          backoff = r.readVarint();
          break;
        case 7:
          cookie = r.readBytes(); // nested PlaybackCookie bytes
          break;
        default:
          r.skipField(wire);
      }
    }
    return (cookie: cookie, backoffMs: backoff);
  }

  String _parseSabrRedirect(Uint8List data) {
    final r = ProtoReader(data);
    while (!r.isDone) {
      final (field, wire) = r.readField();
      if (field == 1 && wire == 2) {
        return utf8.decode(r.readBytes());
      }
      r.skipField(wire);
    }
    return '';
  }

  String _parseSabrError(Uint8List data) {
    final r = ProtoReader(data);
    final sb = StringBuffer();
    while (!r.isDone) {
      final (field, wire) = r.readField();
      sb.write('f$field=');
      if (wire == 0) {
        sb.write(r.readVarint());
      } else if (wire == 2) {
        sb.write(utf8.decode(r.readBytes(), allowMalformed: true));
      } else {
        r.skipField(wire);
      }
      sb.write('; ');
    }
    return sb.toString();
  }

  void _handleContextUpdate(
    Uint8List data,
    List<MapEntry<int, Uint8List>> sabrContexts,
  ) {
    final r = ProtoReader(data);
    int? type;
    Uint8List? value;
    while (!r.isDone) {
      final (field, wire) = r.readField();
      switch (field) {
        case 1:
          type = r.readVarint();
          break;
        case 2:
          value = r.readBytes();
          break;
        default:
          r.skipField(wire);
      }
    }
    if (type != null && value != null) {
      sabrContexts
          .removeWhere((e) => e.key == type);
      sabrContexts.add(MapEntry(type, value));
    }
  }
}
