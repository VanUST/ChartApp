// PURPOSE: Draw one laid-out page of a chart so that a reader can be compared against the
//          application a file came from. That comparison is the whole job of this renderer: it is
//          a READING renderer, not a finished engraver, and it favours showing every symbol the
//          model carries over matching iReal Pro's spacing or glyph shapes.
// INPUTS: song — the model the page was laid out from. It is needed because [PageLayout] carries
//         addresses (`sectionId`, `barIndex`) rather than the bars themselves, and the barlines,
//         repeat marks and voltas live on the [Bar]. Staff text is the exception: the layout
//         publishes its display form and measured box on [PlacedBar], so the painter draws those
//         and never reads `Bar.staffText`. page — the [PageLayout] to draw.
//         metrics — the same [FlutterTextMetrics] the layout was measured with, so drawn text
//         lands in the box the engine reserved. selection — the bar and cell a musician touched, or
//         null; it is what makes an interaction visible rather than only logged.
// OUTPUTS: [paint] writes into the canvas and returns nothing. A page whose bars cannot be
//          resolved against the song still draws its barlines, so a missing bar is visible as an
//          empty measure rather than as a gap.
// KEYWORDS: chart-renderer, custom-painter, barline, repeat, volta, chord-symbol, reader
//
// WHAT IS DELIBERATELY A GLYPH AND NOT A DRAWING. Where a music font would supply a shaped symbol
// — the repeat-previous sign, the slash repeat, the segno, the coda, the fermata, the player's
// ending, the volta figure — this renderer draws a readable stand-in instead, because shipping a
// font is a dependency this package does not take. The mapping is fixed and documented here so a
// reader is never guessing what a mark means:
//
//     repeat previous one bar   `%`
//     repeat previous two bars  `2%`
//     slash repeat              `/`
//     no chord                  `N.C.`
//     volta                     `[1.` and `[2.`, or `[` for the unnumbered bracket
//     meter                     the model's own `M/N` — `3/4`, `15/8` — at the bar where it changes
//                               and at the start of a system that is not in 4/4 (see
//                               `chart_core`'s `showsMeterSign`, which decides it)
//     key and opening meter     the header line above the first system, `C major · 4/4`, drawn in
//                               the chord's own ink because it is notation rather than a heading
//     segno `S` · coda `C` · fermata `^` · player ending `End`
//
// Barlines ARE drawn as lines, because the model names them exactly (single, double, repeat start,
// repeat end, final) and lines carry that distinction without a font.

import 'package:chart_core/chart_core.dart';
import 'package:flutter/rendering.dart';

import 'flutter_text_metrics.dart';

/// Draws one [PageLayout] of [song] onto a canvas.
class ChartPainter extends CustomPainter {
  /// Creates a painter for one page.
  ///
  /// [metrics] must be the instance the layout was measured with; see the file header.
  /// [selection] is the bar the musician has touched, or null when nothing is selected; the painter
  /// draws the highlight, and it is the only thing on the page that says "you are here" without a
  /// word.
  const ChartPainter({
    required this.song,
    required this.page,
    required this.metrics,
    this.selection,
    this.lineColor = const Color(0xFF102A43),
    this.backgroundColor = const Color(0xFFFFFFFF),
  });

  /// The model the page was laid out from, read for the signs [PageLayout] does not carry.
  final Song song;

  /// The page to draw.
  final PageLayout page;

  /// The metrics the layout was measured with, reused so text lands in its reserved box.
  final FlutterTextMetrics metrics;

  /// The bar and cell to highlight, or null when nothing is selected.
  ///
  /// The hit is matched by ADDRESS — section id, bar index and beat — and not by object identity,
  /// because the viewer holds the hit from the tap while a rebuild may have produced a fresh
  /// layout with equal values. Matching the address is what lets a highlight survive a rebuild,
  /// a transposition or a page mode change without being re-derived.
  final ChartHit? selection;

  /// Colour of barlines, repeat dots and text.
  final Color lineColor;

  /// Colour the page is filled with before anything is drawn.
  final Color backgroundColor;
  // PURPOSE: Draw the page: section labels, then each bar's rectangle and barlines, then the
  //          highlight on the bar the musician touched.
  // INPUTS: canvas — the target. size — the extent the painter was given, which is the page's own
  //         size when the viewer sizes the widget to the layout.
  // OUTPUTS: Nothing. Everything is drawn clipped to `size`, so a system the engine deliberately
  //          let overflow the page edge cannot bleed into the neighbouring page of a PageView. The
  //          canvas is scaled by [PageLayout.drawnScale] before the geometry is drawn and panned by
  //          [PageLayout.pan], which is what lets the same painter draw an ordinary page, a page the
  //          FIT mode shrank, and either of those under the musician's own zoom and pan.
  // KEYWORDS: paint, clipping, section-label, reading-order, view-zoom, view-pan, chart-header
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // The page's geometry is in engraved coordinates. FIT produces a page engraved at a larger
    // virtual size and records the factor that brings it back onto this surface, so one scale here
    // keeps every rectangle, hit test and annotation anchor in a single coordinate system.
    //
    // THE VIEW GOES ON FIRST, and it is the same transform `PageLayout.pagePointOf` inverts: the
    // musician's pan is a translate, the musician's zoom multiplies the page's own scale, and the
    // two together are `drawnScale`. It is applied HERE, in the chart painter, and not as a
    // `Transform` widget around the stack, because the clip above must stay in surface coordinates
    // — a zoomed page has to keep being clipped to the pane it is drawn in.
    if (page.pan != LayoutOffset.zero) {
      canvas.translate(page.pan.x, page.pan.y);
    }
    final double scale = page.drawnScale;
    if (scale != 1) {
      canvas.scale(scale, scale);
    }
    // The chart's own opening statement is gone with the header; the page now begins with the
    // first system's section letter.
    for (final PlacedSystem system in page.systems) {
      _paintSectionLabel(canvas, system);
      for (int index = 0; index < system.bars.length; index++) {
        _paintBar(canvas, system.bars[index], firstInSystem: index == 0);
      }
    }
    canvas.restore();
  }

  // PURPOSE: State on the page, before any music, what key and meter the chart is written in — the
  //          one thing a musician holding the chart at a stand could not see, because the key lived
  //          in the scene bar and the meter appeared only on a bar that changed it.
  // INPUTS: canvas — the target.
  // OUTPUTS: Nothing. Draws the published words in the band the layout reserved for them, or nothing
  //          at all on a page that carries no header, which is every page after the first.
  //
  //          IT IS DRAWN IN THE CHORD'S OWN STYLE AND INK, not in the section letter's. The key and
  //          the meter are NOTATION — they mean exactly what a chord symbol means, in the same
  //          language — while a section letter is a heading this application puts on a page. Two
  //          left-aligned lines one above the other must not read as one heading in two rows, and
  //          the ink does the distinguishing: the darkest ink for the notation, the blue of a
  //          heading for the heading. The band's height was measured in this same role, so the line
  //          the page gave up and the line drawn are the same number.
  // KEYWORDS: chart-header, key, meter, notation, draw-order, one-band, d27
  // PURPOSE: Report whether a new painter changes anything on screen.
  // INPUTS: oldDelegate — the painter this one replaces.
  // OUTPUTS: True when the page, the song, the metrics, the tapped bar or a colour differ.
  // KEYWORDS: should-repaint, value-comparison, cache
  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.song != song ||
      oldDelegate.metrics != metrics ||
      oldDelegate.selection != selection ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.backgroundColor != backgroundColor;

  // PURPOSE: Draw the section heading a system starts, in the band the engine reserved for it above
  //          the stave, so the heading is never drawn over a chord.
  // INPUTS: canvas — the target. system — the system whose label to draw.
  // OUTPUTS: Nothing when [PlacedSystem.sectionLabel] is null or its [PlacedSystem.labelBand] is
  //          absent. The band comes from the layout rather than from this painter's arithmetic, so
  //          the heading keeps its own room at the top of the system: a system's band above the
  //          stave also holds the cue rows of the bars on it, and a label centred in the whole band
  //          would be drawn among them, where a cue plate could cover the letter that names the
  //          section. On a system with no cue the band is exactly the label's own height, so the
  //          heading lands where it always did.
  // KEYWORDS: section-label, heading, published-band, cue-rows, geometry-derived, null-safe
  void _paintSectionLabel(Canvas canvas, PlacedSystem system) {
    final String? label = system.sectionLabel;
    final LayoutRect? band = system.labelBand;
    if (label == null || label.isEmpty || band == null) {
      return;
    }
    final Size textSize = _measureText(label, metrics.sectionLabelStyle);
    final double top = band.size.height > textSize.height
        ? band.top + (band.size.height - textSize.height) / 2
        : band.top;
    _paintText(
      canvas,
      label,
      Offset(band.left, top),
      metrics.sectionLabelStyle,
    );
  }

  // PURPOSE: Mark the bar and cell the musician touched, so a selection is visible on the page and
  //          not only stated beside it. The mark is drawn from the layout's own rectangles, which is
  //          what guarantees it lands exactly where the hit test said the touch was rather than a
  //          little to one side.
  // INPUTS: canvas — the target. placed — the bar being drawn, with the cells it owns.
  // OUTPUTS: Nothing. Draws for the one bar whose address matches [selection], and for the cell
  //          whose beat matches; a selection naming a bar on another page draws nothing here. When
  //          the selection names no cell — a touch in a bar's padding — the whole bar is marked,
  //          which is the honest picture of a bar-level selection. A beat the bar does not have
  //          falls back to the whole bar rather than drawing nothing, because a highlight that
  //          silently vanishes is indistinguishable from a tap that missed.
  // KEYWORDS: selection, highlight, address-match, cell, bar-level, visual-feedback
  void _paintSelection(Canvas canvas, PlacedBar placed) {
    final ChartHit? hit = selection;
    if (hit == null ||
        hit.sectionId != placed.sectionId ||
        hit.barIndex != placed.barIndex) {
      return;
    }
    // THE BAR IS THE REGION, and there is no cell to narrow it to any more. A hit names the bar and a
    // point inside it; the visible mark is the bar, because a highlight drawn around the point would
    // be a rectangle the layout never published, and one drawn from a beat column would vanish the
    // day the columns did (which is exactly how the selection became unreachable once already).
    final LayoutRect region = placed.bounds;
    final Rect rect = Rect.fromLTWH(
      region.left,
      region.top,
      region.size.width,
      region.size.height,
    );
    const Color fill = Color(0x2E2F80ED);
    const Color stroke = Color(0xFF2F80ED);
    canvas.drawRect(rect, Paint()..color = fill);
    // The outline is inset by half its own width so it sits inside the region. Drawn centred it
    // would straddle the cell's edge and tint the neighbouring cell, which is exactly the confusion
    // the label beside the chart exists to remove.
    const double strokeWidth = 2;
    canvas.drawRect(
      rect.deflate(strokeWidth / 2),
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  // PURPOSE: Draw one bar: its bounding barlines, the signs the bar carries, and its chords.
  // INPUTS: canvas — the target. placed — the bar and its rectangle. firstInSystem — whether this
  //         bar opens its system, which decides whether its opening barline needs drawing.
  // OUTPUTS: Nothing. A bar whose address does not resolve in the song still draws its bounding
  //          barlines, so the measure is visible as empty rather than as missing.
  // KEYWORDS: bar, barline, opening, closing, null-safe
  void _paintBar(
    Canvas canvas,
    PlacedBar placed, {
    required bool firstInSystem,
  }) {
    final Bar? bar = song.barAt(placed.sectionId, placed.barIndex);
    final LayoutRect bounds = placed.bounds;

    // The wash goes down first, under the barlines, so the bar the musician touched is marked
    // without hiding anything he is about to write in it.
    _paintSelection(canvas, placed);

    // An interior barline is shared: the previous bar's closing line already draws it. So the
    // opening barline is drawn when it opens the system, or when it is a SIGN rather than a plain
    // single line — a repeat start in the middle of a system must not be dropped.
    final Barline opening = bar?.openingBarline ?? Barline.single;
    if (firstInSystem || opening != Barline.single) {
      _paintLeftBarline(
        canvas,
        bounds.left,
        bounds.top,
        bounds.bottom,
        opening,
      );
    }
    _paintRightBarline(
      canvas,
      bounds.right,
      bounds.top,
      bounds.bottom,
      bar?.closingBarline ?? Barline.single,
    );
  }

  // PURPOSE: Draw a bar's left boundary as the line or sign the model names.
  // INPUTS: canvas — the target. x — the bar's left edge. top and bottom — the stave's extent.
  //         line — the opening barline.
  // OUTPUTS: Nothing. A repeat start is drawn as a thin line, a thick line and two dots to the
  //          right of them, which is the reading direction of `|:`.
  // KEYWORDS: barline, left, repeat-start, double, final, drawing
  void _paintLeftBarline(
    Canvas canvas,
    double x,
    double top,
    double bottom,
    Barline line,
  ) {
    switch (line) {
      case Barline.single:
        _line(canvas, x, top, bottom, _thin);
      case Barline.double:
        _line(canvas, x, top, bottom, _thin);
        _line(canvas, x + 3, top, bottom, _thin);
      case Barline.repeatStart:
        _line(canvas, x, top, bottom, _thin);
        _line(canvas, x + 1.5, top, bottom, _thick);
        _paintRepeatDots(canvas, x + 9, top, bottom);
      case Barline.repeatEnd:
        _line(canvas, x + 1.5, top, bottom, _thick);
        _line(canvas, x + 6, top, bottom, _thin);
        _paintRepeatDots(canvas, x + 12, top, bottom);
      case Barline.finalBar:
        _line(canvas, x + 1.5, top, bottom, _thick);
        _line(canvas, x + 5, top, bottom, _thin);
    }
  }

  // PURPOSE: Draw a bar's right boundary as the line or sign the model names.
  // INPUTS: canvas — the target. x — the bar's right edge. top and bottom — the stave's extent.
  //         line — the closing barline.
  // OUTPUTS: Nothing. A repeat end is drawn as two dots, a thin line and a thick line, which is
  //          `:|` read from inside the repeated passage outward.
  // KEYWORDS: barline, right, repeat-end, double, final, drawing
  void _paintRightBarline(
    Canvas canvas,
    double x,
    double top,
    double bottom,
    Barline line,
  ) {
    switch (line) {
      case Barline.single:
        _line(canvas, x, top, bottom, _thin);
      case Barline.double:
        _line(canvas, x, top, bottom, _thin);
        _line(canvas, x - 3, top, bottom, _thin);
      case Barline.repeatStart:
        _line(canvas, x - 1.5, top, bottom, _thick);
        _line(canvas, x - 6, top, bottom, _thin);
        _paintRepeatDots(canvas, x - 12, top, bottom);
      case Barline.repeatEnd:
        _line(canvas, x - 1.5, top, bottom, _thick);
        _line(canvas, x - 6, top, bottom, _thin);
        _paintRepeatDots(canvas, x - 12, top, bottom);
      case Barline.finalBar:
        _line(canvas, x - 1.5, top, bottom, _thick);
        _line(canvas, x - 5, top, bottom, _thin);
    }
  }

  // PURPOSE: Draw the two dots of a repeat sign, which are what distinguishes it from a double
  //          barline at a glance.
  // INPUTS: canvas — the target. x — the dots' centre line. top and bottom — the stave's extent.
  // OUTPUTS: Nothing. The dots sit a third and two thirds down the stave, so they read the same on
  //          a tall bar and a short one.
  // KEYWORDS: repeat, dots, circle, drawing
  void _paintRepeatDots(Canvas canvas, double x, double top, double bottom) {
    final double height = bottom - top;
    canvas.drawCircle(Offset(x, top + height / 3), 1.6, _thin);
    canvas.drawCircle(Offset(x, top + 2 * height / 3), 1.6, _thin);
  }

  // PURPOSE: Draw a vertical line with one of the two stroke weights the barlines use, keeping the
  //          weight choice out of the geometry.
  // INPUTS: canvas — the target. x — the line's position. top and bottom — its extent. paint — a
  //         paint whose stroke width is the weight.
  // OUTPUTS: Nothing. A zero-height stave still draws a dot-length line rather than throwing.
  // KEYWORDS: line, stroke, drawing, primitive
  void _line(Canvas canvas, double x, double top, double bottom, Paint paint) {
    canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
  }

  // PURPOSE: Report the box a string occupies in a style, so a caller can align it before it is
  //          drawn.
  // INPUTS: text — the string; may be empty. style — the style.
  // OUTPUTS: The painted size. An empty string returns Size.zero, which makes every alignment
  //          arithmetic below a no-op rather than a division by an unmeasured value.
  // KEYWORDS: measure, text-painter, size, empty-string
  Size _measureText(String text, TextStyle style) {
    if (text.isEmpty) {
      return Size.zero;
    }
    final TextPainter painter = _painterFor(text, style)..layout();
    final Size size = Size(painter.width, painter.height);
    painter.dispose();
    return size;
  }

  // PURPOSE: Paint a string at a top-left position.
  // INPUTS: canvas — the target. text — the string; may be empty. topLeft — where its box starts.
  //         style — the style.
  // OUTPUTS: Nothing. An empty string paints nothing, and the painter is always disposed so a
  //          redraw does not leak the paragraph it built.
  // KEYWORDS: paint, text, top-left, dispose
  void _paintText(Canvas canvas, String text, Offset topLeft, TextStyle style) {
    if (text.isEmpty) {
      return;
    }
    final TextPainter painter = _painterFor(text, style)..layout();
    painter.paint(canvas, topLeft);
    painter.dispose();
  }

  // PURPOSE: Build the one painter configuration every text draw uses, so measurement and painting
  //          cannot disagree about direction or line count.
  // INPUTS: text — the string. style — the style.
  // OUTPUTS: A laid-out-ready [TextPainter]; the caller owns it and must dispose it.
  // KEYWORDS: text-painter, factory, left-to-right, single-line
  TextPainter _painterFor(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );

  /// The stroke used for thin barlines; a getter rather than a field so the color follows the
  /// painter's own [lineColor].
  Paint get _thin => Paint()
    ..color = lineColor
    ..strokeWidth = 1;

  /// The stroke used for the thick half of a repeat or final barline.
  Paint get _thick => Paint()
    ..color = lineColor
    ..strokeWidth = 3;
}
