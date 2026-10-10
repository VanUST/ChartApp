// PURPOSE: Record the edits to the text a musician writes into a chart — put a cue in, type into
//          it, move it, take it out — with editing and moving kept apart, because they are
//          different intentions and a single "changed" event would force undo to decide which one
//          it was undoing.
// INPUTS: The cue itself or its identity, its anchored place, and for an edit the text before and
//         after.
// OUTPUTS: Immutable events and their inverses. An edit carries both texts rather than the new
//          one alone, so its inverse is a swap and needs no access to the cue's current words. A
//          deletion event exists in this family even though the catalogue lists only insert, edit
//          and move; it is the missing half of insert's inverse and it is reported as an addition.
// KEYWORDS: text-cue-event, insert, delete, edit, move, before-after, anchored-place, undo
part of 'oplog.dart';

/// Inserts a text cue into the document's cue list.
class TextCueInsertEvent extends ChartEvent {
  /// Creates an insertion of [cue] at [index].
  const TextCueInsertEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.cue,
  });

  /// Zero-based position the cue takes in the document's text-cue list, or that list's length to
  /// append.
  final int index;

  /// The cue to insert, in full.
  final TextCue cue;
  @override
  String get type => 'textcue.insert';
  @override
  EventAnchor get anchor => cue.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'cue': cue.toJson(),
  };
  @override
  TextCueDeleteEvent inverse() =>
      TextCueDeleteEvent(docId: docId, seq: seq, index: index, removed: cue);
  @override
  TextCueInsertEvent withSeq(int seq) =>
      TextCueInsertEvent(docId: docId, seq: seq, index: index, cue: cue);
  @override
  bool operator ==(Object other) =>
      other is TextCueInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.cue == cue;
  @override
  int get hashCode => Object.hash(docId, seq, index, cue);
}

/// Removes a text cue from the document's cue list.
///
/// This event is the missing half of [TextCueInsertEvent]'s inverse: a cue that can be inserted
/// has to be removable, and the catalogue's `textcue.*` family lists no deletion. It is added
/// here rather than left to a method that throws, and it is reported as an addition.
class TextCueDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed] from position [index].
  const TextCueDeleteEvent({
    required super.docId,
    required super.seq,
    required this.index,
    required this.removed,
  });

  /// Zero-based position the cue occupied, used by the inverse.
  final int index;

  /// The cue that was removed, in full.
  final TextCue removed;
  @override
  String get type => 'textcue.delete';
  @override
  EventAnchor get anchor => removed.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'index': index,
    'cue': removed.toJson(),
  };
  @override
  TextCueInsertEvent inverse() =>
      TextCueInsertEvent(docId: docId, seq: seq, index: index, cue: removed);
  @override
  TextCueDeleteEvent withSeq(int seq) => TextCueDeleteEvent(
    docId: docId,
    seq: seq,
    index: index,
    removed: removed,
  );
  @override
  bool operator ==(Object other) =>
      other is TextCueDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.index == index &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, index, removed);
}

/// Replaces the words of the text cue with a given identity.
class TextCueEditEvent extends ChartEvent {
  /// Creates an edit of the cue [id] from [from] to [to].
  const TextCueEditEvent({
    required super.docId,
    required super.seq,
    required this.id,
    required this.from,
    required this.to,
  });

  /// Identity of the cue being edited.
  final String id;

  /// The words before the edit, empty when the cue was blank.
  final String from;

  /// The words after the edit, empty when the cue was cleared.
  final String to;
  @override
  String get type => 'textcue.edit';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'id': id,
    'from': from,
    'to': to,
  };
  @override
  TextCueEditEvent inverse() =>
      TextCueEditEvent(docId: docId, seq: seq, id: id, from: to, to: from);
  @override
  TextCueEditEvent withSeq(int seq) =>
      TextCueEditEvent(docId: docId, seq: seq, id: id, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is TextCueEditEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.id == id &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, id, from, to);
}

/// Moves the text cue with a given identity to another place.
class TextCueMoveEvent extends ChartEvent {
  /// Creates a move of the cue [id] from [from] to [to].
  const TextCueMoveEvent({
    required super.docId,
    required super.seq,
    required this.id,
    required this.from,
    required this.to,
  });

  /// Identity of the cue being moved.
  final String id;

  /// The place the cue occupied before the move.
  final AnchoredPlace from;

  /// The place the cue occupies after the move.
  final AnchoredPlace to;
  @override
  String get type => 'textcue.move';
  @override
  EventAnchor get anchor => to.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'id': id,
    'from': from.toJson(),
    'to': to.toJson(),
  };
  @override
  TextCueMoveEvent inverse() =>
      TextCueMoveEvent(docId: docId, seq: seq, id: id, from: to, to: from);
  @override
  TextCueMoveEvent withSeq(int seq) =>
      TextCueMoveEvent(docId: docId, seq: seq, id: id, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is TextCueMoveEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.id == id &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, id, from, to);
}
