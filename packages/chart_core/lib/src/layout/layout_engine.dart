// PURPOSE: Turn a song into positioned pages. This is the pipeline the design describes — plan
//          the bars, measure each one from its content, pack bars into systems, pack systems into
//          pages — implemented as pure functions over the song model so that a page can be
//          engraved, and its cost measured, without a device and without a rendering stack.
// INPUTS: A Song, a page size in logical pixels, a LayoutStyle carrying the spacing constants and
//         the text metrics, and — optionally — the document's text cues. The cues are the one
//         input that is not part of the song: a remark a musician writes on a chart belongs to the
//         DOCUMENT, and no song carries it. They arrive here because the engine is the only thing
//         that can give a cue the vertical room it needs, exactly as it already does for a bar's
//         own staff text, and they default to none so that a caller with no document gets the same
//         pages it always did.
// OUTPUTS: A list of PageLayout values with every bar, chord and text cue positioned. An empty
//          song yields an empty list rather than a blank page, so a caller cannot mistake "nothing
//          to draw" for "a page that came out empty".
// KEYWORDS: layout-engine, engraving, system-building, pagination, measure, pure-function,
//           text-cue, spike-s4
//
// Two properties of this pipeline are load-bearing for the rest of the system:
//
//   1. It is PURE. Same song, same style, same page size, same cues gives the same geometry on
//      every machine and every run. That is what makes a layout assertion exact, and it is why the
//      engine takes text metrics as an input rather than reaching for a font.
//   2. It is ADDRESSABLE. Every placed bar carries the (sectionId, barIndex) that names it in the
//      song, and every placed chord carries the [AnchoredPlace] it was drawn from. An annotation
//      anchored in the song model can therefore be drawn at the right place without either side
//      knowing the other's coordinates — and a chord's place IS the drawing's own address, because
//      the owner removed the grid and a mark's position is a coordinate rather than a cell index.
//
// What it deliberately does not do: rasterisation, glyph shaping, and play-order expansion. The
// first two belong to the renderer, and the third is not yet written (see the song model notes in
// docs/sdd.md). The engine lays out the bars as WRITTEN, which is the edit view.
//
// THE METRE IS A LABEL AND THIS FILE PLACES NOTHING BY IT. `Bar.timeSignature` is read for exactly
// two things now: the opening statement in the page header (`chartOpeningText`) and the meter-change
// sign a bar draws (`meter_sign.dart`). It does not divide a bar, it does not decide how wide a bar
// is, and it does not group beams. A bar's width follows its CONTENT: the furthest mark written in
// it, plus the bar's own padding. That is the owner's decision («Просто надпись») taken as far as the
// engraving can take it.
import '../key.dart';
import '../oplog/oplog.dart';
import '../song/bar.dart';
import '../song/section.dart';
import '../song/song.dart';
import '../song/time_signature.dart';
import '../spelling_table.dart';
import 'chart_header.dart';
import 'geometry.dart';
import 'layout_style.dart';
import 'page_layout.dart';
import 'staff_text_display.dart';
import 'text_metrics.dart';

/// Engraves a song into pages.
class LayoutEngine {
  /// Creates an engine with the given [style] and chord [spellingTable].
  const LayoutEngine({
    this.style = const LayoutStyle(),
    this.spellingTable = const SpellingTable(),
  });

  /// The spacing and metrics the engine uses.
  final LayoutStyle style;

  /// The rule that renders a chord to text before it is measured.
  final SpellingTable spellingTable;

  // PURPOSE: Lay a song out into as many pages as it needs.
  // INPUTS: song — the chart, in its written form. pageWidth and pageHeight — the page extent in
  //         logical pixels, including the margins the style reserves. cues — the text cues the
  //         document holds, already addressed by section and bar. They are an input rather than
  //         something the engine reaches for, because the song does not carry them: a cue is a
  //         remark a musician wrote in the DOCUMENT, and the engine is a pure function of the
  //         chart. Passing them in is what keeps the engine pure while still letting it reserve
  //         the vertical room the remarks need — the duty A44 already performs for a bar's own
  //         staff text.
  // OUTPUTS: The pages, in reading order, each with its systems and bars positioned, and with the
  //          cues of every bar placed in the rows reserved above it. An empty song yields an empty
  //          list. A cue naming a bar the song does not have is simply not placed, because there
  //          is no bar to reserve a row above.
  //
  //          If a single bar is wider than the content width it still forms a system of its own
  //          and overflows the page rather than being dropped or shrinking to nothing. That is a
  //          deliberate failure mode: a chord that runs off the edge is visible and reported, and
  //          a layout that silently omitted it would look correct while losing music. A system
  //          whose cue rows make it taller than the page overflows the BOTTOM on the same terms:
  //          the rows are reserved first and the page's edge is what gives way, because a cue that
  //          was dropped or drawn over a chord would be an invisible loss.
  // KEYWORDS: pagination, system-building, overflow-behaviour, reading-order, text-cue, cue-row
  /// Returns the pages [song] is engraved into.
  List<PageLayout> layout(
    Song song, {
    required double pageWidth,
    required double pageHeight,
    List<TextCue> cues = const <TextCue>[],
  }) => _engrave(
    song,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    cues: cues,
    drawScale: 1,
  );

  // PURPOSE: Engrave a song for a surface it will later be shrunk onto, which is the one place the
  //          page scale reaches the geometry.
  // INPUTS: song, the page extent in the ENGRAVED coordinate system, the cues, and drawScale — the
  //         factor the finished page will be multiplied by to reach the surface the musician sees.
  // OUTPUTS: The pages, with every rectangle in engraved coordinates and `PageLayout.scale` set to
  //          [drawScale] so one multiplication bridges the two systems.
  //
  //          WHY THE SCALE IS AN INPUT AND NOT ALWAYS 1. A cue's letters have a legibility floor
  //          of their own (`textCueMinLegibleScale`), so below a page scale of 0.8 they stop
  //          shrinking while the music keeps going: the row a cue needs is
  //          `letters / drawScale` pixels tall in the engraved system, and the reservation is
  //          therefore scale-aware. Engraving for a scale of 1 and then shrinking would reserve a
  //          row that is too short at exactly the scales where the defect was measured.
  // KEYWORDS: engraving, fit-scale, cue-row, scale-aware-reservation, pure-function
  List<PageLayout> _engrave(
    Song song, {
    required double pageWidth,
    required double pageHeight,
    required List<TextCue> cues,
    required double drawScale,
  }) {
    if (song.sections.isEmpty) {
      return const <PageLayout>[];
    }
    final double contentWidth = pageWidth - 2 * style.pageMargin;
    final double contentHeight = pageHeight - 2 * style.pageMargin;
    final List<_MeasuredBar> measured = _measureBars(song, cues);
    final List<_SystemPlan> systems = _buildSystems(measured, contentWidth);
    return _buildPages(
      song,
      measured.isEmpty ? null : measured.first.bar.timeSignature,
      systems,
      contentWidth,
      contentHeight,
      pageWidth,
      pageHeight,
      drawScale,
    );
  }

  /// The meter a musician assumes when a page writes nothing, and therefore the one a bar does not
  /// repeat at the head of every line.
  ///
  /// 4/4, and deliberately nothing else: 2/4, 3/4 and 6/8 are unusual enough in this repertoire to be
  /// worth a sign, and this model has no cut-time value. It is read by [_showsMeterSign] and by
  /// nothing else, and no geometry is measured from it — the owner ruled the meter is a label that
  /// divides nothing («Просто надпись»).
  static const TimeSignature assumedMeter = TimeSignature.fourFour;

  /// The smallest fraction of the requested page size the FIT mode will shrink to.
  ///
  /// Below this the chord line stops being readable at arm's length on the tablet this is built
  /// for, and a chart that has been shrunk past it is worse than one that is honestly reported as
  /// not fitting. The value is a product decision, not a measurement: 50% of a 15-pixel chord
  /// symbol is 7.5 logical pixels, which is about 16 physical pixels at the reference tablet's
  /// 2.125 device pixel ratio.
  static const double minLegibleScale = 0.5;

  // PURPOSE: Put a whole song on one page, scaled down rather than paginated, which is what a
  //          musician reading a chart on stage asks for when the tune is short enough.
  // INPUTS: song — the chart. pageWidth and pageHeight — the surface the single page must fit
  //         inside, in logical pixels. minScale — the smallest scale that counts as legible; the
  //         default is [minLegibleScale]. cues — the document's text cues, for the same reason
  //         [layout] takes them: the rows they need are part of the height that has to fit.
  // OUTPUTS: A [FitOutcome]. It fits when the whole song lands on one page at a scale of at least
  //          [minScale], and the outcome then carries that page and its scale. It does not fit
  //          when even [minScale] leaves more than one page, and the outcome then carries no page
  //          and the smallest scale that was tried, so a caller can say how far off it is. A song
  //          with no bars reports that it does not fit rather than a blank page, matching the
  //          contract of [layout].
  //
  //          HOW THE SCALE IS FOUND. The page is re-engraved at `pageWidth / scale` by
  //          `pageHeight / scale`: a larger virtual page packs the systems wider, so fewer of
  //          them are needed, and shrinking the result by `scale` lands it on the real surface.
  //          That is why the scale lives on [PageLayout] as one factor between engraved
  //          coordinates and the surface, instead of the engine emitting pre-multiplied geometry
  //          that no longer matches the page it was laid out for. The largest workable scale is
  //          found by a fixed-count bisection, so the result is the same on every run. Each trial
  //          is engraved AT the scale it is testing, so a cue's row is sized by the letters the
  //          page will really show and the search sees the same height the reader will.
  // KEYWORDS: fit-page, one-page, auto-scale, bisection, legibility-floor, page-mode, cue-row
  /// Returns the single page [song] fits on, or why it does not.
  FitOutcome fitToPage(
    Song song, {
    required double pageWidth,
    required double pageHeight,
    double minScale = minLegibleScale,
    List<TextCue> cues = const <TextCue>[],
  }) {
    if (song.sections.isEmpty || minScale <= 0 || minScale > 1) {
      return const FitOutcome(page: null, scale: 1, fits: false);
    }
    final List<PageLayout> asRequested = layout(
      song,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      cues: cues,
    );
    if (asRequested.length == 1) {
      // Already one page at full size, so no shrinking is needed and none is done: a chart is
      // never enlarged past the surface it was given.
      return FitOutcome(page: asRequested.single, scale: 1, fits: true);
    }
    if (asRequested.isEmpty ||
        !_fitsOnOnePage(song, pageWidth, pageHeight, minScale, cues)) {
      return FitOutcome(page: null, scale: minScale, fits: false);
    }
    double low = minScale;
    double high = 1;
    for (int step = 0; step < 24; step++) {
      final double mid = (low + high) / 2;
      if (_fitsOnOnePage(song, pageWidth, pageHeight, mid, cues)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final PageLayout raw = _engrave(
      song,
      pageWidth: pageWidth / low,
      pageHeight: pageHeight / low,
      cues: cues,
      drawScale: low,
    ).single;
    return FitOutcome(page: raw, scale: low, fits: true);
  }

  // PURPOSE: Answer whether the song would be one page if it were engraved at [scale] and shrunk
  //          back onto the caller's surface.
  // INPUTS: song, the surface size, the scale to test, and the cues — which are engraved at that
  //         scale too, because a cue's row is taller in engraved pixels the smaller the scale.
  // OUTPUTS: True when the enlarged page needs no more than one page.
  // KEYWORDS: fit-test, virtual-page, single-page, scale-aware-cue-row
  bool _fitsOnOnePage(
    Song song,
    double pageWidth,
    double pageHeight,
    double scale,
    List<TextCue> cues,
  ) =>
      _engrave(
        song,
        pageWidth: pageWidth / scale,
        pageHeight: pageHeight / scale,
        cues: cues,
        drawScale: scale,
      ).length ==
      1;

  // PURPOSE: Report the width a bar needs for its content. Exposed because the bar width is the
  //          unit a layout test reasons in, and because a caller sizing a single bar should not
  //          have to lay out a whole song to find out.
  // INPUTS: bar — the bar to measure, including its own [Bar.size]. key — the key its chords are
  //         spelled in, which affects the width because `Bb` and `A#` are different strings.
  // OUTPUTS: The bar's width as the engine will draw it, which is its natural width multiplied by
  //          its [BarSize] factor: never less than the style's minimum bar width, and a bar at
  //          [BarSize.natural] is exactly the number this returned before the factor existed. A bar
  //          with no chords measures to the minimum, because an empty cell still reserves room. A
  //          bar whose staff text is wider than its cells widens to hold that text as DISPLAYED —
  //          the `*NN` prefix and the exporter's padding are gone (see `displayStaffText`), so the
  //          layout does not reserve room for words it will not draw.
  //
  //          THIS IS THE SAME ARITHMETIC THE ENGRAVING USES, not a second copy of it: the private
  //          [_barWidth] is the one implementation and this method is its way out of the library,
  //          which is what lets a caller ask "how wide will this bar be" and get the width the page
  //          will really give it.
  // KEYWORDS: bar-measurement, natural-width, minimum-width, key-dependent-width, staff-text,
  //           bar-size, one-implementation
  /// Returns the width [bar] needs when its chords are spelled in [key].
  double measureBar(Bar bar, Key key) => _barWidth(bar, key);

  // PURPOSE: Answer the width a bar needs, given its already-measured staff-text lines, so that the
  //          width reserved for the words and the box the words are placed in come from ONE
  //          measurement rather than two calls that happen to agree.
  // INPUTS: bar — the bar, whose own [Bar.size] decides how many times its natural width it takes.
  //         key — the key its chords are spelled in. staffLines — the bar's staff text in display
  //         form with its measured sizes, from [_measureStaffText].
  // OUTPUTS: The bar's width: the furthest piece of content plus the bar's own right padding, or
  //          the width its widest staff line needs, whichever is larger, floored at the style's
  //          minimum bar width and then multiplied by [Bar.size]'s factor. A bar at
  //          [BarSize.natural] is returned as the very same double as before the factor existed, so
  //          every chart that never resized a bar engraves the page it always did.
  //
  //          THE WIDTH FOLLOWS THE CONTENT, and that is the visible consequence of removing the
  //          grid: a bar's width used to be "one minimum column per beat of the meter, widened by
  //          any chord written past it", so a 4/4 bar was four columns wide whether it held one
  //          chord or six. Now it is exactly as wide as the furthest thing written in it, which
  //          means a bar holding one chord is a THIRD narrower than it was and the page reads as
  //          music rather than as a form with blanks in it.
  //
  //          WHAT COUNTS AS CONTENT, and why each thing is here. A CHORD contributes its own drawn
  //          right edge: the x the bar's chord row puts it at plus the width its symbol measures —
  //          and the drawn x is the row's own number, so a symbol the minimum-gap rule has moved
  //          right is reserved for where it is really drawn, not where it is stored. Staff text
  //          contributes its own line, as it always did, because a phrase wider than the bar would
  //          otherwise be measured into a box that does not hold it. NOTHING ELSE DOES: a text cue
  //          hangs ABOVE the bar in a row the page gives up, a document remark is not part of the
  //          music, a bar SIGN lives in the lane the chords leave and never widens the bar, and
  //          handwriting has its own coordinate space. The meter contributes NOTHING — it is not read
  //          here at all.
  //
  //          THIS FUNCTION IS THE ONLY PLACE A BAR'S WIDTH IS DECIDED, and the factor is applied
  //          HERE and nowhere else on purpose. Everything the width feeds already derives from the
  //          rectangle this number becomes: the chord x positions, the text cues, the hit test's
  //          rectangle and the bar rectangle an ink stroke is anchored against. A second place that
  //          knew about the factor — a painter multiplying a bar it drew, or a hit test adjusting for
  //          a resized bar — would be the second source of truth for the coordinate system's one
  //          load-bearing number, which is the defect A33 and A47 already paid for once here.
  //
  //          WHY THE FACTOR MULTIPLIES THE FLOORED WIDTH rather than being folded into the paddings:
  //          the surplus a wider bar gets then widens the whole bar, which is what gives a musician
  //          who asked for more room somewhere to write. Scaling only the padding would widen the
  //          gap beside the first mark and leave the middle of the bar exactly as it was.
  // KEYWORDS: bar-width, content-driven, follow-the-content, staff-text-room, single-measurement,
  //           minimum-width, bar-size, width-multiplier, single-source-of-truth, metre-not-read
  double _barWidth(Bar bar, Key key) => _barWidthOf(bar, _chordRow(bar, key));

  // PURPOSE: Turn an already-laid-out chord row into the width its bar needs, so the width and the
  //          drawing come from the same row rather than from two measurements that must agree.
  // INPUTS: bar — the bar, whose own `size` decides how many times its natural width it takes.
  //         chordRow — the bar's chord row, from [_chordRow], with the drawn left edge of every
  //         symbol already resolved.
  // OUTPUTS: The bar's width: the furthest drawn right edge in the row plus the bar's trailing
  //          padding, floored at [LayoutStyle.barMinWidth] and multiplied by [BarSize.factor]. A bar
  //          with no chord is the floor, and a bar at [BarSize.natural] is returned as the very same
  //          double it was before the factor existed.
  // KEYWORDS: bar-width, chord-row, trailing-padding, floor, bar-size-factor
  double _barWidthOf(Bar bar, List<_ChordCell> chordRow) {
    double content = 0;
    for (final _ChordCell cell in chordRow) {
      final double right = cell.left + cell.size.width;
      if (right > content) {
        content = right;
      }
    }
    final double natural = content + style.barPadding;
    final double floored = natural < style.barMinWidth
        ? style.barMinWidth
        : natural;
    // The natural bar is returned untouched rather than multiplied by 1. Multiplication by 1 is
    // exact for every double, but comparing the factors first keeps the promise visible in the code:
    // a chart of unresized bars computes the identical geometry it computed before this property
    // existed, not merely an equal one.
    final double factor = bar.size.factor;
    return factor == 1 ? floored : floored * factor;
  }

  // PURPOSE: Lay one bar's chord row out ONCE — the string of every mark, the box it measures to and
  //          the x it is DRAWN at — so that the width the bar reserves and the symbols the painter
  //          draws come from one computation instead of two that have to agree.
  // INPUTS: bar — the bar whose `chords` to lay out, in model order. key — the key its symbols are
  //         spelled in, which changes the strings and therefore the widths.
  // OUTPUTS: One [_ChordCell] per mark, in model order, with its left edge RELATIVE to the bar's
  //          left edge. Empty for a bar with no chord.
  //
  //          A SYMBOL IS DRAWN AT ITS OWN STORED X, AND NEVER ON TOP OF THE ONE BEFORE IT. A mark's
  //          `offsetX` is its TIME — the written position the importer read out of the source — and
  //          it is data: saved, reopened and compared. `LayoutStyle.chordSpacing` is the smallest gap
  //          at which two symbols still read as two words, and a symbol whose stored x would put it
  //          nearer than that to the previous one's right edge is drawn at that edge plus the gap
  //          instead. The rule therefore only ever moves a symbol LATER, never earlier: it cannot
  //          make a chord look as though it sounds before its time, and it cannot reorder a bar.
  //
  //          WHY THE STORED X IS NOT REWRITTEN INSTEAD. Two reasons, and both make this a DRAWING
  //          rule rather than an import rule. The gap depends on the FONT, and the document must not:
  //          the same `.irealb` imported on two devices must produce the same chart, and the importer
  //          has no font by design (see `irealChordX`). And a bar's stored x is what a saved file
  //          carries, so rewriting it would re-engrave the owner's book — 1 103 stored positions —
  //          to repair a defect of the page. The page is derived; the document is not.
  //
  //          WHY A FIXED IMPORTER SLOT WOULD NOT HAVE DONE. A symbol's width is unbounded: `F7#11` is
  //          four times `Db`, and `Gb7#11` wider still, so no constant number of points per cell can
  //          keep every pair apart. The engraver is the only thing that has measured the string it is
  //          about to draw, so it is the only thing that can answer this.
  // KEYWORDS: chord-row, drawn-x, minimum-gap, no-overlap, single-computation, written-position,
  //           document-unchanged
  List<_ChordCell> _chordRow(Bar bar, Key key) {
    final List<_ChordCell> cells = <_ChordCell>[];
    double previousRight = 0;
    for (final ChordMark mark in bar.chords) {
      final String text = mark.chord.render(key, spellingTable);
      final LayoutSize size = style.textMetrics.measure(
        text,
        ChartTextRole.chord,
      );
      double left = mark.offsetX;
      if (cells.isNotEmpty) {
        final double earliest = previousRight + style.chordSpacing;
        if (left < earliest) {
          left = earliest;
        }
      }
      previousRight = left + size.width;
      cells.add(
        _ChordCell(
          text: text,
          size: size,
          left: left,
          offsetY: mark.place.offsetY,
          small: mark.size == ChordSize.small,
        ),
      );
    }
    return cells;
  }

  // PURPOSE: Report the line height of one chord symbol in this style, which is the vertical extent
  //          of the chord row and therefore the number every other row inside a bar is measured
  //          against.
  // INPUTS: None.
  // OUTPUTS: The measured height of the chord role at zero width. An empty string measures to a
  //          zero-WIDTH box at the role's line height, which is exactly the number wanted here and is
  //          guaranteed by the `TextMetrics` contract for every implementation.
  // KEYWORDS: chord-row, line-height, metrics, row-measurement
  double get _chordLineHeight =>
      style.textMetrics.measure('', ChartTextRole.chord).height;

  // PURPOSE: Read a bar's stored staff text into the lines it shows, measuring each line once so
  //          that the room reserved for it and the box it is placed in are the same number.
  // INPUTS: bar — the bar whose `Bar.staffText` to read.
  // OUTPUTS: One entry per stored line that has words to show, in model order, carrying the display
  //          string and the size it measured to. A stored entry whose display form is empty (a bare
  //          `*NN`, or whitespace alone) is skipped: it names a position and says nothing, and
  //          placing a zero-width line would reserve a line height for nothing. An empty input
  //          yields an empty list.
  //
  //          THE STRING MEASURED IS THE STRING DRAWN: `displayStaffText` is the one place that
  //          decides the display form, so the prefix and the padding are gone before the measurement
  //          and the box the page reserves is the box the reader's words occupy.
  // KEYWORDS: staff-text, display-form, measurement, empty-skip, single-source
  List<_MeasuredStaffText> _measureStaffText(Bar bar) {
    final List<_MeasuredStaffText> lines = <_MeasuredStaffText>[];
    for (final String stored in bar.staffText) {
      final String text = displayStaffText(stored);
      if (text.isEmpty) {
        continue;
      }
      lines.add(
        _MeasuredStaffText(
          text: text,
          size: style.textMetrics.measure(text, ChartTextRole.staffText),
        ),
      );
    }
    return lines;
  }

  // PURPOSE: Turn a bar's measured staff text into placed boxes, stacked upward from the bar's bottom
  //          edge so several phrases stay inside the bar instead of running past the system below.
  //          The painter draws these boxes and nothing else, which is what makes the reserved room
  //          and the drawn words one value.
  // INPUTS: lines — the bar's measured lines, from [_measureStaffText]. bounds — where the bar sits.
  // OUTPUTS: One placed line per measured line, in the same order, each with its display words and
  //          its box. The first sits [LayoutStyle.staffTextBottomInset] above the bar's bottom and
  //          each later one is stacked above it. An empty input yields an empty list.
  //
  //          THE STACK FACES UPWARD FOR A REASON: the row nearest the bar's own lane is the first
  //          line the file wrote, so a bar carrying `Solo` and `4×` reads them in the order they were
  //          written, bottom to top, instead of inverting them.
  // KEYWORDS: staff-text, placement, stacking-upward, display-form, painter-contract
  List<PlacedStaffText> _placeStaffText(
    List<_MeasuredStaffText> lines,
    LayoutRect bounds,
  ) {
    if (lines.isEmpty) {
      return const <PlacedStaffText>[];
    }
    final List<PlacedStaffText> placed = <PlacedStaffText>[];
    double top = bounds.bottom - style.staffTextBottomInset;
    for (final _MeasuredStaffText line in lines) {
      top -= line.size.height;
      placed.add(
        PlacedStaffText(
          text: line.text,
          bounds: LayoutRect.fromLTWH(
            bounds.left + style.staffTextInset,
            top,
            line.size.width,
            line.size.height,
          ),
        ),
      );
    }
    return placed;
  }

  // PURPOSE: Report the vertical room a bar must give up for the words written on it, which is the
  //          stack of its staff-text lines plus the air under the last one.
  // INPUTS: lines — the bar's measured staff text.
  // OUTPUTS: Zero for a bar with nothing to say; otherwise the sum of the line heights plus
  //          [LayoutStyle.staffTextBottomInset]. The sign lane inside the bar stops where this ends,
  //          so a sign and a phrase on one bar never cover each other.
  // KEYWORDS: staff-text, reserved-room, stack-height, sign-lane
  double _staffTextHeight(List<_MeasuredStaffText> lines) {
    if (lines.isEmpty) {
      return 0;
    }
    double height = style.staffTextBottomInset;
    for (final _MeasuredStaffText line in lines) {
      height += line.size.height;
    }
    return height;
  }

  // PURPOSE: Decide whether one bar's meter is DRAWN, which is owner decision D22's rendering half
  //          taken as far as the engraving can take it: a chart that changes meter must SAY SO at the
  //          bar where it changes, and a chart that spends a whole line in an unusual meter must say
  //          so again at the start of that line, where a musician's eye returns.
  // INPUTS: meter — the bar's own meter. preceding — the meter of the bar before it in reading
  //         order, or null when this is the chart's first bar. opensSystem — whether this bar begins
  //         a line. headerStatesOpeningMeter — whether the page's own header line has already printed
  //         this bar's meter as the meter the music opens in.
  // OUTPUTS: True when the sign is drawn; false otherwise, and false for EVERY bar of a 4/4 chart,
  //          which is what keeps such a page identical to the page drawn before signs existed.
  //          Never throws: a bar is signed or it is not, and there is no third answer.
  //
  //          THE RULE, WRITTEN OUT, BECAUSE IT IS A DECISION AND NOT AN IMPLEMENTATION DETAIL:
  //            1. A bar whose meter differs from the bar BEFORE it in reading order is signed. That is
  //               the bar where the meter CHANGES, and the one place a musician looks for it.
  //            2. A bar that OPENS A SYSTEM is signed when its meter is not [assumedMeter]. 4/4 is the
  //               meter a musician assumes when nothing is written — it is the one `Bar.timeSignature`
  //               defaults to, and the meter of every bar of the owner's book but one — so writing it
  //               at the head of every line would be a column of identical symbols saying nothing.
  //            3. The chart's FIRST bar is treated as opening a system, and is NOT signed when the
  //               page's header has already stated its meter one line above. Printing the same fact
  //               twice within a centimetre is one fact in two places, and the header is the place
  //               the reader meets first.
  //
  //          WHAT IT DELIBERATELY DOES NOT DO: sign every bar, or divide anything. The meter is
  //          «Просто надпись» — a label — and nothing in this engine measures from it.
  // KEYWORDS: meter-sign, change-bar, system-start, assumed-meter, header-suppression, label-only,
  //           no-division
  static bool _showsMeterSign({
    required TimeSignature meter,
    required TimeSignature? preceding,
    required bool opensSystem,
    required bool headerStatesOpeningMeter,
  }) {
    if (preceding == null) {
      return !headerStatesOpeningMeter && meter != assumedMeter;
    }
    if (meter != preceding) {
      return true;
    }
    return opensSystem && meter != assumedMeter;
  }

  // PURPOSE: Read every bar of the song once, in reading order, into the numbers and the measured
  //          strings the rest of the engraving uses — its width, its chord row, its staff text, its
  //          cues, whether it opens a section and whether the musician ended a line after it.
  // INPUTS: song — the chart. cues — the document's text cues, which hang on bars by address.
  // OUTPUTS: One [_MeasuredBar] per bar of the song, in reading order, with every measurement taken
  //          ONCE so that the room reserved and the box drawn are the same numbers. Each bar also
  //          carries the meter of the bar BEFORE it, because the meter sign rule compares the two and
  //          a painter drawing one page cannot see the previous page.
  // KEYWORDS: bar-measurement, reading-order, single-pass, preceding-meter, chord-row, staff-text
  List<_MeasuredBar> _measureBars(Song song, List<TextCue> cues) {
    final Map<String, List<TextCue>> cuesByBar = _cuesByBar(cues);
    final List<_MeasuredBar> measured = <_MeasuredBar>[];
    TimeSignature? precedingMeter;
    for (final Section section in song.sections) {
      for (int index = 0; index < section.bars.length; index++) {
        final Bar bar = section.bars[index];
        final List<_ChordCell> chordRow = _chordRow(bar, song.key);
        measured.add(
          _MeasuredBar(
            sectionId: section.id,
            barIndex: index,
            bar: bar,
            key: song.key,
            width: _barWidthOf(bar, chordRow),
            chordRow: chordRow,
            staffText: _measureStaffText(bar),
            precedingMeter: precedingMeter,
            textCues: _measureTextCues(
              cuesByBar[_barKey(section.id, index)] ?? const <TextCue>[],
            ),
            startsSection: index == 0,
            sectionLabel: index == 0 ? section.label.toString() : null,
            // Rule 3 of the line-breaking rules, read from the bar's own marks: the sign that says
            // the line ends after this bar. Read once while measuring so the system builder does not
            // have to know what a mark is.
            breaksLine: bar.marks.contains(BarMark.lineBreak),
          ),
        );
        precedingMeter = bar.timeSignature;
      }
    }
    return measured;
  }

  // PURPOSE: Group the document's cues by the bar they are anchored to, so laying a bar out can
  //          ask for its own remarks without scanning the whole document once per bar.
  // INPUTS: cues — every cue of the document, in document order.
  // OUTPUTS: The cues that have words, keyed by [LayoutEngine._barKey], each list in document
  //          order. A cue with empty words is DROPPED: it is the state the model documents as
  //          "inserted and not yet typed into", it draws nothing, and reserving a row for it would
  //          spend the page's height on a remark that is not there.
  // KEYWORDS: cue-grouping, bar-key, document-order, empty-skip, single-scan
  Map<String, List<TextCue>> _cuesByBar(List<TextCue> cues) {
    final Map<String, List<TextCue>> byBar = <String, List<TextCue>>{};
    for (final TextCue cue in cues) {
      if (cue.text.isEmpty) {
        continue;
      }
      final String key = _barKey(
        cue.place.anchor.sectionId,
        cue.place.anchor.bar,
      );
      (byBar[key] ??= <TextCue>[]).add(cue);
    }
    return byBar;
  }

  /// The key a cue and a bar meet on: the section identity and the bar index inside it.
  static String _barKey(String sectionId, int barIndex) =>
      '$sectionId\u0000$barIndex';

  // PURPOSE: Read a bar's cues into the rows it must reserve for them, measuring each one once so
  //          that the room reserved and the box drawn come from the same measurement — the rule
  //          [_measureStaffText] follows for the words a bar carries itself.
  // INPUTS: cues — this bar's cues, in document order, with their words already known non-empty.
  // OUTPUTS: One entry per cue, in the same order, carrying the words, the address it hangs on, the
  //          identity the document gave it and the size the words measured to at a page scale of 1.
  //          An empty input yields an empty list.
  // KEYWORDS: cue-measurement, text-cue-role, document-order, single-measurement
  List<_MeasuredTextCue> _measureTextCues(List<TextCue> cues) =>
      <_MeasuredTextCue>[
        for (final TextCue cue in cues)
          _MeasuredTextCue(
            id: cue.id,
            offsetX: cue.place.offsetX,
            text: cue.text,
            size: style.textMetrics.measure(cue.text, ChartTextRole.textCue),
          ),
      ];

  // PURPOSE: Pack bars into systems, honouring the owner's four line-breaking rules in one place.
  // INPUTS: measured — the bars in reading order with their widths and their own break flags.
  //         availableWidth — the width a system may occupy, which is the page's content width.
  // OUTPUTS: One plan per system. THE FOUR RULES, AND WHERE EACH IS APPLIED:
  //
  //            1. THE RIGHT EDGE OF THE PAGE IS THE HARD LIMIT. doesNotFit below breaks the line as
  //               soon as the next bar would take the system past vailableWidth. It is the one
  //               rule that is a MEASUREMENT rather than a decision, and it is reached after the two
  //               deliberate ones so a bar that follows a break is not pulled back onto a full line.
  //            2. A SECTION ALWAYS STARTS A NEW SYSTEM, even when the previous one is not full. A
  //               section heading names the music under it, and a heading sharing a line with the
  //               end of the previous section would be read as belonging to it. startsSection is
  //               set while measuring, on the first bar of every section.
  //            3. THE MUSICIAN MAY BREAK A LINE HIMSELF, through a bar mark — BarMark.lineBreak on
  //               the bar the line ends on (see that value for why the break is a mark rather than a
  //               layout setting). It breaks even when the line is half full, which is the whole of
  //               what asking for one means.
  //            4. HANDWRITING TRAVELS WITH ITS BAR (owner decision D32), which is NOT ENFORCED HERE
  //               because it cannot be broken here: a stroke is anchored to a bar and its points are
  //               bar-local, so re-flowing the page moves it with the music it was written over. This
  //               function moves bars between systems, and the ink follows by construction. A rule
  //               that had to be checked would be a rule the coordinate system had stopped giving.
  //
  //          A bar wider than the page still forms a system of its own and overflows rather than
  //          being dropped or shrunk; that is the documented failure mode of [layout].
  // KEYWORDS: system-building, greedy-packing, section-break, line-break, bar-mark, hard-right-edge,
  //           ink-travels-with-its-bar, d32, four-rules
  List<_SystemPlan> _buildSystems(
    List<_MeasuredBar> measured,
    double availableWidth,
  ) {
    final List<_SystemPlan> systems = <_SystemPlan>[];
    List<_MeasuredBar> current = <_MeasuredBar>[];
    double currentWidth = 0;

    void flush() {
      if (current.isEmpty) {
        return;
      }
      systems.add(
        _SystemPlan(
          bars: current,
          sectionId: current.first.startsSection
              ? current.first.sectionId
              : null,
          sectionLabel: current.first.sectionLabel,
        ),
      );
      current = <_MeasuredBar>[];
      currentWidth = 0;
    }

    for (final _MeasuredBar bar in measured) {
      // Rule 2 and rule 3 are DELIBERATE breaks and are tested before the measurement, so a line the
      // musician ended stays ended however much room is left on it.
      final bool sectionStarts = current.isNotEmpty && bar.startsSection;
      final bool musicianBroke = current.isNotEmpty && current.last.breaksLine;
      // Rule 1, and only when no deliberate break already applies.
      final bool doesNotFit =
          current.isNotEmpty && currentWidth + bar.width > availableWidth;
      if (sectionStarts || musicianBroke || doesNotFit) {
        flush();
      }
      current.add(bar);
      currentWidth += bar.width;
    }
    flush();
    return systems;
  }

  List<PageLayout> _buildPages(
    Song song,
    TimeSignature? openingMeter,
    List<_SystemPlan> systems,
    double contentWidth,
    double contentHeight,
    double pageWidth,
    double pageHeight,
    double drawScale,
  ) {
    final List<PageLayout> pages = <PageLayout>[];
    List<PlacedSystem> currentSystems = <PlacedSystem>[];
    // THE HEADER IS THE FIRST PAGE'S, AND IT IS PAID FOR BY THE MUSIC BELOW IT. Its band is placed
    // before the first system and the first system starts under it, so nothing is drawn over
    // anything and the room it takes is the room it measured.
    PlacedChartHeader? header = _chartHeader(song, openingMeter, contentWidth);
    double y = header == null
        ? style.pageMargin
        : header.bounds.bottom + style.chartHeaderGap;
    int pageIndex = 0;
    bool firstOnPage = true;

    void flushPage() {
      if (currentSystems.isEmpty) {
        return;
      }
      pages.add(
        PageLayout(
          index: pageIndex,
          size: LayoutSize(pageWidth, pageHeight),
          systems: currentSystems,
          header: header,
          scale: drawScale,
        ),
      );
      pageIndex++;
      currentSystems = <PlacedSystem>[];
      // Every page after the first states nothing about the chart: the key and the meter are a fact
      // a reader needs once, so a page that began the statement has paid for it and the next one
      // gives up no room.
      header = null;
      y = style.pageMargin;
      firstOnPage = true;
    }

    for (final _SystemPlan plan in systems) {
      final double height = _systemHeight(plan, drawScale);
      final double spacing = firstOnPage ? 0 : style.systemSpacing;
      // A system that does not fit this page, and a page that already holds one, means a new page.
      if (!firstOnPage &&
          y + spacing + height > style.pageMargin + contentHeight) {
        flushPage();
      }
      // A system taller than a whole page cannot be made to fit by pagination, because a page is
      // the most there is. It is then placed with the MUSIC's bottom on the content box's bottom, so
      // the overflow comes off its TOP — its section label, its cue rows and its brackets — and the
      // chord line stays on the page. That is the same priority the whole feature rests on: a remark
      // gives way to the chart, never the other way round, and a performance instruction gives way to
      // the music it is written about. A page too short for even one chord line is the one case this
      // cannot help, and there the system keeps its ordinary place and overflows the bottom.
      //
      // THE HEADER IS ON THE SAME LADDER AND AT THE SAME RUNG as the label and the cue rows, which is
      // stated rather than hidden: on a page too short to hold one system, the system's top is put
      // where the music's bottom forces it and the header — which sits in the top margin — is what
      // the system then reaches over. Nothing is more honest available: a page that cannot hold one
      // line of music has no room to state anything about the music, and drawing the header over the
      // chord line would hide the very thing the page exists to show.
      final double musicHeight = _musicHeight(plan);
      final bool overflowsPage =
          height > contentHeight && musicHeight <= contentHeight;
      final double top = overflowsPage
          ? style.pageMargin + contentHeight - height
          : (firstOnPage ? y : y + spacing);
      currentSystems.add(
        _placeSystem(plan, top, drawScale, statesOpening: header != null),
      );
      y = top + height;
      firstOnPage = false;
    }
    flushPage();
    return pages;
  }

  // PURPOSE: Publish the line stating the chart's key and its opening meter, in the band the first
  //          page gives up above its music, so that the one fact a page could not tell a musician is
  //          on the page and not only in the chrome beside it.
  // INPUTS: song — the chart, whose key is what every chord on the page is spelled against.
  //         openingMeter — the meter of the chart's FIRST bar in reading order, or null when the
  //         chart has no bar at all. contentWidth — the width between the page's margins, which the
  //         published band spans.
  // OUTPUTS: A [PlacedChartHeader] on the page where the music begins, or null when there is no
  //          meter to state — a chart with no bar has nothing to say about what it is written in,
  //          and no page is produced for it anyway.
  //
  //          THE METER IT STATES IS THE FIRST BAR'S, and that is the definition rather than a
  //          simplification: a chart's meter is whatever its first bar is counted in, and a bar that
  //          changes it is signed at the bar where it changes ([_showsMeterSign]). What the header
  //          says is the state the music opens in, which is what a printed chart's opening time
  //          signature says too.
  // KEYWORDS: chart-header, opening-statement, key-and-meter, first-page-only, no-collision,
  //           section-letter, first-bar-independent
  PlacedChartHeader? _chartHeader(
    Song song,
    TimeSignature? openingMeter,
    double contentWidth,
  ) {
    if (openingMeter == null) {
      return null;
    }
    final String text = chartOpeningText(song.key, openingMeter);
    final LayoutSize size = style.textMetrics.measure(
      text,
      ChartTextRole.chord,
    );
    return PlacedChartHeader(
      text: text,
      bounds: LayoutRect.fromLTWH(
        style.pageMargin,
        style.pageMargin,
        contentWidth,
        size.height,
      ),
    );
  }

  // PURPOSE: Report the height of everything a system must draw BELOW its label, its cue rows and
  //          its brackets: the bars' band.
  // INPUTS: plan — the system, whose bars decide whether the band has to be taller than the style's.
  // OUTPUTS: [LayoutStyle.barHeight], or a taller band when a bar on the system carries both its
  //          chords and words AND a sign that needs the room between them. For a chart of bars that
  //          carry no such combination — every bar of the owner's book, and every plain chart — this
  //          is exactly [LayoutStyle.barHeight], which is the number the overflow rule compared
  //          before signs were drawn.
  //
  //          WHY THE BAND GROWS AT ALL RATHER THAN THE SIGN SHRINKING TO NOTHING. A bar's band holds
  //          three rows and they cannot be reordered: the chord row at the head (that is where a
  //          chart writes its harmony), the sign lane under it, and the words at the foot. When a bar
  //          carries a chord, a sign AND a phrase, the three do not fit the style's 52 points — so
  //          the page gives the band the few points it needs instead of squeezing the sign down to a
  //          size at which a musician cannot tell a simile mark from a speck. The cost is a few
  //          points on the systems that hold such a bar and nothing anywhere else.
  // KEYWORDS: music-height, band-growth, three-rows, sign-lane, overflow-floor, unchanged-chords-only
  double _musicHeight(_SystemPlan plan) {
    double extra = 0;
    for (final _MeasuredBar bar in plan.bars) {
      if (!_hasLaneSign(bar)) {
        continue;
      }
      final double needed =
          _signLaneTop(bar) + _signSide + _staffTextHeight(bar.staffText);
      final double over = needed - style.barHeight;
      if (over > extra) {
        extra = over;
      }
    }
    return style.barHeight + extra;
  }

  // PURPOSE: Report the size of the square a drawn bar sign occupies, which is one number for the
  //          whole page rather than a per-bar fit.
  // INPUTS: None; reads [LayoutStyle.signSizeLimit].
  // OUTPUTS: The limit itself — a sign is drawn at the size a musician can read from a stand, not at
  //          the chord's line height, because a simile mark at 17 points inside a 52-point bar is a
  //          speck beside the symbols it is telling him to repeat. The band gives a bar the few
  //          points it needs when a bar cannot hold both its chords, its sign and its words (see
  //          [_musicHeight]), so the size is decided here and the room follows it rather than the
  //          other way round.
  // KEYWORDS: sign-size, legibility-first, band-follows-sign, one-number-per-page
  double get _signSide => style.signSizeLimit;

  // PURPOSE: Report where a bar's sign lane begins, measured from the bar's own top edge, so that the
  //          room a sign needs and the room the band reserves are decided by one rule.
  // INPUTS: bar — the measured bar.
  // OUTPUTS: The bottom of the chord row when the bar carries chords, and the bar's own top when it
  //          carries none — a bar with no harmony has its whole band free for the sign, which is the
  //          state of every bar in the owner's book that carries a simile mark.
  // KEYWORDS: sign-lane, chord-row-bottom, free-band, single-rule
  double _signLaneTop(_MeasuredBar bar) =>
      bar.chordRow.isEmpty ? 0 : style.chordRowTopInset + _chordLineHeight;

  // PURPOSE: Answer whether a bar carries any sign that lives in the sign lane, which is what decides
  //          whether its band may need to grow.
  // INPUTS: bar — the measured bar.
  // OUTPUTS: True for a simile mark, a slash repeat, or any of the three drawn music marks. False for
  //          the no-chord sign (which sits in the chord row, where a chord would be) and for the meter
  //          sign of a bar that also carries chords — neither is placed in the lane by [_placeSigns].
  //          A bar with no lane sign never grows the band.
  // KEYWORDS: sign-lane, occupancy, band-growth-decision
  bool _hasLaneSign(_MeasuredBar bar) =>
      bar.bar.repeatPrevious != RepeatPrevious.none ||
      bar.bar.slashRepeat ||
      bar.bar.marks.contains(BarMark.segno) ||
      bar.bar.marks.contains(BarMark.coda) ||
      bar.bar.marks.contains(BarMark.fermata);

  // PURPOSE: Report how tall a system is, which is the bands reserved above its stave plus its music.
  // INPUTS: plan — the system. drawScale — the page scale the engraved coordinates will be multiplied
  //         by, which is what turns a cue's surface-sized letters into engraved room.
  // OUTPUTS: The system's height. A system with no cue, no heading and no ending is exactly the
  //          style's stave height, which is what keeps a page of plain bars laid out as it always was.
  // KEYWORDS: system-height, cue-band, section-label, volta-band, stave, unchanged-when-empty
  double _systemHeight(_SystemPlan plan, double drawScale) =>
      (plan.sectionLabel == null ? 0 : style.sectionLabelHeight) +
      _cueBandHeight(plan, drawScale) +
      _voltaBandHeight(plan) +
      _musicHeight(plan);

  // PURPOSE: Report the room a system gives up for the alternative-ending brackets of its bars.
  // INPUTS: plan — the system.
  // OUTPUTS: [LayoutStyle.voltaBandHeight] when any bar on the system sits under a bracket, and zero
  //          otherwise — so a chart without endings, and every system of one that has none, engraves
  //          exactly the page it engraved before brackets were drawn.
  // KEYWORDS: volta-band, ending, per-system, unchanged-when-absent
  double _voltaBandHeight(_SystemPlan plan) {
    for (final _MeasuredBar bar in plan.bars) {
      if (bar.bar.volta != null) {
        return style.voltaBandHeight;
      }
    }
    return 0;
  }

  // PURPOSE: Report the vertical room one system must give up for the cues of the bars on it, which
  //          is the tallest stack any one of its bars needs.
  // INPUTS: plan — the system. drawScale — the page scale, for the reason [_cueRowHeight] records.
  // OUTPUTS: The band height. Zero when no bar on the system carries a cue, so a page without
  //          remarks is engraved exactly as it was.
  //
  //          WHY THE MAXIMUM AND NOT THE SUM. A system's stave is one horizontal row: every bar on
  //          it must start at the same height or the barlines would not line up. So the band is
  //          the deepest stack any single bar needs, and each bar's own cues are stacked inside it
  //          from the stave upward. Two cues on one bar push only that bar's stack up; a bar with
  //          one cue is not lifted because its neighbour has three.
  // KEYWORDS: cue-band, per-bar-stack, maximum, system-alignment, reservation
  double _cueBandHeight(_SystemPlan plan, double drawScale) {
    double band = 0;
    for (final _MeasuredBar bar in plan.bars) {
      double rows = 0;
      for (final _MeasuredTextCue cue in bar.textCues) {
        rows += _cueRowHeight(cue, drawScale);
      }
      if (rows > band) {
        band = rows;
      }
    }
    return band;
  }

  // PURPOSE: Report how much engraved height one cue's row needs.
  // INPUTS: cue — the cue with the size its words measured to at a page scale of 1. drawScale —
  //         the page scale the row is engraved for.
  // OUTPUTS: The row height in the page's engraved coordinates: the words' line height and the
  //          plate's two vertical insets, all measured at the size the cue is DRAWN, divided by
  //          [drawScale].
  //
  //          THE DIVISION IS THE WHOLE POINT. The letters are drawn in surface pixels and never
  //          below [textCueMinLegibleScale] of their size, so below a page scale of 0.8 they stop
  //          shrinking while the music keeps going. The engraved box that lands at that surface
  //          size is therefore `surface / drawScale`, and it grows as the page shrinks. Reserving
  //          the undivided line height would under-reserve at exactly the fitted scales where the
  //          plate was measured covering the chord.
  // KEYWORDS: cue-row-height, letter-floor, surface-to-engraved, scale-aware, plate-inset
  double _cueRowHeight(_MeasuredTextCue cue, double drawScale) =>
      (cue.size.height * _cueLetterScale(drawScale) + 2 * textCuePlateInsetY) /
      drawScale;

  // PURPOSE: Report the factor a cue's letters are drawn at, which is the page scale with the cue's
  //          own legibility floor under it.
  // INPUTS: drawScale — the page scale.
  // OUTPUTS: [drawScale], or [textCueMinLegibleScale] when the page is smaller. Never zero, for
  //          the reason the engine's own floor is never zero: a page the engine produces carries a
  //          scale of at least `minLegibleScale`.
  // KEYWORDS: letter-scale, legibility-floor, cue, single-decision
  double _cueLetterScale(double drawScale) =>
      drawScale < textCueMinLegibleScale ? textCueMinLegibleScale : drawScale;

  // PURPOSE: Place one system's bars, their chords, their signs, the words written on them, their
  //          cues and the alternative-ending brackets that span them, so that everything a musician
  //          reads off one line of the chart is published with a box the painter draws in.
  // INPUTS: plan — the system and its bars in reading order. top — the top of the band above the
  //         stave, in page coordinates. drawScale — the page scale the cue rows are engraved for.
  //         statesOpening — whether the page this system is on carries the chart's opening statement,
  //         which is what decides whether the chart's first bar repeats its meter in the bar itself.
  // OUTPUTS: The placed system. Every bar's rectangle is the full height of the band, so the barlines
  //          run the height of the music and a tap anywhere in the band names the bar.
  //
  //          THE BAND ABOVE THE STAVE IS FILLED TOP DOWN in one fixed order — heading, cue rows,
  //          brackets — because each of them can be absent and the ones that remain must not move:
  //          a page of bars with no cue keeps its heading where it always was, and a system with no
  //          ending keeps its bars where they were before brackets existed.
  PlacedSystem _placeSystem(
    _SystemPlan plan,
    double top,
    double drawScale, {
    required bool statesOpening,
  }) {
    final double labelHeight = plan.sectionLabel == null
        ? 0
        : style.sectionLabelHeight;
    final double cueBand = _cueBandHeight(plan, drawScale);
    final double voltaBand = _voltaBandHeight(plan);
    final double bandHeight = _musicHeight(plan);
    final double staveTop = top + labelHeight + cueBand + voltaBand;
    final List<PlacedBar> bars = <PlacedBar>[];
    double x = style.pageMargin;
    for (int index = 0; index < plan.bars.length; index++) {
      final _MeasuredBar measured = plan.bars[index];
      final LayoutRect bounds = LayoutRect.fromLTWH(
        x,
        staveTop,
        measured.width,
        bandHeight,
      );
      bars.add(
        PlacedBar(
          sectionId: measured.sectionId,
          barIndex: measured.barIndex,
          bounds: bounds,
          // The chords are placed from the SAME rectangle the bar was given, so the symbol's x and
          // the width the bar was measured to are one relationship and not two.
          chords: _placeChords(measured, bounds),
          signs: _placeSigns(
            measured,
            bounds: bounds,
            opensSystem: index == 0,
            statesOpening: statesOpening,
          ),
          staffText: _placeStaffText(measured.staffText, bounds),
          // A cue carries its own x, so placing it needs the bar's left edge and nothing else.
          textCues: _placeTextCues(
            measured.textCues,
            bounds,
            staveTop,
            drawScale,
          ),
        ),
      );
      x += measured.width;
    }
    return PlacedSystem(
      bounds: LayoutRect.fromLTWH(
        style.pageMargin,
        top,
        x - style.pageMargin,
        labelHeight + cueBand + voltaBand + bandHeight,
      ),
      bars: bars,
      sectionId: plan.sectionId,
      sectionLabel: plan.sectionLabel,
      // The heading's own band, published so that the painter does not have to guess how much of
      // the room above the stave belongs to the words rather than to the label. A system with no
      // cue has a band of exactly `sectionLabelHeight`, which is the band the painter used to infer
      // from the geometry, so a page without remarks is drawn as it always was.
      labelBand: plan.sectionLabel == null
          ? null
          : LayoutRect.fromLTWH(
              style.pageMargin,
              top,
              x - style.pageMargin,
              labelHeight,
            ),
      voltas: _placeVoltas(plan, bars, staveTop - voltaBand, voltaBand),
    );
  }

  // PURPOSE: Turn the alternative endings on one system into the brackets a painter draws, one per
  //          RUN of adjacent bars carrying the same number.
  // INPUTS: plan — the system, whose bars carry the model's endings. placed — the same bars with
  //         their rectangles, which is where a bracket's horizontal span comes from. bandTop — the
  //         top of the slab the page reserved for brackets. bandHeight — its height, zero when the
  //         system carries no ending at all.
  // OUTPUTS: One [PlacedVolta] per run, in reading order, spanning the run's bars from the left edge
  //          of the first to the right edge of the last. Empty when the system has no ending, and
  //          empty when the band has no height — a bracket with no room is not drawn rather than
  //          drawn over the chords below it.
  //
  //          A RUN IS NEVER CARRIED ACROSS A SYSTEM BREAK. An ending that spans a line break is drawn
  //          as one bracket per line, which is what a printed chart does and what the page can show:
  //          a bracket is a mark above a line of music, and a line is what a system is.
  List<PlacedVolta> _placeVoltas(
    _SystemPlan plan,
    List<PlacedBar> placed,
    double bandTop,
    double bandHeight,
  ) {
    if (bandHeight <= 0) {
      return const <PlacedVolta>[];
    }
    final List<PlacedVolta> voltas = <PlacedVolta>[];
    int start = -1;
    Volta? run;
    void closeRun(int endExclusive) {
      if (run == null || start < 0) {
        return;
      }
      final PlacedBar first = placed[start];
      final PlacedBar last = placed[endExclusive - 1];
      voltas.add(
        PlacedVolta(
          number: run!.number,
          bounds: LayoutRect.fromLTWH(
            first.bounds.left,
            bandTop,
            last.bounds.right - first.bounds.left,
            bandHeight,
          ),
        ),
      );
      start = -1;
      run = null;
    }

    for (int index = 0; index < plan.bars.length; index++) {
      final Volta? volta = plan.bars[index].bar.volta;
      if (volta == null) {
        closeRun(index);
        continue;
      }
      if (run != null && volta == run) {
        continue;
      }
      closeRun(index);
      start = index;
      run = volta;
    }
    closeRun(plan.bars.length);
    return voltas;
  }

  // PURPOSE: Place every sign a bar carries — the simile mark, the slash repeat, `N.C.`, the drawn
  //          music marks and the meter it changes to — as the row of boxes the painter draws, so the
  //          room a sign was given and the shape drawn in it are one value.
  // INPUTS: measured — the bar, with its chord row already laid out. bounds — its rectangle, whose
  //         height is the band the page reserved for it. opensSystem — whether it begins a line, which
  //         the meter rule needs. statesOpening — whether the page has already stated the opening
  //         meter in its header.
  // OUTPUTS: The signs to draw, in reading order from left to right inside the bar. Empty for a bar
  //          that carries none, which is most bars of most charts.
  //
  //          WHERE EACH ONE GOES, AND WHY THERE IS ONE RULE FOR ALL OF THEM. `N.C.` is the bar's
  //          HARMONY — it says what sounds — so it is drawn where a chord would be, at the head of the
  //          chord row. Everything else is a mark ABOUT the bar, and those share one lane: from the
  //          bottom of the chord row (or from the bar's own top when the bar holds no chord) down to
  //          the top of the words written on it. Signs share the lane by taking equal slots across the
  //          bar, and a sign is centred in its slot, so one sign sits in the middle of the bar and two
  //          sit side by side without a second rule for each kind.
  //
  //          THE METER SIGN IS A LABEL AND NOTHING IS MEASURED FROM IT. The owner ruled the meter
  //          «Просто надпись»: it is drawn and it divides nothing — not a bar's width, not a chord's
  //          place, not a count of beats. The rule that decides WHICH bars state it is
  //          [_showsMeterSign], and it is the only reader of a bar's meter in this file.
  List<PlacedBarSign> _placeSigns(
    _MeasuredBar measured, {
    required LayoutRect bounds,
    required bool opensSystem,
    required bool statesOpening,
  }) {
    final Bar bar = measured.bar;
    final List<PlacedBarSign> signs = <PlacedBarSign>[];
    final double chordRowTop = bounds.top + style.chordRowTopInset;

    if (bar.noChord) {
      final String text = 'N.C.';
      final LayoutSize size = style.textMetrics.measure(
        text,
        ChartTextRole.chord,
      );
      signs.add(
        PlacedBarSign(
          kind: BarSignKind.noChord,
          text: text,
          bounds: LayoutRect.fromLTWH(
            bounds.left + style.barPadding,
            chordRowTop,
            size.width,
            size.height,
          ),
        ),
      );
    }

    // The lane signs, in the order a reader meets them when they share a bar: what to play first,
    // then the marks about the bar.
    final List<BarSignKind> kinds = <BarSignKind>[];
    if (bar.repeatPrevious == RepeatPrevious.oneBar) {
      kinds.add(BarSignKind.repeatPreviousOneBar);
    } else if (bar.repeatPrevious == RepeatPrevious.twoBars) {
      kinds.add(BarSignKind.repeatPreviousTwoBars);
    }
    if (bar.slashRepeat) {
      kinds.add(BarSignKind.slashRepeat);
    }
    if (bar.marks.contains(BarMark.segno)) {
      kinds.add(BarSignKind.segno);
    }
    if (bar.marks.contains(BarMark.coda)) {
      kinds.add(BarSignKind.coda);
    }
    if (bar.marks.contains(BarMark.fermata)) {
      kinds.add(BarSignKind.fermata);
    }
    final TimeSignature meter = bar.timeSignature;
    if (_showsMeterSign(
      meter: meter,
      preceding: measured.precedingMeter,
      opensSystem: opensSystem,
      headerStatesOpeningMeter: statesOpening,
    )) {
      kinds.insert(0, BarSignKind.meterChange);
    }

    if (kinds.isEmpty) {
      return signs;
    }
    final double staffHeight = _staffTextHeight(measured.staffText);
    final double laneTop = bounds.top + _signLaneTop(measured);
    final double laneBottom = bounds.bottom - staffHeight;
    final double laneHeight = laneBottom - laneTop;
    // A lane the page could not make room for still draws its signs rather than losing them: the
    // band grows for exactly this (see [_musicHeight]), so this clamp is the case of a page too short
    // for one system, where something has to give and a sign drawn small is better than a lost one.
    final double side = laneHeight < _signSide ? laneHeight : _signSide;
    final double laneCentre = (laneTop + laneBottom) / 2;
    final double slot =
        (bounds.size.width - 2 * style.barPadding) / kinds.length;
    for (int index = 0; index < kinds.length; index++) {
      final BarSignKind kind = kinds[index];
      final bool written = kind == BarSignKind.meterChange;
      final String text = written ? meter.toString() : '';
      final LayoutSize textSize = written
          ? style.textMetrics.measure(text, ChartTextRole.staffText)
          : const LayoutSize(0, 0);
      final double width = written ? textSize.width : side;
      final double height = written ? textSize.height : side;
      final double centre =
          bounds.left + style.barPadding + slot * index + slot / 2;
      signs.add(
        PlacedBarSign(
          kind: kind,
          text: text,
          bounds: LayoutRect.fromLTWH(
            centre - width / 2,
            laneCentre - height / 2,
            width,
            height,
          ),
        ),
      );
    }
    return signs;
  }

  // PURPOSE: Turn a bar's measured cues into placed rows, stacked upward from the stave so the
  //          first cue stays closest to the bar it remarks on and none of them falls onto the
  //          chord below. The painter draws these rows and nothing else, which is what makes the
  //          room the page gave up and the plate the reader sees the same value.
  // INPUTS: cues — this bar's cues in document order, with the size each measured to and the x each
  //         was written at. bounds — where the bar sits, which supplies the origin its own offsetX
  //         is measured from. staveTop — the top of the stave, which is also the bottom of the band.
  //         drawScale — the page scale the rows are engraved for.
  // OUTPUTS: One placed cue per measured cue, in the same order, each carrying the words and the
  //          box it occupies. The first sits directly above the stave and each later one above
  //          that. A cue's row is published at THE BAR'S OWN LEFT EDGE, and the cue's own stored
  //          offset is applied by the painter that draws it — see below.
  //
  //          THE OFFSET IS APPLIED ONCE, AND THIS FUNCTION USED TO APPLY IT AS WELL. It published
  //          `bounds.left + place.offsetX` here while the painter drew the plate at
  //          `row.x + place.offsetX`, so every text cue on the page was drawn one whole offset too
  //          far along its bar — two pixels for a cue nudged two pixels, and the full offset twice
  //          for a cue dragged to the far end of a bar. Two documents state the rule and both say
  //          the painter's half is the one that applies it: [PlacedTextCue.origin] says "its x is
  //          the anchor's own left edge, unchanged", and [ResolvedTextCue.origin] says the same.
  //          The vertical offset was never applied here — it was always the painter's — and that
  //          symmetry is the reason the horizontal one belongs there too.
  //
  //          A cue that overhangs its neighbour is still a remark written over the barline and is
  //          drawn as one: nothing here clamps it, rounds it to a column, or falls back to the
  //          bar's edge when its offset is unusual.
  //
  //          The stored vertical offset is NOT applied here, so a nudge up or down moves the cue by
  //          the number the musician stored and the layout does not interpret a value it does not
  //          own.
  // KEYWORDS: cue-placement, stacking, own-offset, origin, painter-contract, no-column,
  //           offset-applied-once
  List<PlacedTextCue> _placeTextCues(
    List<_MeasuredTextCue> cues,
    LayoutRect bounds,
    double staveTop,
    double drawScale,
  ) {
    if (cues.isEmpty) {
      return const <PlacedTextCue>[];
    }
    final double letterScale = _cueLetterScale(drawScale);
    final List<PlacedTextCue> placed = <PlacedTextCue>[];
    double y = staveTop;
    for (final _MeasuredTextCue cue in cues) {
      final double height = _cueRowHeight(cue, drawScale);
      y -= height;
      final double left = bounds.left;
      placed.add(
        PlacedTextCue(
          id: cue.id,
          text: cue.text,
          origin: LayoutOffset(left, y),
          size: LayoutSize(
            (cue.size.width * letterScale + 2 * textCuePlateInsetX) / drawScale,
            height,
          ),
        ),
      );
    }
    return placed;
  }

  // PURPOSE: Place each of a bar's chords in the bar's chord row, in the box its symbol measured to,
  //          so that the page shows the symbols the chart was written with and a musician can read
  //          the bar instead of an empty lane.
  // INPUTS: measured — the bar with its model, its key, its width and the chord row already laid out
  //         by [_chordRow]. barBounds — the bar's rectangle, which is also the band its row lives in.
  // OUTPUTS: One placement per mark, in the model's own order, each carrying the rendered symbol, the
  //          box it measured to and the size the mark asks for. A bar with no mark yields an empty
  //          list, and the page then shows nothing in that bar's row: a chord is drawn only where the
  //          file put one.
  //
  //          THE X IS THE ROW'S OWN NUMBER AND NOT A SECOND OPINION ABOUT IT. The row already
  //          resolved each symbol's drawn x — its stored place, moved right only where the minimum-gap
  //          rule requires it (see [_chordRow]) — and the bar's width was measured from that same row,
  //          so the symbol that is drawn last is the symbol the bar was widened for. Reading
  //          `mark.offsetX` here instead would draw two symbols on top of each other while reserving
  //          room for the second one, which is the defect this change exists to remove, put back in
  //          the one place that looks like it agrees.
  //
  //          THE VERTICAL ROW, AND WHY IT IS THE TOP ONE. A printed chart writes its chords in a row
  //          at the head of each bar and leaves the rest of the lane under them, and that is the
  //          idiom a musician reads. The row therefore begins [LayoutStyle.chordRowTopInset] below
  //          the band's top rather than being centred in a band that holds nothing else: a symbol
  //          floating in the middle of an empty cell reads as a table of names, while a symbol at the
  //          head of the cell reads as a chart. The inset is also the room between the symbol and the
  //          section heading above the system, which is centred in its own band and ends within a few
  //          pixels of that band's bottom edge.
  //
  //          A MARK'S OWN `offsetY` IS ADDED TO THAT ROW, and the sum is clamped into the band. Zero
  //          — the only value the importer writes — leaves the symbol in the row exactly as above.
  //          A value from a file written by an editor that no longer exists moves it within the band
  //          and no further: [PlacedChord.clampedIntoBand] then says the stored number was not
  //          honoured. Dropping such a mark would make a chart silently lose a chord, and drawing it
  //          outside the band would put it on the heading above or the system below.
  //
  //          NOTHING IS PACKED, AND NOTHING IS ARBITRATED. Two marks may legitimately stand at the
  //          same x, so they are drawn where they say and overlap; the layout does not move a
  //          position the chart chose. This function is also the ONLY place a chord's drawn text is
  //          produced, so the string that is measured and the string that is drawn are one value.
  // KEYWORDS: chord-placement, coordinate-driven, chord-row, top-row, clamping, clampedIntoBand,
  //           no-packing, measured-once, written-spelling, display-only
  List<PlacedChord> _placeChords(_MeasuredBar measured, LayoutRect barBounds) {
    final List<_ChordCell> row = measured.chordRow;
    if (row.isEmpty) {
      return const <PlacedChord>[];
    }
    final List<PlacedChord> placed = <PlacedChord>[];
    for (final _ChordCell cell in row) {
      final LayoutSize size = cell.size;
      // The band the symbol may occupy, expressed as the range its own box's TOP may take: it may
      // not rise above the band and may not hang past its bottom edge.
      final double highest = barBounds.top;
      final double lowest = barBounds.bottom - size.height;
      double top = barBounds.top + style.chordRowTopInset + cell.offsetY;
      bool clamped = false;
      if (top < highest) {
        top = highest;
        clamped = true;
      } else if (top > lowest) {
        // A band too short to hold the symbol at all keeps it at the band's top, where at least its
        // ascender is drawn on the page the bar occupies rather than on the neighbour above.
        top = lowest > highest ? lowest : highest;
        clamped = true;
      }
      placed.add(
        PlacedChord(
          text: cell.text,
          bounds: LayoutRect.fromLTWH(
            barBounds.left + cell.left,
            top,
            size.width,
            size.height,
          ),
          small: cell.small,
          clampedIntoBand: clamped,
        ),
      );
    }
    return placed;
  }
}

/// The result of asking the engine to put a whole song on one page.
class FitOutcome {
  /// Creates an outcome that either carries the fitted [page] or reports that none fits.
  const FitOutcome({
    required this.page,
    required this.scale,
    required this.fits,
  });

  /// The single page holding the whole song, or null when the song does not fit legibly.
  final PageLayout? page;

  /// The factor the page is drawn at.
  ///
  /// When [fits], this is the scale the engine chose, at least the `minScale` the caller allowed.
  /// When not, it is that floor — the smallest the engine was willing to try — so a caller can say
  /// how far short the chart fell without inventing a number.
  final double scale;

  /// Whether [page] holds the whole song at a legible scale.
  final bool fits;

  @override
  String toString() => fits
      ? 'FitOutcome(fits, scale $scale, ${page?.systems.length} system(s))'
      : 'FitOutcome(does not fit, floor $scale)';
}

/// A bar together with the width it needs and whether it opens a section.
class _MeasuredBar {
  const _MeasuredBar({
    required this.sectionId,
    required this.barIndex,
    required this.bar,
    required this.key,
    required this.width,
    required this.chordRow,
    required this.staffText,
    required this.precedingMeter,
    required this.textCues,
    required this.startsSection,
    required this.sectionLabel,
    required this.breaksLine,
  });

  final String sectionId;
  final int barIndex;
  final Bar bar;

  /// The key the bar's chords are spelled in, carried so that measuring and placing a chord use
  /// the same spelling and a bar cannot be measured as `Bb` and drawn as `A#`.
  final Key key;

  final double width;

  /// The bar's chord row, laid out once by [_chordRow]: the string, the measured box and the drawn
  /// left edge of every symbol.
  ///
  /// CARRIED RATHER THAN RECOMPUTED, because the width above was measured from THIS row: a second
  /// call could only disagree, and a disagreement between the width and the drawing is a symbol
  /// drawn past its own bar or on top of its neighbour.
  final List<_ChordCell> chordRow;

  /// The words written on this bar by the file, in display form, with their measured sizes.
  final List<_MeasuredStaffText> staffText;

  /// The meter of the bar before this one in reading order, or null for the chart's first bar.
  ///
  /// Carried because the meter sign rule compares a bar with its predecessor, and the painter of one
  /// page cannot see the page before it: a change that lands on the first bar of a new page must still
  /// be signed.
  final TimeSignature? precedingMeter;

  /// The document's cues that hang on this bar, in document order, with their measured size.
  /// Measured once and carried so that the row reserved above the bar and the box drawn in it are
  /// the same value.
  final List<_MeasuredTextCue> textCues;
  final bool startsSection;
  final String? sectionLabel;

  /// Whether the musician ended the line after this bar, from BarMark.lineBreak.
  ///
  /// Carried with the measurement rather than read again by the system builder so that the rule and
  /// the bar it belongs to are decided once: a layout that read the marks later would be a second
  /// place that had to agree with this one about what a break is.
  final bool breaksLine;
}

/// One chord symbol of a bar's row: the words, the box they measured to and the x they are DRAWN at.
///
/// The left edge is relative to the bar's own left edge. It is NOT the mark's stored `offsetX` when
/// the minimum-gap rule moved the symbol, which is why the drawing and the width share this value
/// instead of each reading the mark.
class _ChordCell {
  const _ChordCell({
    required this.text,
    required this.size,
    required this.left,
    required this.offsetY,
    required this.small,
  });

  /// The symbol exactly as the chart writes it.
  final String text;

  /// The box the symbol measured to at the chord role.
  final LayoutSize size;

  /// The drawn left edge, in bar-local logical pixels.
  final double left;

  /// The mark's own vertical offset from the chord row, carried so a file written by an older editor
  /// still draws its symbol where it said.
  final double offsetY;

  /// Whether the model marks this symbol small.
  final bool small;
}

/// One line of a bar's own staff text, in display form, with the box it measured to.
class _MeasuredStaffText {
  const _MeasuredStaffText({required this.text, required this.size});

  /// The words to draw, as `displayStaffText` returns them.
  final String text;

  /// The box the words occupy at the staff-text role, at a page scale of 1.
  final LayoutSize size;
}

/// One text cue of the document that hangs on a bar, with the size its words measured to.
class _MeasuredTextCue {
  const _MeasuredTextCue({
    required this.id,
    required this.offsetX,
    required this.text,
    required this.size,
  });

  /// The identity the document gave the cue, carried through to [PlacedTextCue] so the caller can
  /// pair a placement with the cue it came from even when two cues share one anchor.
  final String id;

  /// The x the cue starts at inside its bar: the cue's own place, carried through so that measuring
  /// the row and drawing it in it use one number. It is not rounded to anything.
  final double offsetX;

  /// The words to draw, exactly as the document stores them.
  final String text;

  /// The box the words occupy at a page scale of 1, from the style's text metrics.
  final LayoutSize size;
}

/// A planned system: the bars it holds and the section heading above it, if any.
class _SystemPlan {
  const _SystemPlan({
    required this.bars,
    required this.sectionId,
    required this.sectionLabel,
  });

  final List<_MeasuredBar> bars;
  final String? sectionId;
  final String? sectionLabel;
}
