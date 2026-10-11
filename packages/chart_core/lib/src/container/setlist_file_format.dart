// PURPOSE: State the fixed facts of the `.setlist` HEADER — the format string a reader must find,
//          the version of the header a reader may treat as required — and declare the warnings a
//          `.setlist` decode can carry instead of a failure. The envelope around the header, and
//          every typed failure that reading it can produce, is the shared container family in
//          `container_frame.dart` and is not restated here.
// INPUTS: None.
// OUTPUTS: Constants and the warning value with a machine-readable code. Nothing here touches
//          bytes.
// KEYWORDS: setlist-file, format-tag, version, warnings, forward-compatibility
part of 'setlist_file.dart';

/// The `format` string written inside the header JSON, beside [setlistContainerVersion].
///
/// It is what tells a `.setlist` file from a `.chart` file: the two share an envelope, so the frame
/// alone cannot say which one this is, and a reader that finds the other tag refuses the file
/// rather than reading a header whose keys it does not know.
const String setlistFileFormatTag = 'chartapp.setlist';

/// The extension a programme is saved under.
const String setlistFileExtension = '.setlist';

/// The version of the `.setlist` header this build writes, and the only one it reads.
///
/// The same doctrine as the `.chart` envelope version, applied to this format's own required header
/// keys: it is NOT bumped when a new operation type or a new OPTIONAL header field is added, and it
/// MUST be bumped when a header key becomes required, because an old reader has no way to notice
/// the absence of a field it never knew about. It is a separate number from the `.chart` one on
/// purpose — see this library's header.
const int setlistContainerVersion = 1;

/// What a [SetlistFileWarning] is about, so a caller can branch on the warning without matching
/// text.
enum SetlistFileWarningCode {
  /// The file holds an operation of a type this build does not know, written by a newer build. The
  /// operation was skipped; the programme is the snapshot plus the operations before and after it
  /// that this build does understand.
  unknownEventType,

  /// The file holds an operation whose own format version this build does not know. Skipped for the
  /// same reason as [unknownEventType].
  unsupportedEventVersion,
}

/// Something a reader had to report but that is not a failure.
///
/// A warning is never a substitute for a failure: it records a part of the file this build chose not
/// to read, and the message states what was skipped and what the caller is left with. It is most
/// important for a setlist, because a skipped insertion or deletion is a running order that is
/// almost — but not exactly — the one the writer saved, and an empty programme would look exactly
/// like a programme somebody had not built yet.
class SetlistFileWarning {
  /// Creates a warning of [code] described by [message].
  const SetlistFileWarning({required this.code, required this.message});

  /// What the warning is about.
  final SetlistFileWarningCode code;

  /// What was skipped or left out, and what the programme is without it.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is SetlistFileWarning &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'SetlistFileWarning(${code.name}: $message)';
}
