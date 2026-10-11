// PURPOSE: State the fixed facts of the `.chart` header — the format string a reader must find, the
//          version of the envelope it sits in, the D19 inline limit — and name the `.chart` spelling
//          of the shared container failure family. The failures themselves are declared once in
//          `container_frame.dart`, beside the frame that raises them, because the `.setlist`
//          container fails in exactly the same ways; the names here are aliases of that one family,
//          so `on ChartFileException` and `on ContainerException` catch the same failures and a
//          `.chart` file and a `.setlist` file cannot come to report the same damage two ways.
// INPUTS: The size a PDF occupies, or the numbers a failed read observed.
// OUTPUTS: Constants and aliases. Nothing here touches bytes; the frame is read in
//          `container_frame.dart` and the header is read in `chart_file_codec.dart`.
// KEYWORDS: magic, version, checksum, truncation, corruption, forward-compatibility, d19, warnings,
//           shared-container-family
part of 'chart_file.dart';

/// The eight bytes every `.chart` container begins with.
///
/// The same eight bytes every ChartApp container begins with: see [containerMagic], which this is an
/// alias of so that a reader and a writer cannot disagree about one of the two.
const List<int> chartFileMagic = containerMagic;

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
///
/// The `.setlist` container carries its OWN version number rather than sharing this one: the frame
/// is shared and the version is a property of the header inside it, so a change that makes a
/// `.setlist` key required must not make an old build refuse every `.chart` file as well.
const int chartContainerVersion = 1;

/// The size of the fixed frame that precedes the header JSON.
///
/// An alias of [containerPrefixLength]: the frame is one implementation, and a caller that reads
/// this name and a caller that reads that one are reading the same number.
const int chartFilePrefixLength = containerPrefixLength;

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

/// The base class of every failure the `.chart` container reports.
///
/// An alias of [ContainerException], which is declared once in `container_frame.dart` and shared
/// with the `.setlist` container. It is an alias rather than a second class so that the `catch`
/// clause a caller writes does not have to know which of the two formats produced the failure: the
/// envelope fails the same way for both, and the two must not be able to drift apart.
typedef ChartFileException = ContainerException;

/// The bytes are not a container: the magic does not match.
typedef ChartFileSignatureException = ContainerSignatureException;

/// The file ends before the length its own frame declares.
typedef ChartFileTruncatedException = ContainerTruncatedException;

/// The file has the right shape but its content cannot be read as a container.
typedef ChartFileCorruptException = ContainerCorruptException;

/// The envelope's version is not one this build reads.
typedef ChartFileVersionException = ContainerVersionException;

/// The container cannot be WRITTEN as asked, because the value handed to the encoder does not
/// describe a legal chart file.
typedef ChartFileWriteException = ContainerWriteException;

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
