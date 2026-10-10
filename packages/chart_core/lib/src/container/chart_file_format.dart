// PURPOSE: State the fixed facts of the `.chart` envelope — the bytes a container starts with, the
//          version a reader must know, the D19 inline limit — and declare the failures a reader can
//          report and the warnings it can carry instead. Every wrong file has exactly one typed
//          reason here, so a caller never has to interpret a raw parse exception to decide whether
//          a file was truncated, corrupt, or merely written by a newer build.
// INPUTS: The size a PDF occupies, or the numbers a failed read observed.
// OUTPUTS: Constants, a sealed exception hierarchy, and a warning value with a machine-readable
//          code. Nothing here touches bytes; the frame is read in `chart_file_codec.dart`.
// KEYWORDS: magic, version, checksum, truncation, corruption, forward-compatibility, d19, warnings
part of 'chart_file.dart';

/// The eight bytes every `.chart` container begins with.
///
/// The first byte is `0x89`, which is not valid UTF-8, so a container can never be mistaken for
/// the JSON or text file it would otherwise look like. The trailing CRLF catches a file that a
/// tool has rewritten in text mode, which is a real way binary payloads are damaged by editors and
/// version-control settings.
const List<int> chartFileMagic = <int>[
  0x89,
  0x43, // C
  0x48, // H
  0x41, // A
  0x52, // R
  0x54, // T
  0x0d,
  0x0a,
];

/// The `format` string written inside the header JSON, alongside [chartContainerVersion].
const String chartFileFormatTag = 'chartapp.chart';

/// The extension a chart document is saved under.
const String chartFileExtension = '.chart';

/// The version of the ENVELOPE this build writes, and the only one it reads.
///
/// This number describes the frame: the magic, the fixed prefix, and the set of header keys a
/// reader may treat as required. It is deliberately NOT bumped when a new operation type or a new
/// OPTIONAL header field is added — those are forward-compatible by construction, and bumping
/// would make an old build refuse a file it could have read most of. A writer that makes a new
/// header key required must bump this number, because an old reader has no way to notice the
/// absence of a field it never knew about.
///
/// A reader refuses an envelope version it does not know with [ChartFileVersionException]. Inside
/// a known envelope it reads the operations it understands and reports the rest as warnings.
const int chartContainerVersion = 1;

/// The size of the fixed frame that precedes the header JSON.
///
/// Eight magic bytes, then five little-endian `uint32` fields: envelope version, header length,
/// payload length, header CRC-32 and payload CRC-32.
const int chartFilePrefixLength = 28;

/// The media type recorded for every attachment this format writes.
const String pdfMediaType = 'application/pdf';

/// D19: a PDF is embedded inline when it is at most this many bytes, and named as a sidecar
/// reference otherwise, with a warning either way.
///
/// Owner decision D19 says "50 MB per song". MB is read here as 50 MiB (52,428,800 bytes), which
/// is the binary meaning a file size on a musician's own disk is measured in. The wording does not
/// say which, so the choice is recorded rather than hidden: a caller that must match a decimal
/// 50,000,000-byte reading can compare against [pdfInlineLimitBytes] itself.
const int pdfInlineLimitBytes = 50 * 1024 * 1024;

/// The base class of every failure the container reports.
///
/// It is sealed, so a caller that switches over it is told by the compiler when a new failure is
/// added, and every message is written to be shown to a person rather than logged as a number.
sealed class ChartFileException implements Exception {
  /// Creates a failure described by [message].
  const ChartFileException(this.message);

  /// What was wrong, in terms a caller can act on.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The bytes are not a `.chart` container: the magic does not match.
class ChartFileSignatureException extends ChartFileException {
  /// Creates a failure naming what was found instead of the magic.
  const ChartFileSignatureException(super.message);
}

/// The file ends before the length its own frame declares.
///
/// This is the failure a half-written or half-copied file produces. It is separate from corruption
/// because the two call for different answers: a truncated file may be recoverable from a backup,
/// while corrupt bytes in the middle of a complete file are a different problem.
class ChartFileTruncatedException extends ChartFileException {
  /// Creates a failure describing how many bytes were found and how many were needed.
  const ChartFileTruncatedException(
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
/// A checksum that does not match, header JSON that does not parse, a field of the wrong type, an
/// operation whose payload is malformed and an attachment whose byte range falls outside the file
/// all land here. None of them is ever absorbed: a corrupt file must not decode to a plausible
/// document.
class ChartFileCorruptException extends ChartFileException {
  /// Creates a failure described by [message].
  const ChartFileCorruptException(super.message);
}

/// The envelope's version is not one this build reads.
class ChartFileVersionException extends ChartFileException {
  /// Creates a failure naming the version found and the one this build writes.
  const ChartFileVersionException(
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
/// describe a legal chart file.
///
/// This is a programming error at the call site — an empty document id, an operation belonging to
/// another document, a PDF with no name — and it is typed rather than an [ArgumentError] so that
/// the app can catch one family of failure around both saving and opening.
class ChartFileWriteException extends ChartFileException {
  /// Creates a failure described by [message].
  const ChartFileWriteException(super.message);
}

/// What a [ChartFileWarning] is about, so a caller can branch on the warning without matching
/// text.
enum ChartFileWarningCode {
  /// D19 left the PDF on disk instead of embedding it, or a file names a sidecar this build does
  /// not hold. The chart is still complete; the PDF is not in it.
  pdfSidecar,

  /// The file holds an operation of a type this build does not know, written by a newer build. The
  /// operation was skipped; the document is the snapshot plus the operations before and after it
  /// that this build does understand.
  unknownEventType,

  /// The file holds an operation whose own format version this build does not know. Skipped for
  /// the same reason as [unknownEventType].
  unsupportedEventVersion,

  /// The file holds something this build cannot represent at all. It was skipped, and whatever it
  /// held is NOT available; a caller that re-saves the document will not carry it forward.
  unknownAttachment,
}

/// Something a reader had to report but that is not a failure.
///
/// A warning is never a substitute for a failure: it records a part of the file this build chose
/// not to read, and the message states what was skipped and what the caller is left with.
class ChartFileWarning {
  /// Creates a warning of [code] described by [message].
  const ChartFileWarning({required this.code, required this.message});

  /// What the warning is about.
  final ChartFileWarningCode code;

  /// What was skipped or left out, and what the document is without it.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ChartFileWarning &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'ChartFileWarning(${code.name}: $message)';
}
