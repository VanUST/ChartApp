// PURPOSE: Draw one laid-out page of a chart so that a musician reading a part at a stand can find
//          the bars, the sections, the repeats and the chords without looking away from the music.
//          That comparison against the application a file came from is the whole job of this
//          renderer: it is a READING renderer, not a finished engraver, and it favours showing every
//          symbol the model carries over matching iReal Pro's spacing or glyph shapes.
// INPUTS: song — the model the page was laid out from. It is needed because [PageLayout] carries
//         addresses (`sectionId`, `barIndex`) rather than the bars themselves, and the barlines,
//         repeats and voltas live on the [Bar]. Everything with WORDS or a BOX is the layout's
//         exception and not this painter's work: the chords, the signs, the staff text and the
//         alternative-ending brackets all arrive on [PageLayout] already rendered and measured, so
//         the painter draws the string or fills the box it was handed and never spells a chord,
//         decides a position or measures a phrase itself. page — the [PageLayout] to draw, whose
//         `header` is the chart's opening key-and-meter line on the first page and null after it.
//         metrics — the same [FlutterTextMetrics] the layout was measured with, so drawn text
//         lands in the box the engine reserved. selection — the bar a musician touched, or
//         null; it is what makes an interaction visible rather than only logged.
// OUTPUTS: [paint] writes into the canvas and returns nothing. A page whose bars cannot be
//          resolved against the song still draws its barlines, so a missing bar is visible as an
//          empty measure rather than as a gap.
// KEYWORDS: chart-renderer, custom-painter, barline, repeat, volta, chord-symbol, simile, segno,
//           coda, fermata, staff-text, chart-header, meter-sign, reader
//
// WHAT THIS RENDERER DRAWS, AND WHY EACH THING IS HERE. The page is a chord chart read at a stand, so
// it draws what a musician has to find while playing: the chart's key and opening meter where its
// music begins; the section heading a system begins; the bars' barlines with the repeat signs their
// models name; the alternative-ending brackets, with their figures; the chord symbols written in each
// bar, at the beat the bar puts them on; and the marks a musician reads as instructions — the
// repeat-previous simile sign, the slash repeat, `N.C.`, the segno, the coda, the fermata, and the
// words the file wrote on the bar (`Solo`, `х4`, `проигрыш`).
//
// THE SIGNS THAT NEED A MUSIC GLYPH ARE DRAWN AS SHAPES, AND THAT IS THE ONE RULE THIS RENDERER KEEPS
// FROM THE MUSIC FONT IT NEVER HAD. There is no music font here and none is planned, so a segno could
// be approximated by an `S` and a coda by a `C` — and a letter a musician has to guess at is worse
// than nothing (A68), because `C` on a chart means a section, not a coda. So the simile sign, the
// slash, the segno, the coda and the fermata are DRAWN: a diagonal stroke with two dots, a slash, an
// S-curve cut by a stroke with a dot either side, a circled cross, an arc over a dot. They are the
// shapes an engraver cuts, they scale with the page, and none of them can be confused with a letter
// the chart wrote.
//
// A CHORD SYMBOL IS NOT SUCH A CASE: it is TEXT, written by the chart in the Latin letters and
// accidentals a chart uses (`F#h`, `A/C#`, `Cb`), so it is drawn exactly as it was written and
// nothing is substituted. Barlines ARE drawn as lines, because the model names them exactly (single,
// double, repeat start, repeat end, final) and lines carry that distinction without a font.
//
// NOTHING HERE IS A CONTROL. The page is a reading surface with no hit target on a symbol: the only
// thing drawn in response to the musician is the highlight on the bar a tap named, and it is drawn
// under the music so it does not hide anything.

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
  // PURPOSE: Draw the page: section labels, then each bar's barlines and the chord symbols written
  //          in it, then the highlight on the bar the musician touched.
  // INPUTS: canvas — the target. size — the extent the painter was given, which is the page's own
  //         size when the viewer sizes the widget to the layout.
  // OUTPUTS: Nothing. Everything is drawn clipped to `size`, so a system the engine deliberately
  //          let overflow the page edge cannot bleed into the neighbouring page of a PageView. The
  //          canvas is scaled by [PageLayout.drawnScale] before the geometry is drawn and panned by
  //          [PageLayout.pan], which is what lets the same painter draw an ordinary page, a page the
  //          FIT mode shrank, and either of those under the musician's own zoom and pan.
  // KEYWORDS: paint, clipping, section-label, chord-symbol, reading-order, view-zoom, view-pan
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
    // The chart's own opening statement: what key it is in and what meter its first bar counts.
    // Drawn before anything else, in the band the layout reserved in the page's top margin, so the
    // first thing a reader meets is what the music is written in.
    _paintChartHeader(canvas);
    for (final PlacedSystem system in page.systems) {
      _paintSectionLabel(canvas, system);
      for (final PlacedVolta volta in system.voltas) {
        _paintVolta(canvas, volta);
      }
      for (int index = 0; index < system.bars.length; index++) {
        _paintBar(canvas, system.bars[index], firstInSystem: index == 0);
      }
    }
    canvas.restore();
  }

  // PURPOSE: State on the page, before any music, what key the chart is in and what meter its music
  //          opens in — the two facts a musician holding the chart at a stand has to know before the
  //          first chord means anything, and the two the page could not tell him at all.
  // INPUTS: canvas — the target.
  // OUTPUTS: Nothing. Draws the published words at the top-left of the band the layout reserved for
  //          them, and draws nothing at all on a page with no header, which is every page after the
  //          first.
  //
  //          IT IS DRAWN IN THE CHORD'S OWN STYLE AND INK, not in the section letter's. The key and the
  //          meter are NOTATION — they mean exactly what a chord symbol means, in the same language —
  //          while a section letter is a heading this application puts on a page. Two left-aligned
  //          lines, one above the other, must not read as one heading in two rows, and the ink does
  //          the distinguishing: the darkest ink for the notation, the blue of a heading for the
  //          heading. The band's height was measured in this same role, so the line the page gave up
  //          and the line drawn are the same number.
  // KEYWORDS: chart-header, key, meter, notation, draw-order, one-band
  void _paintChartHeader(Canvas canvas) {
    final PlacedChartHeader? header = page.header;
    if (header == null) {
      return;
    }
    _paintText(
      canvas,
      header.text,
      Offset(header.bounds.left, header.bounds.top),
      metrics.chordStyle,
    );
  }

  // PURPOSE: Draw one alternative-ending bracket over the bars it covers, with its figure, so a
  //          musician can see which ending he is in and where it ends.
  // INPUTS: canvas — the target. volta — the run's horizontal span and the band reserved for it.
  // OUTPUTS: Nothing. Draws a horizontal line along the top of the span, a short descender at each
  //          end — the left one is what says where the bracket BEGINS — and the figure under the line
  //          at the left, in the staff-text style.
  //
  //          WHY IT IS DRAWN AND NOT SET. A first-ending bracket is a line with a figure in it, and the
  //          figure is a digit the font has; the line is not a character in any font, so it is drawn.
  //          An unnumbered bracket (`Volta.number == 0`, which iReal writes as `N0`) draws the line and
  //          no figure, which is exactly what it means.
  // KEYWORDS: volta, ending, bracket, first-ending, second-ending, drawn-sign, unnumbered
  void _paintVolta(Canvas canvas, PlacedVolta volta) {
    final LayoutRect band = volta.bounds;
    final double top = band.top + 1;
    final double left = band.left;
    final double right = band.right;
    const double descender = 4;
    canvas.drawLine(Offset(left, top), Offset(right, top), _thin);
    canvas.drawLine(Offset(left, top), Offset(left, top + descender), _thin);
    canvas.drawLine(Offset(right, top), Offset(right, top + descender), _thin);
    if (volta.number > 0) {
      _paintText(
        canvas,
        '${volta.number}.',
        Offset(left + 3, top + 1),
        metrics.staffTextStyle,
      );
    }
  }

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

  // PURPOSE: Draw one bar: its bounding barlines, the signs it carries, the words written on it and
  //          the chord symbols written in it.
  // INPUTS: canvas — the target. placed — the bar and its rectangle, with its chords, its signs and
  //         its staff text already measured and placed. firstInSystem — whether this bar opens its
  //         system, which decides whether its opening barline needs drawing.
  // OUTPUTS: Nothing. A bar whose address does not resolve in the song still draws its bounding
  //          barlines, so the measure is visible as empty rather than as missing; and a bar that
  //          resolves but holds no chord draws NOTHING in its chord row, which is the honest
  //          picture of a bar whose chord sustains from the one before it.
  //
  //          THE DRAW ORDER IS: lines, then signs and words, then chords. The chords go last and on
  //          top of everything, because a symbol whose stored x is close to the bar's left edge
  //          overlaps the opening barline and has to stay readable: drawing it underneath would cut
  //          the first character of the first chord of a bar, which is the one character that names
  //          the harmony. A sign is never drawn over the chords — the layout gives it the lane the
  //          chord row leaves — so the order between those two is not a conflict, it is a
  //          consequence of the placement.
  // KEYWORDS: bar, barline, chord-symbol, sign, staff-text, opening, closing, draw-order,
  //           no-chord-drawn-nothing, null-safe
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

    for (final PlacedBarSign sign in placed.signs) {
      _paintSign(canvas, sign);
    }
    for (final PlacedStaffText line in placed.staffText) {
      _paintText(
        canvas,
        line.text,
        Offset(line.bounds.left, line.bounds.top),
        metrics.staffTextStyle,
      );
    }
    for (final PlacedChord chord in placed.chords) {
      _paintChord(canvas, chord);
    }
  }

  // PURPOSE: Draw one of a bar's signs — the one kind that is written as words, and the five that are
  //          drawn as shapes — in the box the layout placed it in.
  // INPUTS: canvas — the target. sign — its kind, its words for the written kinds and the square or
  //         measured box it occupies.
  // OUTPUTS: Nothing. `N.C.` and a meter such as `3/4` are drawn as text in the style the layout
  //          measured them with; the simile mark, the slash repeat, the segno, the coda and the
  //          fermata are drawn as geometry inside the square.
  //
  //          WHY EACH SHAPE IS THE SHAPE IT IS, since a drawn sign has no font to answer for it:
  //            * THE SIMILE MARK is a diagonal stroke with a dot on either side — the two-measure form
  //              puts a second stroke through it, which is the whole difference between "play that bar
  //              again" and "play those two bars again";
  //            * THE SLASH REPEAT is a single heavy slash, the mark a chart uses for "keep comping";
  //            * THE SEGNO is an S-curve cut by a diagonal stroke with a dot on each side of it;
  //            * THE CODA is a circle with a cross through it, the arms reaching past the ring;
  //            * THE FERMATA is an arc over a dot.
  //          All five are the shapes an engraver cuts. None of them is a letter, which is the point:
  //          `S` and `C` are what a chart writes for a SECTION, and a section letter that means a coda
  //          is worse than a blank because it reads.
  // KEYWORDS: bar-sign, simile, repeat-previous-two-bars, slash-repeat, no-chord, segno, coda,
  //           fermata, meter-sign, drawn-geometry
  void _paintSign(Canvas canvas, PlacedBarSign sign) {
    final LayoutRect box = sign.bounds;
    switch (sign.kind) {
      case BarSignKind.noChord:
        _paintText(
          canvas,
          sign.text,
          Offset(box.left, box.top),
          metrics.chordStyle,
        );
      case BarSignKind.meterChange:
        _paintText(
          canvas,
          sign.text,
          Offset(box.left, box.top),
          metrics.staffTextStyle,
        );
      case BarSignKind.repeatPreviousOneBar:
        _paintSimile(canvas, box, strokes: 1);
      case BarSignKind.repeatPreviousTwoBars:
        _paintSimile(canvas, box, strokes: 2);
      case BarSignKind.slashRepeat:
        _paintSimile(canvas, box, strokes: 1, withDots: false);
      case BarSignKind.segno:
        _paintSegno(canvas, box);
      case BarSignKind.coda:
        _paintCoda(canvas, box);
      case BarSignKind.fermata:
        _paintFermata(canvas, box);
    }
  }

  // PURPOSE: Draw the repeat-previous simile mark — one or two diagonal strokes through a box with a
  //          dot at either side — which is how a chart says "play the bar again" or "play the last two
  //          bars again" without writing the music out.
  // INPUTS: canvas — the target. box — the square the sign occupies. strokes — 1 for the one-bar form
  //         and 2 for the two-bar form. withDots — whether the two dots are drawn; the slash repeat
  //         uses the same strokes with none, because a slash is not a simile mark.
  // OUTPUTS: Nothing. The strokes run from the bottom-left to the top-right of the box, which is the
  //          direction of a written `%` and the reason the mark reads at a glance; the dots sit in the
  //          upper-left and lower-right corners the stroke leaves free. A box too small to hold two
  //          dots still draws its strokes, so a bar of an unusual height shows the mark rather than
  //          nothing.
  // KEYWORDS: simile, repeat-previous, percent-sign, two-bars, dots, slash, drawn-mark
  void _paintSimile(
    Canvas canvas,
    LayoutRect box, {
    required int strokes,
    bool withDots = true,
  }) {
    final double inset = box.size.width * 0.18;
    final double left = box.left + inset;
    final double right = box.right - inset;
    final double top = box.top + inset * 0.6;
    final double bottom = box.bottom - inset * 0.6;
    if (strokes == 1) {
      canvas.drawLine(Offset(left, bottom), Offset(right, top), _thin);
    } else {
      // TWO PARALLEL STROKES, which is the two-measure form and not a second symbol: a musician reads
      // the doubling as "twice as much music", the same way he reads a double barline as a boundary.
      canvas.drawLine(Offset(left, bottom), Offset(right, top), _thin);
      canvas.drawLine(
        Offset(left, top + (bottom - top) * 0.15),
        Offset(left + (right - left) * 0.55, bottom),
        _thin,
      );
      canvas.drawLine(
        Offset(left + (right - left) * 0.45, top),
        Offset(right, top + (bottom - top) * 0.85),
        _thin,
      );
    }
    if (!withDots) {
      return;
    }
    final double radius = (box.size.width * 0.09).clamp(1.0, 2.2);
    canvas.drawCircle(
      Offset(left + (right - left) * 0.18, top + (bottom - top) * 0.18),
      radius,
      _thin,
    );
    canvas.drawCircle(
      Offset(left + (right - left) * 0.82, top + (bottom - top) * 0.82),
      radius,
      _thin,
    );
  }

  // PURPOSE: Draw a segno sign — the mark that says where a `D.S.` returns to — as an S-shaped curve
  //          cut by a diagonal stroke, with a dot on either side of the stroke.
  // INPUTS: canvas — the target. box — the square the sign occupies.
  // OUTPUTS: Nothing. Two counter-curving arcs form the S, one stroke crosses it from lower-left to
  //          upper-right, and two dots sit clear of the curve at the stroke's ends. A degenerate box
  //          draws a single dot rather than a curve with no extent, so a sign given no room is still
  //          visibly present rather than silently missing.
  // KEYWORDS: segno, dal-segno, drawn-glyph, s-curve, dots, no-font
  void _paintSegno(Canvas canvas, LayoutRect box) {
    final double size = box.size.width < box.size.height
        ? box.size.width
        : box.size.height;
    if (size <= 0) {
      return;
    }
    final Offset centre = Offset(
      box.left + box.size.width / 2,
      box.top + box.size.height / 2,
    );
    final double half = size / 2;
    final Paint stroke = _thin
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    // The S: an upper arc opening left and a lower arc opening right.
    final Path s = Path()
      ..moveTo(centre.dx + half * 0.45, centre.dy - half * 0.85)
      ..cubicTo(
        centre.dx - half * 0.75,
        centre.dy - half * 0.85,
        centre.dx - half * 0.75,
        centre.dy - half * 0.1,
        centre.dx - half * 0.05,
        centre.dy - half * 0.05,
      )
      ..cubicTo(
        centre.dx + half * 0.7,
        centre.dy,
        centre.dx + half * 0.7,
        centre.dy + half * 0.85,
        centre.dx - half * 0.45,
        centre.dy + half * 0.85,
      );
    canvas.drawPath(s, stroke);
    // The stroke through it, and the two dots at its ends.
    canvas.drawLine(
      Offset(centre.dx - half * 0.9, centre.dy + half * 0.55),
      Offset(centre.dx + half * 0.9, centre.dy - half * 0.55),
      stroke,
    );
    final Paint dot = _thin;
    final double radius = (size * 0.08).clamp(0.8, 1.8);
    canvas.drawCircle(
      Offset(centre.dx - half * 0.72, centre.dy - half * 0.72),
      radius,
      dot,
    );
    canvas.drawCircle(
      Offset(centre.dx + half * 0.72, centre.dy + half * 0.72),
      radius,
      dot,
    );
  }

  // PURPOSE: Draw a coda sign — the mark that says where a `To Coda` jump lands — as a ring with a
  //          cross through it.
  // INPUTS: canvas — the target. box — the square the sign occupies.
  // OUTPUTS: Nothing. The ring is inscribed in the box and the cross's arms reach past it, which is
  //          what distinguishes a coda from a target or a circled letter.
  // KEYWORDS: coda, to-coda, drawn-glyph, ring, cross, no-font
  void _paintCoda(Canvas canvas, LayoutRect box) {
    final double size = box.size.width < box.size.height
        ? box.size.width
        : box.size.height;
    if (size <= 0) {
      return;
    }
    final Offset centre = Offset(
      box.left + box.size.width / 2,
      box.top + box.size.height / 2,
    );
    final double radius = size * 0.32;
    final Paint stroke = _thin
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(centre, radius, stroke);
    final double arm = size / 2;
    canvas.drawLine(
      Offset(centre.dx - arm, centre.dy),
      Offset(centre.dx + arm, centre.dy),
      stroke,
    );
    canvas.drawLine(
      Offset(centre.dx, centre.dy - arm),
      Offset(centre.dx, centre.dy + arm),
      stroke,
    );
  }

  // PURPOSE: Draw a fermata — the sign that says "hold this" — as a semicircular arc over a dot.
  // INPUTS: canvas — the target. box — the square the sign occupies.
  // OUTPUTS: Nothing. The arc opens downward and the dot sits under its crown, which is the shape
  //          every musician recognises; a box too short for both still draws the arc, because a
  //          fermata without its dot is still a fermata and a fermata not drawn is a lost hold.
  // KEYWORDS: fermata, hold, drawn-glyph, arc, dot, no-font
  void _paintFermata(Canvas canvas, LayoutRect box) {
    final double size = box.size.width < box.size.height
        ? box.size.width
        : box.size.height;
    if (size <= 0) {
      return;
    }
    final Offset centre = Offset(
      box.left + box.size.width / 2,
      box.top + box.size.height / 2,
    );
    final double radius = size * 0.38;
    final Paint stroke = _thin
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(centre.dx, centre.dy + radius * 0.25),
        radius: radius,
      ),
      3.14159,
      3.14159,
      false,
      stroke,
    );
    canvas.drawCircle(
      Offset(centre.dx, centre.dy + radius * 0.55),
      (size * 0.09).clamp(0.8, 1.8),
      _thin,
    );
  }

  // PURPOSE: Draw one chord symbol in the box the layout reserved for it and in the spelling the
  //          layout rendered, so that what a musician reads is what the chart says.
  // INPUTS: canvas — the target. placed — the symbol's words, its box and the size the model asked
  //         for.
  // OUTPUTS: Nothing. The words are drawn from [PlacedChord.text] EXACTLY as they arrived: this
  //          method spells nothing, transposes nothing and normalises no accidental, which is what
  //          keeps `F#h` an `F#h` and `Cb` a `Cb` on the glass. An empty string paints nothing,
  //          although the layout never publishes one.
  //
  //          THE TWO SIZES ARE A PROPERTY OF THE MARK, NOT OF THE PAGE. A chord the chart marked
  //          small is drawn with the small style at the same box origin: the box was measured with
  //          the normal chord style by the same metrics the layout used, so a small symbol sits at
  //          the row's top-left and is simply set smaller within it, exactly as a chart prints a
  //          passing chord.
  // KEYWORDS: chord-symbol, text, written-spelling, small-chord, measured-box, no-respelling
  void _paintChord(Canvas canvas, PlacedChord placed) {
    _paintText(
      canvas,
      placed.text,
      Offset(placed.bounds.left, placed.bounds.top),
      placed.small ? metrics.smallChordStyle : metrics.chordStyle,
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
