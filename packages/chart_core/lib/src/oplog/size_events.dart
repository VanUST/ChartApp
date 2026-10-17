// PURPOSE: Record a change of a bar's SIZE — how much room the page gives it, relative to the room
//          its own content needs — as a before/after pair, so the musician can widen a bar that has
//          six chords in it, or put one back, and undo either without the previous size having to be
//          reconstructed. Until this family existed a bar's width was decided entirely by the
//          engraver from its own content, so a bar that held a run of eighths and an accidental was
//          given the same arithmetic as an empty one and nothing could be done about it.
// INPUTS: The section and bar the size sits on, and the WHOLE size before and after.
// OUTPUTS: An immutable event and its inverse. Both sides carry the complete [BarSize], never a
//          delta: the property is the musician's decision about one bar, and a delta would have to
//          be replayed against whatever the bar holds at the time, which is what makes an inverse
//          restore something the musician never chose. The event addresses its bar through
//          [EventAnchor] with a null beat, because a size belongs to the bar rather than to a cell
//          inside it.
// KEYWORDS: bar-size, width, bar, sign-event, before-after, whole-value, inverse, undo,
//           the-musician-decides
part of 'oplog.dart';

/// Sets the size of one bar.
///
/// WHY THE SIZE IS AN EVENT AND NOT A SCREEN SETTING. Undo, the `.chart` container and a future sync
/// all rest on the operation log being the only writer, so a property a musician changes has to
/// travel the same road as a chord or a meter. The alternative — a zoom-like value held beside the
/// page — would save a chart that reopened at the wrong size and could not be undone, and it would
/// make a chart look different on another device, which is the one thing the owner asked this
/// property NOT to do.
///
/// WHY NOTHING HERE IS A NESTED OBJECT. A size is one number, so the payload carries that number on
/// each side, the way `volta.set` carries a bracket's figure rather than a bracket object. The
/// reader turns the number into a [BarSize] and refuses a factor the engraver cannot honour, which
/// is the same division of labour `meter.set` follows for a meter's two figures.
class BarSizeSetEvent extends ChartEvent {
  /// Creates a change of the size of bar [barIndex] in section [sectionId].
  const BarSizeSetEvent({
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

  /// The size in force before the edit.
  final BarSize from;

  /// The size in force after the edit.
  final BarSize to;
  @override
  String get type => 'size.set';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: barIndex);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'from': from.factor,
    'to': to.factor,
  };
  @override
  BarSizeSetEvent inverse() => BarSizeSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: to,
    to: from,
  );
  @override
  BarSizeSetEvent withSeq(int seq) => BarSizeSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is BarSizeSetEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, from, to);
}
