// PURPOSE: Hold a whole `.chart` file as one value — what it is about, the document it starts
//          from, the operations after that, and the PDFs it carries — so that encoding and decoding
//          have a single shape to agree on and a caller can inspect a file without parsing bytes.
// INPUTS: The file's metadata, a document snapshot, a chart-operation tail, and the PDFs D19 placed
//         either inside the container or beside it.
// OUTPUTS: Immutable values with value equality, so a round trip is checkable with `==`. The
//          document after the operation tail is available as [ChartFile.reducedDocument], which
//          throws [DocumentReducerException] when an operation cannot be applied to the snapshot.
// KEYWORDS: chart-file, metadata, snapshot, operations, pdf, attachment, value-semantics, d19
part of 'chart_file.dart';

/// What a `.chart` file knows about itself rather than about the music.
///
/// The music's own facts — title, composer, style, key, tempo, staves — live in the song inside
/// [ChartFile.snapshot], which is where the model already keeps them. This type holds only what is
/// about the FILE: the identity its operation log is keyed by, when it was written, and what wrote
/// it.
class ChartMetadata {
  /// Creates metadata for the document [docId], optionally dated and attributed.
  ///
  /// [docId] is the identity the operation log is keyed by, and it must not be empty: an operation
  /// carries its document id, and a container whose operations belong to no document cannot be
  /// checked against anything. It is deliberately a separate value from the song's own `id`, which
  /// the model allows to be empty for a chart that was never assigned one.
  const ChartMetadata({
    required this.docId,
    this.createdAt,
    this.modifiedAt,
    this.writer = '',
  });

  /// The document identity every operation in this file must carry.
  final String docId;

  /// When the document was first written, or null when the writer did not record it.
  ///
  /// The codec writes the instant in UTC, so a value read back is a UTC [DateTime] and compares
  /// equal to a UTC value passed in. A caller that supplies a local time gets the same instant back
  /// in UTC, which its own `==` will not match; compare with [DateTime.isAtSameMomentAs] in that
  /// case. Nothing here reads a clock: a caller that wants a timestamp passes one.
  final DateTime? createdAt;

  /// When the document was last written, with the same UTC rule as [createdAt].
  final DateTime? modifiedAt;

  /// A free-form note about what wrote the file, empty when nothing was recorded.
  ///
  /// Free text rather than a version number because it is diagnostic: the version that matters for
  /// compatibility is [chartContainerVersion] and each operation's own `v`, not a build string.
  final String writer;

  @override
  bool operator ==(Object other) =>
      other is ChartMetadata &&
      other.docId == docId &&
      other.createdAt == createdAt &&
      other.modifiedAt == modifiedAt &&
      other.writer == writer;

  @override
  int get hashCode => Object.hash(docId, createdAt, modifiedAt, writer);

  @override
  String toString() =>
      'ChartMetadata($docId'
      '${writer.isEmpty ? '' : ', "$writer"'}'
      '${createdAt == null ? '' : ', created $createdAt'})';
}

/// A PDF a chart carries, either inside the container or beside it.
///
/// D19 decides which: at most [pdfInlineLimitBytes] the bytes are embedded, beyond it the PDF stays
/// on the musician's disk and the container records where it is, with a warning. The two cases are
/// two types rather than one type with a nullable byte list, because "embedded" and "referenced"
/// are not two states of one thing — a reader either has the bytes or it does not, and the compiler
/// should make the caller say which.
sealed class ChartPdf {
  /// Creates an attachment called [name].
  const ChartPdf({required this.name});

  /// The PDF's file name, as the writer knew it. Never empty.
  final String name;

  /// How many bytes the PDF is, whether or not this container holds them.
  int get byteLength;
}

/// A PDF whose bytes are inside the container.
class EmbeddedPdf extends ChartPdf {
  /// Embeds [bytes] as the PDF called [name].
  const EmbeddedPdf({required super.name, required this.bytes});

  /// The PDF's own bytes, exactly as the writer read them.
  final Uint8List bytes;

  @override
  int get byteLength => bytes.length;

  @override
  bool operator ==(Object other) =>
      other is EmbeddedPdf &&
      other.name == name &&
      _sameBytes(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(bytes));

  @override
  String toString() => 'EmbeddedPdf($name, ${bytes.length} bytes)';
}

/// A PDF that stayed on disk and is named by [reference].
class SidecarPdf extends ChartPdf {
  /// Names the PDF [name], reachable as [reference], known to be [byteLength] bytes.
  const SidecarPdf({
    required super.name,
    required this.reference,
    required this.byteLength,
  });

  /// Where the PDF is, as the writer wrote it.
  ///
  /// Usually a file name beside the `.chart` file, so that moving the two together keeps the
  /// reference valid. The codec never resolves it: resolving a path is the caller's job, because
  /// this package has no filesystem.
  final String reference;

  @override
  final int byteLength;

  @override
  bool operator ==(Object other) =>
      other is SidecarPdf &&
      other.name == name &&
      other.reference == reference &&
      other.byteLength == byteLength;

  @override
  int get hashCode => Object.hash(name, reference, byteLength);

  @override
  String toString() =>
      'SidecarPdf($name, "$reference", $byteLength bytes, not embedded)';
}

/// One `.chart` file's worth of content.
class ChartFile {
  /// Creates a chart file over [snapshot], with [events] applying on top of it.
  ///
  /// [metadata]'s `docId` must be non-empty and every operation must carry the same id; both are
  /// checked when the file is encoded, with a [ChartFileWriteException].
  const ChartFile({
    required this.metadata,
    required this.snapshot,
    this.events = const <ChartEvent>[],
    this.attachments = const <ChartPdf>[],
  });

  /// What the file knows about itself.
  final ChartMetadata metadata;

  /// The document the operation tail starts from.
  ///
  /// This is the materialised state at the moment the log was cut. It is stored, and not derived
  /// from the operations, so that opening does not depend on replaying them all and so that a
  /// reader which cannot read a newer operation still has the song the writer saw.
  final DocumentState snapshot;

  /// The chart operations after [snapshot], in log order.
  final List<ChartEvent> events;

  /// The PDFs this chart carries, embedded or referenced under D19's rule.
  ///
  /// A list rather than a single value so that the container does not have to change shape the day
  /// a chart needs a second page image; today a `.chart` writes at most the one its song has.
  final List<ChartPdf> attachments;

  /// The document with every operation in [events] applied to [snapshot].
  ///
  /// Throws [DocumentReducerException] when an operation names something the document does not
  /// contain, which is the same failure the reducer reports anywhere else: an operation that cannot
  /// be placed is a document and a log that disagree, and silently skipping it would produce a
  /// chart that is neither the old one nor the new one.
  DocumentState get reducedDocument {
    DocumentState state = snapshot;
    for (final ChartEvent event in events) {
      state = DocumentReducer.apply(state, event);
    }
    return state;
  }

  @override
  bool operator ==(Object other) =>
      other is ChartFile &&
      other.metadata == metadata &&
      other.snapshot == snapshot &&
      _sameList<DocumentEvent>(other.events, events) &&
      _sameList<ChartPdf>(other.attachments, attachments);

  @override
  int get hashCode => Object.hash(
    metadata,
    snapshot,
    Object.hashAll(events),
    Object.hashAll(attachments),
  );

  @override
  String toString() =>
      'ChartFile($metadata, ${snapshot.strokes.length} stroke(s), '
      '${events.length} operation(s), ${attachments.length} attachment(s))';
}

/// What an encode produced: the bytes, and anything the writer had to report about them.
class ChartFileEncodeResult {
  /// Creates a result over [bytes] carrying [warnings], which is empty for an ordinary file.
  const ChartFileEncodeResult({
    required this.bytes,
    this.warnings = const <ChartFileWarning>[],
  });

  /// The whole container, ready to be handed to the caller's file writer.
  final Uint8List bytes;

  /// What D19 left out, in the order it was left out. Empty when everything was embedded.
  final List<ChartFileWarning> warnings;

  /// Whether the writer had to leave anything out.
  bool get hasWarnings => warnings.isNotEmpty;
}

/// What a decode produced: the file, and everything it could not read whole.
class ChartFileDecodeResult {
  /// Creates a result over [file] carrying [warnings], which is empty for an ordinary file.
  const ChartFileDecodeResult({
    required this.file,
    this.warnings = const <ChartFileWarning>[],
  });

  /// The decoded file. A file that was truncated, corrupt or of an unknown envelope version is
  /// never reported here as a plausible document; it throws instead.
  final ChartFile file;

  /// The parts of the file this build did not read, in the order it met them.
  final List<ChartFileWarning> warnings;

  /// Whether anything in the file was skipped. A caller that edits and re-saves should see this
  /// before assuming the document it shows is the whole file.
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Whether two lists hold equal elements in the same order.
bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

/// Whether two byte lists hold the same bytes.
///
/// A [Uint8List]'s own `==` is identity, so an embedded PDF would compare unequal to an identical
/// one without this; a round trip that compared identity would pass while comparing nothing.
bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
