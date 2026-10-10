// PURPOSE: Provide the one place that reads and writes a document, so the append-only rule and
//          the snapshot-plus-tail rule are enforced here instead of being re-implemented — and
//          eventually forgotten — by every caller that needs a chart on screen.
// INPUTS: A ChartDatabase, and the values of a document or an event.
// OUTPUTS: An [OpenDocument] holding exactly what opening a chart needs: its metadata, its
//          snapshot, and the tail of events after that snapshot. Reading a document never loads
//          its whole history, so open cost is proportional to the tail.
// KEYWORDS: repository, document-store, append-only, snapshot, cold-open, drift
import 'package:drift/drift.dart';

import 'database.dart';

/// One event to append to a document's log.
class DocumentEventInput {
  /// Creates an event at [seq] of [type], carrying [json].
  const DocumentEventInput({
    required this.seq,
    required this.type,
    required this.json,
    required this.ts,
    this.deviceId = '',
  });

  /// Position in the document's log.
  final int seq;

  /// The event type, such as `chord.insert`.
  final String type;

  /// The event payload and anchor, as JSON. Opaque to this package.
  final String json;

  /// When the event was produced, as an ISO-8601 UTC string.
  final String ts;

  /// The device that produced it, or empty when unknown.
  final String deviceId;

  @override
  String toString() => 'DocumentEventInput($seq, $type)';
}

/// Everything needed to open a chart: its metadata, its snapshot, and the events after it.
class OpenDocument {
  /// Creates an open document.
  const OpenDocument({
    required this.id,
    required this.title,
    required this.songKey,
    required this.bpm,
    required this.updatedAt,
    required this.snapshotJson,
    required this.snapshotSeq,
    required this.tail,
  });

  /// Document identity.
  final String id;

  /// The title as written.
  final String title;

  /// The key the chart is written in, as it was stored.
  final String songKey;

  /// Tempo in beats per minute, or 0 when unset.
  final int bpm;

  /// When the document was last written, as an ISO-8601 UTC string.
  final String updatedAt;

  /// The snapshot to start from, or null when the whole state is in [tail].
  final String? snapshotJson;

  /// The sequence the snapshot folds up to. Zero when there is no snapshot.
  final int snapshotSeq;

  /// Events after [snapshotSeq], in ascending sequence order.
  ///
  /// Ordered here rather than left to the caller: a fold applied out of order produces a different
  /// document, and the ordering is a property of the log, not of whoever happens to read it.
  final List<DocumentEventInput> tail;

  @override
  String toString() =>
      'OpenDocument($id, ${tail.length} tail event(s), snapshotSeq $snapshotSeq)';
}

/// Reads and writes documents.
class ChartStore {
  /// Creates a store over [database].
  ChartStore(this.database);

  /// Opens the store held in the file at [path].
  static ChartStore openFile(String path) =>
      ChartStore(ChartDatabase.openFile(path));

  /// Creates a store entirely in memory, for a test that wants no file.
  static ChartStore inMemory() => ChartStore(ChartDatabase.inMemory());

  /// The database underneath, for a caller that needs a table this store does not cover yet.
  final ChartDatabase database;

  /// Closes the database and releases the file handle.
  Future<void> close() => database.close();

  // PURPOSE: Create or replace a document's metadata and snapshot in one write, so a reader can
  //          never observe a snapshot that claims a sequence its events do not support.
  // INPUTS: id and title identify the document; songKey and bpm are its metadata; snapshotJson and
  //         snapshotSeq are the fold point, where a null snapshot means "no snapshot yet" and the
  //         sequence must be 0; updatedAt is the timestamp to record.
  // OUTPUTS: Nothing. The row is inserted or replaced by primary key.
  //
  //          This is an upsert of the DOCUMENT ROW, which is not a violation of the append-only
  //          rule: that rule governs the event log. The snapshot is a derived cache of the log, so
  //          replacing it is exactly what taking a new snapshot means, and the events it folds are
  //          left untouched.
  // KEYWORDS: upsert, snapshot, document-metadata, derived-cache
  /// Writes a document's metadata and snapshot.
  Future<void> putDocument({
    required String id,
    required String title,
    required String songKey,
    required int bpm,
    required String? snapshotJson,
    required int snapshotSeq,
    required String updatedAt,
  }) {
    return database
        .into(database.documents)
        .insertOnConflictUpdate(
          DocumentsCompanion.insert(
            id: id,
            title: Value(title),
            songKey: Value(songKey),
            bpm: Value(bpm),
            updatedAt: updatedAt,
            snapshotJson: Value(snapshotJson),
            snapshotSeq: Value(snapshotSeq),
          ),
        );
  }

  // PURPOSE: Append events to a document's log without touching anything already there.
  // INPUTS: docId — the document. events — the events to add, each carrying its own sequence
  //         number.
  // OUTPUTS: Nothing. The insert ignores a sequence number that already exists rather than
  //          replacing it, because two events cannot occupy one position and the one already
  //          stored is the one that happened.
  //
  //          The whole batch is one transaction: a partially applied batch would leave the log
  //          with a gap, and a gap is indistinguishable from a lost event.
  // KEYWORDS: append-only, transaction, insert-ignore, idempotent-import
  /// Appends [events] to the log of the document [docId].
  Future<void> appendEvents(String docId, Iterable<DocumentEventInput> events) {
    return database.transaction(() async {
      for (final DocumentEventInput event in events) {
        await database
            .into(database.documentEvents)
            .insert(
              DocumentEventsCompanion.insert(
                docId: docId,
                seq: event.seq,
                deviceId: Value(event.deviceId),
                ts: event.ts,
                type: event.type,
                json: event.json,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
  }

  // PURPOSE: Read everything needed to open a chart, in the two queries the design's cold-open
  //          path is defined by: the document row, and the events after its snapshot.
  // INPUTS: docId — the document to open.
  // OUTPUTS: An [OpenDocument], or null when no such document exists. The tail contains only
  //          events with a sequence greater than the snapshot's, in ascending order, so a caller
  //          folds the snapshot once and then applies the tail.
  //
  //          Null rather than an exception for a missing document: whether that is an error
  //          depends on the caller — an open request for a deleted chart is ordinary, while an
  //          import that lost a row is not.
  // KEYWORDS: cold-open, snapshot-plus-tail, two-queries, boundary-condition
  /// Loads the document [docId], or null when it does not exist.
  Future<OpenDocument?> loadForOpen(String docId) async {
    final Document? row = await (database.select(
      database.documents,
    )..where((Documents table) => table.id.equals(docId))).getSingleOrNull();
    if (row == null) {
      return null;
    }

    // The statement is built in two steps rather than one cascade expression, so that its type is
    // inferred from `select` and the lambdas below take their parameter types from it. Naming the
    // type explicitly would mean naming drift's generated table class, which would put a
    // code-generation detail into hand-written code.
    final statement = database.select(database.documentEvents)
      ..where(
        (DocumentEvents table) =>
            table.docId.equals(docId) &
            table.seq.isBiggerThanValue(row.snapshotSeq),
      )
      ..orderBy([(table) => OrderingTerm.asc(table.seq)]);
    final List<DocumentEvent> tail = await statement.get();

    return OpenDocument(
      id: row.id,
      title: row.title,
      songKey: row.songKey,
      bpm: row.bpm,
      updatedAt: row.updatedAt,
      snapshotJson: row.snapshotJson,
      snapshotSeq: row.snapshotSeq,
      tail: <DocumentEventInput>[
        for (final DocumentEvent event in tail)
          DocumentEventInput(
            seq: event.seq,
            type: event.type,
            json: event.json,
            ts: event.ts,
            deviceId: event.deviceId,
          ),
      ],
    );
  }

  // PURPOSE: Report how many events a document's log holds, which is what a caller checks before
  //          deciding that pruning or re-snapshotting is worth doing.
  // INPUTS: docId — the document.
  // OUTPUTS: The number of rows in the log for that document, including those the snapshot
  //          already folds. Zero for an unknown document rather than null, because "no events"
  //          and "no document" lead to the same decision here.
  // KEYWORDS: count, log-size, maintenance-decision
  /// Returns how many events the log of [docId] holds.
  Future<int> eventCount(String docId) async {
    final rows = await (database.select(
      database.documentEvents,
    )..where((DocumentEvents table) => table.docId.equals(docId))).get();
    return rows.length;
  }

  // PURPOSE: Store a schema-level key/value pair, so a migration or a feature flag has somewhere
  //          to record its state that is not another table.
  // INPUTS: k — the key. v — the value.
  // OUTPUTS: Nothing. Writing an existing key replaces its value.
  // KEYWORDS: meta, key-value, upsert
  /// Writes the metadata entry [k] with value [v].
  Future<void> setMeta(String k, String v) {
    return database
        .into(database.meta)
        .insertOnConflictUpdate(MetaCompanion.insert(k: k, v: v));
  }

  // PURPOSE: Read a schema-level key/value pair.
  // INPUTS: k — the key.
  // OUTPUTS: The value, or null when the key is absent.
  // KEYWORDS: meta, key-value, read
  /// Returns the metadata entry [k], or null.
  Future<String?> getMeta(String k) async {
    final MetaData? row = await (database.select(
      database.meta,
    )..where((Meta table) => table.k.equals(k))).getSingleOrNull();
    return row?.v;
  }
}
