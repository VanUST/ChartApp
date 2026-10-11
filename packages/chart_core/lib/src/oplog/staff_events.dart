// PURPOSE: Record a change to the STAVES a song declares — which staff lines its bars are drawn
//          with — as a before/after pair, so that the melodist's staff can be turned on and off
//          through the operation log instead of behind its back. Until this family existed a song's
//          staves could be READ from a `.chart` snapshot and decided once, at creation, and there
//          was no way to give an existing chart a staff at all: owner decision D29 requires the
//          staff to appear because the chart DECLARES it, and owner decision D25 requires the
//          musician to hold that choice.
// INPUTS: The whole [StaffSet] before the edit and the whole one after it. Nothing else — a staff
//         belongs to the SONG and not to a bar, because the five lines must run at one height
//         across every system, so this event carries no address at all, like [SongUpdateEvent].
// OUTPUTS: An immutable event whose inverse is another set with the two whole values swapped. Both
//          sides carry the complete set rather than a flag such as "melody on", because a flag
//          cannot say WHICH clef, and because undo must restore the staves that were there rather
//          than a set reconstructed from a boolean.
// KEYWORDS: staff, staves, song-event, whole-value, inverse, undo, d25, d29
part of 'oplog.dart';

/// Replaces the staves a song declares.
///
/// WHY THE WHOLE SET AND NOT A BOOLEAN. `StaffSet` holds at most one pitched and at most one
/// percussion staff, each with its own clef, so "melody on" is not enough to rebuild what a chart
/// carried: a song engraving in bass clef would come back in treble after one undo of a boolean.
/// Carrying the value costs a few bytes per toggle and cannot be wrong.
class StaffSetEvent extends ChartEvent {
  /// Creates a change of the song's staves from [from] to [to].
  const StaffSetEvent({
    required super.docId,
    required super.seq,
    required this.from,
    required this.to,
  });

  /// The staves the song declared before this event.
  ///
  /// Recorded although the reducer never reads it, because it is what the inverse is built from:
  /// undo restores the staves as they were DECLARED rather than deriving them from the ones that
  /// replaced them.
  final StaffSet from;

  /// The staves the song declares after this event.
  final StaffSet to;
  @override
  String get type => 'staff.set';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'from': ModelJson.staffSet(from),
    'to': ModelJson.staffSet(to),
  };
  @override
  StaffSetEvent inverse() =>
      StaffSetEvent(docId: docId, seq: seq, from: to, to: from);
  @override
  StaffSetEvent withSeq(int seq) =>
      StaffSetEvent(docId: docId, seq: seq, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is StaffSetEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, from, to);
}
