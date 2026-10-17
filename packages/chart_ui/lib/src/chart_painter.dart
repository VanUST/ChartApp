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
  /// [selection] is the bar and cell the musician has touched, or null when nothing is selected;
  /// the painter draws the highlight, and it is the only thing on the page that says "you are
  /// here" without a word.
  const ChartPainter({
    required this.song,
    required this.page,
    required this.metrics,
    this.spellingTable = const SpellingTable(),
    this.selection,
    this.selectionRange,
    this.lineColor = const Color(0xFF102A43),
    this.melodyLineColor = const Color(0xFF243B53),
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.selectionFillColor = const Color(0x2E2F80ED),
    this.selectionStrokeColor = const Color(0xFF2F80ED),
  });

  /// The least weight, in SURFACE pixels, that a staff line or a stem may be drawn at.
  ///
  /// Slightly above one so that a line survives the antialiasing of the surface instead of fading
  /// into the paper at 30 per cent of its ink. It is the number behind [_inkFloor], and it is a
  /// surface measurement rather than a page one: how thick a line is in page units depends on how
  /// much the page was scaled to fit, and how thick it must be for a musician to see it does not.
  static const double _minimumInkWeight = 1.4;

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

  /// The run of bars, or the window of beats, the musician has selected, or null.
  ///
  /// This is the owner's SELECTION (D35/D36): an address in the interface, not a value of the
  /// document, which is why it is a parameter of the painter rather than a field of the song. It is
  /// separate from [selection] because the two say different things: [selection] is where the last
  /// touch landed, and this is everything the next operation would act on.
  final ChartSelection? selectionRange;

  /// Colour of barlines, repeat dots and text.
  final Color lineColor;

  /// Colour of the melody staff and everything engraved on it.
  ///
  /// Slightly lighter than [lineColor] so that the music the chart is read for stays the darkest
  /// ink on the page. It is a property of the painter rather than of the layout because it is a
  /// rendering decision: the same geometry serves a screen and a printed page, and neither the
  /// noteheads nor their ledger lines carry a colour in the model.
  final Color melodyLineColor;

  /// Colour the page is filled with before anything is drawn.
  final Color backgroundColor;

  /// Colour the selected region is washed with, under the music so chords stay readable.
  final Color selectionFillColor;

  /// Colour of the outline drawn around the selected region.
  final Color selectionStrokeColor;

  // PURPOSE: Draw the page: the chart's opening statement, then section labels, then each bar's
  //          barlines, signs and chords.
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
    // The chart's own opening statement goes down first and outside the systems loop, because it
    // belongs to the page rather than to a line of music: it is what the reader sees before the
    // first chord, and it must not be moved by anything that moves a system.
    _paintChartHeader(canvas);
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
      // A RANGE MUST BE COMPARED HERE OR THE HIGHLIGHT WOULD NOT FOLLOW THE GESTURE. The range is
      // not part of the song and not part of the page, so without this line a musician who extended
      // a selection from one bar to sixteen would see the label change and the page stay as it was.
      oldDelegate.selectionRange != selectionRange ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.melodyLineColor != melodyLineColor ||
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

  // PURPOSE: Mark every bar (and, for a window, the cells) a musician has SELECTED, so a range of
  //          sixteen bars is visibly sixteen bars and not one highlighted bar with a number beside
  //          it. The owner's workflow begins with selecting a run (D35), and a highlight that marks
  //          only the bar last touched would be a picture of the wrong thing.
  // INPUTS: canvas — the target. placed — the bar being drawn, with its cells.
  // OUTPUTS: Nothing. Draws when [selectionRange] names a section and bar this placed bar belongs
  //          to: the whole bar for a bar-deep selection, and the window's cells for a selection of
  //          beats, each cell looked up by `.beat` so a cell the bar does not have is skipped rather
  //          than drawn at a guessed offset. The single-hit highlight ([selection]) is drawn by
  //          [_paintSelection] as before; when both are set the range wins for the bars it covers,
  //          because the range is the more recent gesture.
  // KEYWORDS: selection-range, highlight, many-bars, beat-window, visual-feedback, d35
  void _paintSelectionRange(Canvas canvas, PlacedBar placed) {
    final ChartSelection? range = selectionRange;
    if (range == null ||
        range.sectionId != placed.sectionId ||
        placed.barIndex < range.firstBar ||
        placed.barIndex > range.lastBar) {
      return;
    }
    if (!range.isBeatWindow || range.firstBar != placed.barIndex) {
      _paintSelectionRegion(canvas, placed.bounds);
      return;
    }
    for (final PlacedCell cell in placed.cells) {
      if (cell.beat < range.firstBeat! || cell.beat > range.lastBeat!) {
        continue;
      }
      _paintSelectionRegion(canvas, cell.bounds);
    }
  }

  // PURPOSE: Fill and outline one region as selected, so every place the selection covers is marked
  //          by the same rule and the fill and the outline cannot drift apart.
  // INPUTS: canvas — the target. region — a rectangle in page coordinates.
  // OUTPUTS: Nothing. Draws the fill, then the outline inset by half its own width so it sits inside
  //          the region rather than straddling its edge and tinting the neighbour.
  // KEYWORDS: selection-paint, fill, outline, inset, shared-rule
  void _paintSelectionRegion(Canvas canvas, LayoutRect region) {
    final Rect rect = Rect.fromLTWH(
      region.left,
      region.top,
      region.size.width,
      region.size.height,
    );
    canvas.drawRect(rect, Paint()..color = selectionFillColor);
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
    _paintSelectionRange(canvas, placed);
    _paintSelection(canvas, placed);

    // The melody staff is underneath the chord line with its own extent, so it is drawn before the
    // chords: a chord symbol that runs a little low must stay the topmost thing on its own line.
    //
    // THE BEAT CAPTIONS GO DOWN FIRST AND THE NOTES OVER THEM, which is a hierarchy and not a
    // drawing order: the caption row hangs directly under the staff, and a melody note written just
    // below the staff — D4 or C4 under a treble staff, which is where a jazz line lives — occupies
    // exactly that row. On the rendered page the two overlapped and the DIGIT was drawn on top of
    // the notehead, so the music was covered by a number naming a column the musician had already
    // found. The music wins; where a digit is behind a notehead the tick beside it and the same
    // number on the bar that opens the system still give the grid.
    _paintBeatMarkers(canvas, placed);
    _paintMelody(canvas, placed);

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
    // The meter is drawn AFTER the other signs for one reason: a bar that changes meter is a bar
    // whose three beats a musician would otherwise have to count, and for 15/8 could not recover at
    // all, so the sign that explains the bar is never the symbol that gets covered. On the rare bar
    // that carries BOTH a volta and a change — `[1.` is drawn at the same top-left corner — the two
    // overlap and the meter wins; that is a blemish of this reading renderer, not a lost edit, and
    // it is stated rather than hidden.
    _paintMeterSign(canvas, bar, placed, firstInSystem: firstInSystem);
    for (final PlacedChord placedChord in placed.chords) {
      _paintChord(canvas, bar, placedChord);
    }
  }

  // PURPOSE: Report the least stroke weight, in PAGE units, that still arrives on the glass as a
  //          visible line at the current view.
  // INPUTS: None; reads [page]'s own `drawnScale`, which is the page mode's scale times the
  //         musician's zoom.
  // OUTPUTS: A weight in page pixels. A page drawn at scale 1 gets [_minimumInkWeight]; a page the
  //          FIT mode shrank to 0.7 gets that weight divided by 0.7, so the line lands at the same
  //          number of SCREEN pixels either way.
  //
  //          WHY THIS EXISTS AT ALL, AND IT IS A MEASUREMENT RATHER THAN A TASTE. The engraving's
  //          own weights are proportional to the staff space (1.56 page pixels for a 13-pixel
  //          space), which is right for print and wrong for a lit screen: at the owner's fitted
  //          scale of 0.70 that is 1.09 device pixels, which the rasteriser draws as a grey
  //          suggestion rather than as a line. The staff's five lines, its barlines, its beat ticks
  //          and its stems were all specified that way, and the owner's report of the result is
  //          that the staff "looks bad and unclear". A line that is thinner than a pixel on the
  //          glass is not a thin line, it is an invisible one.
  // KEYWORDS: stroke-weight, drawn-scale, legibility, sub-pixel, staff-lines, view-zoom
  double get _inkFloor => page.drawnScale > 0
      ? _minimumInkWeight / page.drawnScale
      : _minimumInkWeight;

  // PURPOSE: Draw the melody staff under a bar: its five lines, the barlines that carry them, the
  //          clef and every glyph the layout placed on them.
  // INPUTS: canvas — the target. placed — the bar's layout, carrying the staff the engine engraved.
  // OUTPUTS: Nothing. A bar whose system reserved no melody band draws NOTHING AT ALL, which is
  //          what makes a chords-only chart print identically to the way it printed before a melody
  //          staff existed: the empty staff the engine publishes has no extent, so this returns
  //          before touching the canvas.
  //
  //          THE FIVE LINES ARE DERIVED HERE FROM THE STAFF'S OWN BOX, and that is the one number
  //          this painter has to agree with the engine about. The box's top and bottom edges are
  //          the staff's outer lines and the engine's [LayoutStyle.melodyStaffSpace] is the
  //          distance between two of them, so four equal divisions of the box is the whole of the
  //          staff: there is no second geometry here to drift from the one a notehead's y was
  //          computed against.
  //
  //          ITS WEIGHT IS THE VIEW'S, NOT THE PAGE'S — see [_inkFloor]. The five lines, the two
  //          barlines and every glyph's stem are drawn at whichever is larger, the engraving's own
  //          proportional weight or one visible pixel of the surface the page is drawn on.
  // KEYWORDS: melody-staff, staff-lines, five-lines, notehead, stem, flag, ledger, accidental,
  //           tie, draw-order, ink-floor
  void _paintMelody(Canvas canvas, PlacedBar placed) {
    final PlacedMelodyStaff staff = placed.melody;
    if (staff.isEmpty) {
      return;
    }
    final LayoutRect bounds = staff.bounds;
    final double floor = _inkFloor;
    final Paint stroke = Paint()
      ..color = melodyLineColor
      ..strokeWidth = floor;
    // The five lines, from the top edge down; four equal divisions of the box the engine published.
    for (int line = 0; line < 5; line++) {
      final double y = bounds.top + bounds.size.height * line / 4;
      canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), stroke);
    }
    // Barlines reach from the staff's top line to its bottom line at both edges of the bar. The
    // chord line already draws its own, which stops at the stave; without these the staff would
    // read as one unmeasured strip of five lines — and "where does the bar end" is the one question
    // a chart must answer without being asked, so this line is the staff's most important one.
    //
    // IT IS HEAVIER THAN EVERYTHING ELSE ON THE STAFF, and that is a distinction rather than a
    // preference: a stem is 3.5 staff spaces long, vertical and the same ink, so drawn at the same
    // weight a stem in the middle of a bar reads as a barline. Measured on the rendered page: the
    // note C4 sits a ledger line below the staff and its up-stem runs the whole staff, so the
    // first thing a musician saw in the bar was two vertical lines and no way to tell which was
    // which.
    final Paint barline = Paint()
      ..color = melodyLineColor
      ..strokeWidth = floor * 1.6;
    canvas.drawLine(
      Offset(bounds.left, bounds.top),
      Offset(bounds.left, bounds.bottom),
      barline,
    );
    canvas.drawLine(
      Offset(bounds.right, bounds.top),
      Offset(bounds.right, bounds.bottom),
      barline,
    );

    // THE CLEF IS NOT DRAWN, AND THAT IS THE OWNER'S VERDICT RATHER THAN AN OMISSION. This renderer
    // ships no music font, so the treble clef was drawn as the LETTER `G` in the margin — and the
    // owner's report of it is «зачем то буква G в начале. Если это просто убрать - уже будет лучше».
    // He is right and the reason is not cosmetic: a letter where a musician expects a clef makes the
    // staff LOOK signed while saying nothing he can read, and a staff with no clef is at least
    // honest. `PlacedMelodyStaff.clef` still carries which clef the staff was engraved in, because
    // the pitch placement needs it and because a later renderer with a music font may draw it; what
    // stopped is the painting.
    //
    // The alternative — a vector treble clef — was built and LOOKED at (see `_paintMelodyGlyph`'s
    // rejected-alternative note in the decision record): two cubic curves read as an ampersand, not
    // as a clef. A wrong sign in the clef's place is the same lie in a different shape.

    // The glyphs are drawn in the order the engine published them, and that order is the contract:
    // a ledger line before the notehead that hides its end, a stem before the notehead that covers
    // it, an accidental and a dot after the head they belong to, and ties last so a tie is never
    // buried under the note it joins.
    for (final MelodyGlyph glyph in staff.glyphs) {
      _paintMelodyGlyph(canvas, glyph, inkFloor: floor);
    }
  }

  // PURPOSE: Name the beats of a bar under its staff, so a musician can see which beat he is about
  //          to choose instead of counting columns of blank paper — the defect owner decision D28
  //          records: «ориентироваться внутри такта трудно».
  // INPUTS: canvas — the target. placed — the bar's layout, carrying the markers the engine placed.
  // OUTPUTS: Nothing. For every marker, a short tick at the bottom of its column and — when the
  //          engine decided the column is wide enough — the beat's ordinal centred over it. A bar
  //          whose song carries no staff publishes no markers, so this returns before touching the
  //          canvas and a chords-only chart prints exactly what it printed before beat captions
  //          existed.
  //
  //          WHY THE TICK IS DRAWN EVEN WITH NO NUMBER. The captions are printed on the bar that
  //          opens a system, and the beats of the bars after it are named by those same numbers on
  //          the same columns. Without a tick there would be nothing on those bars at all and the
  //          caption would look like it belonged to the first bar rather than to the line; the tick
  //          is what says "this column is still beat n" without repeating the digit nine times.
  // KEYWORDS: beat-marker, beat-orientation, caption, tick, centred-ordinal, no-staff-no-marker
  void _paintBeatMarkers(Canvas canvas, PlacedBar placed) {
    final List<PlacedBeatMarker> markers = placed.beatMarkers;
    if (markers.isEmpty) {
      return;
    }
    final PlacedMelodyStaff staff = placed.melody;
    final double staffSpace = staff.isEmpty ? 0 : staff.bounds.size.height / 4;
    // THE CAPTION IS SIZED FROM THE STAFF IT BELONGS TO, at nine tenths of a staff space, and set
    // bold in the staff's own ink rather than in the caption grey it used to be. It names the beat a
    // musician is choosing — the defect D28 records as «ориентироваться внутри такта трудно» — and
    // a number that is two millimetres tall in pale grey is a number nobody reads at a stand.
    final TextStyle style = metrics.staffTextStyle.copyWith(
      color: melodyLineColor,
      fontSize: staffSpace > 0 ? staffSpace * 0.9 : null,
      fontWeight: FontWeight.w600,
    );
    final Paint tick = Paint()
      ..color = melodyLineColor
      ..strokeWidth = _inkFloor;
    for (final PlacedBeatMarker marker in markers) {
      final LayoutRect box = marker.bounds;
      // The tick is a third of the marker's box, centred in its column, and it is what the eye
      // follows down the staff when the digits are only on the bar that opens the system.
      final double centre = box.left + box.size.width / 2;
      canvas.drawLine(
        Offset(centre, box.bottom - box.size.height / 3),
        Offset(centre, box.bottom),
        tick,
      );
      if (marker.label.isEmpty) {
        continue;
      }
      final Size size = _measureText(marker.label, style);
      _paintText(
        canvas,
        marker.label,
        Offset(centre - size.width / 2, box.bottom - size.height),
        style,
      );
    }
  }

  // PURPOSE: Draw one glyph of a melody staff.
  // INPUTS: canvas — the target. glyph — the element and the box the layout placed it in, with the
  //         weight, the flag length and the tie's own curve points published alongside it. inkFloor
  //         — the least weight, in page units, that still arrives on the glass as a drawn line; see
  //         [_inkFloor] for why a stem is not allowed to be thinner than that.
  // OUTPUTS: Nothing. Every position comes from the box; this method makes no musical decision, so
  //          a notehead cannot be drawn at a height the layout did not reserve.
  // KEYWORDS: glyph-switch, notehead, stem, flag, ledger, accidental, dot, tie, no-musical-logic,
  //           ink-floor
  void _paintMelodyGlyph(
    Canvas canvas,
    MelodyGlyph glyph, {
    required double inkFloor,
  }) {
    final LayoutRect box = glyph.bounds;
    final Paint stroke = Paint()
      ..color = melodyLineColor
      ..strokeWidth = glyph.strokeWidth > inkFloor
          ? glyph.strokeWidth
          : inkFloor;
    switch (glyph.kind) {
      case MelodyGlyphKind.notehead:
        final Rect ellipse = Rect.fromLTWH(
          box.left,
          box.top,
          box.size.width,
          box.size.height,
        );
        if (glyph.filled) {
          canvas.drawOval(ellipse, Paint()..color = melodyLineColor);
        } else {
          // A hollow notehead keeps its own weight rather than the glyph's, because a whole note's
          // ring drawn at a stem's weight reads as a filled head on a small page — and the ring is
          // raised to the ink floor for the same reason every other stroke is.
          canvas.drawOval(
            ellipse,
            Paint()
              ..color = melodyLineColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = inkFloor > 1.6 ? inkFloor : 1.6,
          );
        }
      case MelodyGlyphKind.stem:
        // The stem is drawn as a line down the centre of its box, so its published weight and what
        // the reader sees are the same number.
        final double x = box.left + box.size.width / 2;
        canvas.drawLine(Offset(x, box.top), Offset(x, box.bottom), stroke);
        if (glyph.flagLength > 0) {
          _paintMelodyFlag(canvas, box, glyph, stroke);
        }
      case MelodyGlyphKind.beam:
        // A BEAM IS ONE HEAVY, STRAIGHT STROKE BETWEEN TWO STEMS, so it is drawn from its own two
        // published ends and at its own published weight. Nothing is derived here: the slope, the
        // length and the thickness were all decided by the engraving, where they can be asserted
        // without a canvas — and the slope is the one thing a musician reads as the shape of the
        // phrase, so a painter that recomputed it would be the second author of it.
        //
        // It is NOT raised to the ink floor the way a hairline is (see [_paintMelodyGlyph]'s
        // `stroke`): a beam is half a staff space thick by convention and is the heaviest thing on
        // the staff after the barlines, so the floor exists for the strokes beside it, not for this
        // one. `stroke` still supplies the colour, and its width is the glyph's own unless the view
        // is shrunk so far that the floor exceeds it, which is the same legibility rule every other
        // stroke follows.
        canvas.drawLine(
          Offset(glyph.from.x, glyph.from.y),
          Offset(glyph.to.x, glyph.to.y),
          stroke,
        );
      case MelodyGlyphKind.ledgerLine:
        canvas.drawLine(
          Offset(box.left, box.top + box.size.height / 2),
          Offset(box.right, box.top + box.size.height / 2),
          stroke,
        );
      case MelodyGlyphKind.accidental:
        // The sign is drawn at the same proportional size as the beat caption, from the box the
        // layout reserved for it: its height is [MelodyMetrics.accidentalHeight] staff spaces, so
        // the space is recovered from the box rather than guessed from the style.
        _paintText(
          canvas,
          glyph.text ?? '',
          Offset(box.left, box.top),
          metrics.staffTextStyle.copyWith(
            color: melodyLineColor,
            fontSize: box.size.height / 1.7 * 0.85,
            fontWeight: FontWeight.w600,
          ),
        );
      case MelodyGlyphKind.dot:
        canvas.drawOval(
          Rect.fromLTWH(box.left, box.top, box.size.width, box.size.height),
          Paint()..color = melodyLineColor,
        );
      case MelodyGlyphKind.tie:
        // A quadratic curve, which is what an engraved tie is: it leaves one notehead, bulges away
        // from the slope between the two, and reaches the next. The three points come from the
        // layout, so the curve is drawn exactly where the tie was measured to be.
        final Path path = Path()
          ..moveTo(glyph.from.x, glyph.from.y)
          ..quadraticBezierTo(
            glyph.control.x,
            glyph.control.y,
            glyph.to.x,
            glyph.to.y,
          );
        canvas.drawPath(
          path,
          Paint()
            ..color = melodyLineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.strokeWidth
            ..strokeCap = StrokeCap.round,
        );
      case MelodyGlyphKind.flag:
        // A flag is generated from a stem rather than placed on its own, so no glyph of this kind
        // is ever published; the branch exists because the enum is exhaustive.
        break;
    }
  }

  // PURPOSE: Draw the flag of an eighth note or shorter, as a curve from the end of the stem.
  // INPUTS: canvas — the target. stem — the stem's box. glyph — the stem glyph, carrying the
  //         direction and the flag's length in page pixels. stroke — the staff's own paint.
  // OUTPUTS: Nothing. The curve starts at the free end of the stem, in the direction the stem
  //          points, and sweeps back toward the staff.
  //
  //          A DRAWING RATHER THAN A GLYPH, for the reason the bar signs are glyphs and this is
  //          not: a flag has no ASCII stand-in a font is certain to carry, and a wrong glyph is
  //          worse than a plain curve, which every musician reads correctly at any size.
  // KEYWORDS: flag, eighth-note, curve, glyph-free, stroke
  void _paintMelodyFlag(
    Canvas canvas,
    LayoutRect stem,
    MelodyGlyph glyph,
    Paint stroke,
  ) {
    final double x = stem.left + stem.size.width / 2;
    final double tip = glyph.stemUp ? stem.top : stem.bottom;
    final double direction = glyph.stemUp ? 1 : -1;
    final double reach = glyph.flagLength * direction;
    final Path path = Path()
      ..moveTo(x, tip)
      ..quadraticBezierTo(
        x + glyph.flagLength * 0.9,
        tip + reach * 0.25,
        x + glyph.flagLength * 1.1,
        tip + reach,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = melodyLineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round,
    );
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
      // SORTED BY THE ENUM'S OWN ORDER, because rendering must be a function of the VALUE and not of
      // the order the marks happened to be inserted in. `Bar` compares its marks as a SET
      // (`containsAll` both ways, `hashAllUnordered`), so two bars with the same signs are the same
      // value — but a `Set` iterates in insertion order, so drawing them as iterated would render
      // "segno coda" and "coda segno" for two bars that are `==`. A chart that redraws differently
      // from a value it already agreed on is the kind of difference that is invisible until it is
      // compared, which is when it is hardest to explain.
      final List<BarMark> ordered = bar.marks.toList()
        ..sort((BarMark a, BarMark b) => a.index.compareTo(b.index));
      final String text = ordered.map(_markGlyph).join(' ');
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

  // PURPOSE: Draw the meter a bar is counted in, where a musician looks for it: at the bar where the
  //          meter CHANGES, and at the start of a system whose meter is not the one the reader
  //          assumes. It is the sign that turns "three chord cells and no explanation" into a chart
  //          that can be played — owner decision D22's rendering half.
  // INPUTS: canvas — the target. bar — the bar, read for its meter. placed — the bar's layout, whose
  //         bounds the sign is placed inside. firstInSystem — whether this bar opens its system,
  //         which is one of the three things the rule reads.
  // OUTPUTS: Nothing, and NOTHING AT ALL for a bar the rule does not sign, which is every bar of a
  //          chart in 4/4 throughout — that is what makes such a chart print byte-for-byte what it
  //          printed before a meter sign existed.
  //
  //          WHERE IT IS DRAWN, AND WHY THERE. In the bar's own top-left corner, in the band the
  //          stave leaves above its centred chords — the position a printed time signature occupies
  //          relative to the barline, and the same corner and the same style the volta's `[1.` uses.
  //          It is drawn INSIDE the bar's published rectangle and derives no geometry of its own, so
  //          the layout did not have to change for it: the cells the hit test reads, the chord
  //          positions and every measured width are exactly what they were, which is the property
  //          requirement 4 of D22's implementation demands.
  // KEYWORDS: meter, time-signature, meter-sign, drawing, top-left, no-geometry-change, d22
  void _paintMeterSign(
    Canvas canvas,
    Bar bar,
    PlacedBar placed, {
    required bool firstInSystem,
  }) {
    final TimeSignature meter = bar.timeSignature;
    if (!showsMeterSign(
      meter: meter,
      preceding: precedingMeter(song, placed.sectionId, placed.barIndex),
      opensSystem: firstInSystem,
      // The metre is stated once where the music begins, and on this tree that statement is the
      // page's own header line. A page without one — a page the engine engraved with no header,
      // which every page after the first is — keeps the bar's own sign.
      headerStatesOpeningMeter: page.header != null,
    )) {
      return;
    }
    _paintText(
      canvas,
      meter.toString(),
      Offset(placed.bounds.left + 2, placed.bounds.top + 1),
      metrics.staffTextStyle,
    );
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
