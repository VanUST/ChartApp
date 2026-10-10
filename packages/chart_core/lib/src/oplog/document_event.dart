// PURPOSE: Declare the shape every document event shares, so that undo, autosave and a future
//          sync all fold one kind of value instead of each keeping its own notion of an edit.
//          The hierarchy is sealed, which is the point: a consumer that switches over the events
//          is told by the compiler when a family is added, and cannot silently ignore one.
// INPUTS: The document id the event belongs to and its sequence number in that document's log.
// OUTPUTS: An immutable event carrying its own inverse. [DocumentEvent.toJson] is implemented
//          once here, over [type], [anchor] and [payloadJson], so a new event cannot forget the
//          format version, the document id or the discriminator.
// KEYWORDS: event, op-log, sealed, inverse, json, sequence-number, document-id, exhaustive-switch
//
// WHY THE IDENTITY IS ON THE EVENT AND NOT ONLY ON THE LOG ROW.
//
// The storage layer indexes `document_events(doc_id, seq)` and replays everything the snapshot
// does not already fold up. Putting both on the event means an event carries enough to be placed
// in that log by itself: a caller holding an event can decide whether it belongs to the document
// in front of it and whether it is newer than the snapshot, without a second lookup. The id is
// also what keeps a replayed inverse from being applied to the wrong document.
//
// WHY THE INVERSE IS AN EVENT RATHER THAN AN UNDO METHOD.
//
// Recording the inverse as an event makes undo an ordinary append: the audit trail keeps both the
// edit and its reversal, and a device that never saw the original still converges. An undo
// implemented as "pop the last event" would erase the record of what happened, which is exactly
// what a document that is edited on two devices cannot afford.
part of 'oplog.dart';

/// The version of the encoded event format written into every event object as `v`.
///
/// A reader compares nothing against it today; it is written so that a future reader can, and so
/// that a file whose format changed is identifiable rather than merely wrong.
const int documentEventFormatVersion = 1;

/// One recorded edit to a document.
sealed class DocumentEvent {
  /// Creates an event belonging to [docId] at sequence number [seq].
  const DocumentEvent({required this.docId, required this.seq});

  /// The document this event belongs to.
  final String docId;

  /// Position of this event in its document's log, monotonically increasing per document.
  final int seq;

  /// The discriminator written as `type`, such as `chord.insert`.
  String get type;

  /// The place this event acts on, or null for an event that addresses its target another way
  /// (a whole section, the document's key, a setlist entry).
  ///
  /// The default is null because most families address their target through their payload — a
  /// section index, a key, a list position — and an anchor invented for those would be a place
  /// that means nothing. Only the spatially addressed families override it.
  EventAnchor? get anchor => null;

  /// The family-specific fields, as a JSON object.
  Map<String, Object?> payloadJson();

  /// The event that undoes this one, carrying the same document id and sequence number.
  ///
  /// The returned event's [seq] is this event's, because the inverse is a description of the
  /// reversal and not yet a log row. A writer appending it assigns a fresh sequence with
  /// [withSeq]; equality between two events still compares the sequence, so the renumbering is
  /// visible.
  DocumentEvent inverse();

  /// Returns this event with its sequence number replaced by [seq].
  ///
  /// Appending an inverse needs this, and so does rebuilding a log from a snapshot that was
  /// taken at a different offset.
  DocumentEvent withSeq(int seq);

  /// Writes this event as a stable JSON object with a `type` discriminator.
  Map<String, Object?> toJson() {
    final EventAnchor? where = anchor;
    return <String, Object?>{
      'v': documentEventFormatVersion,
      'docId': docId,
      'seq': seq,
      'type': type,
      if (where != null) 'anchor': where.toJson(),
      'payload': payloadJson(),
    };
  }

  @override
  String toString() => '$type(docId: $docId, seq: $seq)';
}

/// An event that edits a chart document, which is what [DocumentState] folds.
sealed class ChartEvent extends DocumentEvent {
  /// Creates a chart event belonging to [docId] at [seq].
  const ChartEvent({required super.docId, required super.seq});

  /// The chart event that undoes this one.
  ///
  /// Narrowed from the base so that a caller folding a chart never has to downcast the inverse
  /// before applying it: every chart event's inverse is again a chart event.
  @override
  ChartEvent inverse();
}

/// An event that edits a setlist document.
///
/// Setlists are a separate branch rather than a family inside [ChartEvent] so that the chart
/// reducer's switch stays exhaustive over chart edits alone: a caller that folds a chart cannot
/// be handed a setlist event, and the compiler says so.
sealed class SetlistEvent extends DocumentEvent {
  /// Creates a setlist event belonging to [docId], which is the setlist's id, at [seq].
  const SetlistEvent({required super.docId, required super.seq});

  /// The setlist event that undoes this one.
  ///
  /// Narrowed from the base so that a caller folding a setlist never has to downcast the inverse
  /// before applying it.
  @override
  SetlistEvent inverse();
}
