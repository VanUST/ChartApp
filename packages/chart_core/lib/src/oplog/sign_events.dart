// PURPOSE: Record the two structural signs that live on a single bar and are read by the
//          play-order expansion — the repeat signs and the alternative-ending bracket — as
//          before/after pairs, so a musician toggling a repeat or lettering an ending can undo
//          it without the sign's previous value having to be reconstructed.
// INPUTS: The section and bar the sign sits on, and the sign's value before and after.
// OUTPUTS: Immutable events and their inverses. A bracket is nullable, and a null on either side
//          is a real value: removing the only ending from a bar is an edit, so `to` being null
//          has to be distinguishable from "leave the bracket alone". Both events address their
//          bar through [EventAnchor] with a null beat, because a sign belongs to the bar rather
//          than to a cell inside it.
// KEYWORDS: repeat, volta, ending, barline, sign-event, before-after, inverse, play-order
part of 'oplog.dart';

/// The repeat-related state of one bar, gathered so a single event can set all of it at once.
///
/// The four fields travel together because they are set together: a musician making a passage
/// repeat marks the opening barline of the first bar and the closing barline of the last, and a
/// bar that says "play the previous bar again" says it in place of chords. Splitting them into
/// four events would let a half-applied repeat exist between two undo steps.
class RepeatSigns {
  /// Creates repeat signs from each of the four values.
  const RepeatSigns({
    this.openingBarline = Barline.single,
    this.closingBarline = Barline.single,
    this.repeatPrevious = RepeatPrevious.none,
    this.slashRepeat = false,
  });

  /// Reads the repeat signs currently carried by [bar].
  ///
  /// This is the constructor a caller uses to build the `from` half of a [RepeatSetEvent]: it
  /// cannot be a const constructor because it reads fields of a value, which a constant
  /// initializer may not do.
  factory RepeatSigns.of(Bar bar) => RepeatSigns(
    openingBarline: bar.openingBarline,
    closingBarline: bar.closingBarline,
    repeatPrevious: bar.repeatPrevious,
    slashRepeat: bar.slashRepeat,
  );

  /// Rebuilds repeat signs from [json].
  factory RepeatSigns.fromJson(Map<String, Object?> json) => RepeatSigns(
    openingBarline: EventJson.enumeration(
      Barline.values,
      EventJson.string(json, 'opening'),
      'opening',
    ),
    closingBarline: EventJson.enumeration(
      Barline.values,
      EventJson.string(json, 'closing'),
      'closing',
    ),
    repeatPrevious: EventJson.enumeration(
      RepeatPrevious.values,
      EventJson.string(json, 'previous'),
      'previous',
    ),
    slashRepeat: EventJson.boolean(json, 'slash'),
  );

  /// The barline drawn at the left edge of the bar.
  final Barline openingBarline;

  /// The barline drawn at the right edge of the bar.
  final Barline closingBarline;

  /// Whether the bar says "play the previous bar again".
  final RepeatPrevious repeatPrevious;

  /// Whether the bar is marked with the slash repeat.
  final bool slashRepeat;

  /// Writes these signs as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'opening': openingBarline.name,
    'closing': closingBarline.name,
    'previous': repeatPrevious.name,
    'slash': slashRepeat,
  };
  @override
  bool operator ==(Object other) =>
      other is RepeatSigns &&
      other.openingBarline == openingBarline &&
      other.closingBarline == closingBarline &&
      other.repeatPrevious == repeatPrevious &&
      other.slashRepeat == slashRepeat;
  @override
  int get hashCode =>
      Object.hash(openingBarline, closingBarline, repeatPrevious, slashRepeat);
  @override
  String toString() =>
      'RepeatSigns($openingBarline..$closingBarline, $repeatPrevious'
      '${slashRepeat ? ', slash' : ''})';
}

/// Sets the repeat signs of one bar.
class RepeatSetEvent extends ChartEvent {
  /// Creates a change of the repeat signs of bar [barIndex] in section [sectionId].
  const RepeatSetEvent({
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

  /// The signs in force before the edit.
  final RepeatSigns from;

  /// The signs in force after the edit.
  final RepeatSigns to;
  @override
  String get type => 'repeat.set';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: barIndex);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'from': from.toJson(),
    'to': to.toJson(),
  };
  @override
  RepeatSetEvent inverse() => RepeatSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: to,
    to: from,
  );
  @override
  RepeatSetEvent withSeq(int seq) => RepeatSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is RepeatSetEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, from, to);
}

/// Sets or clears the alternative-ending bracket of one bar.
class VoltaSetEvent extends ChartEvent {
  /// Creates a change of the bracket of bar [barIndex] in section [sectionId].
  const VoltaSetEvent({
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

  /// The bracket in force before the edit, or null when the bar had none.
  final Volta? from;

  /// The bracket in force after the edit, or null when the bracket is removed.
  final Volta? to;
  @override
  String get type => 'volta.set';
  @override
  EventAnchor get anchor => EventAnchor(sectionId: sectionId, bar: barIndex);
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': barIndex,
    'from': from?.number,
    'to': to?.number,
  };
  @override
  VoltaSetEvent inverse() => VoltaSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: to,
    to: from,
  );
  @override
  VoltaSetEvent withSeq(int seq) => VoltaSetEvent(
    docId: docId,
    seq: seq,
    sectionId: sectionId,
    barIndex: barIndex,
    from: from,
    to: to,
  );
  @override
  bool operator ==(Object other) =>
      other is VoltaSetEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.sectionId == sectionId &&
      other.barIndex == barIndex &&
      other.from == from &&
      other.to == to;
  @override
  int get hashCode => Object.hash(docId, seq, sectionId, barIndex, from, to);
}
