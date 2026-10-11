// PURPOSE: Turn the document an editing session holds into the `.chart` file that will be written,
//          in one place, so that the save button, a probe and any future exporter all produce the
//          same file. A second construction of the metadata would be a second chance to write a
//          document id that does not match the operations the file carries.
// INPUTS: The [DocumentState] on screen — the song plus any anchored marks — the operation tail
//         that produced it since the snapshot, and the instant to record as the document's
//         modification time.
// OUTPUTS: A [ChartFile] whose snapshot is that document and whose operation tail is the one it was
//          given. Deliberately free of Flutter, so it can be exercised by `dart run` without a
//          window.
// KEYWORDS: chart-file, document, snapshot, op-log, metadata, doc-id, d19, d20, flutter-free
//
// WHY THE SNAPSHOT CARRIES THE WHOLE DOCUMENT AND THE TAIL CARRIES THE EDITS.
//
// A `.chart` file is a snapshot plus the operations after it, and this function is where an edited
// session becomes that pair. The snapshot is the document as it stands, so a reader that does not
// understand a newer operation still gets the chart the writer saw; the tail is the session's log,
// so the file also records HOW it got there and undo, redo and a future sync have something to
// replay. Both are handed over untouched: this function does not fold one into the other, because
// folding would erase the record the tail exists to keep.
import 'package:chart_core/chart_core.dart';

/// The document id written when a song carries none of its own.
///
/// The container requires a non-empty document id, because an operation log needs a document to
/// belong to. A song that has never been assigned one — a chart typed from scratch, before any
/// store has given it an identity — is written under this one rather than being refused.
///
/// Aliased to [EditSession.untitledDocumentId] rather than restated, because the id a file is
/// written under and the id the events inside it carry are the same id, and two constants would
/// eventually disagree.
const String untitledDocumentId = EditSession.untitledDocumentId;

// PURPOSE: Name the document a song is EDITED AND SAVED UNDER, so that a chart typed from scratch
//          and an imported one reach the same answer, and so the session that applies an event and
//          the file that stores it cannot name two different documents.
// INPUTS: song — any song, including one whose `id` is empty, which is every chart that has never
//         been stored.
// OUTPUTS: The song's own id when it has one, and [untitledDocumentId] otherwise. Never empty: a
//          `.chart` container rejects a header whose document id is empty, and an event whose
//          `docId` is empty would name no document at all.
// KEYWORDS: document-id, untitled, from-scratch-chart, one-rule, session-vs-container
//
// WHY THIS IS A FUNCTION AND NOT A TERNARY WRITTEN TWICE. The rule is needed in two places that
// must agree — the session that writes the operation log and the container header that the log is
// checked against — and a container refuses a file whose operations name a different document than
// its header. Two copies of `id.isEmpty ? … : id` would be two chances for that check to fail on a
// chart the musician can actually reach: one typed from scratch, whose `Song.id` is empty.
/// Returns the document id [song] is edited and saved under.
String documentIdFor(Song song) =>
    song.id.isEmpty ? untitledDocumentId : song.id;

// PURPOSE: Build the document a session is saved as.
// INPUTS: document — the state to write, whose song is the WRITTEN chart and never the transposed
//         view. It must be the document BEFORE [events], which is `EditSession.baseDocument` for a
//         session that has been edited; passing the session's CURRENT document instead would store
//         every operation twice, because the container defines the document as the snapshot plus
//         the operations. events — the operations applied since that state, in log order; the empty
//         list is an ordinary document with no log rather than a special case. modifiedAt — the
//         instant to record, or null to record none; nothing here reads a clock.
// OUTPUTS: A [ChartFile] carrying that document, that tail and no attachments. The document id is
//          the song's own id when it has one, so the operations a restored session appended — which
//          were written under that same id — are accepted by the container's own check. Reducing
//          the result returns the document the musician was looking at, which is the property a
//          round trip has to have: reopening a file must not run its own history a second time.
// KEYWORDS: chart-file, snapshot, operation-tail, written-form, metadata, doc-id, base-document
/// Returns the `.chart` document that represents [document] with [events] applied since it.
ChartFile chartFileFor(
  DocumentState document, {
  List<ChartEvent> events = const <ChartEvent>[],
  DateTime? modifiedAt,
}) => ChartFile(
  metadata: ChartMetadata(
    docId: documentIdFor(document.song),
    modifiedAt: modifiedAt?.toUtc(),
    writer: 'chartapp',
  ),
  snapshot: document,
  events: events,
);
