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
import '../song/song.dart';
import '../spelling_table.dart';
import 'geometry.dart';
import 'layout_style.dart';
import 'page_layout.dart';
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
      systems,
      contentWidth,
      contentHeight,
      pageWidth,
      pageHeight,
      drawScale,
    );
  }

  // PURPOSE: Publish the line that states the chart's key and meter where its music begins, which
  //          is the thing a musician reads first and the one thing the page could not tell him
  //          before: the key lived in the scene bar and the meter appeared only on a bar that
  //          changed it.
  // INPUTS: song — the chart. measured — the bars in reading order, whose FIRST entry supplies the
  //         meter the chart opens in. contentWidth — the width between the page's margins, which the
  //         published band spans.
  // OUTPUTS: A [PlacedChartHeader] on the page where the music begins, or NULL when the song carries
  //          no bar at all: a chart with no music has nothing to state about what key it is in, and
  //          a page is never produced for it anyway.
  //
  //          WHERE IT SITS. In the page's own top margin band, above the first system and above the
  //          section letter that system carries, so it collides with neither: a section letter marks
  //          where a SECTION begins, the header marks what the whole chart is written in, and a
  //          page whose first bar is not the first bar of a section — a continuation of a section
  //          that began on the previous page — still carries the header on the only page it is
  //          printed on, because it is the PAGE's statement and not the first bar's. Nothing about
  //          the bar's own rectangle or chords is touched by it.
  //
  //          THE METER IT STATES IS THE FIRST BAR'S, and that is the definition rather than a
  //          simplification: a chart's meter is whatever its first bar is counted in, and a bar that
  //          changes it is signed at the bar where it changes by `meter_sign.dart`. What the header
  //          says is therefore the state the music opens in, which is what a printed chart's opening
  //          time signature says too.
  // KEYWORDS: chart-header, opening-statement, key-and-meter, first-page-only, no-collision,
  //           section-letter, first-bar-independent
  // PURPOSE: Report the vertical room a system's melody staff needs, which is a property of the
  //          SONG rather than of a bar: either every bar on the page carries a staff, so that the
  //          five lines run unbroken across each system, or none does.
  // INPUTS: song — the chart about to be engraved.
  // OUTPUTS: ZERO when the song declares no pitched staff (`song.staffSet.pitched == null`), which
  //          is the load-bearing case: a chords-only chart — every imported chart, and every chart
  //          that never declared a staff — then computes exactly the page it computed before a
  //          melody staff existed, because the band is the only term this change adds to a system's
  //          height.
  //
  //          [LayoutStyle.melodyBandHeight] when the song declares a pitched staff AND carries at
  //          least one note somewhere, and [LayoutStyle.melodyEmptyBandHeight] when it declares one
  //          and carries none. That last case is the refinement of D29 the owner's picture asked
  //          for: a chord-only chart in the app's default state declared a staff and therefore
  //          reserved the full 270-pixel band — five ledger lines' worth of room above and below the
  //          five lines — to draw nothing on. The staff still exists (D29), with its lines, its clef
  //          and its beat captions; only the room reserved for notes that do not exist is gone.
  //          See [LayoutStyle.melodyEmptyBandHeight] for why the reserve may follow the music while
  //          the staff follows the declaration, and for the derivation of the smaller number.
  //
  //          WHY THE DECLARATION AND NOT THE NOTES, FOR THE STAFF ITSELF. This used to return the
  //          band only when some bar already carried a note, which made the staff appear AFTER the
  //          musician had written on it — and therefore nowhere to write. Owner decision D29: the
  //          staff exists because the chart DECLARED it, and `Song.staffSet` is that declaration. A
  //          chart whose pitched staff is declared and holds no note is a blank staff, which is
  //          exactly what a musician needs in order to put the first note on it. The page a
  //          chords-only chart computes is untouched, and that is what keeps every imported chart
  //          byte-identical.
  //
  //          THE WHOLE SONG DECIDES, NOT THE BAR. One bar carrying a note puts the full band on every
  //          system of the song, so the staff sits at one height across the chart — the property
  //          `melody_layout_test.dart` measures. A note in bar 40 must not make page 1 reserve a
  //          different amount of paper from the page the note is on.
  // KEYWORDS: melody-band, song-level-decision, declared-staff, blank-staff, empty-staff-shallower,
  //           unchanged-chords-only, d29, d32
  // PURPOSE: Answer whether the song holds a pitched note anywhere, which is the one fact that
  //          separates a staff being written on from a staff that is merely there.
  // INPUTS: song — the chart.
  // OUTPUTS: True when any bar of any section carries a non-empty `melody`. False for a song with no
  //          bars, which is the same answer an empty song must give: nothing is written on it.
  //          The walk is bounded by the bar count and allocates nothing, so calling it once per
  //          engraving costs a comparison per bar.
  // KEYWORDS: melody-presence, song-level, no-allocation, band-decision
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
  //          WHAT COUNTS AS CONTENT, and why each thing is here. A CHORD contributes its own right
  //          edge: `place.offsetX` plus the width its symbol measures. A NOTE contributes the same,
  //          less half a notehead, because a note's `offsetX` is its notehead's CENTRE while a
  //          chord's is its symbol's left edge — the two anchors their glyphs are naturally drawn
  //          from, stated here because a bar that reserved the wrong one would clip the last mark
  //          on the line. Staff text contributes its own line, as it always did. NOTHING ELSE DOES:
  //          a text cue hangs ABOVE the bar in a row the page gives up, a document remark is not
  //          part of the music, and handwriting has its own coordinate space and never widened a
  //          bar. The metre contributes NOTHING — it is not read here at all.
  //
  //          THIS FUNCTION IS THE ONLY PLACE A BAR'S WIDTH IS DECIDED, and the factor is applied
  //          HERE and nowhere else on purpose. Everything the width feeds already derives from the
  //          rectangle this number becomes: the chord x positions, the melody staff's own extent,
  //          the text cues, the hit test's rectangle and the bar rectangle an ink stroke is anchored
  //          against. A second place that knew about the factor — a painter multiplying a bar it
  //          drew, or a hit test adjusting for a resized bar — would be the second source of truth
  //          for the coordinate system's one load-bearing number, which is the defect A33 and A47
  //          already paid for once here.
  //
  //          WHY THE FACTOR MULTIPLIES THE FLOORED WIDTH rather than being folded into the paddings:
  //          the surplus a wider bar gets then widens the whole bar, which is what gives a musician
  //          who asked for more room somewhere to write. Scaling only the padding would widen the
  //          gap beside the first mark and leave the middle of the bar exactly as it was.
  // KEYWORDS: bar-width, content-driven, follow-the-content, staff-text-room, single-measurement,
  //           minimum-width, bar-size, width-multiplier, single-source-of-truth, metre-not-read
  double _barWidth(Bar bar, Key key) {
    double content = 0;
    for (final ChordMark mark in bar.chords) {
      final String text = mark.chord.render(key, spellingTable);
      final double right =
          mark.offsetX +
          style.textMetrics.measure(text, ChartTextRole.chord).width;
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

  // PURPOSE: Read a bar's stored staff text into the lines it shows, measuring each line once so
  //          that the room reserved for it and the box it is placed in are the same number.
  // INPUTS: bar — the bar whose `Bar.staffText` to read.
  // OUTPUTS: One entry per stored line that has words to show, in model order, carrying the display
  //          string and the size it measured to. A stored entry whose display form is empty (a bare
  //          `*NN`, or whitespace alone) is skipped: it names a position and says nothing, and
  //          placing a zero-width line would reserve a line height for nothing. An empty input
  //          yields an empty list.
  // KEYWORDS: staff-text, display-form, measurement, empty-skip, single-source
  // PURPOSE: Place a bar's melody notes on the staff band beneath its chord line, each notehead at
  //          the x its own place names, so that the five staff lines run unbroken across the whole
  //          system and every note is drawn where the musician wrote it.
  // INPUTS: measured — the bar with its model, key and the clef its staff is written in.
  //         barBounds — the bar's CHORD-LINE rectangle; the staff is placed below it, never inside
  //         it, so the bar's own rectangle — and therefore every tap on the chord line — is
  //         untouched by a staff existing. melodyTop — the y where the system's melody band begins.
  //         melodyBand — the band's height; zero for a chords-only song, which is the case that
  //         yields an empty staff and an unchanged page. opensSystem — whether this bar prints the
  //         clef, which only the bar that opens a system does.
  // OUTPUTS: The placed staff, or [PlacedMelodyStaff.empty] when the system reserved no band at all.
  //          A bar that carries no note still gets its staff, because the five lines are drawn
  //          across every bar of a system; only a system with no melody anywhere gets none.
  //
  //          THE NOTES ARE POSITIONED BY THEIR OWN PLACES AND BY NOTHING ELSE. There is no cell
  //          list to hand the staff any more, no stride for a beat's run and no fitting of a run
  //          into a column: a note's x is `bar.left + place.offsetX` and its y comes from its pitch.
  //          This is the property the whole change exists for — one answer to "where is this note",
  //          and it is the same number the model stores and the reader measured.
  // KEYWORDS: melody-placement, coordinate-driven, staff-lines, empty-when-no-band, no-cells
  // PURPOSE: Turn the bar's measured staff-text lines into placed boxes, stacked upward from the
  //          bar's bottom edge so several phrases stay inside the bar instead of running past the
  //          system below. The painter draws these boxes and nothing else, which is what makes the
  //          drawn width and the measured width the same value.
  // INPUTS: lines — the bar's measured lines, from [_measureStaffText]. bounds — where the bar sits.
  // OUTPUTS: One placed line per measured line, in the same order, each with the display words and
  //          its box. The first sits [LayoutStyle.staffTextBottomInset] above the bar's bottom and
  //          each later one is stacked above it. An empty input yields an empty list.
  // KEYWORDS: staff-text, placement, stacking, display-form, painter-contract
  // The CELL DIVISION IS GONE, AND ITS REMOVAL ATE FOUR FUNCTIONS AT ONCE. `_cellWidths` decided
  // how wide each beat's column had to be, `_cellOffsets` turned those columns into x positions
  // inside the bar, `_placeCells` published them as hit targets and `_placeBeatMarkers` drew them.
  // All four existed because the layout divided a bar by its metre. The owner removed that division
  // («Просто надпись»), so there is no column to widen, no offset to distribute, no target to
  // publish and no number to print: a mark is at its own x (see [_placeChords]) and a touch names
  // the bar and its own coordinate (see `hitTest.dart`).
  //
  // WHAT WAS LOST WITH THEM, said rather than discovered later. A bar used to reserve at least one
  // minimum column per beat, which is what gave a musician blank room to write into; a bar's width
  // now follows only what is already written in it, so an empty bar is exactly `barMinWidth` and a
  // bar with one chord is barely wider. `barMinWidth` is therefore the number that decides how much
  // empty room a bar gives, and raising it is the honest way to give more — not the return of
  // columns.

  List<_MeasuredBar> _measureBars(Song song, List<TextCue> cues) {
    final Map<String, List<TextCue>> cuesByBar = _cuesByBar(cues);
    final List<_MeasuredBar> measured = <_MeasuredBar>[];
    for (final section in song.sections) {
      for (int index = 0; index < section.bars.length; index++) {
        final Bar bar = section.bars[index];
        measured.add(
          _MeasuredBar(
            sectionId: section.id,
            barIndex: index,
            bar: bar,
            key: song.key,
            width: _barWidth(bar, song.key),
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
    List<_SystemPlan> systems,
    double contentWidth,
    double contentHeight,
    double pageWidth,
    double pageHeight,
    double drawScale,
  ) {
    final List<PageLayout> pages = <PageLayout>[];
    List<PlacedSystem> currentSystems = <PlacedSystem>[];
    double y = style.pageMargin;
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
          scale: drawScale,
        ),
      );
      pageIndex++;
      currentSystems = <PlacedSystem>[];
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
      // the overflow comes off its TOP — its section label, its cue rows and, when the music itself
      // will not fit, its melody staff — and the chord line stays on the page. That is the same
      // priority the whole feature rests on: a remark gives way to the chart, never the other way
      // round, and a performance instruction gives way to the music it is written about. A page too
      // short for even one chord line is the one case this cannot help, and there the system keeps
      // its ordinary place and overflows the bottom, as it did before cues existed.
      //
      // THE HEADER IS ON THE SAME LADDER AND AT THE SAME RUNG as the label and the cue rows, which is
      // stated rather than hidden: on a page too short to hold one system, the system's top is put
      // where the music's bottom forces it and the header — which sits in the top margin — is what
      // the system then reaches over. Nothing is more honest available: a page that cannot hold one
      // line of music has no room to state anything about the music, and drawing the header over the
      // chord line would hide the very thing the page exists to show.
      final double musicHeight = style.barHeight;
      final bool overflowsPage =
          height > contentHeight && musicHeight <= contentHeight;
      final double top = overflowsPage
          ? style.pageMargin + contentHeight - height
          : (firstOnPage ? y : y + spacing);
      currentSystems.add(_placeSystem(plan, top, drawScale));
      y = top + height;
      firstOnPage = false;
    }
    flushPage();
    return pages;
  }

  // PURPOSE: Report the height of everything a system must draw BELOW its label and its cue rows:
  //          the chord stave and, when the song has one, the melody staff.
  // INPUTS: drawScale — the page scale, unused here but kept so that a future scale-aware part of
  //         the music measures on the same terms as the cue rows. melodyBand — the room the melody
  //         staff needs, from [_melodyBand].
  // OUTPUTS: The stave height plus the melody band. For a chords-only song this is exactly
  //          [LayoutStyle.barHeight], which is the number the overflow rule compared before a
  //          melody staff existed.
  // KEYWORDS: music-height, overflow-floor, stave, melody-band, unchanged-chords-only
  double _musicHeight(double drawScale) => style.barHeight;

  // PURPOSE: Report how tall a system is, which is the band reserved for its cues plus its heading
  //          plus its music.
  // INPUTS: plan — the system. drawScale — the page scale the engraved coordinates will be
  //         multiplied by, which is what turns a cue's surface-sized letters into engraved room.
  // OUTPUTS: The system's height. A system with no cue and no heading is exactly the style's stave
  //          height, which is what keeps a page of plain bars laid out as it always was.
  // KEYWORDS: system-height, cue-band, section-label, stave, unchanged-when-empty
  double _systemHeight(_SystemPlan plan, double drawScale) =>
      (plan.sectionLabel == null ? 0 : style.sectionLabelHeight) +
      _cueBandHeight(plan, drawScale) +
      _musicHeight(drawScale);

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

  PlacedSystem _placeSystem(_SystemPlan plan, double top, double drawScale) {
    final double labelHeight = plan.sectionLabel == null
        ? 0
        : style.sectionLabelHeight;
    final double cueBand = _cueBandHeight(plan, drawScale);
    final double staveTop = top + labelHeight + cueBand;
    final List<PlacedBar> bars = <PlacedBar>[];
    double x = style.pageMargin;
    for (final _MeasuredBar measured in plan.bars) {
      final LayoutRect bounds = LayoutRect.fromLTWH(
        x,
        staveTop,
        measured.width,
        style.barHeight,
      );
      bars.add(
        PlacedBar(
          sectionId: measured.sectionId,
          barIndex: measured.barIndex,
          bounds: bounds,
          // The chords are placed from the SAME rectangle the bar was given, so the symbol's x and
          // the width the bar was measured to are one relationship and not two.
          chords: _placeChords(measured, bounds),
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
        labelHeight + cueBand + _musicHeight(drawScale),
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
    );
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

  // PURPOSE: Place each of a bar's chords in the bar's chord row, at the x the model stores, so
  //          that the page shows the symbols the chart was written with and a musician can read the
  //          bar instead of an empty lane.
  // INPUTS: measured — the bar with its model, its key and its width. barBounds — the bar's
  //         rectangle, which is also the band its chord row lives in.
  // OUTPUTS: One placement per mark, in the model's own order, each carrying the rendered symbol,
  //          the box it measured to and the size the mark asks for. A bar with no mark yields an
  //          empty list, and the page then shows nothing in that bar's row: a chord is drawn only
  //          where the file put one.
  //
  //          THE X IS THE MODEL'S OWN NUMBER. `barLeft + mark.offsetX`, read straight off the mark —
  //          no column, no beat, no rounding — because under the coordinate model a mark's place IS
  //          its time. The bar's width was measured from the same number (see [_barWidth]), so a bar
  //          is wide enough for the last symbol it holds by construction.
  //
  //          THE VERTICAL ROW, AND WHY IT IS THE TOP ONE. A printed chart writes its chords in a row
  //          at the head of each bar and leaves the rest of the lane under them, and that is the
  //          idiom a musician reads. The row therefore begins [LayoutStyle.chordRowTopInset] below
  //          the band's top rather than being centred in a band that is now [LayoutStyle.barHeight]
  //          tall and holds nothing else: a symbol floating in the middle of an empty cell reads as
  //          a table of names, while a symbol at the head of the cell reads as a chart. The inset is
  //          the room between the symbol and the section heading above the system, which is centred
  //          in its own band and ends within a few pixels of that band's bottom edge.
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
    final List<ChordMark> marks = measured.bar.chords;
    if (marks.isEmpty) {
      return const <PlacedChord>[];
    }
    final List<PlacedChord> placed = <PlacedChord>[];
    for (final ChordMark mark in marks) {
      final String text = mark.chord.render(measured.key, spellingTable);
      final LayoutSize size = style.textMetrics.measure(
        text,
        ChartTextRole.chord,
      );
      // The band the symbol may occupy, expressed as the range its own box's TOP may take: it may
      // not rise above the band and may not hang past its bottom edge.
      final double highest = barBounds.top;
      final double lowest = barBounds.bottom - size.height;
      double top = barBounds.top + style.chordRowTopInset + mark.place.offsetY;
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
          text: text,
          bounds: LayoutRect.fromLTWH(
            barBounds.left + mark.offsetX,
            top,
            size.width,
            size.height,
          ),
          small: mark.size == ChordSize.small,
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
