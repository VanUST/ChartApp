// PURPOSE: Draw the divisions the document HOLDS — the bar boundaries the application recognised
//          in the musician's handwriting, or that he placed himself — as IDEAL vertical lines on the
//          page, and draw them from the structure rather than from the ink, because the owner's rule
//          is that a recognised boundary is turned into a structured unit and displayed as an ideal
//          vertical line.
//
//          WHY THIS IS A PAINTER OF ITS OWN. `ChartPainter` draws the engraved chart, which is the
//          same for every reader of a tune; `InkPainter` draws one person's handwriting in the
//          coordinates it was captured in. A division is neither: it is structure the application
//          derived from that person's ink, and it has to be drawable without the ink layer, without
//          the engraver and at a different rate from either — the display rule in D37 switches
//          between the two, and a switch that had to rebuild the page would not be one.
//
//          WHAT TELLS A MUSICIAN A LINE WAS RECOGNISED. Three things, and all three are visible:
//          the line is STRAIGHT (his hand is not), it is the chart's own line weight and colour
//          rather than his nib, and the handwriting it came from is not drawn at all while
//          recognition is on. Nothing here has to be explained in words, and nothing here can be
//          mistaken for a mark he made, which is what D37's display rule requires.
// INPUTS: The document's divisions, each resolved to the page position of its anchor; the page's
//         own scale; the musician's zoom and pan — the same three numbers `ChartPainter` and
//         `InkPainter` are given, because a layer that used a different transform would slide the
//         line off the bar it divides.
// OUTPUTS: [paint] writes into the canvas and returns nothing. A division whose anchor this page
//          cannot place is simply not in the list the caller builds; this painter has no third
//          state. An empty list paints nothing and does not touch the canvas.
// KEYWORDS: bar-division, ideal-line, structural-layer, renderer, d37, display-rule,
//           anchor-local, page-scale, view-zoom, view-pan
import 'package:chart_core/chart_core.dart';
import 'package:flutter/rendering.dart';

/// A stored division placed at the page position of its anchor.
///
/// The division's own offsets are NOT copied or transformed: they are anchor-local logical pixels,
/// and the anchor's origin is the only thing the painter needs to add. That is the same contract
/// `ResolvedInkStroke` carries, so a division and the stroke it came from are placed by the same
/// arithmetic and cannot drift apart on a fitted page.
class ResolvedDivision {
  /// Places [division] at [origin], the anchor's top-left corner in page coordinates.
  const ResolvedDivision({required this.division, required this.origin});

  /// The division, whose offsets are anchor-local.
  final BarDivision division;

  /// The anchor's top-left corner on the page, in the page's engraved coordinates.
  final LayoutOffset origin;

  @override
  String toString() =>
      'ResolvedDivision(${division.id} at '
      '${origin.x.toStringAsFixed(1)},${origin.y.toStringAsFixed(1)})';
}

/// Draws the divisions of one page as ideal vertical lines.
class BarlinePainter extends CustomPainter {
  /// Creates a painter for the divisions that belong on one page.
  ///
  /// [lineColor] and [lineWidth] default to the engraved chart's own, because an ideal division is
  /// structure and must look like the structure around it rather than like a second kind of ink.
  const BarlinePainter({
    required this.divisions,
    required this.pageScale,
    this.pageZoom = 1,
    this.pagePan = LayoutOffset.zero,
    this.lineColor = const Color(0xFF102A43),
    this.lineWidth = 2,
  });

  /// The divisions to draw, each carrying the page position of its anchor.
  final List<ResolvedDivision> divisions;

  /// The page's own scale, applied exactly as `ChartPainter` applies it.
  final double pageScale;

  /// The musician's magnification, applied exactly as `ChartPainter` applies it.
  final double pageZoom;

  /// The musician's pan in surface logical pixels, applied exactly as `ChartPainter` applies it.
  final LayoutOffset pagePan;

  /// The colour of an ideal division.
  final Color lineColor;

  /// The width of an ideal division in the page's own coordinates.
  final double lineWidth;

  // PURPOSE: Draw one straight, evenly weighted line per division, at the place the structure says.
  // INPUTS: canvas — the target. size — the extent the painter was given, used only as the clip.
  // OUTPUTS: Nothing. The canvas is saved and restored around the clip, so stacking this over the
  //          chart painter and under the ink painter leaves their transforms untouched.
  //
  //          THE LINE IS NOT DRAWN FROM THE INK. Its x is the division's own anchor-local offset
  //          and its extent is the division's own height, both rounded by nothing: an ideal line is
  //          the whole point, and re-deriving either from the stroke would make the structure a
  //          second copy of the handwriting.
  // KEYWORDS: paint, ideal-line, clip, save-restore, transform, no-ink-re-derivation
  @override
  void paint(Canvas canvas, Size size) {
    if (divisions.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (pagePan != LayoutOffset.zero) {
      canvas.translate(pagePan.x, pagePan.y);
    }
    final double drawn = pageScale * pageZoom;
    if (drawn != 1) {
      canvas.scale(drawn, drawn);
    }
    final Paint stroke = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      // SQUARE CAPS, so the line ends where the musician's did instead of growing half a nib past
      // it. A division recognised from a short stroke must not become taller than the stroke.
      ..strokeCap = StrokeCap.butt;
    for (final ResolvedDivision resolved in divisions) {
      final BarDivision division = resolved.division;
      final double x = resolved.origin.x + division.place.offsetX;
      final double top = resolved.origin.y + division.top;
      final double bottom = resolved.origin.y + division.bottom;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), stroke);
    }
    canvas.restore();
  }

  // PURPOSE: Repaint when, and only when, something that changes the picture changed.
  // INPUTS: oldDelegate — the painter the last frame used.
  // OUTPUTS: True when the list identity, a division's value, the scale, the zoom, the pan, the
  //          colour or the width differ. List identity is compared before contents because the
  //          document rebuilds the list only when a division event landed, and comparing a hundred
  //          divisions per frame to learn that nothing changed is work the pen pays for.
  // KEYWORDS: should-repaint, list-identity, value-equality, frame-cost
  @override
  bool shouldRepaint(BarlinePainter oldDelegate) {
    if (!identical(oldDelegate.divisions, divisions) ||
        oldDelegate.pageScale != pageScale ||
        oldDelegate.pageZoom != pageZoom ||
        oldDelegate.pagePan != pagePan ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.lineWidth != lineWidth) {
      return true;
    }
    if (oldDelegate.divisions.length != divisions.length) {
      return true;
    }
    for (int index = 0; index < divisions.length; index++) {
      if (oldDelegate.divisions[index] != divisions[index]) {
        return true;
      }
    }
    return false;
  }
}
