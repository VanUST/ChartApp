// PURPOSE: Give the layout engine the few geometric values it needs without pulling in a
//          rendering stack. chart_core must stay free of Flutter — that is what lets the whole
//          layout pipeline be measured on a desktop with `dart test` — so it cannot use dart:ui's
//          Offset, Size and Rect, and defining the three it actually needs is cheaper than
//          adding a geometry dependency to a package whose dependency list is empty on purpose.
// INPUTS: Plain doubles in logical pixels.
// OUTPUTS: Immutable values. LayoutRect reports its edges and answers containment, which is the
//          operation a tap handler needs to turn a touch into the chord underneath it.
// KEYWORDS: geometry, rectangle, size, offset, hit-testing, layout, pure-dart
//
// The axis convention matches Flutter's: x grows right, y grows down, and the origin is the
// top-left of the page.

/// A width and a height, in logical pixels.
class LayoutSize {
  /// Creates a size with the given [width] and [height].
  const LayoutSize(this.width, this.height);

  /// A size with no extent.
  static const LayoutSize zero = LayoutSize(0, 0);

  /// Horizontal extent.
  final double width;

  /// Vertical extent.
  final double height;

  @override
  bool operator ==(Object other) =>
      other is LayoutSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// A position measured from the top-left corner of a page, in logical pixels.
class LayoutOffset {
  /// Creates an offset at ([x], [y]).
  const LayoutOffset(this.x, this.y);

  /// The top-left corner of a page.
  static const LayoutOffset zero = LayoutOffset(0, 0);

  /// Horizontal distance from the page's left edge.
  final double x;

  /// Vertical distance from the page's top edge.
  final double y;

  @override
  bool operator ==(Object other) =>
      other is LayoutOffset && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// An axis-aligned rectangle: where something landed on the page.
class LayoutRect {
  /// Creates a rectangle from its top-left [origin] and its [size].
  const LayoutRect({required this.origin, required this.size});

  /// Creates a rectangle from its left, top, width and height.
  ///
  /// NOT a const constructor, and this is a language rule rather than a preference: a const
  /// constructor's initializer list may reference its own parameters but may not INVOKE another
  /// constructor, not even a const one and not even with a literal argument. Measured, not
  /// assumed — with `const` on this constructor the analyzer reports `invalid_constant` on both
  /// `LayoutOffset(x, y)` and `LayoutSize(width, height)`, and the same error appears in a
  /// three-line reduction of this file. It is why the Flutter framework writes
  /// `Rect.fromLTWH` as a `this.fromLTRB(...)` redirect rather than initialising fields directly.
  ///
  /// The primary constructor stays const, so a rectangle built from an [origin] and a [size] is
  /// still a compile-time constant; only this convenience form is built at run time.
  ///
  /// The parameters are named [x] and [y] rather than `left` and `top` so that they do not shadow
  /// this class's getters of those names, which would make the body harder to read.
  LayoutRect.fromLTWH(double x, double y, double width, double height)
    : origin = LayoutOffset(x, y),
      size = LayoutSize(width, height);

  /// The top-left corner.
  final LayoutOffset origin;

  /// The extent from [origin].
  final LayoutSize size;

  /// The x coordinate of the left edge.
  double get left => origin.x;

  /// The y coordinate of the top edge.
  double get top => origin.y;

  /// The x coordinate of the right edge.
  double get right => origin.x + size.width;

  /// The y coordinate of the bottom edge.
  double get bottom => origin.y + size.height;

  // PURPOSE: Answer whether a point lies inside this rectangle, which is how a touch becomes the
  //          chord under it. The engine produces rectangles precisely so that this question has
  //          an answer that does not require re-running the layout.
  // INPUTS: point — a position in the same coordinate space as this rectangle.
  // OUTPUTS: True when the point is inside or on the boundary. A rectangle with zero width or
  //          height therefore contains only points exactly on its edge; the engine never emits
  //          one, because a bar is always given a non-zero minimum width.
  // KEYWORDS: hit-testing, containment, tap-target, boundary-inclusive
  /// Returns whether [point] lies inside this rectangle, boundary included.
  bool contains(LayoutOffset point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  @override
  bool operator ==(Object other) =>
      other is LayoutRect && other.origin == origin && other.size == size;

  @override
  int get hashCode => Object.hash(origin, size);

  @override
  String toString() => 'LayoutRect($left, $top, ${size.width}, ${size.height})';
}
