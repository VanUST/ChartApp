// PURPOSE: Record the three edits to the melodic staff — place a note, change it, remove it — on
//          exactly the addressing the chord line uses, so that one undo path covers both and a
//          bar holding chords and a melody is still two independent lists addressed the same way.
// INPUTS: The section and bar index, and the note placement itself, which carries its beat, step,
//         written duration and tie.
// OUTPUTS: Immutable events and their inverses. As with the chord family, inserting into a beat
//          pushes the notes already there one step up and deleting closes the gap, so the notes
//          sharing a cell stay a dense sequence. Percussion is NOT part of this family: a drum
//          hit is addressed the same way but is not a pitch, and folding the two into one event
//          would make "transpose" mean two different things.
// KEYWORDS: note-event, melody, insert, update, delete, inverse, beat-step-address, undo
part of 'oplog.dart';

/// Places a melodic note at its beat and step, pushing the notes already there one step up.
class NoteInsertEvent extends ChartEvent {
  /// Creates an insertion of [note] into bar [barIndex] of section [sectionId].
  const NoteInsertEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.barIndex,
    required this.note,
  });

  /// The section the bar belongs to.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int barIndex;

  /// The note placement to insert, carrying its own beat, step, duration and tie.
  final BeatNote note;
  @override
  String get type => 'note.insert';
  @override
  EventAnchor get anchor => EventAnchor(
    sectionId: sectionId,
    bar: barIndex,
    beat: note.beat,
    step: note.step,
  );
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'note': ModelJson.beatNote(note),
  };
  @override
  NoteDeleteEvent inverse() => NoteDeleteEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    removed: note,
  );
  @override
  NoteInsertEvent withSeq(int seq) => NoteInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    note: note,
  );
  @override
  bool operator ==(Object other) =>
      other is NoteInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.note == note;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, note);
}

/// Replaces the note at one address with another, leaving its address unchanged.
class NoteUpdateEvent extends ChartEvent {
  /// Creates an update of the note at [from]'s address to [to].
  ///
  /// [from] and [to] must address the same (beat, step); moving a note is a deletion and an
  /// insertion, so that the inverse never has to guess which address to restore.
  NoteUpdateEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.barIndex,
    required this.from,
    required this.to,
  }) : assert(
         from.beat == to.beat && from.step == to.step,
         'a note update cannot move a note; use delete then insert',
       );

  /// The section the bar belongs to.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int barIndex;

  /// The note placement being replaced.
  final BeatNote from;

  /// The replacement, at the same beat and step.
  final BeatNote to;
  @override
  String get type => 'note.update';
  @override
  EventAnchor get anchor => EventAnchor(
    sectionId: sectionId,
    bar: barIndex,
    beat: from.beat,
    step: from.step,
  );
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'from': ModelJson.beatNote(from),
    'to': ModelJson.beatNote(to),
  };
  @override
  NoteUpdateEvent inverse() => NoteUpdateEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: to,
    to: from,
  );
  @override
  NoteUpdateEvent withSeq(int seq) => NoteUpdateEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is NoteUpdateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, from, to);
}

/// Removes the note at one address and closes the gap in its beat.
class NoteDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed] from bar [barIndex] of section [sectionId].
  const NoteDeleteEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.barIndex,
    required this.removed,
  });

  /// The section the bar belongs to.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int barIndex;

  /// The note placement that was removed.
  final BeatNote removed;
  @override
  String get type => 'note.delete';
  @override
  EventAnchor get anchor => EventAnchor(
    sectionId: sectionId,
    bar: barIndex,
    beat: removed.beat,
    step: removed.step,
  );
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'note': ModelJson.beatNote(removed),
  };
  @override
  NoteInsertEvent inverse() => NoteInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    note: removed,
  );
  @override
  NoteDeleteEvent withSeq(int seq) => NoteDeleteEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    removed: removed,
  );
  @override
  bool operator ==(Object other) =>
      other is NoteDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, removed);
}
