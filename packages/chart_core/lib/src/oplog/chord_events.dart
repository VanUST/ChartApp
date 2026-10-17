// PURPOSE: Record the three edits a user makes to the chord line — write a chord at a place, change
//          it, remove it — as events carrying their own inverse, so that undo never needs a second
//          code path and a redo is the inverse of the inverse.
// INPUTS: The chord mark itself, whose place names the bar and gives the position in it. There is
//         no separate section or bar argument, because the place already carries one: two addresses
//         for one mark is the second answer this project removes wherever it finds it, and the
//         annotation family has worked this way since it was written.
// OUTPUTS: Immutable events and their inverses. WRITING A CHORD ANYWHERE IN A BAR IS ONE EVENT: the
//          owner removed the grid, so a new chord does not push its neighbours along a step and
//          deleting one does not close a gap. A chord's position is part of its value, which means
//          an update MAY MOVE IT — that is what moving a chord is, now that there is no address to
//          keep fixed.
// KEYWORDS: chord-event, insert, update, delete, inverse, place, no-grid, undo, d36, a73
part of 'oplog.dart';

/// Writes a chord at the place its mark carries.
class ChordInsertEvent extends ChartEvent {
  /// Creates an insertion of [chord].
  const ChordInsertEvent({
    required super.docId,
    required super.seq,
    required this.chord,
  });

  /// The chord mark to write, carrying its place and its engraving size.
  final ChordMark chord;
  @override
  String get type => 'chord.insert';
  @override
  EventAnchor get anchor => chord.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'chord': ModelJson.chordMark(chord),
  };
  @override
  ChordDeleteEvent inverse() =>
      ChordDeleteEvent(docId: docId, seq: seq, removed: chord);
  @override
  ChordInsertEvent withSeq(int seq) =>
      ChordInsertEvent(docId: docId, seq: seq, chord: chord);
  @override
  bool operator ==(Object other) =>
      other is ChordInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.chord == chord;
  @override
  int get hashCode => Object.hash(docId, seq, chord);
}

/// Replaces one chord mark with another, which under a coordinate model may also move it.
class ChordUpdateEvent extends ChartEvent {
  /// Creates an update of the chord at [from]'s place to [to].
  ///
  /// [to] must live in the same bar as [from] — moving a chord from one bar to another is a
  /// deletion and an insertion, because a single event that changed the bar would have to say which
  /// bar's list the inverse restores it to and there would be two answers. Within a bar, though,
  /// [to] MAY sit at a different place: that is what dragging a chord is.
  ChordUpdateEvent({
    required super.docId,
    required super.seq,
    required this.from,
    required this.to,
  }) : assert(
         from.place.anchor == to.place.anchor,
         'a chord update cannot move a chord to another bar; '
         'use delete then insert',
       );

  /// The chord mark being replaced.
  final ChordMark from;

  /// The replacement, in the same bar.
  final ChordMark to;
  @override
  String get type => 'chord.update';
  @override
  EventAnchor get anchor => from.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'from': ModelJson.chordMark(from),
    'to': ModelJson.chordMark(to),
  };
  @override
  ChordUpdateEvent inverse() =>
      ChordUpdateEvent(docId: docId, seq: seq, from: to, to: from);
  @override
  ChordUpdateEvent withSeq(int seq) =>
      ChordUpdateEvent(docId: docId, seq: seq, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is ChordUpdateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, from, to);
}

/// Removes one chord mark from the bar its place names.
class ChordDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed].
  ///
  /// The removed placement is carried in full rather than described by its place, because the
  /// inverse has to put back exactly what was there and a place alone would restore whatever the
  /// document happens to hold there by the time undo runs.
  const ChordDeleteEvent({
    required super.docId,
    required super.seq,
    required this.removed,
  });

  /// The chord mark that was removed.
  final ChordMark removed;
  @override
  String get type => 'chord.delete';
  @override
  EventAnchor get anchor => removed.place.anchor;
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'chord': ModelJson.chordMark(removed),
  };
  @override
  ChordInsertEvent inverse() =>
      ChordInsertEvent(docId: docId, seq: seq, chord: removed);
  @override
  ChordDeleteEvent withSeq(int seq) =>
      ChordDeleteEvent(docId: docId, seq: seq, removed: removed);
  @override
  bool operator ==(Object other) =>
      other is ChordDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, removed);
}
