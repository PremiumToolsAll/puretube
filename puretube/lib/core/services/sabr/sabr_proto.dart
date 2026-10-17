/// Minimal proto2 protobuf encoder for YouTube's SABR protocol.
/// Implements only what's needed for VideoPlaybackAbrRequest and related
/// messages. Field numbers from sabr-rs proto definitions.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Protobuf wire types.
class _Wire {
  static const varint = 0;
  static const fixed64 = 1;
  static const lengthDelimited = 2;
  static const fixed32 = 5;
}

/// Low-level proto2 writer.
class ProtoWriter {
  final BytesBuilder _out = BytesBuilder();

  Uint8List toBytes() => _out.toBytes();

  void _writeKey(int fieldNumber, int wireType) {
    _writeVarint((fieldNumber << 3) | wireType);
  }

  void _writeVarint(int value) {
    var v = value;
    // Handle negative int64 as 64-bit two's complement.
    if (v < 0) v += 1 << 64;
    while (v >= 0x80) {
      _out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    _out.addByte(v & 0x7F);
  }

  void writeInt32(int field, int value) {
    if (value == 0) return; // proto2 optional: skip default
    _writeKey(field, _Wire.varint);
    _writeVarint(value & 0xFFFFFFFF);
  }

  void writeInt64(int field, int value) {
    if (value == 0) return;
    _writeKey(field, _Wire.varint);
    _writeVarint(value);
  }

  void writeUint32(int field, int value) {
    if (value == 0) return;
    _writeKey(field, _Wire.varint);
    _writeVarint(value);
  }

  void writeUint64(int field, int value) {
    if (value == 0) return;
    _writeKey(field, _Wire.varint);
    _writeVarint(value);
  }

  void writeBool(int field, bool value) {
    if (!value) return;
    _writeKey(field, _Wire.varint);
    _out.addByte(1);
  }

  void writeFloat(int field, double value) {
    if (value == 0.0) return;
    _writeKey(field, _Wire.fixed32);
    final b = ByteData(4)..setFloat32(0, value, Endian.little);
    _out.add(b.buffer.asUint8List());
  }

  void writeString(int field, String value) {
    if (value.isEmpty) return;
    _writeKey(field, _Wire.lengthDelimited);
    final bytes = utf8.encode(value);
    _writeVarint(bytes.length);
    _out.add(bytes);
  }

  void writeBytes(int field, List<int> value) {
    if (value.isEmpty) return;
    _writeKey(field, _Wire.lengthDelimited);
    _writeVarint(value.length);
    _out.add(value);
  }

  void writeMessage(int field, Uint8List value) {
    if (value.isEmpty) return;
    _writeKey(field, _Wire.lengthDelimited);
    _writeVarint(value.length);
    _out.add(value);
  }

  /// Always writes a message field, even if empty (for required fields).
  void writeMessageForced(int field, Uint8List value) {
    _writeKey(field, _Wire.lengthDelimited);
    _writeVarint(value.length);
    _out.add(value);
  }
}

/// misc.FormatId: itag + last_modified + xtags.
Uint8List encodeFormatId({
  required int itag,
  required int lastModified,
  String xtags = '',
}) {
  final w = ProtoWriter();
  w.writeInt32(1, itag);
  w.writeUint64(2, lastModified);
  w.writeString(3, xtags);
  return w.toBytes();
}

/// video_streaming.TimeRange.
Uint8List encodeTimeRange({
  required int startTicks,
  required int durationTicks,
  required int timescale,
}) {
  final w = ProtoWriter();
  w.writeInt64(1, startTicks);
  w.writeInt64(2, durationTicks);
  w.writeInt64(3, timescale);
  return w.toBytes();
}

/// video_streaming.BufferedRange.
Uint8List encodeBufferedRange({
  required Uint8List formatId,
  required int startTimeMs,
  required int durationMs,
  required int startSegmentIndex,
  required int endSegmentIndex,
}) {
  final w = ProtoWriter();
  w.writeMessageForced(1, formatId);
  w.writeInt64(2, startTimeMs);
  w.writeInt64(3, durationMs);
  w.writeInt32(4, startSegmentIndex);
  w.writeInt32(5, endSegmentIndex);
  w.writeMessage(
      6,
      encodeTimeRange(
        startTicks: 0,
        durationTicks: durationMs,
        timescale: 1000,
      ));
  return w.toBytes();
}

/// video_streaming.ClientAbrState (key fields only).
Uint8List encodeClientAbrState({
  int bandwidthEstimate = 5000000,
  int playerTimeMs = 0,
  int visibility = 1,
  double playbackRate = 1.0,
  int enabledTrackTypesBitfield = 3,
  int playerState = 1,
}) {
  final w = ProtoWriter();
  w.writeInt64(23, bandwidthEstimate);
  w.writeInt64(28, playerTimeMs);
  w.writeInt32(34, visibility);
  w.writeFloat(35, playbackRate);
  w.writeInt32(40, enabledTrackTypesBitfield);
  w.writeInt32(44, playerState);
  return w.toBytes();
}

/// video_streaming.StreamerContext.ClientInfo.
Uint8List encodeClientInfo() {
  final w = ProtoWriter();
  w.writeString(12, 'Google'); // device_make
  w.writeString(13, 'Pixel 8'); // device_model
  w.writeInt32(16, 3); // client_name = ANDROID
  w.writeString(17, '19.44.38'); // client_version
  w.writeString(18, 'Android'); // os_name
  w.writeString(19, '14'); // os_version
  w.writeInt32(64, 34); // android_sdk_version
  return w.toBytes();
}

/// video_streaming.StreamerContext.
Uint8List encodeStreamerContext({
  required Uint8List clientInfo,
  Uint8List? playbackCookie,
  List<MapEntry<int, Uint8List>> sabrContexts = const [],
}) {
  final cookie = playbackCookie ?? Uint8List(0);
  final w = ProtoWriter();
  w.writeMessageForced(1, clientInfo);
  w.writeBytes(3, cookie);
  for (final ctx in sabrContexts) {
    final cw = ProtoWriter();
    cw.writeInt32(1, ctx.key); // type
    cw.writeBytes(2, ctx.value); // value
    w.writeMessage(5, cw.toBytes());
  }
  return w.toBytes();
}

/// video_streaming.VideoPlaybackAbrRequest.
Uint8List encodeAbrRequest({
  required Uint8List clientAbrState,
  required List<Uint8List> selectedFormatIds,
  required List<Uint8List> bufferedRanges,
  required Uint8List videoPlaybackUstreamerConfig,
  required List<Uint8List> preferredAudioFormatIds,
  required List<Uint8List> preferredVideoFormatIds,
  required Uint8List streamerContext,
}) {
  final w = ProtoWriter();
  w.writeMessageForced(1, clientAbrState);
  for (final f in selectedFormatIds) {
    w.writeMessage(2, f);
  }
  for (final r in bufferedRanges) {
    w.writeMessage(3, r);
  }
  w.writeBytes(5, videoPlaybackUstreamerConfig);
  for (final f in preferredAudioFormatIds) {
    w.writeMessage(16, f);
  }
  for (final f in preferredVideoFormatIds) {
    w.writeMessage(17, f);
  }
  w.writeMessageForced(19, streamerContext);
  return w.toBytes();
}
