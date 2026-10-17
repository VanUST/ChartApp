// PURPOSE: Name WHERE something is written in a chart, as a coordinate rather than as a grid
//          index. The owner removed the grid as a class («Сетка НЕ квантизована. Вообще
//          квантизацию сетки надо убрать как класс»), so a chord, a note, a handwritten stroke, a
//          recognised division and a text cue are all located the same way: by the bar they belong
//          to and an offset in logical pixels from that bar's own rectangle. This is the ONE place
//          a document position is expressed, which is why the song model and the operation log can
//          both depend on it without either owning it.
// INPUTS: An [EventAnchor] naming the bar, plus horizontal and vertical offsets in anchor-local
//         logical pixels.
// OUTPUTS: Two immutable value types. Equality compares every field, so a moved object is a
//         different value and undo of a move is observable.
// KEYWORDS: place, coordinate, anchor, bar-relative, logical-pixels, no-grid, d28, d36, a73
//
// WHY THE ANCHOR IS A BAR AND NOT A PAGE. A page number is an OUTPUT of layout, so a mark stored
// against it teleports onto somebody else's music the moment the music is reflowed onto another
// number of pages. A bar index survives reflow, transposition and resizing, which is exactly what
// a position has to survive; the offset is measured from the bar's own rectangle, so the mark
// keeps its distance to its bar and not to the edge of the paper.
//
// WHY THE OFFSETS ARE PIXELS AND NOT A FRACTION OF THE BAR'S WIDTH. A fraction would make a mark
// slide when its bar widens for its own content — a chord that moved because a NEIGHBOUR got
// wider is a chord the musician did not move. Pixels also happen to be what the pen already
// records, so handwriting and structure share one coordinate system and can be compared.
library;

/// A place in a document, addressed the way the song model addresses objects: a bar.
///
/// THE BEAT AND THE STEP THAT USED TO LIVE HERE ARE GONE, and their removal is the point of the
/// change that made this file. A beat was an index into a grid the application imposed; the owner
/// removed the grid, so a mark's horizontal position is its [AnchoredPlace.offsetX] and there is no
/// second number that could disagree with it.
class EventAnchor {
  /// Creates an anchor naming bar [bar] of section [sectionId].
  const EventAnchor({required this.sectionId, required this.bar});

  /// Rebuilds an anchor from [json].
  ///
  /// Throws [Object] of whatever type the caller's json helper raises when a field is missing or of
  /// the wrong type; a file written by this build always carries both fields.
  factory EventAnchor.fromJson(Map<String, Object?> json) => EventAnchor(
    sectionId: _string(json, 'sectionId'),
    bar: _integer(json, 'bar'),
  );

  /// The section the object sits in, named by the section's stable identity.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int bar;

  /// Writes this anchor as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'sectionId': sectionId,
    'bar': bar,
  };
  @override
  bool operator ==(Object other) =>
      other is EventAnchor && other.sectionId == sectionId && other.bar == bar;
  @override
  int get hashCode => Object.hash(sectionId, bar);
  @override
  String toString() => 'EventAnchor($sectionId bar $bar)';
}

/// A place for an object that hangs off its anchor by an offset rather than sitting on it.
///
/// A chord the musician typed, a note the reader measured, a handwritten stroke and an ideal
/// barline are all drawn NEAR a bar, not exactly on its corner, so the anchor plus an offset in
/// anchor-local logical pixels is what actually locates them. Storing the offset here rather than
/// inside each object's payload means moving handwriting and moving a chord are the same operation
/// on the same value.
class AnchoredPlace {
  /// Creates a place [offsetX] and [offsetY] logical pixels from [anchor].
  const AnchoredPlace({
    required this.anchor,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  /// Rebuilds a place from [json].
  factory AnchoredPlace.fromJson(Map<String, Object?> json) => AnchoredPlace(
    anchor: EventAnchor.fromJson(_object(json, 'anchor')),
    offsetX: _number(json, 'offsetX'),
    offsetY: _number(json, 'offsetY'),
  );

  /// The anchor the object is captured against.
  final EventAnchor anchor;

  /// Horizontal offset from the anchor, in anchor-local logical pixels.
  ///
  /// FOR A CHORD OR A NOTE THIS IS ITS TIME. There is no separate duration position: a mark is at
  /// the x it was written at, and the engraver draws it there.
  final double offsetX;

  /// Vertical offset from the anchor, in anchor-local logical pixels.
  ///
  /// FOR A CHORD THIS IS ITS OWN PLACE ON THE CHORD LINE, freely chosen: a symbol may sit above the
  /// line, on it, or below it, and the application does not correct it. FOR A NOTE IT IS ALWAYS
  /// ZERO, because a note's height is its pitch and the melody staff derives the y from it — a
  /// stored y there would be a second answer to a question the model already answers.
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

// The four readers below are deliberately local rather than borrowed from the operation log's json
// helpers: this library is imported BY the log, so it may not import the log back. They therefore
// throw [FormatException], and the log's own readers (`EventJson.anchoredPlace`, `EventJson.anchor`)
// translate that into the log's [EventFormatException] at the one boundary that needs it.
String _string(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String) {
    throw FormatException('field "$key" must be a string, found $value');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('field "$key" must be an integer, found $value');
  }
  return value;
}

double _number(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! num) {
    throw FormatException('field "$key" must be a number, found $value');
  }
  return value.toDouble();
}

Map<String, Object?> _object(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('field "$key" must be an object, found $value');
  }
  return value;
}
