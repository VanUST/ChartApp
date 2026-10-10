// PURPOSE: Record a committed handwritten stroke entering or leaving a document. The eraser in
//          this design deletes whole strokes, so these two events are the entire ink history: a
//          stroke is never edited in place, and the live platform surface that produced it is not
//          part of the record at all.
// INPUTS: The stroke in its canonical anchor-local form, and the position it occupies in the
//         document's stroke list.
// OUTPUTS: Immutable events and their inverses. Both carry the position, because the order of
//          strokes is render order and a stroke restored at the end instead of where it was would
//          change which ink lies on top of which. Both carry the whole stroke: the inverse of a
//          deletion has to put back the exact geometry, and the geometry is the only thing that
//          was deleted.
// KEYWORDS: ink-event, stroke, undo, erase, canonical-form, render-order, anchor-local
part of 'oplog.dart';

/// Inserts a committed stroke into the document's stroke list.
class InkStrokeAddEvent extends ChartEvent {
  /// Creates an insertion of [stroke] at [index].
  const InkStrokeAddEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.stroke,
  });

  /// Zero-based position the stroke takes in the document's stroke list, or the list's length to
  /// append.
  final int index;

  /// The stroke, in canonical form, with its own anchor and anchor-local points.
  final InkStroke stroke;
  @override
  String get type => 'ink.stroke.add';
  @override
  EventAnchor get anchor => stroke.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'stroke': stroke.toJson(),
  };
  @override
  InkStrokeDeleteEvent inverse() => InkStrokeDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    stroke: stroke,
  );
  @override
  InkStrokeAddEvent withSeq(int seq) =>
      InkStrokeAddEvent(docId: docId, seq: seq, index: index, stroke: stroke);
  @override
  bool operator ==(Object other) =>
      other is InkStrokeAddEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.stroke == stroke;
  @override
  int get hashCode => Object.hash(docId, seq, index, stroke);
}

/// Removes a stroke from the document's stroke list.
class InkStrokeDeleteEvent extends ChartEvent {
  /// Creates a deletion of [stroke] from position [index].
  ///
  /// The stroke is removed by identity, not by position, so that a delete recorded against a
  /// stroke is applied to that stroke even if earlier edits shifted the list. The position is
  /// carried for the inverse alone.
  const InkStrokeDeleteEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.stroke,
  });

  /// Zero-based position the stroke occupied, used by the inverse.
  final int index;

  /// The stroke that was removed, in full.
  final InkStroke stroke;
  @override
  String get type => 'ink.stroke.delete';
  @override
  EventAnchor get anchor => stroke.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'stroke': stroke.toJson(),
  };
  @override
  InkStrokeAddEvent inverse() =>
      InkStrokeAddEvent(docId: docId, seq: seq, index: index, stroke: stroke);
  @override
  InkStrokeDeleteEvent withSeq(int seq) => InkStrokeDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    stroke: stroke,
  );
  @override
  bool operator ==(Object other) =>
      other is InkStrokeDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.stroke == stroke;
  @override
  int get hashCode => Object.hash(docId, seq, index, stroke);
}
