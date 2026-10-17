/// UMP (Unified Media Protocol) parser for YouTube's SABR streaming.
/// Each part: [youtube-varint: part_type] [youtube-varint: part_size]
///            [part_size bytes: part_data]
///
/// The varint is YouTube's own format, NOT standard protobuf varint.
library;

import 'dart:typed_data';

/// UMP part types.
class UmpPartType {
  static const mediaHeader = 20;
  static const media = 21;
  static const mediaEnd = 22;
  static const nextRequestPolicy = 35;
  static const formatInitializationMetadata = 42;
  static const sabrRedirect = 43;
  static const sabrError = 44;
  static const sabrContextUpdate = 57;
  static const streamProtectionStatus = 58;
  static const sabrContextSendingPolicy = 59;
}

/// Reads a YouTube-style varint from [buf] at [offset].
/// Returns (value, bytesConsumed), or null if buf is too short.
(int, int)? readYtVarint(Uint8List buf, int offset) {
  if (offset >= buf.length) return null;
  final first = buf[offset];
  if (first < 128) {
    return (first, 1);
  } else if (first < 192) {
    if (offset + 1 >= buf.length) return null;
    final b1 = buf[offset + 1];
    return ((first & 0x3F) + 64 * b1, 2);
  } else if (first < 224) {
    if (offset + 2 >= buf.length) return null;
    final b1 = buf[offset + 1];
    final b2 = buf[offset + 2];
    return ((first & 0x1F) + 32 * (b1 + 256 * b2), 3);
  } else if (first < 240) {
    if (offset + 3 >= buf.length) return null;
    final b1 = buf[offset + 1];
    final b2 = buf[offset + 2];
    final b3 = buf[offset + 3];
    return (
      (first & 0x0F) + 16 * (b1 + 256 * (b2 + 256 * b3)),
      4
    );
  } else {
    if (offset + 4 >= buf.length) return null;
    final v = buf[offset + 1] |
        (buf[offset + 2] << 8) |
        (buf[offset + 3] << 16) |
        (buf[offset + 4] << 24);
    return (v, 5);
  }
}

/// A single parsed UMP part.
class UmpPart {
  final int type;
  final Uint8List data;
  const UmpPart(this.type, this.data);
}

/// Streaming UMP parser: feed chunks, get complete parts.
class UmpParser {
  final BytesBuilder _buf = BytesBuilder();
  int _buffered = 0;

  void addChunk(List<int> chunk) {
    _buf.add(chunk);
    _buffered += chunk.length;
  }

  /// Extracts all complete parts currently buffered.
  /// Incomplete trailing data stays buffered for the next chunk.
  List<UmpPart> drainParts() {
    final parts = <UmpPart>[];
    var bytes = _buf.toBytes();
    var offset = 0;
    while (true) {
      final t = readYtVarint(bytes, offset);
      if (t == null) break;
      final (type, typeLen) = t;
      final s = readYtVarint(bytes, offset + typeLen);
      if (s == null) break;
      final (size, sizeLen) = s;
      final dataStart = offset + typeLen + sizeLen;
      if (dataStart + size > bytes.length) break; // incomplete
      parts.add(UmpPart(
        type,
        bytes.sublist(dataStart, dataStart + size),
      ));
      offset = dataStart + size;
    }
    // Keep the unconsumed tail.
    if (offset > 0) {
      final remaining = bytes.sublist(offset);
      _buf.clear();
      _buf.add(remaining);
      _buffered = remaining.length;
    }
    return parts;
  }
}

/// Minimal protobuf reader for parsing UMP part payloads.
/// Only implements what's needed: varint, length-delimited, 32-bit.
class ProtoReader {
  final Uint8List buf;
  int offset = 0;

  ProtoReader(this.buf);

  bool get isDone => offset >= buf.length;

  /// Reads a standard protobuf varint.
  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = buf[offset++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  Uint8List readBytes() {
    final len = readVarint();
    final out = buf.sublist(offset, offset + len);
    offset += len;
    return out;
  }

  double readFloat() {
    final v =
        ByteData.sublistView(buf, offset, offset + 4)
            .getFloat32(0, Endian.little);
    offset += 4;
    return v;
  }

  /// Reads one field, returning (fieldNumber, wireType).
  /// The value must be consumed via readVarint/readBytes/readFloat.
  (int, int) readField() {
    final key = readVarint();
    return (key >> 3, key & 0x07);
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        offset += 8;
        break;
      case 2:
        final len = readVarint();
        offset += len;
        break;
      case 5:
        offset += 4;
        break;
      default:
        throw StateError('Unknown wire type $wireType');
    }
  }
}
