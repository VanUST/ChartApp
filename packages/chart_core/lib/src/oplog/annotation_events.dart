// PURPOSE: Record the edits to anchored marks — create one, remove one, move one, copy one — as
//          events carrying the mark and its place, so an annotation can be rearranged, duplicated
//          and undone without being recomputed from the layout.
// INPUTS: The mark itself, its place (an anchor plus an anchor-local offset), and for a move the
//         place it came from and the place it went to.
// OUTPUTS: Immutable events and their inverses. A move is a before/after pair rather than a
//          displacement, so the inverse is a swap and the event does not depend on the mark's
//          current place to be replayed. An insertion event exists in this family even though the
//          catalogue lists only move, duplicate and delete; it is the missing half of delete's
//          inverse and it is reported as an addition.
// KEYWORDS: annotation-event, insert, delete, move, duplicate, anchored-place, inverse, undo
part of 'oplog.dart';

/// Inserts an annotation into the document's mark list.
///
/// The catalogue's `annotation.*` family lists no insertion, because a mark is normally created by
/// a gesture — a stamp, a pen stroke — rather than typed in. Removing one, though, has to be
/// undoable, and the undo of a deletion IS an insertion, so the half is supplied here rather than
/// faked with a duplicate that pretends to copy a mark it cannot name.
class AnnotationInsertEvent extends ChartEvent {
  /// Creates an insertion of [annotation] at [index].
  const AnnotationInsertEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.annotation,
  });

  /// Zero-based position the mark takes in the document's annotation list, or that list's length
  /// to append.
  final int index;

  /// The mark to insert, in full.
  final Annotation annotation;
  @override
  String get type => 'annotation.insert';
  @override
  EventAnchor get anchor => annotation.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'annotation': annotation.toJson(),
  };
  @override
  AnnotationDeleteEvent inverse() => AnnotationDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: annotation,
  );
  @override
  AnnotationInsertEvent withSeq(int seq) => AnnotationInsertEvent(
    docId: docId,
    seq: seq,
    index: index,
    annotation: annotation,
  );
  @override
  bool operator ==(Object other) =>
      other is AnnotationInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.annotation == annotation;
  @override
  int get hashCode => Object.hash(docId, seq, index, annotation);
}

/// Removes an annotation from the document's mark list.
class AnnotationDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed] from position [index].
  ///
  /// The mark is removed by identity, so a delete recorded against it still finds it after earlier
  /// edits shifted the list; the position is carried for the inverse.
  const AnnotationDeleteEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.removed,
  });

  /// Zero-based position the mark occupied, used by the inverse.
  final int index;

  /// The mark that was removed, in full.
  final Annotation removed;
  @override
  String get type => 'annotation.delete';
  @override
  EventAnchor get anchor => removed.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'annotation': removed.toJson(),
  };
  @override
  AnnotationInsertEvent inverse() => AnnotationInsertEvent(
    docId: docId,
    seq: seq,
    index: index,
    annotation: removed,
  );
  @override
  AnnotationDeleteEvent withSeq(int seq) => AnnotationDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: removed,
  );
  @override
  bool operator ==(Object other) =>
      other is AnnotationDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, index, removed);
}

/// Moves the annotation with a given identity to another place.
class AnnotationMoveEvent extends ChartEvent {
  /// Creates a move of the mark identified by [id] from [from] to [to].
  ///
  /// The identity is part of the event because a move is the one edit that does not restate the
  /// mark's contents: the mark keeps its kind and its payload and only its place changes.
  const AnnotationMoveEvent({
    required super.docId,
    required super.seq,
    required this.id,
    required this.from,
    required this.to,
  });

  /// Identity of the mark being moved.
  final String id;

  /// The place the mark occupied before the move.
  final AnchoredPlace from;

  /// The place the mark occupies after the move.
  final AnchoredPlace to;
  @override
  String get type => 'annotation.move';
  @override
  EventAnchor get anchor => to.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'id': id,
    'from': from.toJson(),
    'to': to.toJson(),
  };
  @override
  AnnotationMoveEvent inverse() =>
      AnnotationMoveEvent(docId: docId, seq: seq, id: id, from: to, to: from);
  @override
  AnnotationMoveEvent withSeq(int seq) =>
      AnnotationMoveEvent(docId: docId, seq: seq, id: id, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is AnnotationMoveEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.id == id &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, id, from, to);
}

/// Copies an annotation into the document's mark list under a new identity.
class AnnotationDuplicateEvent extends ChartEvent {
  /// Creates a duplication of the mark [sourceId], placing [duplicate] at [index].
  ///
  /// The copy is materialised in the event rather than recomputed by the reducer, for the same
  /// reason a duplicated bar is: replay has to be deterministic, and the inverse has to name the
  /// exact mark to remove. The source identity is recorded so a reader can say what was copied.
  const AnnotationDuplicateEvent({
    required super.docId,
    required super.seq,
    required this.sourceId,
    required this.index,
    required this.duplicate,
  });

  /// Identity of the mark being copied.
  final String sourceId;

  /// Zero-based position the copy takes in the document's annotation list.
  final int index;

  /// The copy, which carries its own new identity.
  final Annotation duplicate;
  @override
  String get type => 'annotation.duplicate';
  @override
  EventAnchor get anchor => duplicate.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sourceId': sourceId,
    'index': index,
    'annotation': duplicate.toJson(),
  };
  @override
  AnnotationDeleteEvent inverse() => AnnotationDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: duplicate,
  );
  @override
  AnnotationDuplicateEvent withSeq(int seq) => AnnotationDuplicateEvent(
    docId: docId,
    seq: seq,
    sourceId: sourceId,
    index: index,
    duplicate: duplicate,
  );
  @override
  bool operator ==(Object other) =>
      other is AnnotationDuplicateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sourceId == sourceId &&
      other.index == index &&
      other.duplicate == duplicate;
  @override
  int get hashCode => Object.hash(docId, seq, sourceId, index, duplicate);
}
