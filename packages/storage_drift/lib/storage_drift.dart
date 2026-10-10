// PURPOSE: Mark the persistence boundary and record the schema this package is contracted to
//          own, so a later change does not spread database access into the UI or the domain.
// INPUTS: None.
// OUTPUTS: A library with no public API in Phase 0; the drift tables, repositories and
//          migrations are Phase 2/3 work.
// KEYWORDS: storage, schema, op-log, ink-blobs, setlists, phase-0, no-api-yet
//
// The schema this package owns (from the design document):
//
//   documents(id, title, key, bpm, updated_at, snapshot_json, snapshot_seq)
//   document_events(doc_id, seq, device_id, ts, type, json)   -- indexed on (doc_id, seq)
//   ink_blobs(id, doc_id, anchor_json, format, path)
//   setlists(id, title)
//   setlist_items(setlist_id, pos, doc_id, transpose_sem, notes)
//   meta(k, v)
//
// Two invariants make the event log work, and both are enforced here rather than in callers:
//
//   1. `document_events` is append-only. A correction is a new row, never an update; this is
//      what makes undo an audit trail instead of a lossy stack.
//   2. A snapshot is a fold of events up to `snapshot_seq`. Reading a document means loading
//      the snapshot and then the tail after that sequence, and nothing else.
//
// No opener is chosen yet. See the note in pubspec.yaml: sqlite3_flutter_libs is end-of-life,
// and which replacement to use is decided by spike S5 against the cold-open threshold.

/// SQLite persistence for ChartApp.
library;
