// PURPOSE: Define the canonical form a committed handwritten stroke is stored in, so that a
//          stroke written on an iPad with PencilKit and one written on Android with the custom
//          InkView become the same value before either reaches the event log. The platform views
//          are only the live engine: their archives are a latency mechanism, they name no
//          portable geometry, and replaying one on the other platform is impossible. Canonicalising
//          on commit is what lets a stroke survive a device change, a transposition and a reflow.
// INPUTS: A tool token, a colour, a nib size, an object anchor, and the sampled points with
//         pressure and time.
// OUTPUTS: Immutable values. A point is `(x, y, w, t)` in ANCHOR-LOCAL logical pixels, where `w`
//          is pressure in `[0, 1]` and `t` is milliseconds since the start of the stroke. The
//          points are stored in the order they were drawn; an empty point list is not a stroke
//          and is rejected on decode rather than accepted as a degenerate one.
// KEYWORDS: ink, stroke, canonical-form, anchor-local, pencilkit, inkview, pressure, sampling
part of 'oplog.dart';

/// The tools that produce a stored stroke.
///
/// The eraser is deliberately absent. In this design the eraser deletes whole strokes rather than
/// nibbling pixels, so it is an operation on the stroke list (`ink.stroke.delete`) and not a
/// stroke that could be stored alongside the others.
enum StrokeTool {
  /// Fine opaque ink.
  pen('pen'),

  /// Wide translucent ink, drawn beneath the pen layer.
  highlighter('highlighter');

  const StrokeTool(this.token);

  /// The canonical token written into `events.jsonl`.
  final String token;
}

/// One sampled point of a stroke, in anchor-local logical pixels.
class InkPoint {
  /// Creates a point at ([x], [y]) with pressure [w] at [t] milliseconds.
  const InkPoint({
    required this.x,
    required this.y,
    required this.w,
    required this.t,
  });

  /// Rebuilds a point from the four-element array `[x, y, w, t]`.
  ///
  /// The positional form is the storage contract, so a point encodes as a list and not as an
  /// object. A list of any other length is a failure: silently reading the first four entries of
  /// a five-element list would attribute the fifth value to nothing and lose it.
  factory InkPoint.fromJson(List<Object?> json) {
    if (json.length != 4) {
      throw EventFormatException(
        'an ink point must hold exactly four numbers, found ${json.length}',
      );
    }
    return InkPoint(
      x: _numberAt(json, 0),
      y: _numberAt(json, 1),
      w: _numberAt(json, 2),
      t: _numberAt(json, 3),
    );
  }

  /// Horizontal position from the anchor, in anchor-local logical pixels.
  final double x;

  /// Vertical position from the anchor, in anchor-local logical pixels.
  final double y;

  /// Nib pressure at this sample, in `[0, 1]`.
  final double w;

  /// Milliseconds since the first point of this stroke.
  final double t;

  /// Writes this point as the four-element array `[x, y, w, t]`.
  List<Object?> toJson() => <Object?>[x, y, w, t];

  /// Reads entry [index] of [json] as a number, reporting the index when it is not one.
  static double _numberAt(List<Object?> json, int index) {
    final Object? value = json[index];
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    throw EventFormatException(
      'entry $index of an ink point is not a number, found '
      '${value == null ? 'null' : value.runtimeType}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InkPoint &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.t == t;
  @override
  int get hashCode => Object.hash(x, y, w, t);
  @override
  String toString() => 'InkPoint($x, $y, w=$w, t=$t)';
}

/// One committed handwritten stroke, in the canonical cross-platform form.
class InkStroke {
  /// Creates a stroke identified by [id], drawn with [tool], anchored by [anchor].
  const InkStroke({
    required this.id,
    required this.tool,
    required this.color,
    required this.size,
    required this.anchor,
    required this.points,
  });

  /// Rebuilds a stroke from [json].
  ///
  /// Throws [EventFormatException] for an unknown tool token, an empty point list, or any
  /// malformed field. An unknown tool is a failure rather than a fallback to [StrokeTool.pen]:
  /// a stroke drawn with a tool this build does not know must not be rendered as a nib.
  factory InkStroke.fromJson(Map<String, Object?> json) {
    final StrokeTool tool = _toolFromToken(EventJson.string(json, 'tool'));
    final List<InkPoint> points = <InkPoint>[
      for (final Object? entry in EventJson.array(json, 'points'))
        InkPoint.fromJson(_pointArray(entry)),
    ];
    if (points.isEmpty) {
      throw EventFormatException('an ink stroke carries no points');
    }
    return InkStroke(
      id: EventJson.string(json, 'id'),
      tool: tool,
      color: EventJson.string(json, 'color'),
      size: EventJson.number(json, 'size'),
      anchor: EventAnchor.fromJson(EventJson.object(json, 'anchor')),
      points: points,
    );
  }

  /// Resolves a canonical [token] to its tool, reporting an unknown one.
  static StrokeTool _toolFromToken(String token) {
    for (final StrokeTool tool in StrokeTool.values) {
      if (tool.token == token) {
        return tool;
      }
    }
    throw EventFormatException('field "tool" names no stroke tool: "$token"');
  }

  /// Reads one entry of the `points` array as the four-element list a point is written as.
  static List<Object?> _pointArray(Object? entry) {
    if (entry is! List<Object?>) {
      throw EventFormatException('an entry of "points" is not an array');
    }
    return entry;
  }

  /// Stable identifier of this stroke, unique within its document, and the identity the eraser
  /// removes by.
  final String id;

  /// The tool the stroke was drawn with.
  final StrokeTool tool;

  /// The stroke colour, as a `#rrggbb` or `#rrggbbaa` string.
  ///
  /// A string rather than a packed integer because the colour is data a user picked and is
  /// written to a file that outlives this build's colour model, and because a hex string is
  /// readable in a log line without a conversion.
  final String color;

  /// The nib width in anchor-local logical pixels.
  final double size;

  /// The object this stroke was captured against. Every coordinate in [points] is relative to it,
  /// which is what lets the stroke move with its bar and keep its own geometry.
  final EventAnchor anchor;

  /// The sampled points, in drawing order, at least one of them.
  final List<InkPoint> points;

  /// Writes this stroke as `{tool, color, size, anchor, points}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'tool': tool.token,
    'color': color,
    'size': size,
    'anchor': anchor.toJson(),
    'points': <Object?>[for (final InkPoint point in points) point.toJson()],
  };
  @override
  bool operator ==(Object other) {
    if (other is! InkStroke ||
        other.id != id ||
        other.tool != tool ||
        other.color != color ||
        other.size != size ||
        other.anchor != anchor ||
        other.points.length != points.length) {
      return false;
    }
    for (int index = 0; index < points.length; index++) {
      if (other.points[index] != points[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(id, tool, color, size, anchor, Object.hashAll(points));
  @override
  String toString() =>
      'InkStroke($id, ${tool.token}, $color, $size, ${points.length} point(s), $anchor)';
}
