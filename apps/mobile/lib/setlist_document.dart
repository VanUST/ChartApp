// PURPOSE: Build the `.setlist` file that represents a programme being edited, in one place, so the
//          Save button, a probe and any future exporter all produce the same file. A second
//          construction of the metadata would be a second chance to write a document id that does
//          not match the operations the file carries.
// INPUTS: The programme's editing session — which holds both the value it started from and the
//         operations applied since — and the instant to record as the modification time.
// OUTPUTS: A [SetlistFile] whose snapshot is the session's BASE programme and whose operation tail
//          is the session's log. Deliberately free of Flutter, so it can be exercised by `dart run`
//          without a window.
// KEYWORDS: setlist-file, programme, snapshot, op-log, metadata, doc-id, flutter-free
//
// WHY THE SNAPSHOT IS THE BASE AND THE TAIL IS THE LOG, AND WHY NEITHER IS DERIVED FROM THE OTHER.
//
// A `.setlist` file is a snapshot plus the operations after it, and this function is where an edited
// session becomes that pair. The snapshot is the programme as it stood when the session opened, so a
// reader that does not understand a newer operation still gets the running order the writer saw; the
// tail is everything applied since, so the file also records HOW the programme got there and undo,
// redo and a future sync have something to replay. Writing the CURRENT programme as the snapshot
// with the tail beside it would store every edit twice and re-apply it on the way back in.
import 'package:chart_core/chart_core.dart';

// PURPOSE: Build the `.setlist` document a session is saved as.
// INPUTS: session — the programme being edited. modifiedAt — the instant to record, or null to
//         record none; nothing here reads a clock.
// OUTPUTS: A [SetlistFile] carrying the session's base programme, its whole log and no attachments.
//          The document id is the session's own `docId`, which is also the `docId` every event in
//          the log carries, so the container's own check accepts them; reducing the result returns
//          the programme the musician is looking at, which is the property a round trip has to have.
// KEYWORDS: setlist-file, snapshot, operation-tail, written-form, metadata, doc-id, base-programme
/// Returns the `.setlist` document that represents [session].
SetlistFile setlistFileFor(SetlistSession session, {DateTime? modifiedAt}) =>
    SetlistFile(
      metadata: SetlistMetadata(
        docId: session.docId,
        modifiedAt: modifiedAt?.toUtc(),
        writer: 'chartapp',
      ),
      snapshot: session.baseSetlist,
      events: session.log,
    );

// PURPOSE: Open the editing session a decoded `.setlist` file describes, which is the other half of
//          [setlistFileFor] and the pair that has to agree: what the writer split into a snapshot
//          and a tail, the reader folds back together and continues.
// INPUTS: docId — the id the file's own operation log is keyed by. snapshot — the programme before
//         the tail. events — the tail, in log order.
// OUTPUTS: A [SetlistSession] whose programme is the snapshot with every event applied and whose
//          sequence continues past the tail's highest number, so the next edit appends a row nobody
//          has used. The id is the FILE's and not one derived from the snapshot, because a session
//          that renamed its document would write events the container refuses on the next save.
//
//          AN EMPTY TAIL IS THE ORDINARY CASE: the file holds a programme and a log with nothing in
//          it, and the session starts at sequence 0 ready to record the first edit. Throws
//          [DocumentReducerException] when a tail operation cannot be applied to the snapshot, which
//          is a programme and a log that disagree and must not be shown as either one.
// KEYWORDS: open-setlist, session, snapshot-plus-tail, seq-continuation, fail-loud
/// Opens the session a decoded `.setlist` file describes.
SetlistSession setlistSessionFor({
  required String docId,
  required Setlist snapshot,
  required List<SetlistEvent> events,
}) => SetlistSession(
  setlist: snapshot,
  docId: docId,
  seq: highestSetlistSeq(events),
  restored: events,
);

// PURPOSE: Find the sequence number a setlist log ends at, so a session continuing it issues the
//          next free number rather than a used one.
// INPUTS: events — setlist operations in log order, possibly empty.
// OUTPUTS: The highest `seq` the events carry, or 0 when there are none. The maximum is taken
//          rather than the last element alone so that a hand-assembled list is still safe.
// KEYWORDS: seq, restored-log, continuation, max, empty-safe
/// Returns the highest sequence number [events] carries, or zero when it carries none.
int highestSetlistSeq(List<SetlistEvent> events) {
  int highest = 0;
  for (final SetlistEvent event in events) {
    if (event.seq > highest) {
      highest = event.seq;
    }
  }
  return highest;
}
