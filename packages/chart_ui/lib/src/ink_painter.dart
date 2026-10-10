// PURPOSE: Draw the committed handwritten strokes of one page on top of the music, so that a mark
//          the musician made with a pen is visible where they put it. It is a separate painter from
//          `ChartPainter` on purpose: the chart painter's job is engraved notation, which is
//          identical for every reader of a tune, while a stroke belongs to one person and one
//          moment. Keeping them apart means the ink can be added, cleared or drawn at a different
//          rate without touching a line of the engraver, and it is what makes the ink layer
//          testable as a painter in its own right.
//
//          WHY THE STROKE IS DRAWN FROM ITS ANCHOR AND NOT FROM ITS CAPTURE POSITION. A stroke is
//          stored in anchor-local logical pixels — see `packages/chart_core/lib/src/oplog/ink.dart`
//          — so drawing it at a stored coordinate is only correct for the layout that was current
//          when it was captured. Adding the resolved anchor's origin, and then the page's own scale
//          exactly as the chart painter applies it, is what makes the same stroke land on the same
//          musical position when the page is FITTED, when the key is transposed and after the file
//          has been saved and read back.
// INPUTS: A list of [ResolvedInkStroke], each already carrying the page position of its anchor; the
//         page's scale; and the colours the two tools draw with.
// OUTPUTS: [paint] writes into the canvas and returns nothing. A stroke drawn beneath the page's
//          clip is clipped away rather than bleeding into a neighbouring page of a `PageView`.
// KEYWORDS: ink-renderer, custom-painter, anchor-local, page-scale, pressure, highlighter, pen,
//           render-order
import 'package:chart_core/chart_core.dart';
import 'package:flutter/rendering.dart';

// PURPOSE: Carry one stroke together with the page position of its anchor, which is the pair a
//          renderer needs and the pair the capture side has just computed. It exists so that the
//          painter never has to search a layout for an anchor mid-frame: the search happens once
//          per rebuild, in one place, and its result is this value.
// INPUTS: The stored stroke and the anchor's top-left corner in the page's engraved coordinates.
// OUTPUTS: An immutable value. The stroke's own points are NOT copied or transformed, so a page that
//          cannot resolve the anchor is the only way a stroke is absent — there is no third state.
// KEYWORDS: resolved-stroke, anchor-origin, page-coordinates, render-input, immutable
/// A stored stroke placed at the anchor's position on a page.
class ResolvedInkStroke {
  /// Creates a resolved stroke for [stroke] whose anchor sits at [origin].
  const ResolvedInkStroke({required this.stroke, required this.origin});

  /// The canonical stroke, whose points are anchor-local logical pixels.
  final InkStroke stroke;

  /// The anchor's top-left corner on the page, in the page's engraved coordinates.
  final LayoutOffset origin;

  @override
  String toString() =>
      'ResolvedInkStroke(${stroke.id} at ${origin.x.toStringAsFixed(1)},'
      '${origin.y.toStringAsFixed(1)})';
}

/// Draws handwritten strokes over one laid-out page.
class InkPainter extends CustomPainter {
  /// Creates a painter for the strokes that belong on one page.
  ///
  /// [pageScale] must be the same `PageLayout.scale` the `ChartPainter` drawing this page was given,
  /// because the two layers are positioned by the same transform and a mismatch would slide the ink
  /// off the music by an amount proportional to the distance from the page's corner — the failure
  /// that looks plausible in the middle of a page and obviously wrong at its edge.
  const InkPainter({
    required this.strokes,
    required this.pageScale,
    this.penColor = const Color(0xFF102A43),
    this.highlighterColor = const Color(0x66FFC857),
  });

  /// The strokes to draw, in render order: later entries lie on top, as they do in the document.
  final List<ResolvedInkStroke> strokes;

  /// The page's own scale, applied exactly as `ChartPainter` applies it.
  final double pageScale;

  /// The colour a pen stroke is drawn in when the stroke itself names none.
  final Color penColor;

  /// The colour a highlighter stroke is drawn in when the stroke itself names none.
  final Color highlighterColor;

  // PURPOSE: Draw every stroke at its anchor, in the document's own order, so that the ink on screen
  //          is the ink in the file rather than a re-derivation of it.
  // INPUTS: canvas — the target. size — the extent the painter was given, used only as the clip.
  // OUTPUTS: Nothing. The canvas is saved and restored around the clip, so a caller stacking this
  //          painter over the chart painter gets its transform back unchanged.
  // KEYWORDS: paint, clip, render-order, save-restore, transform
  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (pageScale != 1) {
      canvas.scale(pageScale, pageScale);
    }
    for (final ResolvedInkStroke resolved in strokes) {
      _paintStroke(canvas, resolved);
    }
    canvas.restore();
  }

  // PURPOSE: Draw one stroke, as a sequence of round-capped segments whose widths follow the
  //          pressure recorded with each point.
  // INPUTS: canvas — the target. resolved — the stroke and the page position of its anchor.
  // OUTPUTS: Nothing. A stroke with no points draws nothing; a one-point stroke draws a dot, because
  //          its stored form repeats the point and a zero-length segment with a round cap is a dot.
  //
  //          WHY SEGMENTS AND NOT ONE PATH. A single path would force one width for the whole stroke,
  //          and a musician's line thickens and thins with the hand: the pressure axis of the stored
  //          point exists for exactly this and would otherwise be carried through capture, storage
  //          and the file without ever being used. Per-segment width is the cheapest honest way to
  //          spend it, and the overlap at a joint is invisible because the caps are round and the
  //          width change between neighbouring samples is small.
  // KEYWORDS: segment, pressure-width, round-cap, nib, dot, tilt-not-used
  void _paintStroke(Canvas canvas, ResolvedInkStroke resolved) {
    final InkStroke stroke = resolved.stroke;
    final List<InkPoint> points = stroke.points;
    if (points.isEmpty) {
      return;
    }
    final bool isHighlighter = stroke.tool == StrokeTool.highlighter;
    final Color color = _colorOf(stroke, isHighlighter: isHighlighter);
    final double nib = stroke.size <= 0
        ? (isHighlighter ? 18 : 3)
        : stroke.size;
    final LayoutOffset origin = resolved.origin;

    if (points.length == 1) {
      canvas.drawCircle(
        Offset(origin.x + points.first.x, origin.y + points.first.y),
        nib / 2,
        Paint()..color = color,
      );
      return;
    }
    for (int index = 1; index < points.length; index++) {
      final InkPoint from = points[index - 1];
      final InkPoint to = points[index];
      final double pressure = (from.w + to.w) / 2;
      final double width = isHighlighter ? nib : nib * (0.65 + 0.7 * pressure);
      final Paint paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawLine(
        Offset(origin.x + from.x, origin.y + from.y),
        Offset(origin.x + to.x, origin.y + to.y),
        paint,
      );
    }
  }

  // PURPOSE: Resolve a stroke's colour string into a colour, so a stroke written to a file by another
  //          build — or by hand — draws with its own colour rather than making the whole layer fail.
  // INPUTS: stroke — the stroke, whose `color` is a `#rrggbb` or `#rrggbbaa` string. isHighlighter —
  //         which default to fall back to.
  // OUTPUTS: The parsed colour, or the tool's default when the string is empty or malformed. A
  //          fallback rather than a throw, because a colour nobody can read must not cost the
  //          musician the whole drawing.
  // KEYWORDS: colour-parse, hex-rgb, fallback, no-throw
  Color _colorOf(InkStroke stroke, {required bool isHighlighter}) {
    final String hex = stroke.color;
    if (hex.isEmpty) {
      return isHighlighter ? highlighterColor : penColor;
    }
    final String digits = hex.startsWith('#') ? hex.substring(1) : hex;
    final int? value = int.tryParse(digits, radix: 16);
    if (value == null) {
      return isHighlighter ? highlighterColor : penColor;
    }
    // A six-digit string is opaque; an eight-digit one carries its own alpha, which the document's
    // own `#rrggbbaa` form uses.
    return digits.length <= 6 ? Color(0xFF000000 | value) : Color(value);
  }

  // PURPOSE: Report whether a new painter changes anything on screen, so a stroke committed to the
  //          document repaints the layer.
  // INPUTS: oldDelegate — the painter this one replaces.
  // OUTPUTS: True when the stroke list, the page scale or either default colour differs. The list is
  //          compared element by element because `List` has no value equality, and comparing
  //          identity would miss a freshly built list holding the same strokes — which is the
  //          ordinary case after a rebuild.
  // KEYWORDS: should-repaint, element-comparison, rebuild, value-comparison
  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) =>
      oldDelegate.pageScale != pageScale ||
      oldDelegate.penColor != penColor ||
      oldDelegate.highlighterColor != highlighterColor ||
      !_sameStrokes(oldDelegate.strokes, strokes);

  /// Whether two resolved-stroke lists hold equal elements in the same order.
  static bool _sameStrokes(
    List<ResolvedInkStroke> left,
    List<ResolvedInkStroke> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index++) {
      final ResolvedInkStroke a = left[index];
      final ResolvedInkStroke b = right[index];
      if (a.origin != b.origin || a.stroke != b.stroke) {
        return false;
      }
    }
    return true;
  }
}

/// The `Path` a stroke would draw as one outline, for a caller that wants the shape rather than the
/// painted segments — a hit test on ink, or a future export.
///
/// Not used by [InkPainter], which draws segments so it can vary the width with pressure. Kept here
/// beside that decision so the two cannot drift into disagreement about where a stroke begins.
Path inkStrokePath(ResolvedInkStroke resolved) {
  final Path path = Path();
  final List<InkPoint> points = resolved.stroke.points;
  if (points.isEmpty) {
    return path;
  }
  final LayoutOffset origin = resolved.origin;
  path.moveTo(origin.x + points.first.x, origin.y + points.first.y);
  for (int index = 1; index < points.length; index++) {
    path.lineTo(origin.x + points[index].x, origin.y + points[index].y);
  }
  return path;
}
