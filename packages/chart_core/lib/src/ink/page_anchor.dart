// PURPOSE: Bridge the two coordinate systems a handwritten stroke lives in — the page the musician
//          is looking at when they draw, and the anchor the stroke is stored against — in one
//          place, so that capture, rendering, the FIT scale and a transposition all agree about
//          where the ink is. This is the file that makes the promise in `oplog/ink.dart` true: a
//          stroke is stored in ANCHOR-LOCAL logical pixels, which is what lets it stay on the same
//          musical position when the page is fitted, when the key is transposed and when the file
//          is saved and read back.
//
//          The anchor rect is the CELL a stroke began in, or the BAR when the musician started in
//          one of the bar's paddings where no cell has a column. A cell rect spans the bar's full
//          stave height and one beat's column, so a stroke begun anywhere in a cell — above, on or
//          below the chord symbol — is anchored to that cell and moves with the music.
//
//          A STROKE THAT BEGINS OUTSIDE EVERY BAR IS ANCHORED TO THE BAR NEAREST IT, and that
//          third case is the rule this file now exists to state. The page a musician writes on has
//          more room than the bars occupy: the top margin above the first system, the space a
//          section label leaves, the gap between two systems, the left margin, the white below the
//          last system and the whole of the melody staff. It is all paper a musician marks, and the
//          anchor is a REFLOW mechanism rather than a permission to write. See
//          [resolveNearestBarAnchor] for why the nearest bar and not the page.
// INPUTS: A [PageLayout], an [EventAnchor], and positions in page or surface logical pixels.
// OUTPUTS: Immutable values and total functions. A resolution that cannot find the anchor on the
//          page returns null rather than a guessed rectangle, because a stroke drawn at a fabricated
//          position is worse than one that is visibly missing: it would look correct on screen and
//          be anchored to nothing. The one place null is still reachable for a stroke's FIRST
//          sample is a page that carries no bar at all, which the layout engine does not produce.
// KEYWORDS: ink, anchor-local, coordinate-transform, fit-scale, page-transform, transposition,
//           reflow-survival, nearest-bar, margin-writing, pure-dart
import 'dart:math' as math;

import 'package:chart_core/src/layout/geometry.dart';
import 'package:chart_core/src/layout/hit_test.dart';
import 'package:chart_core/src/layout/page_layout.dart';
import 'package:chart_core/src/oplog/oplog.dart';

/// Where one anchor landed on one page: both its address and the rectangle that resolves it.
///
/// The rectangle travels with the address because every use of the anchor — placing a point, or
/// drawing a stroke at the right size — needs the rectangle, and re-deriving it from the address at
/// each call site is how two answers to one question start to differ.
class InkPlacement {
  /// Creates a placement for [anchor], resolved in [page] to [bounds].
  const InkPlacement({
    required this.anchor,
    required this.pageIndex,
    required this.bounds,
  });

  /// The address the bounds were resolved from.
  final EventAnchor anchor;

  /// Which page the anchor was found on.
  final int pageIndex;

  /// The rectangle the anchor names, in the page's engraved coordinates.
  ///
  /// Engraved, not surface: multiply by the page's scale to reach the surface the page is drawn on.
  /// That one multiplication is the reason a fitted page does not displace its ink.
  final LayoutRect bounds;

  /// The anchor rectangle's origin, which is the point every stored coordinate is measured from.
  LayoutOffset get origin => bounds.origin;

  /// The anchor as one comparable string key, so placements can be indexed by address.
  ///
  /// THE KEY IS THE BAR AND NOTHING ELSE, because a stroke is anchored to a bar: the position inside
  /// it is in the stroke's own points, which are bar-local logical pixels. There used to be a beat
  /// and a step in this key, from the days when a stroke was captured against a cell; the grid those
  /// two numbers came from is gone, and a key that named one would be a second answer to where the
  /// stroke was drawn.
  static String keyOf(EventAnchor anchor) =>
      '${anchor.sectionId}\u0000${anchor.bar}';

  /// This placement's key, for a lookup indexed by [keyOf].
  String get key => keyOf(anchor);

  @override
  bool operator ==(Object other) =>
      other is InkPlacement &&
      other.anchor == anchor &&
      other.pageIndex == pageIndex &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(anchor, pageIndex, bounds);

  @override
  String toString() => 'InkPlacement($anchor on page $pageIndex at $bounds)';
}

/// The placement of every anchor one page can answer, indexed by [InkPlacement.keyOf].
///
/// Built once per page and per address family that is being drawn, so drawing a hundred strokes
/// walks the page once instead of re-deriving each rectangle from the layout.
class InkPageIndex {
  /// Creates an index over [placements].
  const InkPageIndex(this.placements);

  /// Builds the index for every bar of [page].
  ///
  /// ONE FAMILY OF RECTANGLES, because the grid that gave the other one columns is gone: a stroke is
  /// written beside a BAR and carries its own offsets from that bar, so the bar's rectangle is both
  /// the address and the origin of the coordinates. A row of narrower cell rectangles used to be
  /// indexed first, and the only thing it bought was a narrower origin — which the stroke's own
  /// points now carry without a second lookup.
  factory InkPageIndex.ofPage(PageLayout page) {
    final Map<String, InkPlacement> placements = <String, InkPlacement>{};
    for (final PlacedBar bar in page.bars) {
      final InkPlacement placement = InkPlacement(
        anchor: EventAnchor(sectionId: bar.sectionId, bar: bar.barIndex),
        pageIndex: page.index,
        bounds: bar.bounds,
      );
      placements.putIfAbsent(placement.key, () => placement);
    }
    return InkPageIndex(placements);
  }

  /// The placements, by key.
  final Map<String, InkPlacement> placements;

  /// The placement for [anchor], or null when this page cannot resolve it.
  InkPlacement? placementFor(EventAnchor anchor) =>
      placements[InkPlacement.keyOf(anchor)];
}

// PURPOSE: Find where a stroke's anchor landed on a page, so the stroke can be placed relative to
//          the bar it was drawn in rather than to the page corner. This is the lookup that must
//          succeed for a stroke to appear at all, and it is deliberately a page-level search rather
//          than a stored rectangle: the rectangle stored at capture time would be stale after a
//          transposition moved the bar half a millimetre.
// INPUTS: page — the layout to resolve against. anchor — the address the stroke carries.
// OUTPUTS: The [InkPlacement] for the bar the anchor names, or null when the page has no bar at that
//          address. Null is a real answer and not a failure: an anchor may name a bar on another
//          page of a paginated document, and the caller drawing one page must simply not draw that
//          stroke here.
//
//          THE ANSWER IS ALWAYS THE BAR'S OWN RECTANGLE, and that is what makes a stroke's stored
//          points bar-local. It used to be a narrower cell rectangle when the anchor named a beat,
//          which meant the same stroke's numbers changed meaning depending on where it was written;
//          one family of rectangles means one meaning.
// KEYWORDS: anchor-resolution, placement, lookup, null-when-absent, page-coordinates, bar-anchored
/// Returns the placement of [anchor] on [page], or null when the page does not hold it.
InkPlacement? resolveEventAnchor(PageLayout page, EventAnchor anchor) {
  for (final PlacedBar bar in page.bars) {
    if (bar.sectionId == anchor.sectionId && bar.barIndex == anchor.bar) {
      return InkPlacement(
        anchor: anchor,
        pageIndex: page.index,
        bounds: bar.bounds,
      );
    }
  }
  return null;
}

/// Which of the two rules chose a stroke's anchor, so that "this stroke is anchored to the bar
/// nearest it" is a fact the log states rather than one a reader infers from a rectangle.
enum InkAnchorBasis {
  /// The stroke began on a bar, so it is anchored to the bar itself.
  ///
  /// There used to be a finer case for a stroke begun inside a beat column. The columns went with
  /// the grid that divided the bar into them, and a stroke's own offset from its bar is what tells a
  /// reader where along the bar he wrote — so one case is left, and it is the honest one.
  bar('bar'),

  /// The stroke began outside every bar — a margin, the space between two systems, or the melody
  /// staff — so it is anchored to the bar nearest the point it began at.
  nearestBar('nearest-bar');

  const InkAnchorBasis(this.token);

  /// Stable spelling used in a log line.
  final String token;
}

/// The anchor one stroke's first sample resolved to, together with the rule that chose it.
///
/// The rule travels with the anchor because two strokes with the same rectangle can be different
/// statements — one written inside a cell, one written in the margin and hung on the same bar —
/// and a report that could not tell them apart would be unable to show that margin writing works.
class InkAnchorChoice {
  /// Creates a choice of [placement] made by [basis], [distancePx] from the stroke's first sample.
  const InkAnchorChoice({
    required this.placement,
    required this.basis,
    this.distancePx = 0,
  });

  /// Where the anchor landed on the page the stroke was drawn on.
  final InkPlacement placement;

  /// The rule that chose it.
  final InkAnchorBasis basis;

  /// How far the first sample lay outside the anchor's rectangle, in ENGINE-PAGE pixels.
  ///
  /// Zero for [InkAnchorBasis.bar], which contains the point by
  /// construction. A positive value on [InkAnchorBasis.nearestBar] is the honest measure of how far
  /// into the margin the musician wrote: it is what a reader checks against the picture, and it is
  /// what a future "should this have been refused" question can be asked of instead of a guess.
  final double distancePx;

  /// The address the stroke is stored against.
  EventAnchor get anchor => placement.anchor;

  /// The anchor's top-left corner on the page, which every stored coordinate is measured from.
  LayoutOffset get origin => placement.origin;

  @override
  String toString() =>
      'InkAnchorChoice(${basis.token}, $anchor, '
      'distance=${distancePx.toStringAsFixed(1)})';
}

// PURPOSE: Answer the distance, in page pixels, from a point to a rectangle, which is what "the
//          nearest bar" is measured with. It is a function rather than a line in the search below
//          because the meaning of the number is what the whole rule rests on: a point to the SIDE
//          of a bar and a point ABOVE it are measured on the same footing, and neither is favoured
//          by the page's reading order.
// INPUTS: rect — a rectangle in the page's coordinates. point — a position in the same coordinates.
// OUTPUTS: Zero when the point lies inside or on the rectangle, otherwise the length of the
//          shortest straight line from the point to the rectangle's edge, always finite and never
//          negative. The diagonal case is the Euclidean distance to the nearest corner, which is
//          the only answer consistent with the two axis-aligned cases.
// KEYWORDS: rectangle-distance, nearest, geometry, total-function, pure-dart
/// Returns how far [point] lies outside [rect], in the same units.
double inkRectDistance(LayoutRect rect, LayoutOffset point) {
  final double dx = point.x < rect.left
      ? rect.left - point.x
      : (point.x > rect.right ? point.x - rect.right : 0);
  final double dy = point.y < rect.top
      ? rect.top - point.y
      : (point.y > rect.bottom ? point.y - rect.bottom : 0);
  return math.sqrt(dx * dx + dy * dy);
}

// PURPOSE: Find the bar a stroke written OUTSIDE every bar hangs on, so that the paper between the
//          bars stops being unwritable. This is the answer to a defect the owner reported in his own
//          words — "всё ещё нет свободного письма по всему документу" — after reproducing it with a
//          pen: a stroke that began in a bar committed, and a stroke that began in the margin was
//          refused with `no-anchor-at-start`.
//
//          WHY THE NEAREST BAR, AND WHY THAT IS NOT A GUESS ABOUT INTENT. The alternatives were
//          considered and each fails on the one requirement that matters — that the mark must
//          survive a reflow without teleporting:
//
//            - THE PAGE, stored as page coordinates. A margin mark then does not move when the page
//              is re-paginated, so inserting bars that push the music onto another page leaves the
//              mark on a page whose content has changed: it teleports onto unrelated music, or
//              falls off the document entirely. Page numbers are an OUTPUT of layout and cannot be
//              an address for something that has to outlive it.
//            - A PAGE-LEVEL ANCHOR carried in the anchor's own fields. Same defect, one level down:
//              `EventAnchor` addresses a SECTION and a bar, and a page is not expressible in it
//              without inventing a fifth address space that every renderer, the eraser and the file
//              format would then have to learn.
//            - ATTACHING TO THE NEAREST BAR. This is the only one that survives, and the reason is
//              that the choice is made ONCE, at the moment of writing, and then STORED. The
//              objection that "the nearest bar is a guess about intent" is right about a decision
//              re-derived at every render, and wrong about one frozen at capture: from then on it
//              is a record of where the musician wrote, exactly as the cell anchor is. The mark
//              moves with the bar it was written beside through a transposition, a reflow and a
//              save-and-reopen, which is the same promise every other anchor in the document makes.
//
//          WHAT IT COSTS, NAMED RATHER THAN HIDDEN. A mark in the gap between two systems is hung on
//          whichever of the neighbouring bars is nearer, and on an exact tie on the EARLIER one in
//          reading order; a reflow that moves those bars apart takes the mark with the bar it was
//          hung on. And because a bar index inside a section is the model's address, inserting a bar
//          before it moves the mark with the index, exactly as it moves a chord at that index — the
//          document's existing address semantics, not a new exception.
//
//          WHY IT PREFERS THE BAR AND NEVER THE CELL. A cell is a column of TIME inside a bar, and a
//          point outside the bar has no column: choosing one would silently claim the mark was
//          written on a beat. Bar level is the honest granularity for something written beside the
//          music rather than at a beat of it, and it is the same value `hitTestPage` already
//          returns for a point in a bar's own padding.
// INPUTS: page — the layout the stroke is being drawn on, in engraved coordinates. pagePoint — the
//         stroke's first position in those same coordinates, which a caller obtains through
//         [PageLayout.pagePointOf] if it holds a point on the glass.
// OUTPUTS: The placement of the nearest bar, or null when the page carries no bar at all. Null is
//          reachable only for a page the layout engine does not produce — a song with no bars is
//          reported to the musician as an empty song rather than engraved as a blank page — so in
//          every state a musician can draw on, a stroke begun anywhere resolves to some bar.
//          Ties go to the FIRST bar in reading order, because the comparison is strict: two bars
//          equidistant from a point must not resolve differently on two runs of the same app.
// KEYWORDS: ink-anchor, margin-writing, nearest-bar, reflow-survival, no-teleport, once-at-capture,
//           deterministic-tie-break, d32
/// Returns the placement of the bar nearest [pagePoint], or null when the page has no bar.
InkPlacement? resolveNearestBarAnchor(PageLayout page, LayoutOffset pagePoint) {
  InkPlacement? nearest;
  double nearestDistance = double.infinity;
  for (final PlacedBar bar in page.bars) {
    final double distance = inkRectDistance(bar.bounds, pagePoint);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = InkPlacement(
        anchor: EventAnchor(sectionId: bar.sectionId, bar: bar.barIndex),
        pageIndex: page.index,
        bounds: bar.bounds,
      );
    }
  }
  return nearest;
}

// PURPOSE: Choose, in ONE place, the anchor one stroke is stored against, so that capture has a
//          single rule and a reader can see the whole of it without following a call site. Two cases
//          are decided here: the bar the point lies on, and the nearest bar when it lies on none.
// INPUTS: page — the layout, in engraved coordinates. pagePoint — the stroke's first sample in
//         those coordinates.
// OUTPUTS: The choice, or null only for a page that carries no bar, in which case there is nothing
//          in the document to anchor to and the caller must report the refusal rather than store a
//          fabricated address. Every other outcome is an anchor: refusing to store a mark the
//          musician made is the defect this function was written to remove.
//
//          THE THREE-STEP LADDER LOST A STEP. It used to prefer the CELL the point was over, then
//          the bar, then the nearest bar — and the cell step only ever changed which rectangle the
//          stored coordinates were measured from, which is exactly the second answer to "where is
//          this stroke" that the bar alone gives. A stroke's position along its bar is now in its
//          own points, so the ladder is: the bar under the point, else the nearest bar.
// KEYWORDS: ink-anchor, single-rule, bar-then-nearest, no-refusal, capture-entry, bar-anchored
/// Returns the anchor for a stroke that began at [pagePoint], with the rule that chose it.
InkAnchorChoice? resolveInkAnchor(PageLayout page, LayoutOffset pagePoint) {
  final ChartHit? hit = hitTestPage(page, pagePoint);
  if (hit != null) {
    final InkPlacement? placement = resolveEventAnchor(
      page,
      EventAnchor(sectionId: hit.sectionId, bar: hit.barIndex),
    );
    if (placement != null) {
      return InkAnchorChoice(placement: placement, basis: InkAnchorBasis.bar);
    }
  }
  final InkPlacement? nearest = resolveNearestBarAnchor(page, pagePoint);
  if (nearest == null) {
    return null;
  }
  return InkAnchorChoice(
    placement: nearest,
    basis: InkAnchorBasis.nearestBar,
    distancePx: inkRectDistance(nearest.bounds, pagePoint),
  );
}

// PURPOSE: Turn a stored point into the position it occupies on the page, which is what the
//          renderer needs and what a musician's eye checks. Doing it as one translation is the
//          whole payoff of the anchor-local form: there is no rotation, no scale and no fit in it,
//          because every one of those was divided out at capture time.
// INPUTS: point — the stored `(x, y, w, t)`. origin — the anchor's top-left corner on the page.
// OUTPUTS: The page position of the point. The pressure and the timestamp are untouched, because
//          they are not geometry and translating them would be meaningless.
// KEYWORDS: ink-point, page-position, translation, anchor-local, pressure-preserved
/// Returns [point] translated onto the page by [origin].
LayoutOffset inkPointToPage(InkPoint point, LayoutOffset origin) =>
    LayoutOffset(origin.x + point.x, origin.y + point.y);

// PURPOSE: Turn a page position into an anchor-local coordinate, the inverse of [inkPointToPage].
//          This is the direction capture runs in, and it is the ONLY place that subtraction happens:
//          a second copy of it is how a stroke and its own hit test start to disagree.
// INPUTS: pagePoint — a position in the page's engraved coordinates. origin — the anchor's
//         top-left corner on the page.
// OUTPUTS: The same position measured from the anchor's origin.
// KEYWORDS: ink-capture, anchor-local, translation, inverse, single-source
/// Returns [pagePoint] measured from [origin].
LayoutOffset pagePointToAnchorLocal(
  LayoutOffset pagePoint,
  LayoutOffset origin,
) => LayoutOffset(pagePoint.x - origin.x, pagePoint.y - origin.y);

// NOTE ON THE SURFACE-TO-PAGE TRANSFORM, WHICH IS DELIBERATELY ABSENT FROM THIS FILE.
//
// There was once a function here, `inkSurfaceToPage(surfacePoint, scale)`, that multiplied the
// surface point by the page scale and called itself the inverse of `PageLayout.pagePointOf`. That
// comment was FALSE — `pagePointOf` DIVIDES by the scale — and the code that believed it anchored a
// stroke to the cell at `surfacePoint * scale²` on a fitted page, some ten engraved pixels from the
// nib that drew it. A second transform for one relationship is the defect; a comment asserting the
// two agree is what let it survive review.
//
// The transform exists in exactly one place: [PageLayout.pagePointOf], which removes the pan,
// divides by the zoom and divides by the page scale — all three being the inverse of the one
// transform the renderers apply (see `PageLayout` itself for why the musician's view lives on the
// page rather than beside it). Capture (see `InkStrokeAssembler`), the page hit test
// (`hitTestPage`) and the eraser (`hitTestInkErase`) all call it, and each painter is its inverse
// through `canvas.translate(pan)` + `canvas.scale(drawnScale)`. Do not add a helper beside this
// one: route the caller to the layout instead. The one direction this file does own is the
// translation between the page and the anchor's own corner, above and in [inkPointToPage], because
// that is a subtraction and not a scale.
