// PURPOSE: Model a mark a musician attaches to a place in a chart — a stamp, a cue, or the record
//          that some handwriting exists at an anchor. The mark carries its place rather than a
//          computed coordinate, so it survives transposition, reflow and a section reorder: the
//          anchor is re-resolved by the layout engine and the mark follows the bar it was put on.
// INPUTS: A stable id, a kind, an anchored place, and a free-text payload.
// OUTPUTS: Immutable values. The payload is a string rather than a typed union because the set of
//          things a musician attaches is open — a glyph, a short remark, the id of an ink blob —
//          and a closed union would reject the next one. Equality compares every field, including
//          the place, so moving an annotation produces a different value.
// KEYWORDS: annotation, stamp, cue, anchored-mark, ink-reference, offset, reflow-survival
part of 'oplog.dart';

/// What kind of mark an annotation is.
enum AnnotationKind {
  /// The mark records that handwriting exists at this anchor; the strokes themselves are stored
  /// separately, in anchor-local coordinates.
  ink('ink'),

  /// A stamp, such as a section sign or a rehearsal mark drawn by hand.
  stamp('stamp'),

  /// A short cue written near a beat.
  cue('cue');

  const AnnotationKind(this.token);

  /// The canonical token written into `events.jsonl`.
  final String token;
}

/// A mark attached to a place in a chart.
class Annotation {
  /// Creates a mark identified by [id] of [kind], placed at [place].
  const Annotation({
    required this.id,
    required this.kind,
    required this.place,
    this.payload = '',
  });

  /// Rebuilds an annotation from [json].
  ///
  /// Throws [EventFormatException] for an unknown kind token or a malformed place.
  factory Annotation.fromJson(Map<String, Object?> json) => Annotation(
    id: EventJson.string(json, 'id'),
    kind: _kindFromToken(EventJson.string(json, 'kind')),
    place: AnchoredPlace.fromJson(EventJson.object(json, 'place')),
    payload: EventJson.string(json, 'payload'),
  );

  /// Resolves a canonical [token] to its kind, reporting an unknown one.
  static AnnotationKind _kindFromToken(String token) {
    for (final AnnotationKind kind in AnnotationKind.values) {
      if (kind.token == token) {
        return kind;
      }
    }
    throw EventFormatException(
      'field "kind" names no annotation kind: "$token"',
    );
  }

  /// Stable identifier of this mark, unique within its document.
  final String id;

  /// What kind of mark this is.
  final AnnotationKind kind;

  /// Where the mark hangs, as an anchor plus an anchor-local offset.
  final AnchoredPlace place;

  /// The mark's free text, empty when it carries none.
  final String payload;

  /// Writes this annotation as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.token,
    'place': place.toJson(),
    'payload': payload,
  };

  /// Returns a copy of this annotation with the given fields replaced.
  Annotation copyWith({
    AnnotationKind? kind,
    AnchoredPlace? place,
    String? payload,
  }) => Annotation(
    id: id,
    kind: kind ?? this.kind,
    place: place ?? this.place,
    payload: payload ?? this.payload,
  );
  @override
  bool operator ==(Object other) =>
      other is Annotation &&
      other.id == id &&
      other.kind == kind &&
      other.place == place &&
      other.payload == payload;
  @override
  int get hashCode => Object.hash(id, kind, place, payload);
  @override
  String toString() => 'Annotation($id, ${kind.token}, $place, "$payload")';
}
