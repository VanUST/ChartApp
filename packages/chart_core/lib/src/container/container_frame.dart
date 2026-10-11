// PURPOSE: Be the one place a ChartApp container's ENVELOPE is implemented — the magic every
//          container begins with, the fixed prefix that follows it, the lengths and the two
//          checksums, and the checks that turn a wrong file into one typed reason — so that the
//          `.chart` and `.setlist` formats share one framing rather than each carrying its own copy
//          of it. The two formats differ only in the header they write INSIDE this frame and in what
//          they do with the payload region; the bytes before the header are the same bytes, and a
//          second implementation of them beside this one is the drift a format family must not have.
// INPUTS: The header bytes and the payload bytes on the way out, with the envelope version the
//         format writes; the whole file's bytes on the way in, with that same version and the
//         extension the failure messages should name.
// OUTPUTS: The complete framed container, or a [ContainerFrame] holding views of the header and
//          payload regions. Every way the bytes can fail to be a readable container is a typed
//          [ContainerException] and never a bare `RangeError` or `FormatException`; nothing here
//          ever returns a frame for a file whose checksums, lengths or version do not agree.
// KEYWORDS: container, envelope, frame, magic, version, checksum, crc32, truncation, corruption,
//           typed-failure, shared-framing, pure-dart
//
// WHY THE FAILURES ARE ONE FAMILY AND NOT ONE PER FORMAT.
//
// The envelope is one thing. "These bytes are not a container", "the file ends before its own
// lengths say it should", "the header's checksum does not match", "this envelope version is not one
// this build reads" and "the bytes changed after they were written" are properties of the FRAME, not
// of the document inside it, so a caller that catches [ContainerException] catches every way a file
// can fail to be a container this build can read — whichever of the two formats was asked for. A
// format's own failures (an operation of the wrong document kind, a missing header key) are reported
// by that format, in the same family, with a message that names the file it was reading.
//
// WHY THE READER REFUSES RATHER THAN REPAIRS.
//
// A container whose lengths, checksums or version disagree is refused whole. The alternative — take
// the header and ignore the rest — is the failure mode this family exists to prevent: a malformed
// file quietly becomes an empty document that looks exactly like a real one, and a musician loses a
// chart (or a whole programme) without being told anything. There is no repair path here, and that
// is the decision, not an omission.
library;

import 'dart:typed_data';

/// The eight bytes every ChartApp container begins with, `.chart` and `.setlist` alike.
///
/// The first byte is `0x89`, which is not valid UTF-8, so a container can never be mistaken for the
/// JSON or text file it would otherwise look like. The trailing CRLF catches a file that a tool has
/// rewritten in text mode, which is a real way binary payloads are damaged by editors and
/// version-control settings.
const List<int> containerMagic = <int>[
  0x89,
  0x43, // C
  0x48, // H
  0x41, // A
  0x52, // R
  0x54, // T
  0x0d,
  0x0a,
];

/// The size of the fixed frame that precedes the header JSON.
///
/// Eight magic bytes, then five little-endian `uint32` fields: envelope version, header length,
/// payload length, header CRC-32 and payload CRC-32.
const int containerPrefixLength = 28;

/// The largest value the frame's 32-bit length fields can hold.
const int containerMaxU32 = 0xFFFFFFFF;

/// The base class of every failure a container reports.
///
/// It is sealed, so a caller that switches over it is told by the compiler when a new failure is
/// added, and every message is written to be shown to a person rather than logged as a number.
/// `ChartFileException` and its siblings are aliases of this family declared in
/// `chart_file_format.dart`, so the `.chart` code written against those names is the same type as
/// the `.setlist` code written against these.
sealed class ContainerException implements Exception {
  /// Creates a failure described by [message].
  const ContainerException(this.message);

  /// What was wrong, in terms a caller can act on.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The bytes are not a container: the magic does not match.
class ContainerSignatureException extends ContainerException {
  /// Creates a failure naming what was found instead of the magic.
  const ContainerSignatureException(super.message);
}

/// The file ends before the length its own frame declares.
///
/// This is the failure a half-written or half-copied file produces. It is separate from corruption
/// because the two call for different answers: a truncated file may be recoverable from a backup,
/// while corrupt bytes in the middle of a complete file are a different problem.
class ContainerTruncatedException extends ContainerException {
  /// Creates a failure describing how many bytes were found and how many were needed.
  const ContainerTruncatedException(
    super.message, {
    required this.found,
    required this.expected,
  });

  /// How many bytes the file actually held.
  final int found;

  /// How many bytes the frame declared, or the smallest legal container when the frame itself was
  /// never readable.
  final int expected;
}

/// The file has the right shape but its content cannot be read as a container.
///
/// A checksum that does not match, bytes appended after the declared end and a field of the wrong
/// type all land here. None of them is ever absorbed: a corrupt file must not decode to a plausible
/// document.
class ContainerCorruptException extends ContainerException {
  /// Creates a failure described by [message].
  const ContainerCorruptException(super.message);
}

/// The envelope's version is not one this build reads.
class ContainerVersionException extends ContainerException {
  /// Creates a failure naming the version found and the one this build writes.
  const ContainerVersionException(
    super.message, {
    required this.found,
    required this.supported,
  });

  /// The version the file declares.
  final int found;

  /// The version this build writes and reads.
  final int supported;
}

/// The container cannot be WRITTEN as asked, because the value handed to the encoder does not
/// describe a legal container.
///
/// This is a programming error at the call site — content too large for the frame's own length
/// fields — and it is typed rather than an [ArgumentError] so that the app can catch one family of
/// failure around both saving and opening.
class ContainerWriteException extends ContainerException {
  /// Creates a failure described by [message].
  const ContainerWriteException(super.message);
}

/// The two regions a container's frame has located: the header JSON and the payload bytes.
///
/// Both are views into the file that was read rather than copies, so a caller that only inspects
/// them pays nothing for the region it does not use. The class carries no format knowledge: what
/// the header means is the format's business.
class ContainerFrame {
  /// Creates a frame over [header] and [payload], read from a version-[version] container.
  const ContainerFrame({
    required this.version,
    required this.header,
    required this.payload,
  });

  /// The envelope version the file declared, already checked against the one this build reads.
  final int version;

  /// The header JSON's bytes, exactly as the file holds them.
  final Uint8List header;

  /// The payload region's bytes, empty for a format that carries none.
  final Uint8List payload;
}

/// Writes [headerBytes] and [payloadBytes] as one container at [version].
///
/// Throws [ContainerWriteException] when either region is larger than the frame's 32-bit length
/// fields can address. The caller has already checked that what it is putting INSIDE the regions is
/// legal for its format; this function checks only what the frame itself can hold.
Uint8List encodeContainerFrame({
  required int version,
  required Uint8List headerBytes,
  required Uint8List payloadBytes,
}) {
  if (headerBytes.length > containerMaxU32 ||
      payloadBytes.length > containerMaxU32) {
    throw const ContainerWriteException(
      'the container is too large for its own frame: the header and the '
      'payload region each hold at most 4294967295 bytes',
    );
  }
  final BytesBuilder out = BytesBuilder(copy: false);
  out.add(containerMagic);
  writeU32(out, version);
  writeU32(out, headerBytes.length);
  writeU32(out, payloadBytes.length);
  writeU32(out, crc32(headerBytes));
  writeU32(out, crc32(payloadBytes));
  out
    ..add(headerBytes)
    ..add(payloadBytes);
  return out.takeBytes();
}

/// Reads the frame of a version-[version] container from [bytes], naming [extension] in failures.
///
/// Throws [ContainerTruncatedException] when the file is shorter than the prefix or than the length
/// its own frame declares, [ContainerSignatureException] when the magic does not match,
/// [ContainerVersionException] when the envelope version is not [version], and
/// [ContainerCorruptException] when bytes trail the declared end or either checksum disagrees. The
/// order of those checks is fixed so that one damaged file always reports the same reason.
ContainerFrame decodeContainerFrame(
  Uint8List bytes, {
  required int version,
  required String extension,
}) {
  if (bytes.length < containerPrefixLength) {
    throw ContainerTruncatedException(
      'a $extension container is at least $containerPrefixLength bytes; this '
      'file is ${bytes.length}',
      found: bytes.length,
      expected: containerPrefixLength,
    );
  }
  for (int index = 0; index < containerMagic.length; index++) {
    if (bytes[index] != containerMagic[index]) {
      throw ContainerSignatureException(
        'these bytes do not begin with the $extension magic, so this is not a '
        '$extension container',
      );
    }
  }
  final int found = readU32(bytes, 8);
  if (found != version) {
    throw ContainerVersionException(
      'this is a version $found $extension container; this build reads version '
      '$version and refuses the rest rather than reading a frame it does not '
      'know',
      found: found,
      supported: version,
    );
  }
  final int headerLength = readU32(bytes, 12);
  final int payloadLength = readU32(bytes, 16);
  final int headerCrc = readU32(bytes, 20);
  final int payloadCrc = readU32(bytes, 24);
  final int declared = containerPrefixLength + headerLength + payloadLength;
  if (bytes.length < declared) {
    throw ContainerTruncatedException(
      'the container declares $declared bytes but this file ends at '
      '${bytes.length}',
      found: bytes.length,
      expected: declared,
    );
  }
  if (bytes.length > declared) {
    throw ContainerCorruptException(
      'the container declares $declared bytes but this file holds '
      '${bytes.length}; the ${bytes.length - declared} trailing byte(s) '
      'belong to nothing',
    );
  }
  final Uint8List headerBytes = Uint8List.sublistView(
    bytes,
    containerPrefixLength,
    containerPrefixLength + headerLength,
  );
  final Uint8List payloadBytes = Uint8List.sublistView(
    bytes,
    containerPrefixLength + headerLength,
    declared,
  );
  final int actualHeaderCrc = crc32(headerBytes);
  if (actualHeaderCrc != headerCrc) {
    throw ContainerCorruptException(
      'the header does not match its CRC-32: recorded $headerCrc, computed '
      '$actualHeaderCrc. The bytes have changed since the file was written.',
    );
  }
  if (payloadLength > 0) {
    final int actualPayloadCrc = crc32(payloadBytes);
    if (actualPayloadCrc != payloadCrc) {
      throw ContainerCorruptException(
        'the embedded bytes do not match their CRC-32: recorded $payloadCrc, '
        'computed $actualPayloadCrc.',
      );
    }
  }
  return ContainerFrame(
    version: found,
    header: headerBytes,
    payload: payloadBytes,
  );
}

/// Writes [value] as four little-endian bytes.
void writeU32(BytesBuilder out, int value) {
  out
    ..addByte(value & 0xFF)
    ..addByte((value >> 8) & 0xFF)
    ..addByte((value >> 16) & 0xFF)
    ..addByte((value >> 24) & 0xFF);
}

/// Reads four little-endian bytes at [offset].
int readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// The CRC-32 (IEEE 802.3) of [bytes]: reflected polynomial `0xEDB88320`, initial value all ones,
/// final value inverted.
///
/// A checksum is what makes a single flipped byte in the header a REPORTED corruption rather than a
/// slightly different document: header JSON with one character changed still parses, so nothing else
/// in a codec would notice it.
int crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte & 0xFF;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
