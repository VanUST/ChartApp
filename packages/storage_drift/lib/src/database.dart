// PURPOSE: Declare the SQLite schema and the drift database that owns it. The schema is declared
//          once, here, so that a change to it is a single visible edit with a migration attached,
//          rather than a table created somewhere by whoever needed it first.
// INPUTS: A drift query executor. [ChartDatabase.openFile] builds one over a database file; tests
//         build one over memory.
// OUTPUTS: A ChartDatabase exposing the six tables of the design. Opening an in-memory database
//          is always available; opening a file requires only a path, because this package does
//          not depend on Flutter and does not decide where the app keeps its data.
// KEYWORDS: schema, drift, sqlite, documents, event-log, ink-blobs, setlists, migrations
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

/// The `documents` table: one row per chart, carrying the snapshot the tail is folded onto.
class Documents extends Table {
  /// Document identity, and the key every other table refers to.
  TextColumn get id => text()();

  /// The title as written.
  TextColumn get title => text().withDefault(const Constant(''))();

  /// The key the chart is written in, as a spelled tonic plus mode.
  ///
  /// Stored as text because a key is not a number: C-sharp major and D-flat major sound alike and
  /// are different keys, and a numeric pitch class would throw that distinction away at the
  /// storage boundary, where it is hardest to recover.
  ///
  /// The design document names this column `key`. It is called `songKey` here because `key` is a
  /// name Dart reserves in enough contexts to make the generated accessors awkward.
  TextColumn get songKey => text().withDefault(const Constant('C major'))();

  /// Tempo in beats per minute, or 0 when the chart sets none.
  IntColumn get bpm => integer().withDefault(const Constant(0))();

  /// When this row was last written, as an ISO-8601 UTC string.
  ///
  /// Text rather than a native date type so that the stored value is exactly what the writer
  /// produced: no timezone interpretation happens on the way in or out, and ISO-8601 UTC sorts
  /// lexicographically, so "most recently updated" is still an ordinary ORDER BY.
  TextColumn get updatedAt => text()();

  /// The snapshot: a serialised document as of [snapshotSeq], or null when no snapshot has been
  /// taken and the whole history is in the event tail.
  TextColumn get snapshotJson => text().nullable()();

  /// The sequence number the snapshot folds up to.
  ///
  /// Reading a document is: take this snapshot, then apply every event with a greater sequence.
  /// Nothing else is read, which is what makes open cost proportional to the tail rather than to
  /// the document's whole history.
  IntColumn get snapshotSeq => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// The `document_events` table: the append-only log that is the source of truth.
///
/// APPEND-ONLY is an invariant, not a description. A correction is a new row; nothing in this
/// package updates or deletes a row here. That is what makes undo an audit trail rather than a
/// lossy stack, and it is why a document can be reconstructed from any later device's log.
class DocumentEvents extends Table {
  /// The document this event belongs to.
  TextColumn get docId => text()();

  /// Position in this document's log. Unique per document, assigned by the writer.
  IntColumn get seq => integer()();

  /// Identifier of the device that produced the event, for attributing a merge.
  TextColumn get deviceId => text().withDefault(const Constant(''))();

  /// When the event was produced, as an ISO-8601 UTC string. Preserved exactly as written, which
  /// is why it is text: an event may arrive from another device with another clock, and
  /// reinterpreting its timestamp on this one would rewrite history.
  TextColumn get ts => text()();

  /// The event type, such as `chord.insert`.
  TextColumn get type => text()();

  /// The event payload and its anchor, as JSON.
  ///
  /// Opaque to this package. The payload's shape belongs to the op-log's owner, and parsing it
  /// here would mean this package had to be changed by every change to an event.
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{docId, seq};
}

/// The `ink_blobs` table: handwritten strokes, stored as files and referenced by path.
///
/// A stroke is not stored inline. PencilKit archives and InkView serialisations run to hundreds of
/// kilobytes each, and putting them in a row would make every snapshot rewrite them.
class InkBlobs extends Table {
  /// Stroke identity.
  TextColumn get id => text()();

  /// The document the stroke belongs to.
  TextColumn get docId => text()();

  /// The anchor the stroke was captured against, as JSON.
  ///
  /// Coordinates inside the stroke file are anchor-local, which is what lets a stroke survive
  /// transposition and reflow: when the anchor moves, the stroke moves with it and its own
  /// geometry is unchanged.
  TextColumn get anchorJson => text()();

  /// The native encoding of the stroke file, such as `pencilkit` or `inkview`.
  TextColumn get format => text()();

  /// Where the stroke file lives, relative to the document's blob directory.
  TextColumn get path => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// The `setlists` table.
class Setlists extends Table {
  /// Setlist identity.
  TextColumn get id => text()();

  /// The setlist's name.
  TextColumn get title => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// The `setlist_items` table: the ordered entries of a setlist.
class SetlistItems extends Table {
  /// The setlist this entry belongs to.
  TextColumn get setlistId => text()();

  /// Position in the setlist. Ordering is explicit rather than by insertion, so that a reorder is
  /// a rewrite of positions and not a dependency on rowid behaviour.
  IntColumn get pos => integer()();

  /// The document this entry plays.
  TextColumn get docId => text()();

  /// Semitones to transpose this entry by, which may differ from the song's own key.
  IntColumn get transposeSem => integer().withDefault(const Constant(0))();

  /// Notes the performer attached to this entry.
  TextColumn get notes => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{setlistId, pos};
}

/// The `meta` table: key/value storage for schema-level facts.
class Meta extends Table {
  /// The key.
  TextColumn get k => text()();

  /// The value.
  TextColumn get v => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{k};
}

/// The ChartApp database.
@DriftDatabase(
  tables: <Type>[
    Documents,
    DocumentEvents,
    InkBlobs,
    Setlists,
    SetlistItems,
    Meta,
  ],
)
class ChartDatabase extends _$ChartDatabase {
  /// Creates a database over an arbitrary executor.
  ChartDatabase(super.executor);

  // PURPOSE: Open the database held in a file, which is the operation cold-open pays for.
  // INPUTS: path — the database file. The caller decides where it lives; this package does not
  //         depend on Flutter and so has no way to ask the platform for a documents directory.
  // OUTPUTS: A database backed by that file. The file is created if it does not exist; the
  //          directory is not, because a missing directory is a caller error worth reporting.
  // KEYWORDS: open, native-database, file-path, cold-open
  /// Opens the database stored at [path].
  ChartDatabase.openFile(String path) : super(NativeDatabase(File(path)));

  /// Creates a database entirely in memory, for a test that wants no file.
  ChartDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
