// PURPOSE: Record a change to a document's DIVISIONS — the bar boundaries the application found in
//          handwriting or the musician placed himself — as before/after pairs over the whole list,
//          so that a division can be added, removed or moved and undone without any of the three
//          having to be reconstructed from the others.
//
//          WHY THE EVENT CARRIES THE WHOLE LIST ON BOTH SIDES AND NOT ONE DIVISION. The design rule
//          this repository holds to is that an inverse carries the WHOLE previous value: a delta
//          would have to be replayed against whatever the document holds at the time, and
//          re-deriving the previous division set from the one that replaced it is precisely the
//          reconstruction that goes wrong when two edits land out of order. Divisions on one chart
//          are few — one per bar boundary the musician bothered to draw — so the whole list is the
//          cheap side of that trade.
//
//          WHY ONE FAMILY AND NOT THREE. Adding, deleting and moving a division are three verbs but
//          one state: the set of divisions. A single `division.set` event whose two sides are whole
//          lists expresses all three, needs one case in the reducer and one in the codec, and makes
//          the inverse trivially exact. A musician moving a division therefore gets ONE undo step,
//          which is what the owner's "one or two actions" rule requires of a repair.
// INPUTS: The document events' identity, and the divisions in force before and after.
// OUTPUTS: An immutable event and its inverse. Both sides may be empty, and an empty list is a real
//          value: removing the last division is an edit, so `to` being empty must be
//          distinguishable from "leave the divisions alone". The event is document-level and
//          carries no [EventAnchor]: the divisions it sets are spread over several bars, and an
//          anchor naming one of them would be a place that means nothing.
// KEYWORDS: division-event, bar-division, whole-value, before-after, undo-exact, document-level,
//           d37
part of 'oplog.dart';

/// Replaces the divisions of a document.
class DivisionSetEvent extends ChartEvent {
  /// Creates a change of the document's divisions from [from] to [to].
  const DivisionSetEvent({
    required super.docId,
    required super.seq,
    required this.from,
    required this.to,
  });

  /// The divisions in force before the edit, in the document's own order.
  ///
  /// Recorded although the reducer never reads it, because it is what the inverse is built from:
  /// undo restores the divisions that were there, in the very order they were drawn.
  final List<BarDivision> from;

  /// The divisions in force after the edit.
  final List<BarDivision> to;
  @override
  String get type => 'division.set';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'from': <Object?>[
      for (final BarDivision division in from) division.toJson(),
    ],
    'to': <Object?>[for (final BarDivision division in to) division.toJson()],
  };
  @override
  DivisionSetEvent inverse() =>
      DivisionSetEvent(docId: docId, seq: seq, from: to, to: from);
  @override
  DivisionSetEvent withSeq(int seq) =>
      DivisionSetEvent(docId: docId, seq: seq, from: from, to: to);
  @override
  bool operator ==(Object other) =>
      other is DivisionSetEvent &&
      other.docId == docId &&
      other.seq == seq &&
      _sameDivisions(other.from, from) &&
      _sameDivisions(other.to, to);
  @override
  int get hashCode =>
      Object.hash(docId, seq, Object.hashAll(from), Object.hashAll(to));
}

/// Whether [left] and [right] carry the same divisions in the same order.
///
/// Ordered equality, unlike the signs of a bar: two divisions at different places are different
/// divisions, and the order is the order they are drawn in, which is part of the value the document
/// publishes.
bool _sameDivisions(List<BarDivision> left, List<BarDivision> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
