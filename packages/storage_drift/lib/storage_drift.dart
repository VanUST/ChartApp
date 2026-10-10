// PURPOSE: Mark the persistence boundary and publish the storage surface, so that a later change
//          does not spread database access into the UI or the domain.
// INPUTS: None.
// OUTPUTS: The drift schema and the repository that reads and writes documents.
// KEYWORDS: storage, schema, op-log, ink-blobs, setlists, pure-dart, public-api
//
// The schema this package owns (design document section 3.2):
//
//   documents(id, title, songKey, bpm, updatedAt, snapshotJson, snapshotSeq)
//   document_events(docId, seq, deviceId, ts, type, json)   -- keyed (docId, seq)
//   ink_blobs(id, docId, anchorJson, format, path)
//   setlists(id, title)
//   setlist_items(setlistId, pos, docId, transposeSem, notes)
//   meta(k, v)
//
// Two invariants make the event log work, and both are enforced in this package rather than left
// to callers:
//
//   1. `document_events` is APPEND-ONLY. A correction is a new row, never an update. This is what
//      makes undo an audit trail instead of a lossy stack, and it is why a document can be
//      reconstructed from a later device's log. The document ROW may still be upserted, because a
//      snapshot is a derived cache of the log rather than a record of what happened.
//   2. Reading a document is: take the snapshot, then apply every event after `snapshotSeq`.
//      Nothing else is read, so open cost is proportional to the tail and not to the document's
//      whole history.
//
// This package is pure Dart on purpose. drift opens a file through `NativeDatabase` without any
// Flutter involvement, and the path is an ordinary value, so the app supplies where to put the
// file while every test here runs under `dart test` with no widget binding. That is what lets the
// cold-open budget be measured on a desktop instead of waiting for a device.

/// SQLite persistence for ChartApp.
library;

export 'src/chart_store.dart';
export 'src/database.dart';
