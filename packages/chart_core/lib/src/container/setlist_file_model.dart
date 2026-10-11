// PURPOSE: Hold a whole `.setlist` file as one value — what the file knows about itself, the
//          programme it starts from, and the operations after that — so that encoding and decoding
//          have a single shape to agree on and a caller can inspect a file without parsing bytes.
// INPUTS: The file's metadata, a [Setlist] snapshot, and a `setlist.*` operation tail.
// OUTPUTS: Immutable values with value equality, so a round trip is checkable with `==`. The
//          programme after the operation tail is available as [SetlistFile.reducedSetlist], which
//          throws [DocumentReducerException] when an operation cannot be applied to the snapshot.
// KEYWORDS: setlist-file, metadata, snapshot, operations, value-semantics, programme
part of 'setlist_file.dart';

/// What a `.setlist` file knows about itself rather than about the music.
///
/// The programme's own facts — its name and its entries — live in the [Setlist] inside
/// [SetlistFile.snapshot]. This type holds only what is about the FILE: the identity its operation
/// log is keyed by, when it was written, and what wrote it.
class SetlistMetadata {
  /// Creates metadata for the document [docId], optionally dated and attributed.
  ///
  /// [docId] is the identity the operation log is keyed by, and it must not be empty: an operation
  /// carries its document id, and a container whose operations belong to no document cannot be
  /// checked against anything. It is the SETLIST's id — `Setlist.id`, which is also the `docId`
  /// every `setlist.*` event carries — and never a chart's id.
  const SetlistMetadata({
    required this.docId,
    this.createdAt,
    this.modifiedAt,
    this.writer = '',
  });

  /// The document identity every operation in this file must carry.
  final String docId;

  /// When the programme was first written, or null when the writer did not record it.
  ///
  /// The codec writes the instant in UTC, so a value read back is a UTC [DateTime] and compares
  /// equal to a UTC value passed in. A caller that supplies a local time gets the same instant back
  /// in UTC, which its own `==` will not match; compare with [DateTime.isAtSameMomentAs] in that
  /// case. Nothing here reads a clock: a caller that wants a timestamp passes one.
  final DateTime? createdAt;

  /// When the programme was last written, with the same UTC rule as [createdAt].
  final DateTime? modifiedAt;

  /// A free-form note about what wrote the file, empty when nothing was recorded.
  final String writer;

  @override
  bool operator ==(Object other) =>
      other is SetlistMetadata &&
      other.docId == docId &&
      other.createdAt == createdAt &&
      other.modifiedAt == modifiedAt &&
      other.writer == writer;

  @override
  int get hashCode => Object.hash(docId, createdAt, modifiedAt, writer);

  @override
  String toString() =>
      'SetlistMetadata($docId'
      '${writer.isEmpty ? '' : ', "$writer"'}'
      '${createdAt == null ? '' : ', created $createdAt'})';
}

/// One `.setlist` file's worth of content.
class SetlistFile {
  /// Creates a setlist file over [snapshot], with [events] applying on top of it.
  ///
  /// [metadata]'s `docId` must be non-empty and every operation must carry the same id; both are
  /// checked when the file is encoded, with a [ContainerWriteException].
  const SetlistFile({
    required this.metadata,
    required this.snapshot,
    this.events = const <SetlistEvent>[],
  });

  /// What the file knows about itself.
  final SetlistMetadata metadata;

  /// The document the operation tail starts from.
  ///
  /// This is the programme at the moment the log was cut. It is stored, and not derived from the
  /// operations, so that opening does not depend on replaying them all and so that a reader which
  /// cannot read a newer operation still has the running order the writer saw.
  final Setlist snapshot;

  /// The setlist operations after [snapshot], in log order.
  final List<SetlistEvent> events;

  /// The programme with every operation in [events] applied to [snapshot].
  ///
  /// Throws [DocumentReducerException] when an operation names an entry the programme does not
  /// contain, which is the same failure the reducer reports anywhere else: an operation that cannot
  /// be placed is a programme and a log that disagree, and silently skipping it would produce a
  /// running order that is neither the old one nor the new one.
  Setlist get reducedSetlist {
    Setlist state = snapshot;
    for (final SetlistEvent event in events) {
      state = DocumentReducer.applySetlist(state, event);
    }
    return state;
  }

  @override
  bool operator ==(Object other) =>
      other is SetlistFile &&
      other.metadata == metadata &&
      other.snapshot == snapshot &&
      _sameEvents(other.events, events);

  @override
  int get hashCode => Object.hash(metadata, snapshot, Object.hashAll(events));

  @override
  String toString() =>
      'SetlistFile($metadata, ${snapshot.items.length} entr'
      '${snapshot.items.length == 1 ? 'y' : 'ies'}, '
      '${events.length} operation(s))';
}

/// What an encode produced: the bytes, and anything the writer had to report about them.
class SetlistFileEncodeResult {
  /// Creates a result over [bytes] carrying [warnings], which is empty for an ordinary file.
  const SetlistFileEncodeResult({
    required this.bytes,
    this.warnings = const <SetlistFileWarning>[],
  });

  /// The whole container, ready to be handed to the caller's file writer.
  final Uint8List bytes;

  /// Everything the writer had to leave out. Empty for this format today, which embeds nothing.
  final List<SetlistFileWarning> warnings;

  /// Whether the writer had to leave anything out.
  bool get hasWarnings => warnings.isNotEmpty;
}

/// What a decode produced: the file, and everything it could not read whole.
class SetlistFileDecodeResult {
  /// Creates a result over [file] carrying [warnings], which is empty for an ordinary file.
  const SetlistFileDecodeResult({
    required this.file,
    this.warnings = const <SetlistFileWarning>[],
  });

  /// The decoded file. A file that was truncated, corrupt or of an unknown envelope version is
  /// never reported here as a plausible programme; it throws instead.
  final SetlistFile file;

  /// The parts of the file this build did not read, in the order it met them.
  final List<SetlistFileWarning> warnings;

  /// Whether anything in the file was skipped. A caller that edits and re-saves should see this
  /// before assuming the programme it shows is the whole file.
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Whether two event lists hold equal elements in the same order.
///
/// A `List`'s own `==` is identity, so a round-trip comparison written with it would pass while
/// comparing nothing; this is the comparison that makes the check real.
bool _sameEvents(List<SetlistEvent> left, List<SetlistEvent> right) {
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
