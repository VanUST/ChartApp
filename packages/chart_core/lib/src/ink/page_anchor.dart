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
// INPUTS: A [PageLayout], an [EventAnchor], and positions in page or surface logical pixels.
// OUTPUTS: Immutable values and total functions. A resolution that cannot find the anchor on the
//          page returns null rather than a guessed rectangle, because a stroke drawn at a fabricated
//          position is worse than one that is visibly missing: it would look correct on screen and
//          be anchored to nothing.
// KEYWORDS: ink, anchor-local, coordinate-transform, fit-scale, page-transform, transposition,
//           reflow-survival, pure-dart
import 'package:chart_core/src/layout/geometry.dart';
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
  static String keyOf(EventAnchor anchor) =>
      '${anchor.sectionId}\u0000${anchor.bar}\u0000'
      '${anchor.beat ?? -1}\u0000${anchor.step}';

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

  /// Builds the index for every cell and every bar of [page].
  ///
  /// Cells are indexed first and a bar is only added for an address no cell claimed, so a lookup
  /// can never return the whole bar where a cell exists — the bar and its cells overlap, and the
  /// narrower rectangle is the one a stroke is anchored to.
  factory InkPageIndex.ofPage(PageLayout page) {
    final Map<String, InkPlacement> placements = <String, InkPlacement>{};
    for (final PlacedBar bar in page.bars) {
      for (final PlacedCell cell in bar.cells) {
        final InkPlacement placement = InkPlacement(
          anchor: EventAnchor(
            sectionId: bar.sectionId,
            bar: bar.barIndex,
            beat: cell.beat,
          ),
          pageIndex: page.index,
          bounds: cell.bounds,
        );
        placements[placement.key] = placement;
      }
    }
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
//          the cell it was drawn in rather than to the page corner. This is the lookup that must
//          succeed for a stroke to appear at all, and it is deliberately a page-level search rather
//          than a stored rectangle: the rectangle stored at capture time would be stale after a
//          transposition moved the bar half a millimetre.
// INPUTS: page — the layout to resolve against. anchor — the address the stroke carries.
// OUTPUTS: The [InkPlacement], or null when the page has no bar or cell at that address. Null is a
//          real answer and not a failure: an anchor may name a bar on another page of a paginated
//          document, and the caller drawing one page must simply not draw that stroke here.
// KEYWORDS: anchor-resolution, placement, lookup, null-when-absent, page-coordinates
/// Returns the placement of [anchor] on [page], or null when the page does not hold it.
InkPlacement? resolveEventAnchor(PageLayout page, EventAnchor anchor) {
  for (final PlacedBar bar in page.bars) {
    if (bar.sectionId != anchor.sectionId || bar.barIndex != anchor.bar) {
      continue;
    }
    final int? beat = anchor.beat;
    if (beat == null) {
      return InkPlacement(
        anchor: anchor,
        pageIndex: page.index,
        bounds: bar.bounds,
      );
    }
    for (final PlacedCell cell in bar.cells) {
      if (cell.beat == beat) {
        return InkPlacement(
          anchor: anchor,
          pageIndex: page.index,
          bounds: cell.bounds,
        );
      }
    }
    // The bar is here and the cell is not: the bar has fewer cells than the meter the anchor was
    // written against, which a hand-edited anchor can produce. Falling back to the bar keeps the
    // stroke visible and on the right bar rather than dropping it.
    return InkPlacement(
      anchor: anchor,
      pageIndex: page.index,
      bounds: bar.bounds,
    );
  }
  return null;
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
// The transform exists in exactly one place: [PageLayout.pagePointOf], which divides. Capture (see
// `InkStrokeAssembler`), the page hit test (`hitTestPage`) and the eraser (`hitTestInkErase`) all
// call it, and the painter is its inverse through `canvas.scale(pageScale, pageScale)`. Do not add a
// helper beside this one: route the caller to the layout instead. The one direction this file does
// own is the translation between the page and the anchor's own corner, above and in
// [inkPointToPage], because that is a subtraction and not a scale.
