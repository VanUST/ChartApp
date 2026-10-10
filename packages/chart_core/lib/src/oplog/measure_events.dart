// PURPOSE: Record the structural edits to a bar — put one in, take one out, copy one — as events
//          that carry whole bars. A bar is the unit a chart is built from, and an inserted bar's
//          inverse is a deletion whose inverse is the insertion of the SAME bar, so the bar has
//          to travel with the event; deriving it again at undo time would restore whatever the
//          bar had become in between.
// INPUTS: The section the edit happens in, the zero-based bar index, and the bar itself.
// OUTPUTS: Immutable events and their inverses. Insertion accepts an index equal to the current
//          bar count, which appends; a duplicate writes its copy at index + 1 and its inverse
//          deletes index + 1. An index outside the section is a reducer failure rather than a
//          silent clamp, because a clamped edit is an edit the user did not make.
// KEYWORDS: measure-event, bar, insert, delete, duplicate, inverse, whole-value, undo
part of 'oplog.dart';

/// Inserts a bar into a section at a given index.
class MeasureInsertEvent extends ChartEvent {
  /// Creates an insertion of [bar] at [index] in section [sectionId].
  const MeasureInsertEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.index,
    required this.bar,
  });

  /// The section the bar is inserted into.
  final String sectionId;

  /// Zero-based index the bar takes, or the section's bar count to append.
  final int index;

  /// The bar to insert, in full.
  final Bar bar;
  @override
  String get type => 'measure.insert';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: index);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'index': index,
    'bar': ModelJson.bar(bar),
  };
  @override
  MeasureDeleteEvent inverse() => MeasureDeleteEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    removed: bar,
  );
  @override
  MeasureInsertEvent withSeq(int seq) => MeasureInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    bar: bar,
  );
  @override
  bool operator ==(Object other) =>
      other is MeasureInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.index == index &&
      other.bar == bar;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, index, bar);
}

/// Removes the bar at a given index, carrying it so the deletion can be undone in place.
class MeasureDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed] at [index] in section [sectionId].
  const MeasureDeleteEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.index,
    required this.removed,
  });

  /// The section the bar is removed from.
  final String sectionId;

  /// Zero-based index of the bar being removed.
  final int index;

  /// The bar that was removed, carried for the inverse.
  final Bar removed;
  @override
  String get type => 'measure.delete';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: index);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'index': index,
    'bar': ModelJson.bar(removed),
  };
  @override
  MeasureInsertEvent inverse() => MeasureInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    bar: removed,
  );
  @override
  MeasureDeleteEvent withSeq(int seq) => MeasureDeleteEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    removed: removed,
  );
  @override
  bool operator ==(Object other) =>
      other is MeasureDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.index == index &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, index, removed);
}

/// Copies the bar at a given index into the position after it.
class MeasureDuplicateEvent extends ChartEvent {
  /// Creates a duplication of the bar at [index] in section [sectionId], placing [duplicate] at
  /// [index] + 1.
  ///
  /// The copy is materialised in the event rather than recomputed by the reducer. Replay has to
  /// be deterministic: an event that says "copy whatever is at index 3" would produce a different
  /// document depending on when it is replayed, and its inverse could not name the bar to remove.
  const MeasureDuplicateEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.index,
    required this.duplicate,
  });

  /// The section the bar is copied in.
  final String sectionId;

  /// Zero-based index of the bar being copied.
  final int index;

  /// The copy that is placed at [index] + 1.
  final Bar duplicate;
  @override
  String get type => 'measure.duplicate';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: index + 1);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'index': index,
    'bar': ModelJson.bar(duplicate),
  };
  @override
  MeasureDeleteEvent inverse() => MeasureDeleteEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index + 1,
    removed: duplicate,
  );
  @override
  MeasureDuplicateEvent withSeq(int seq) => MeasureDuplicateEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    index: index,
    duplicate: duplicate,
  );
  @override
  bool operator ==(Object other) =>
      other is MeasureDuplicateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.index == index &&
      other.duplicate == duplicate;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, index, duplicate);
}
