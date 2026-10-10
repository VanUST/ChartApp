// PURPOSE: Name the place in a document that an event acts on, in the one coordinate scheme the
//          song model already uses: a section identity, a bar index inside that section, and —
//          for an object placed inside a bar — a beat and a step within that beat. Keeping the
//          anchor in this shape is what lets an annotation or a handwritten stroke survive a
//          reorder: the section id does not move when the section does, and the bar index is
//          re-resolved against the section each time.
// INPUTS: A section id, a bar index, an optional beat and a step defaulting to 0.
// OUTPUTS: An immutable anchor. A null beat means the event acts on the bar as a whole (its
//          staff text, its repeats, a bar that is being deleted) rather than on one object
//          inside it; a non-null beat addresses one cell, and the step keeps two chords packed
//          into that cell apart. Equality compares all four fields.
// KEYWORDS: anchor, address, section-id, bar-index, beat, step, anchor-local, reorder-survival
part of 'oplog.dart';

/// A place in a document, addressed the way the song model addresses objects.
class EventAnchor {
  /// Creates an anchor at ([sectionId], [bar]), optionally inside a beat and step.
  const EventAnchor({
    required this.sectionId,
    required this.bar,
    this.beat,
    this.step = 0,
  });

  /// Rebuilds an anchor from [json].
  ///
  /// Throws [EventFormatException] when a required field is missing or of the wrong type; the
  /// optional beat is the only field that may be absent.
  factory EventAnchor.fromJson(Map<String, Object?> json) => EventAnchor(
    sectionId: EventJson.string(json, 'sectionId'),
    bar: EventJson.integer(json, 'bar'),
    beat: EventJson.optionalInteger(json, 'beat'),
    step: EventJson.integer(json, 'step'),
  );

  /// The section the object sits in, named by the section's stable identity.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int bar;

  /// Zero-based cell inside the bar, or null when the anchor stops at the bar itself.
  final int? beat;

  /// Order within [beat] when several objects share it, 0 when there is no beat.
  final int step;

  /// Whether this anchor names a whole bar rather than one object inside it.
  bool get isBarLevel => beat == null;

  /// Writes this anchor as a JSON object.
  ///
  /// `beat` is written even when null so that the encoded object has a fixed set of keys: a
  /// reader never has to distinguish "absent" from "bar-level", which are the same state here.
  Map<String, Object?> toJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': bar,
    'beat': beat,
    'step': step,
  };
  @override
  bool operator ==(Object other) =>
      other is EventAnchor &&
      other.sectionId == sectionId &&
      other.bar == bar &&
      other.beat == beat &&
      other.step == step;
  @override
  int get hashCode => Object.hash(sectionId, bar, beat, step);
  @override
  String toString() =>
      'EventAnchor($sectionId bar $bar'
      '${beat == null ? '' : ' beat $beat.$step'})';
}

/// A place for an object that hangs off its anchor by an offset rather than sitting on it.
///
/// A handwritten stroke or a stamp is drawn near a beat, not exactly on it, so the anchor plus an
/// offset in anchor-local logical pixels is what actually locates it. Storing the offset here
/// rather than inside each object's payload means moving an annotation and moving a text cue are
/// the same operation on the same value.
class AnchoredPlace {
  /// Creates a place [offsetX] and [offsetY] logical pixels from [anchor].
  const AnchoredPlace({
    required this.anchor,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  /// Rebuilds a place from [json].
  factory AnchoredPlace.fromJson(Map<String, Object?> json) => AnchoredPlace(
    anchor: EventAnchor.fromJson(EventJson.object(json, 'anchor')),
    offsetX: EventJson.number(json, 'offsetX'),
    offsetY: EventJson.number(json, 'offsetY'),
  );

  /// The anchor the object is captured against.
  final EventAnchor anchor;

  /// Horizontal offset from the anchor, in anchor-local logical pixels.
  final double offsetX;

  /// Vertical offset from the anchor, in anchor-local logical pixels.
  final double offsetY;

  /// Writes this place as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'anchor': anchor.toJson(),
    'offsetX': offsetX,
    'offsetY': offsetY,
  };
  @override
  bool operator ==(Object other) =>
      other is AnchoredPlace &&
      other.anchor == anchor &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY;
  @override
  int get hashCode => Object.hash(anchor, offsetX, offsetY);
  @override
  String toString() => 'AnchoredPlace($anchor +$offsetX,$offsetY)';
}
