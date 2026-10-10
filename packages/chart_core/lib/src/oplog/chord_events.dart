// PURPOSE: Record the three edits a user makes to the chord line — place a chord, change it,
//          remove it — as events carrying their own inverse, so that undo never needs a second
//          code path and a redo is the inverse of the inverse.
// INPUTS: The section and bar index the edit happens in, and the chord placement itself, which
//         already carries its beat and step within the bar.
// OUTPUTS: Immutable events and their inverses. Insertion into a beat that already holds chords
//          pushes the later ones one step up and deletion closes the gap again, which is what
//          keeps a comma-packed cell a dense sequence rather than a growing list of gaps. The
//          address of a chord is therefore NOT stable across an insert or delete at the same
//          beat; that is deliberate, because two chords on one beat are two places in the bar
//          and a gap between them is not a place anything can point at.
// KEYWORDS: chord-event, insert, update, delete, inverse, beat-step-address, packing, undo
part of 'oplog.dart';

/// Places a chord at its beat and step, pushing the chords already there one step up.
class ChordInsertEvent extends ChartEvent {
  /// Creates an insertion of [chord] into bar [barIndex] of section [sectionId].
  const ChordInsertEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.barIndex,
    required this.chord,
  });

  /// The section the bar belongs to.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int barIndex;

  /// The chord placement to insert, carrying its own beat, step and engraving size.
  final BeatChord chord;
  @override
  String get type => 'chord.insert';
  @override
  EventAnchor get anchor => EventAnchor(
    sectionId: sectionId,
    bar: barIndex,
    beat: chord.beat,
    step: chord.step,
  );
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'chord': ModelJson.beatChord(chord),
  };
  @override
  ChordDeleteEvent inverse() => ChordDeleteEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    removed: chord,
  );
  @override
  ChordInsertEvent withSeq(int seq) => ChordInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    chord: chord,
  );
  @override
  bool operator ==(Object other) =>
      other is ChordInsertEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.chord == chord;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, chord);
}

/// Replaces the chord at one address with another, leaving its address unchanged.
class ChordUpdateEvent extends ChartEvent {
  /// Creates an update of the chord at [from]'s address to [to].
  ///
  /// [from] and [to] must address the same (beat, step): moving a chord to a different cell is a
  /// deletion and an insertion, and allowing an update to change the address would make the
  /// event ambiguous about which cell the inverse has to restore.
  ChordUpdateEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.barIndex,
    required this.from,
    required this.to,
  }) : assert(
         from.beat == to.beat && from.step == to.step,
         'a chord update cannot move a chord; use delete then insert',
       );

  /// The section the bar belongs to.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int barIndex;

  /// The chord placement being replaced.
  final BeatChord from;

  /// The replacement, at the same beat and step.
  final BeatChord to;
  @override
  String get type => 'chord.update';
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
    'from': ModelJson.beatChord(from),
    'to': ModelJson.beatChord(to),
  };
  @override
  ChordUpdateEvent inverse() => ChordUpdateEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: to,
    to: from,
  );
  @override
  ChordUpdateEvent withSeq(int seq) => ChordUpdateEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is ChordUpdateEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, from, to);
}

/// Removes the chord at one address and closes the gap in its beat.
class ChordDeleteEvent extends ChartEvent {
  /// Creates a deletion of [removed] from bar [barIndex] of section [sectionId].
  ///
  /// The removed placement is carried in full rather than described by its address, because the
  /// inverse has to put back exactly what was there and an address alone would restore whatever
  /// the document happens to hold by the time undo runs.
  const ChordDeleteEvent({
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

  /// The chord placement that was removed.
  final BeatChord removed;
  @override
  String get type => 'chord.delete';
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
    'chord': ModelJson.beatChord(removed),
  };
  @override
  ChordInsertEvent inverse() => ChordInsertEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    chord: removed,
  );
  @override
  ChordDeleteEvent withSeq(int seq) => ChordDeleteEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    removed: removed,
  );
  @override
  bool operator ==(Object other) =>
      other is ChordDeleteEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.removed == removed;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, removed);
}
