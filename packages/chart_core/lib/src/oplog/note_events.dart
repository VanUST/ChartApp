// PURPOSE: Record the three edits to the melodic staff — write a note at a place, change it, remove
//          it — on exactly the addressing the chord line uses, so that one undo path covers both and
//          a bar holding chords and a melody is still two independent lists addressed the same way.
// INPUTS: The note mark itself, whose place names the bar and gives the position in it. There is no
//         separate section, bar, beat or step argument: the owner removed the grid, so a note's
//         horizontal position IS its time and it is stored in the place.
// OUTPUTS: Immutable events and their inverses. A new note does not push its neighbours along a step
//          and deleting one does not close a gap; an update may move the note within its bar, which
//          is what dragging one is. Percussion is NOT part of this family: a drum hit is located the
//          same way but is not a pitch, and folding the two into one event would make "transpose"
//          mean two different things.
// KEYWORDS: note-event, melody, insert, update, delete, inverse, place, no-grid, undo, a73, a75
part of 'oplog.dart';

/// Writes a melodic note at the place its mark carries.
class NoteInsertEvent extends ChartEvent {
  /// Creates an insertion of [note].
  const NoteInsertEvent({
    required super.docId,
    required super.seq,
    required this.note,
  });

  /// The note to write, carrying its place, pitch, duration and tie.
  final NoteMark note;
  @override
  String get type => 'note.insert';
  @override
  EventAnchor get anchor => note.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'note': ModelJson.noteMark(note),
  };
  @override
  NoteDeleteEvent inverse() =>
      NoteDeleteEvent(docId: docId, seq: seq, removed: note);
  @override
  NoteInsertEvent withSeq(int seq) =>
      NoteInsertEvent(docId: docId, seq: seq, note: note);
  @override
  bool operator ==(Object other) =>
      other is NoteInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.note == note;
  @override
  int get hashCode => Object.hash(docId, seq, note);
}

/// Replaces one note mark with another, which under a coordinate model may also move it.
class NoteUpdateEvent extends ChartEvent {
  /// Creates an update of the note at [from]'s place to [to].
  ///
  /// [to] must stay in the same bar as [from], for the same reason a chord update must: an event
  /// that changed the bar would need two answers for where the inverse restores the note.
  NoteUpdateEvent({
    required super.docId,
    required super.seq,
    required this.from,
    required this.to,
  }) : assert(
         from.place.anchor == to.place.anchor,
         'a note update cannot move a note to another bar; '
         'use delete then insert',
       );

  /// The note being replaced.
  final NoteMark from;

  /// The replacement, in the same bar.
  final NoteMark to;
  @override
  String get type => 'note.update';
  @override
  EventAnchor get anchor => from.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'from': ModelJson.noteMark(from),
    'to': ModelJson.noteMark(to),
  };
  @override
  NoteUpdateEvent inverse() =>
      NoteUpdateEvent(docId: docId, seq: seq, from: to, to: from);
  @override
  NoteUpdateEvent withSeq(int seq) =>
      NoteUpdateEvent(docId: docId, seq: seq, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is NoteUpdateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, from, to);
}

/// Removes one note mark from the bar its place names.
class NoteDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed].
  const NoteDeleteEvent({
    required super.docId,
    required super.seq,
    required this.removed,
  });

  /// The note that was removed.
  final NoteMark removed;
  @override
  String get type => 'note.delete';
  @override
  EventAnchor get anchor => removed.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'note': ModelJson.noteMark(removed),
  };
  @override
  NoteInsertEvent inverse() =>
      NoteInsertEvent(docId: docId, seq: seq, note: removed);
  @override
  NoteDeleteEvent withSeq(int seq) =>
      NoteDeleteEvent(docId: docId, seq: seq, removed: removed);
  @override
  bool operator ==(Object other) =>
      other is NoteDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, removed);
}
