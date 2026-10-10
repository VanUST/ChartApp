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
  /// [selection] is the bar and cell the musician has touched, or null when nothing is selected;
  /// the painter draws the highlight, and it is the only thing on the page that says "you are
  /// here" without a word.
  const ChartPainter({
    required this.song,
    required this.page,
    required this.metrics,
    this.spellingTable = const SpellingTable(),
    this.selection,
    this.lineColor = const Color(0xFF102A43),
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.selectionFillColor = const Color(0x2E2F80ED),
    this.selectionStrokeColor = const Color(0xFF2F80ED),
  });

  /// The model the page was laid out from, read for the signs [PageLayout] does not carry.
  final Song song;

  /// The page to draw.
  final PageLayout page;

  /// The metrics the layout was measured with, reused so text lands in its reserved box.
  final FlutterTextMetrics metrics;

  /// The rule chords are rendered to text with, matching the layout engine's.
  final SpellingTable spellingTable;

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

  /// Colour the selected region is washed with, under the music so chords stay readable.
  final Color selectionFillColor;

  /// Colour of the outline drawn around the selected region.
  final Color selectionStrokeColor;

  // PURPOSE: Draw the page: section labels, then each bar's barlines, signs and chords.
  // INPUTS: canvas — the target. size — the extent the painter was given, which is the page's own
  //         size when the viewer sizes the widget to the layout.
  // OUTPUTS: Nothing. Everything is drawn clipped to `size`, so a system the engine deliberately
  //          let overflow the page edge cannot bleed into the neighbouring page of a PageView. The
  //          canvas is scaled by [PageLayout.scale] before the geometry is drawn, which is what
  //          lets the same painter draw an ordinary page and a page the FIT mode shrank.
  // KEYWORDS: paint, clipping, section-label, reading-order
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // The page's geometry is in engraved coordinates. FIT produces a page engraved at a larger
    // virtual size and records the factor that brings it back onto this surface, so one scale here
    // keeps every rectangle, hit test and annotation anchor in a single coordinate system.
    final double scale = page.scale;
    if (scale != 1) {
      canvas.scale(scale, scale);
    }
    for (final PlacedSystem system in page.systems) {
      _paintSectionLabel(canvas, system);
      for (int index = 0; index < system.bars.length; index++) {
        _paintBar(canvas, system.bars[index], firstInSystem: index == 0);
      }
    }
    canvas.restore();
  }

  // PURPOSE: Report whether a new painter changes anything on screen.
  // INPUTS: oldDelegate — the painter this one replaces.
  // OUTPUTS: True when the page, the song, the metrics or a colour differ. The spelling table is
  //          NOT compared: it has no value equality, and a caller that changes it is expected to
  //          change the layout with it, because the engine measured the text it produces.
  // KEYWORDS: should-repaint, value-comparison, cache
  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.song != song ||
      oldDelegate.metrics != metrics ||
      oldDelegate.selection != selection ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.selectionFillColor != selectionFillColor ||
      oldDelegate.selectionStrokeColor != selectionStrokeColor;

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
    final int? beat = hit.beat;
    final PlacedCell? cell = beat == null ? null : _cellOf(placed, beat);
    final LayoutRect region = cell?.bounds ?? placed.bounds;
    final Rect rect = Rect.fromLTWH(
      region.left,
      region.top,
      region.size.width,
      region.size.height,
    );
    canvas.drawRect(rect, Paint()..color = selectionFillColor);
    // The outline is inset by half its own width so it sits inside the region. Drawn centred it
    // would straddle the cell's edge and tint the neighbouring cell, which is exactly the confusion
    // the label beside the chart exists to remove.
    const double strokeWidth = 2;
    canvas.drawRect(
      rect.deflate(strokeWidth / 2),
      Paint()
        ..color = selectionStrokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  // PURPOSE: Find the cell a selection names, so the highlight can be drawn on a cell that may have
  //          been produced by a different layout instance than the one the hit came from.
  // INPUTS: bar — the bar being drawn. beat — the cell index the selection carries.
  // OUTPUTS: The matching cell, or null when the bar has no cell at that index; the caller then
  //          falls back to marking the whole bar.
  // KEYWORDS: cell-lookup, beat, fallback, value-match
  PlacedCell? _cellOf(PlacedBar bar, int beat) {
    for (final PlacedCell cell in bar.cells) {
      if (cell.beat == beat) {
        return cell;
      }
    }
    return null;
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

    // The selection wash goes down before the barlines and the chords, so the symbol the musician
    // selected stays fully readable — a highlight that dims the chord it marks is worse than none,
    // because the musician is trying to check that the selection landed on the chord they meant.
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

    if (bar == null) {
      return;
    }
    _paintBarSigns(canvas, bar, placed);
    for (final PlacedChord placedChord in placed.chords) {
      _paintChord(canvas, bar, placedChord);
    }
  }

  // PURPOSE: Draw one chord symbol in the box the layout reserved for it.
  // INPUTS: canvas — the target. bar — the bar the chord belongs to, read for the BeatChord that
  //         carries the engraved size. placed — the chord and its rectangle.
  // OUTPUTS: Nothing. A placed chord with no matching BeatChord is drawn at normal size rather
  //          than skipped, because losing a chord is worse than losing its size.
  // KEYWORDS: chord, text, small-chord, beat-step-match, fallback
  void _paintChord(Canvas canvas, Bar bar, PlacedChord placed) {
    final ChordSize engravedSize =
        _beatChordOf(bar, placed)?.size ?? ChordSize.normal;
    final TextStyle style = engravedSize == ChordSize.small
        ? metrics.smallChordStyle
        : metrics.chordStyle;
    _paintText(
      canvas,
      placed.chord.render(song.key, spellingTable),
      Offset(placed.bounds.left, placed.bounds.top),
      style,
    );
  }

  // PURPOSE: Draw every sign the bar model carries that is not a chord: the repeat-previous
  //          symbol, the slash repeat, N.C., the volta bracket, the marks and the staff text.
  // INPUTS: canvas — the target. bar — the bar whose signs to draw. placed — the bar's layout,
  //         which carries the staff-text lines already in display form and already measured.
  // OUTPUTS: Nothing. Signs are placed in the bands above and below the chord line so they cannot
  //          cover a chord, which is the room LayoutStyle.barHeight leaves around the centred
  //          chord text.
  // KEYWORDS: repeat-previous, slash-repeat, no-chord, volta, marks, staff-text, glyph
  void _paintBarSigns(Canvas canvas, Bar bar, PlacedBar placed) {
    final LayoutRect bounds = placed.bounds;
    switch (bar.repeatPrevious) {
      case RepeatPrevious.oneBar:
        _paintCentered(canvas, '%', bounds, metrics.chordStyle);
      case RepeatPrevious.twoBars:
        _paintCentered(canvas, '2%', bounds, metrics.chordStyle);
      case RepeatPrevious.none:
        break;
    }
    if (bar.slashRepeat) {
      _paintCentered(canvas, '/', bounds, metrics.chordStyle);
    }
    if (bar.noChord) {
      _paintCentered(canvas, 'N.C.', bounds, metrics.chordStyle);
    }

    final Volta? volta = bar.volta;
    if (volta != null) {
      final String text = volta.number == 0 ? '[' : '[${volta.number}.';
      _paintText(
        canvas,
        text,
        Offset(bounds.left + 2, bounds.top + 1),
        metrics.staffTextStyle,
      );
    }

    if (bar.marks.isNotEmpty) {
      final String text = bar.marks.map(_markGlyph).join(' ');
      final Size size = _measureText(text, metrics.staffTextStyle);
      _paintText(
        canvas,
        text,
        Offset(bounds.right - size.width - 3, bounds.top + 1),
        metrics.staffTextStyle,
      );
    }

    // Staff text is drawn in the boxes the layout published. Those boxes already hold the DISPLAY
    // form — the `*NN` position prefix and the exporter's padding removed by `displayStaffText` —
    // and were measured with the same metrics the page was laid out with. The painter therefore
    // does not strip the prefix and does not measure the string a second time: a second derivation
    // here is exactly the drift that would let a bar reserve room for `*69` while drawing `Куплет`.
    for (final PlacedStaffText line in placed.staffText) {
      _paintText(
        canvas,
        line.text,
        Offset(line.bounds.left, line.bounds.top),
        metrics.staffTextStyle,
      );
    }
  }

  // PURPOSE: Name the glyph a [BarMark] is drawn as, keeping the mapping in one switch instead of
  //          scattering it through the sign-drawing code.
  // INPUTS: mark — the model's mark.
  // OUTPUTS: A short ASCII stand-in a font is certain to carry. Never null.
  // KEYWORDS: segno, coda, fermata, player-ending, glyph-table
  String _markGlyph(BarMark mark) => switch (mark) {
    BarMark.segno => 'S',
    BarMark.coda => 'C',
    BarMark.fermata => '^',
    BarMark.playerEnding => 'End',
  };

  // PURPOSE: Find the BeatChord that produced a placed chord, because the engraved size lives on
  //          the placement and PageLayout keeps only the chord itself.
  // INPUTS: bar — the bar to search. placed — the placed chord, addressed by beat and step.
  // OUTPUTS: The matching BeatChord, or null when the bar carries none at that address. Null is
  //          for a caller, not for a failure: a bar and a page assembled from different states of
  //          the song can disagree, and the caller falls back to normal size.
  // KEYWORDS: lookup, beat, step, identity, null-safe
  BeatChord? _beatChordOf(Bar bar, PlacedChord placed) {
    for (final BeatChord beatChord in bar.chords) {
      if (beatChord.beat == placed.beat && beatChord.step == placed.step) {
        return beatChord;
      }
    }
    return null;
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

  // PURPOSE: Draw text horizontally centred in a bar's chord band, which is where a chord or a
  //          repeat sign that replaces one belongs.
  // INPUTS: canvas — the target. text — the glyphs. bounds — the bar. style — the text style.
  // OUTPUTS: Nothing. An empty string draws nothing.
  // KEYWORDS: centred, chord-band, sign, drawing
  void _paintCentered(
    Canvas canvas,
    String text,
    LayoutRect bounds,
    TextStyle style,
  ) {
    final Size size = _measureText(text, style);
    _paintText(
      canvas,
      text,
      Offset(
        bounds.left + (bounds.size.width - size.width) / 2,
        bounds.top + (bounds.size.height - size.height) / 2,
      ),
      style,
    );
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
