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
//          AND IT ANSWERS THE SAME QUESTION ALONG A PATH, NOT ONLY AT ONE POINT. An eraser is
//          dragged the way a rubber is ([InkEraseTrail]), and a drag has to name every stroke the
//          path passes over, IN THE ORDER THE PATH REACHES THEM AND EACH EXACTLY ONCE. Order because
//          the deletions are applied one at a time and a musician watching them land expects the
//          order his hand made; once because a stroke that has been named is gone from the document
//          and naming it again would be a second deletion of the same stroke — refused by the log,
//          but still a rule this file should get right rather than rely on a refusal. The trail
//          lives here, beside the point query and for the same reason: it is geometry that decides
//          a rule, and both are checkable with `dart test` on a machine with no device and no hand.
// INPUTS: A [PageLayout], the document's strokes in render order, and a touch in SURFACE logical
//         pixels — the space a pointer event arrives in, not the page's engraved coordinates. The
//         page carries the whole bridge between the two, including the musician's own zoom and pan
//         (see `PageLayout.pagePointOf`), so an eraser aimed at a zoomed page names the stroke it
//         looks like it is aimed at.
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

  /// How far apart the samples of a dragged eraser are taken, in SURFACE logical pixels.
  ///
  /// A POINTER'S SAMPLES ARE NOT SPACED EVENLY AND CANNOT BE TRUSTED TO TOUCH WHAT THE HAND
  /// CROSSED. One `PointerMoveEvent` may carry a sample twenty logical pixels from the last one
  /// when the platform coalesces, and a stroke narrower than that gap would be stepped over by the
  /// eraser that visibly passed over it. The path is therefore resampled at this distance between
  /// consecutive test points, and four is derived rather than tuned: the narrowest band any stroke
  /// has is [tolerancePx], because the nib's own half-width is multiplied by a page scale that the
  /// FIT floor keeps at or above 1/3, so the band is at least six logical pixels wide and a step of
  /// four cannot straddle one. The cost of the smaller step is a test every four pixels instead of
  /// every event, which on this page is a few hundred tests for a screen-wide drag — measured by
  /// `tool/probe_ink_erase.dart`, not assumed.
  static const double pathStepPx = 4.0;
}

// PURPOSE: Say how far from a stroke's drawn line a touch may land and still be on it, in the
//          same SURFACE logical pixels the touch arrives in, so the eraser's band is computed in
//          one place for a tap and for a drag.
// INPUTS: stroke — the committed stroke, whose own nib is in anchor-local logical pixels. page —
//         the layout on screen, which carries both the page's scale and the musician's zoom.
//         aimTolerance — how far outside the drawn band still counts, in surface pixels.
// OUTPUTS: The band's half-width in surface pixels: the drawn half-nib plus [aimTolerance]. It grows
//          with the zoom because the nib is drawn through the same multiplier, and it can never be
//          smaller than the tolerance, because the tolerance is a size on the glass.
// KEYWORDS: erase-band, half-width, drawn-scale, one-formula, tap-and-drag-agree
/// Returns the half-width of the band the eraser measures [stroke] against, in surface pixels.
double inkEraseBandPx(
  InkStroke stroke,
  PageLayout page, {
  double aimTolerance = InkEraseAim.tolerancePx,
}) => inkStrokeNibWidth(stroke) * page.drawnScale / 2 + aimTolerance;

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
//
// THIS IS THE ONE-POINT CASE OF [InkEraseTrail] AND NOTHING ELSE. A tap is a path of one sample, so
// the rule that answers it is literally the rule that answers a drag, and there is no second copy
// of the band, the tie-break or the anchor resolution to drift out of step with the drag's.
/// Returns the stroke a touch at [surfacePoint] would erase, or null when it is on none.
InkEraseHit? hitTestInkErase({
  required PageLayout page,
  required List<InkStroke> strokes,
  required LayoutOffset surfacePoint,
  double aimTolerance = InkEraseAim.tolerancePx,
}) => InkEraseTrail(
  page: page,
  strokes: strokes,
  aimTolerance: aimTolerance,
).hitAt(surfacePoint);

// PURPOSE: Aim the eraser along the path a dragged contact travelled, naming every stroke the path
//          passed over, in the order it reached them and each exactly once, so the eraser works the
//          way a rubber does instead of demanding that a touch land on a stroke and not move. The
//          owner's report of the previous rule is the reason this exists: with it, a contact that
//          travelled at all erased nothing, so the eraser was usable only by a hand that stopped
//          dead on a line.
//
//          WHY IT IS A STATE OBJECT AND NOT A FUNCTION OVER THE WHOLE PATH. Two reasons, and both
//          are about the pen. First, the collection has to be visible WHILE the hand is still down:
//          what the musician needs to see is the rubber taking the ink away, not a result that
//          appears when he lifts. Second, the work has to be spread over the samples instead of
//          paid at the end — a full page holds thousands of points, and one call that measured
//          every stroke against every sample of a screen-wide drag would be a stall on the thread
//          that reads the pen, which is the failure this project already paid for once (A61's 1 738
//          ms of probe publication inside a stroke).
//
//          HOW THE COST IS KEPT SMALL, AND WHY THE FILTER IS EXACT RATHER THAN A HEURISTIC. Each
//          stroke's placed polyline is closed into a bounding box ONCE, inflated by that stroke's
//          own band, and a sample is measured against the polyline only when it falls inside that
//          box. A point outside the inflated box is farther from the box than the band, and the box
//          contains the polyline, so it is certainly farther than the band from the stroke: the
//          filter can only ever skip strokes the exact test would have rejected. What it buys is
//          that the expensive part — walking a polyline of hundreds of points — runs for the one or
//          two strokes under the rubber instead of for every stroke on the page.
// INPUTS: page — the layout on screen, captured when the contact landed and used for the whole
//         gesture, so a page that is re-engraved mid-drag cannot make the box and the exact test
//         disagree. strokes — the document's strokes in render order, as the document held them
//         when the contact landed; a stroke committed after that cannot be crossed by this gesture,
//         which is the safe direction for a pen that is writing while another hand erases.
//         aimTolerance and stepPx — the band's tolerance and the resampling distance.
// OUTPUTS: A trail whose `crossed` list grows by [addSample] and never repeats a stroke. It holds no
//          document and deletes nothing: the caller applies the deletions through the operation log,
//          which is the only writer. An empty stroke list gives a trail that can never cross
//          anything; a stroke whose anchor does not resolve on this page is skipped exactly as the
//          painter skips it; a stroke with no points is skipped rather than treated as a hit
//          everywhere.
// KEYWORDS: erase-trail, drag-erase, order-crossed, no-duplicates, incremental, bounding-box-filter,
//           exact-pruning, surface-coordinates
/// The strokes a dragged eraser has passed over, in the order it reached them.
class InkEraseTrail {
  /// Prepares the eraser's aim over [strokes] on [page].
  InkEraseTrail({
    required PageLayout page,
    required List<InkStroke> strokes,
    this.aimTolerance = InkEraseAim.tolerancePx,
    double stepPx = InkEraseAim.pathStepPx,
  }) : _page = page,
       _stepPx = stepPx.isFinite && stepPx > 0
           ? stepPx
           : InkEraseAim.pathStepPx {
    final double drawn = page.drawnScale;
    for (int index = 0; index < strokes.length; index++) {
      final InkStroke stroke = strokes[index];
      final List<InkPoint> points = stroke.points;
      if (points.isEmpty) {
        continue;
      }
      final InkPlacement? placement = resolveEventAnchor(page, stroke.anchor);
      if (placement == null) {
        continue;
      }
      double left = double.infinity;
      double top = double.infinity;
      double right = double.negativeInfinity;
      double bottom = double.negativeInfinity;
      for (final InkPoint point in points) {
        final double x = (placement.origin.x + point.x) * drawn + page.pan.x;
        final double y = (placement.origin.y + point.y) * drawn + page.pan.y;
        if (x < left) {
          left = x;
        }
        if (x > right) {
          right = x;
        }
        if (y < top) {
          top = y;
        }
        if (y > bottom) {
          bottom = y;
        }
      }
      final double band = inkEraseBandPx(
        stroke,
        page,
        aimTolerance: aimTolerance,
      );
      _candidates.add(
        _EraseCandidate(
          index: index,
          stroke: stroke,
          origin: placement.origin,
          left: left - band,
          top: top - band,
          right: right + band,
          bottom: bottom + band,
          band: band,
        ),
      );
    }
  }

  final PageLayout _page;

  /// How far outside a stroke's drawn band a sample still counts, in surface logical pixels.
  ///
  /// Public because it is the one number that changes what the eraser can be aimed at, and a
  /// reader of a trail in a report should be able to say which band produced the crossings it
  /// holds rather than infer it from the page's scale.
  final double aimTolerance;

  final double _stepPx;

  /// Every stroke the eraser may cross, with its box and its band already measured.
  final List<_EraseCandidate> _candidates = <_EraseCandidate>[];

  /// The strokes already crossed, by id, so a stroke the path stays over is named once.
  final Set<String> _crossedIds = <String>{};

  /// The strokes crossed so far, in the order the path reached them.
  final List<InkEraseHit> _crossed = <InkEraseHit>[];

  /// Where the path was last sampled, so the next segment can be walked rather than jumped.
  LayoutOffset? _last;

  /// The strokes crossed so far, in the order the path reached them, oldest first.
  List<InkEraseHit> get crossed => List<InkEraseHit>.unmodifiable(_crossed);

  /// The ids of the strokes crossed so far, which is what a preview needs to hide them.
  Set<String> get crossedIds => Set<String>.unmodifiable(_crossedIds);

  // PURPOSE: Add one point of the path and answer which strokes this point newly crossed, which is
  //          what lets the caller show the ink going away while the hand is still down.
  // INPUTS: surfacePoint — one sample of the contact, in the page widget's logical pixels.
  // OUTPUTS: The hits this sample added, in the order they were crossed along the segment from the
  //          previous sample, which is exactly one per resampled test point and may be empty. The
  //          area between the previous sample and this one is walked at [InkEraseAim.pathStepPx], so
  //          a fast drag between two far-apart events still tests the pixels it passed over. A
  //          repeated identical sample tests the point once more — which is what makes a tap, whose
  //          down and up are the same point, work — and finds nothing new, because the stroke it
  //          lands on is already crossed.
  // KEYWORDS: add-sample, resample, order-crossed, idempotent, tap-is-a-one-point-path
  /// Adds one sample of the eraser's path, returning the strokes it newly crossed.
  List<InkEraseHit> addSample(LayoutOffset surfacePoint) {
    final List<InkEraseHit> found = <InkEraseHit>[];
    final LayoutOffset? previous = _last;
    _last = surfacePoint;
    if (previous == null) {
      final InkEraseHit? hit = hitAt(surfacePoint);
      if (hit != null) {
        found.add(hit);
      }
      return found;
    }
    final double dx = surfacePoint.x - previous.x;
    final double dy = surfacePoint.y - previous.y;
    final double length = math.sqrt(dx * dx + dy * dy);
    if (length <= 0) {
      final InkEraseHit? hit = hitAt(surfacePoint);
      if (hit != null) {
        found.add(hit);
      }
      return found;
    }
    final int steps = math.max(1, (length / _stepPx).ceil());
    for (int step = 1; step <= steps; step++) {
      final LayoutOffset point = LayoutOffset(
        previous.x + dx * step / steps,
        previous.y + dy * step / steps,
      );
      final InkEraseHit? hit = hitAt(point);
      if (hit != null) {
        found.add(hit);
      }
    }
    return found;
  }

  // PURPOSE: Answer which stroke a single point of the path is on, by the rule the tap has always
  //          used, and record it as crossed so no later sample names it again.
  // INPUTS: surfacePoint — one point, in the page widget's logical pixels.
  // OUTPUTS: The hit, or null when no uncrossed stroke is within its band of the point. A stroke
  //          already crossed is not a candidate: the path may stay over it for hundreds of samples
  //          and must not delete it twice, and a stroke that shares its band with another one is
  //          reached by a later sample of the path rather than by this one.
  // KEYWORDS: hit-query, nearest, tie-break, once-only, band-test
  /// Returns the stroke a single point of the path is on, recording it as crossed.
  InkEraseHit? hitAt(LayoutOffset surfacePoint) {
    final double drawn = _page.drawnScale;
    final LayoutOffset pagePoint = _page.pagePointOf(surfacePoint);
    InkEraseHit? best;
    double nearest = double.infinity;
    for (final _EraseCandidate candidate in _candidates) {
      if (_crossedIds.contains(candidate.stroke.id)) {
        continue;
      }
      if (!candidate.covers(surfacePoint)) {
        continue;
      }
      final double engraved = inkStrokeDistanceToPagePoint(
        stroke: candidate.stroke,
        origin: candidate.origin,
        pagePoint: pagePoint,
      );
      if (!engraved.isFinite) {
        continue;
      }
      final double surface = engraved * drawn;
      if (surface > candidate.band) {
        continue;
      }
      if (surface < nearest - InkEraseAim.tiePx) {
        nearest = surface;
        best = candidate.hitAt(surface);
      } else if (best != null && surface <= nearest + InkEraseAim.tiePx) {
        best = candidate.hitAt(surface);
      }
    }
    if (best != null) {
      _crossedIds.add(best.stroke.id);
      _crossed.add(best);
    }
    return best;
  }
}

/// One stroke the eraser may be aimed at, with everything about it that does not depend on the touch.
///
/// A value rather than a set of parallel lists because the three facts travel together: the box that
/// prunes, the band that decides and the origin the exact distance needs are one stroke's, and a
/// caller that could take one without the others is a caller that can mix two strokes up.
class _EraseCandidate {
  const _EraseCandidate({
    required this.index,
    required this.stroke,
    required this.origin,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.band,
  });

  /// Position in the document's stroke list, which is render order and the tie-breaker.
  final int index;

  /// The stroke itself, which is what a deletion is applied to and what a stroke id names.
  final InkStroke stroke;

  /// The anchor's top-left corner on the page, in engraved page coordinates.
  final LayoutOffset origin;

  /// The placed polyline's bounding box in SURFACE pixels, already inflated by [band].
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// The half-width of the band this stroke is measured against, in SURFACE pixels.
  final double band;

  /// Whether [point] is inside the inflated box, i.e. whether the exact test can possibly pass.
  bool covers(LayoutOffset point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  /// The hit this candidate makes at [surfaceDistance] surface pixels from the touch.
  InkEraseHit hitAt(double surfaceDistance) => InkEraseHit(
    index: index,
    stroke: stroke,
    origin: origin,
    surfaceDistance: surfaceDistance,
  );
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
