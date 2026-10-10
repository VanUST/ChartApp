// PURPOSE: Answer the one question an eraser asks of the ink on a page — which stroke is under this
//          touch, and how far away was it — in pure geometry, so the answer is a measurement rather
//          than a guess and can be checked with `dart test` on a machine with no device and no hand.
//          It exists because the model's own decision is that the eraser removes WHOLE STROKES: the
//          eraser is an operation on the stroke list (`ink.stroke.delete`) and not a stroke of its
//          own, so the entire problem it poses is "which stroke did the musician mean", and that is
//          a distance from a point to a polyline plus one rule for the case where two strokes are
//          both close.
//
//          WHAT "ON THE STROKE" MEANS, DECIDED HERE AND NOT IN A CALLER. A stroke is stored as a
//          polyline — a list of anchor-local samples — and drawn as round-capped segments whose
//          width follows the nib. "On it" is therefore "within the drawn band, plus the width of the
//          thing that touched it": the distance from the touch to the polyline is compared against
//          half the nib (`inkStrokeNibWidth`) plus a declared aim tolerance. The nib half-width is
//          in the stroke's own anchor-local pixels, converted to the surface by the page scale; the
//          tolerance is in surface logical pixels, because it stands for the contact patch of a
//          finger or a stylus tip and that is a size on the glass, not a size in the music.
//
//          WHY THE TIE RULE IS "NEAREST, THEN TOPMOST". Two strokes may pass within a few pixels of
//          one another, and then the band of one contains a point that is nearer the other. The
//          musician can see only one of them at that pixel, and it is the one the renderer drew
//          last, because the document's stroke order IS the render order (see `InkPainter`). So when
//          two candidates are within [InkEraseAim.tiePx] of the same nearest distance, the LATER
//          stroke in document order wins: the eraser takes the stroke the musician can see. A tie
//          rule that preferred the earlier stroke would delete the one hidden underneath — an
//          outcome the musician could not have predicted from the screen, and the failure this
//          feature is most likely to have.
// INPUTS: A [PageLayout], the document's strokes in render order, and a touch in SURFACE logical
//         pixels — the space a pointer event arrives in, not the page's engraved coordinates.
// OUTPUTS: An [InkEraseHit] naming the stroke, its position in the document list, the anchor origin
//          it resolved to and the surface distance that decided it; null when no stroke is within
//          the band. A stroke whose anchor does not resolve on this page is skipped rather than
//          guessed at, which is the same rule the painter follows for a stroke on another page.
//          Nothing throws: a stroke with a meaningless nib (zero, negative or NaN) is measured by
//          the renderer's own fallback and a degenerate one-point stroke is measured as a dot.
// KEYWORDS: eraser, ink, hit-testing, point-to-polyline, nearest-stroke, tie-rule, render-order,
//           pure-dart, anchor-resolution, surface-coordinates
import 'dart:math' as math;

import '../layout/geometry.dart';
import '../layout/page_layout.dart';
import '../oplog/oplog.dart';
import 'page_anchor.dart';

/// The constants that decide whether a touch is on a stroke, and which stroke wins a near tie.
///
/// They are named and stated rather than inlined because each one is a judgement a reader is
/// entitled to disagree with, and a number buried in an expression cannot be argued with.
class InkEraseAim {
  const InkEraseAim._();

  /// How far outside the drawn band a touch may land and still count, in SURFACE logical pixels.
  ///
  /// It stands for the contact patch of the thing that touched the stroke plus the steadiness of a
  /// hand: a finger's contact reported 1 to 8 logical pixels of width in the browser spike (A36),
  /// so half of the widest of those is 4, and a stylus tip is narrower still. Six puts the whole
  /// aim band for a pen (nib 3) at 7.5 logical pixels of radius, which is one comfortable finger
  /// away from the line and still far inside the gap between two systems.
  ///
  /// This is a judgement, not a measurement, and a different panel needs its own separation
  /// measured before the number is reused — the same caveat the palm rule's threshold carries.
  static const double tolerancePx = 6.0;

  /// The distance within which two candidates count as equally near, in SURFACE logical pixels.
  ///
  /// Half a logical pixel: large enough that two parallel strokes a fraction of a pixel apart in
  /// their distance to the touch are treated as the coincidence they are, small enough that a
  /// stroke that is visibly farther away never wins over one the musician is touching.
  static const double tiePx = 0.5;
}

/// One candidate the eraser found: the stroke, where it sits in the document, and how near it was.
class InkEraseHit {
  /// Creates a hit on [stroke] at document position [index], resolved to [origin].
  const InkEraseHit({
    required this.index,
    required this.stroke,
    required this.origin,
    required this.surfaceDistance,
  });

  /// Zero-based position of [stroke] in the document's stroke list, which is its render order.
  final int index;

  /// The stroke the touch was nearest to.
  final InkStroke stroke;

  /// The anchor's top-left corner on the page, in engraved page coordinates, as the painter uses it.
  final LayoutOffset origin;

  /// The distance from the touch to the stroke's polyline, in SURFACE logical pixels.
  final double surfaceDistance;

  @override
  String toString() =>
      'InkEraseHit(${stroke.id} at $index, '
      '${surfaceDistance.toStringAsFixed(2)} px)';
}

// PURPOSE: Give the eraser's band the same nib width the renderer draws with, so the pixels a
//          musician can touch are the pixels the eraser can find. The two would otherwise be a
//          second copy of one rule, and the failure of a copy is silent: the stroke would simply be
//          harder to hit than it looks, and only on the strokes whose stored size happened to be
//          absent.
// INPUTS: stroke — the committed stroke, whose `size` is the nib in anchor-local logical pixels.
// OUTPUTS: The nib width in the stroke's own anchor-local units. A size that is zero or negative
//          falls back to the renderer's per-tool default (3 for the pen, 18 for the highlighter),
//          because `InkStroke` permits a size a file may have written as zero and `InkPainter`
//          draws such a stroke at that default. A non-finite size is returned as it is, and the
//          caller's comparison then refuses the stroke rather than admitting it on a meaningless
//          number — the same fail-closed direction the palm rule takes with an unmeasured width.
// KEYWORDS: nib-width, single-rule, renderer-agreement, fallback, anchor-local, no-throw
/// Returns the nib width [stroke] is drawn with, in anchor-local logical pixels.
double inkStrokeNibWidth(InkStroke stroke) {
  if (stroke.size <= 0) {
    return stroke.tool == StrokeTool.highlighter
        ? inkDefaultHighlighterNib
        : inkDefaultPenNib;
  }
  return stroke.size;
}

/// The nib width a pen stroke is drawn with when its stored size is absent.
const double inkDefaultPenNib = 3;

/// The nib width a highlighter stroke is drawn with when its stored size is absent.
const double inkDefaultHighlighterNib = 18;

// PURPOSE: Measure how far a point on the page is from a stroke's own line, which is the quantity
//          every eraser decision is made from. It walks the polyline rather than a bounding box
//          because a box around a long diagonal stroke covers half the bar it crosses, and an
//          eraser that used the box would delete a stroke from a touch nowhere near its ink.
// INPUTS: stroke — the committed stroke, whose points are anchor-local. origin — the anchor's
//         top-left corner on the page, in engraved coordinates. pagePoint — the point to measure
//         from, in the SAME engraved coordinates.
// OUTPUTS: The shortest distance from [pagePoint] to any segment of the stroke, in engraved page
//          pixels. A one-point stroke — stored as two identical points — measures as the distance
//          to that point, so a dot is as touchable as a line. A stroke with no points, which the
//          storage contract forbids but a hand-built value may still be, measures as infinity so
//          that it can never be the answer.
// KEYWORDS: point-to-segment, distance, polyline, dot, degenerate-input, engraved-coordinates
/// Returns the shortest distance from [pagePoint] to the placed polyline of [stroke].
double inkStrokeDistanceToPagePoint({
  required InkStroke stroke,
  required LayoutOffset origin,
  required LayoutOffset pagePoint,
}) {
  final List<InkPoint> points = stroke.points;
  if (points.isEmpty) {
    return double.infinity;
  }
  double best = double.infinity;
  final LayoutOffset first = LayoutOffset(
    origin.x + points.first.x,
    origin.y + points.first.y,
  );
  if (points.length == 1) {
    return _distance(pagePoint, first);
  }
  LayoutOffset previous = first;
  for (int index = 1; index < points.length; index++) {
    final LayoutOffset current = LayoutOffset(
      origin.x + points[index].x,
      origin.y + points[index].y,
    );
    final double distance = _distanceToSegment(pagePoint, previous, current);
    if (distance < best) {
      best = distance;
    }
    previous = current;
  }
  return best;
}

// PURPOSE: Answer which stroke an eraser touch is on, resolving the near-tie case by the one rule
//          the musician can predict from the screen. It is separate from the distance function
//          above because the distance is geometry and this is a decision, and the decision is the
//          part that has to be stated rather than inferred.
// INPUTS: page — the laid-out page the touch landed on, which resolves every stroke's anchor and
//         carries the scale between engraved and surface coordinates. strokes — the document's
//         strokes in render order, exactly as `DocumentState.strokes` holds them. surfacePoint — the
//         touch, in the page widget's own logical pixels. aimTolerance — how far outside the drawn
//         band still counts, in surface pixels; a caller that wants the plain answer passes nothing.
// OUTPUTS: The [InkEraseHit] to erase, or null when every stroke is farther than its own band plus
//          [aimTolerance]. The nearest stroke wins; among strokes whose distances are within
//          [InkEraseAim.tiePx] of that nearest distance the LAST in document order wins, because
//          the document's order is the render order and the last one drawn is the one visible at the
//          touch. A stroke on another page, or one whose anchor the page cannot resolve, is skipped
//          exactly as the painter skips it.
// KEYWORDS: erase-hit, nearest, topmost-tie-break, render-order, anchor-resolution, null-on-miss
/// Returns the stroke a touch at [surfacePoint] would erase, or null when it is on none.
InkEraseHit? hitTestInkErase({
  required PageLayout page,
  required List<InkStroke> strokes,
  required LayoutOffset surfacePoint,
  double aimTolerance = InkEraseAim.tolerancePx,
}) {
  final double scale = page.scale;
  final LayoutOffset pagePoint = page.pagePointOf(surfacePoint);
  InkEraseHit? best;
  // The strict minimum is tracked separately from [best] so that the tie branch below can promote a
  // later stroke without letting the bar for "nearest" creep upwards one near-tie at a time.
  double nearest = double.infinity;
  for (int index = 0; index < strokes.length; index++) {
    final InkStroke stroke = strokes[index];
    final InkPlacement? placement = resolveEventAnchor(page, stroke.anchor);
    if (placement == null) {
      continue;
    }
    final double engraved = inkStrokeDistanceToPagePoint(
      stroke: stroke,
      origin: placement.origin,
      pagePoint: pagePoint,
    );
    if (!engraved.isFinite) {
      continue;
    }
    final double surface = engraved * scale;
    final double band = inkStrokeNibWidth(stroke) * scale / 2 + aimTolerance;
    if (surface > band) {
      continue;
    }
    if (surface < nearest - InkEraseAim.tiePx) {
      nearest = surface;
      best = InkEraseHit(
        index: index,
        stroke: stroke,
        origin: placement.origin,
        surfaceDistance: surface,
      );
    } else if (best != null && surface <= nearest + InkEraseAim.tiePx) {
      best = InkEraseHit(
        index: index,
        stroke: stroke,
        origin: placement.origin,
        surfaceDistance: surface,
      );
    }
  }
  return best;
}

/// The distance between two points.
double _distance(LayoutOffset a, LayoutOffset b) {
  final double dx = a.x - b.x;
  final double dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// The distance from [point] to the segment [a]–[b], clamped to the segment's own ends.
///
/// A zero-length segment is the dot case and measures as the distance to [a], which is what a
/// one-point stroke is drawn as.
double _distanceToSegment(LayoutOffset point, LayoutOffset a, LayoutOffset b) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double lengthSquared = dx * dx + dy * dy;
  if (lengthSquared <= 0) {
    return _distance(point, a);
  }
  final double projection =
      ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared;
  final double clamped = projection < 0 ? 0 : (projection > 1 ? 1 : projection);
  return _distance(point, LayoutOffset(a.x + clamped * dx, a.y + clamped * dy));
}
