// PURPOSE: Record a change to the signs DRAWN on a bar that are not chords — the segno, the coda,
//          the fermata and the player's stop — as before/after pairs, so a musician can put one on
//          the selected bar or take one off and undo it without the previous set of signs having to
//          be reconstructed. Until this family existed the catalogue could set every other sign on
//          a bar (`repeat.set`, `volta.set`) and the painter drew `Bar.marks`, but nothing could
//          write one: the owner's own setlist carries 31 of them and none of them was reachable
//          from the application.
// INPUTS: The section and bar the signs sit on, and the WHOLE set of signs before and after.
// OUTPUTS: An immutable event and its inverse. Both sides carry the complete set, never a delta
//          and never a single mark: a delta would have to be replayed against whatever the bar
//          holds at the time, and a reconstructed previous value can be reconstructed wrongly —
//          two signs on one bar have no arithmetic that gets back to the exact pair that was there.
//          Both sides may be EMPTY, and an empty set is a real value: taking the last sign off a bar
//          is an edit, so `to` being empty has to be distinguishable from "leave the signs alone".
//          The event addresses its bar through [EventAnchor] with a null beat, because a sign
//          belongs to the bar rather than to a cell inside it.
// KEYWORDS: bar-mark, segno, coda, fermata, player-ending, sign-event, before-after, whole-value,
//           inverse, no-silent-default
part of 'oplog.dart';

/// Sets the signs drawn on one bar.
///
/// A `Set<BarMark>` on each side rather than one mark per event, because a bar legitimately carries
/// several — the painter joins them into one line of glyphs — and an event that named one mark would
/// need an add/remove verb, which is the delta this event deliberately does not carry.
class BarMarkSetEvent extends ChartEvent {
  /// Creates a change of the signs of bar [barIndex] in section [sectionId].
  const BarMarkSetEvent({
    required super.docId,
    required super.seq,
    required this.sectionId,
    required this.barIndex,
    required this.from,
    required this.to,
  });

  /// The section the bar belongs to.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int barIndex;

  /// The signs in force before the edit, in the order the bar held them.
  ///
  /// Recorded although the reducer never reads it, because it is what the inverse is built from:
  /// undo restores the signs that were there, in the very order they were drawn, rather than
  /// deriving them from the set that replaced them.
  final Set<BarMark> from;

  /// The signs in force after the edit.
  final Set<BarMark> to;
  @override
  String get type => 'mark.set';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: barIndex);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'from': ModelJson.barMarks(from),
    'to': ModelJson.barMarks(to),
  };
  @override
  BarMarkSetEvent inverse() => BarMarkSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: to,
    to: from,
  );
  @override
  BarMarkSetEvent withSeq(int seq) => BarMarkSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is BarMarkSetEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      _sameMarks(other.from, from) &&
      _sameMarks(other.to, to);
  @override
  int get hashCode => Object.hash(
    docId,
    seq,
    sectionId,
    barIndex,
    Object.hashAllUnordered(from),
    Object.hashAllUnordered(to),
  );
}

/// Whether [left] and [right] carry the same signs.
///
/// Dart collections compare by IDENTITY, so the event's `==` cannot use `==` on the sets
/// themselves: decoding builds a fresh set, and the event would then deny being equal to its own
/// encoding. Membership equality is used rather than ordered equality because the model's own `Bar`
/// compares its marks that way (see `Bar.==`), so the same signs written in a different order are
/// the same state of the bar. The event still STORES the sets it was given, so undo restores the
/// order it recorded even though the comparison does not distinguish one.
bool _sameMarks(Set<BarMark> left, Set<BarMark> right) =>
    left.length == right.length && left.containsAll(right);
