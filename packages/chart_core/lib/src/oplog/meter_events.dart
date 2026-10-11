// PURPOSE: Record a change of a bar's METER — the M/N written at the start of a bar — as a
//          before/after pair, so that a musician can set 3/4, 15/8 or anything else on one bar and
//          undo it without the previous meter having to be reconstructed. Until this family existed
//          a bar's meter could be READ from an import and was used to decide how many chord cells
//          the bar has, but nothing in the catalogue could write one, so a chart whose meter changes
//          mid-tune could be played wrongly at a bar nobody could fix or sign.
// INPUTS: The section and bar the meter sits on, and the WHOLE meter before and after.
// OUTPUTS: An immutable event and its inverse. Both sides carry the complete meter, never a delta
//          and never one of the two figures: a numerator without a denominator is not a meter, and
//          a delta would have to be replayed against whatever the bar holds at the time. Both
//          figures are positive integers, because a meter of zero cells is not a musical state the
//          model can hold — [EventCodec] refuses a non-positive figure rather than defaulting it.
//          The event addresses its bar through [EventAnchor] with a null beat, because a meter
//          belongs to the bar rather than to a cell inside it.
// KEYWORDS: meter, time-signature, bar, sign-event, before-after, whole-value, inverse,
//           no-silent-default
part of 'oplog.dart';

/// Sets the meter of one bar.
///
/// WHY THE TWO FIGURES TRAVEL TOGETHER rather than as a numerator event and a denominator event:
/// `1/4` and `1/8` are two different meters drawn on the page and counted by the musician, and a
/// half-applied meter between two undo steps would be a chart with a numerator that no longer
/// describes the bar it is written on.
class MeterSetEvent extends ChartEvent {
  /// Creates a change of the meter of bar [barIndex] in section [sectionId].
  const MeterSetEvent({
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

  /// The meter in force before the edit.
  final TimeSignature from;

  /// The meter in force after the edit.
  final TimeSignature to;
  @override
  String get type => 'meter.set';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: barIndex);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'from': ModelJson.timeSignature(from),
    'to': ModelJson.timeSignature(to),
  };
  @override
  MeterSetEvent inverse() => MeterSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: to,
    to: from,
  );
  @override
  MeterSetEvent withSeq(int seq) => MeterSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is MeterSetEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, from, to);
}
