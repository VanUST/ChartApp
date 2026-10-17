// PURPOSE: Model a DIVISION of a bar as a thing the document holds rather than as pixels on it.
//          The owner's requirement is that a boundary the musician draws becomes a structured unit:
//          once the application has found a division in his ink, the division is stored, addressed
//          and drawn as an ideal vertical line, and from then on it is an object like any other —
//          it can be deleted, moved and saved, and undo puts it back.
//
//          WHY THIS IS NOT THE INK. The ink stays in the document beside it (D37 rule 5: the file
//          holds both the structured and the unstructured layer, and the handwriting is never
//          thrown away), because a misrecognition has to be undoable and the file has to keep what
//          he actually wrote. The division is the STRUCTURE; the stroke is the SOURCE.
//
//          WHAT A DIVISION IS NOT, STATED HERE SO NOBODY ASSUMES IT. It does not re-cut the bar
//          model: adding a division does not insert a Bar, and deleting one does not remove a beat
//          from anybody's music. Re-cutting measures from a recognised line would silently reassign
//          which bar a chord's beat belongs to — the class of error this project treats as the
//          worst kind — and the beat each chord sits on is written down already. A division is a
//          structural unit of the DOCUMENT with an identity, an address and an operation-log life;
//          turning one into a different bar count is a separate decision about the music model.
// INPUTS: A stable id, an anchored place, the ideal line's height, how it came to exist, and the
//         identifier of the stroke it was recognised from when there was one.
// OUTPUTS: An immutable value. The place carries the anchor plus the offset of the line's TOP
//          CENTRE, so transposing, fitting and reflowing the page move the division with the bar it
//          divides rather than leaving it at a page coordinate. Equality compares every field, so a
//          moved division is a different value and undo of the move is observable.
// KEYWORDS: bar-division, structural-unit, barline, anchored, ideal-line, source-stroke, undo,
//           d37, d35, no-measure-recut
part of 'oplog.dart';

/// How a bar division came to exist.
///
/// The two levels D37 rule 4 requires the application to be able to tell apart: a RECOGNISED
/// division came from the musician's ink by measurement and can therefore be wrong about his
/// intent, while a DRAWN one is a division he asked for directly and is exactly what he asked for.
enum DivisionSource {
  /// Found in the musician's handwriting by [BarlineDetector].
  recognised('recognised'),

  /// Added by the musician, either at a place he pointed at or by promoting a stroke the detector
  /// refused — the one-action repair for a missed division.
  drawn('drawn');

  const DivisionSource(this.token);

  /// The canonical token written into `events.jsonl`.
  final String token;

  /// Resolves a canonical [token] to its source, reporting an unknown one.
  static DivisionSource fromToken(String token) {
    for (final DivisionSource source in DivisionSource.values) {
      if (source.token == token) {
        return source;
      }
    }
    throw EventFormatException(
      'field "source" names no division source: "$token"',
    );
  }
}

/// A recognised or drawn division of a bar, drawn as an ideal vertical line.
class BarDivision {
  /// Creates a division identified by [id], dividing the bar [place] names.
  const BarDivision({
    required this.id,
    required this.place,
    required this.height,
    this.source = DivisionSource.recognised,
    this.sourceStrokeId = '',
  });

  /// Rebuilds a division from [json].
  ///
  /// Throws [EventFormatException] for an unknown source token, a malformed place, or a height
  /// that is not positive: a division with no height would be drawn as nothing while still
  /// behaving as structure, which is precisely the state D37's display rule forbids.
  factory BarDivision.fromJson(Map<String, Object?> json) {
    final double height = EventJson.number(json, 'height');
    if (height <= 0) {
      throw EventFormatException(
        'field "height" must be positive, found $height',
      );
    }
    return BarDivision(
      id: EventJson.string(json, 'id'),
      place: AnchoredPlace.fromJson(EventJson.object(json, 'place')),
      height: height,
      source: DivisionSource.fromToken(EventJson.string(json, 'source')),
      sourceStrokeId: EventJson.string(json, 'stroke'),
    );
  }

  /// Stable identifier of this division, unique within its document.
  final String id;

  /// Where the ideal line's top centre sits: an anchor plus an anchor-local offset.
  final AnchoredPlace place;

  /// Height of the ideal line in anchor-local logical pixels.
  final double height;

  /// Whether the division was recognised from ink or drawn by the musician.
  final DivisionSource source;

  /// Identifier of the stroke this division was recognised from, empty when there was none.
  ///
  /// THE LINK IS THE REPAIR PATH. Deleting the division leaves the stroke in the document, and the
  /// stroke's own id is what tells a later reader that this ink has already been recognised — so a
  /// musician who rejects a division does not get it back on the next detection pass.
  final String sourceStrokeId;

  /// The anchor the ideal line is measured against.
  EventAnchor get anchor => place.anchor;

  /// The top of the ideal line, in anchor-local logical pixels.
  double get top => place.offsetY;

  /// The bottom of the ideal line, in anchor-local logical pixels.
  double get bottom => place.offsetY + height;

  /// Whether this division was recognised from [strokeId].
  bool cameFrom(String strokeId) =>
      sourceStrokeId.isNotEmpty && sourceStrokeId == strokeId;

  /// Writes this division as a JSON object.
  ///
  /// `stroke` is written even when empty, so the encoded object has a fixed set of keys and a
  /// reader never has to distinguish "absent" from "not recognised from any stroke".
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'place': place.toJson(),
    'height': height,
    'source': source.token,
    'stroke': sourceStrokeId,
  };

  /// Returns a copy of this division with the given fields replaced.
  BarDivision copyWith({
    AnchoredPlace? place,
    double? height,
    DivisionSource? source,
    String? sourceStrokeId,
  }) => BarDivision(
    id: id,
    place: place ?? this.place,
    height: height ?? this.height,
    source: source ?? this.source,
    sourceStrokeId: sourceStrokeId ?? this.sourceStrokeId,
  );
  @override
  bool operator ==(Object other) =>
      other is BarDivision &&
      other.id == id &&
      other.place == place &&
      other.height == height &&
      other.source == source &&
      other.sourceStrokeId == sourceStrokeId;
  @override
  int get hashCode => Object.hash(id, place, height, source, sourceStrokeId);
  @override
  String toString() =>
      'BarDivision($id, ${source.token}, $place, height ${height.toStringAsFixed(1)}'
      '${sourceStrokeId.isEmpty ? '' : ', from $sourceStrokeId'})';
}
