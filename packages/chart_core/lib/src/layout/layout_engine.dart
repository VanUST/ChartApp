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
//      song, and every placed chord carries its (beat, step). An annotation anchored in the song
//      model can therefore be drawn at the right place without either side knowing the other's
//      coordinates.
//
// What it deliberately does not do: rasterisation, glyph shaping, and play-order expansion. The
// first two belong to the renderer, and the third is not yet written (see the song model notes in
// docs/sdd.md). The engine lays out the bars as WRITTEN, which is the edit view.
import '../key.dart';
import '../oplog/oplog.dart';
import '../song/bar.dart';
import '../song/song.dart';
import '../spelling_table.dart';
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
      systems,
      contentWidth,
      contentHeight,
      pageWidth,
      pageHeight,
      drawScale,
    );
  }

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
  // INPUTS: bar — the bar to measure. key — the key its chords are spelled in, which affects the
  //         width because `Bb` and `A#` are different strings.
  // OUTPUTS: The bar's natural width, never less than the style's minimum bar width. A bar with
  //          no chords measures to the minimum, because an empty cell still reserves room. A bar
  //          whose staff text is wider than its cells widens to hold that text as DISPLAYED — the
  //          `*NN` prefix and the exporter's padding are gone (see `displayStaffText`), so the
  //          layout does not reserve room for words it will not draw.
  // KEYWORDS: bar-measurement, natural-width, minimum-width, key-dependent-width, staff-text
  /// Returns the width [bar] needs when its chords are spelled in [key].
  double measureBar(Bar bar, Key key) =>
      _barWidth(bar, key, _measureStaffText(bar));

  // PURPOSE: Answer the width a bar needs, given its already-measured staff-text lines, so that the
  //          width reserved for the words and the box the words are placed in come from ONE
  //          measurement rather than two calls that happen to agree.
  // INPUTS: bar — the bar. key — the key its chords are spelled in. staffLines — the bar's staff
  //         text in display form with its measured sizes, from [_measureStaffText].
  // OUTPUTS: The bar's width: the larger of its cell content plus padding, and its widest staff
  //          line plus the line's left inset and the bar's right padding, floored at the style's
  //          minimum bar width. Never less than [LayoutStyle.barMinWidth].
  // KEYWORDS: bar-width, staff-text-room, single-measurement, minimum-width
  double _barWidth(Bar bar, Key key, List<_MeasuredStaffText> staffLines) {
    double content = 0;
    for (final double cellWidth in _cellWidths(bar, key)) {
      content += cellWidth;
    }
    final double natural = content + 2 * style.barPadding;
    double widest = 0;
    for (final _MeasuredStaffText line in staffLines) {
      if (line.size.width > widest) {
        widest = line.size.width;
      }
    }
    final double withStaffText = widest == 0
        ? 0
        : widest + style.staffTextInset + style.barPadding;
    final double sized = natural > withStaffText ? natural : withStaffText;
    return sized < style.barMinWidth ? style.barMinWidth : sized;
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

  // PURPOSE: Turn a bar's measured staff-text lines into placed boxes, stacked upward from the
  //          bar's bottom edge so several phrases stay inside the bar instead of running past the
  //          system below. The painter draws these boxes and nothing else, which is what makes the
  //          drawn width and the measured width the same value.
  // INPUTS: lines — the bar's measured lines, from [_measureStaffText]. bounds — where the bar sits.
  // OUTPUTS: One placed line per measured line, in the same order, each with the display words and
  //          its box. The first sits [LayoutStyle.staffTextBottomInset] above the bar's bottom and
  //          each later one is stacked above it. An empty input yields an empty list.
  // KEYWORDS: staff-text, placement, stacking, display-form, painter-contract
  List<PlacedStaffText> _placeStaffText(
    List<_MeasuredStaffText> lines,
    LayoutRect bounds,
  ) {
    final List<PlacedStaffText> placed = <PlacedStaffText>[];
    double y = bounds.bottom - style.staffTextBottomInset;
    for (final _MeasuredStaffText line in lines) {
      y -= line.size.height;
      placed.add(
        PlacedStaffText(
          text: line.text,
          bounds: LayoutRect.fromLTWH(
            bounds.left + style.staffTextInset,
            y,
            line.size.width,
            line.size.height,
          ),
        ),
      );
    }
    return placed;
  }

  // PURPOSE: Give each cell of a bar an extent, so that measuring a bar and placing chords inside
  //          it agree on where a cell begins. Having one function decide both is what prevents the
  //          chord positions from drifting away from the width they were measured into.
  // INPUTS: bar — the bar. key — the key its chords are spelled in.
  // OUTPUTS: One width per cell. A bar has at least its meter's cells, and MORE when a chord is
  //          placed beyond the meter: the count widens to include the furthest chord. A cell
  //          holding no chord takes the minimum cell width. A cell holding one or more chords
  //          takes their total width plus a trailing gap, or the minimum if that is larger.
  //
  //          A chord at a NEGATIVE beat is still skipped, because there is no cell to the left of
  //          the bar to widen into.
  //
  // KEYWORDS: cell-extent, chord-width, meter-cells, overfull-bar, widening
  //
  // WHY WIDEN INSTEAD OF SKIP. This function used to skip any chord whose beat lay outside the
  // meter. That is defensible for a hand-built chart and wrong for an imported one: another
  // format's cell model can legitimately place a chord past the last beat this project expected,
  // and skipping it engraves a bar that is silently missing a chord the musician wrote, with
  // nothing on the page to say so. Widening keeps the content and lets the bar overflow the page
  // if it must, which is a visible symptom rather than an invisible loss.
  List<double> _cellWidths(Bar bar, Key key) {
    final int declared = bar.timeSignature.cellsPerBar;
    final int meterCells = declared < 1 ? 1 : declared;
    int cells = meterCells;
    for (final BeatChord placement in bar.chords) {
      if (placement.beat >= cells) {
        cells = placement.beat + 1;
      }
    }
    final List<double> totals = List<double>.filled(cells, 0);
    for (final BeatChord placement in bar.chords) {
      if (placement.beat < 0) {
        continue;
      }
      final String text = placement.chord.render(key, spellingTable);
      final double chordWidth = style.textMetrics
          .measure(text, ChartTextRole.chord)
          .width;
      totals[placement.beat] += chordWidth + style.chordSpacing;
    }
    return <double>[
      for (final double total in totals)
        total < style.minCellWidth ? style.minCellWidth : total,
    ];
  }

  // PURPOSE: Convert cell extents into the x offset of each cell inside a bar of a given drawn
  //          width, spreading any surplus — the room the minimum bar width added — evenly so that
  //          a short bar's single chord does not huddle against the left barline.
  // INPUTS: bar and key as above. barWidth — the width the bar will actually be drawn at, which
  //         may exceed its natural width.
  // OUTPUTS: One offset per cell, relative to the bar's left edge. An empty meter yields an empty
  //          list rather than a division by zero.
  // KEYWORDS: cell-offset, surplus-distribution, even-spacing, placement-agreement
  List<double> _cellOffsets(Bar bar, Key key, double barWidth) {
    final List<double> widths = _cellWidths(bar, key);
    if (widths.isEmpty) {
      return const <double>[];
    }
    double natural = 0;
    for (final double width in widths) {
      natural += width;
    }
    final double available = barWidth - 2 * style.barPadding;
    final double perCell = (available - natural) / widths.length;
    final List<double> offsets = <double>[];
    double x = style.barPadding;
    for (final double width in widths) {
      offsets.add(x);
      x += width + perCell;
    }
    return offsets;
  }

  List<_MeasuredBar> _measureBars(Song song, List<TextCue> cues) {
    final Map<String, List<TextCue>> cuesByBar = _cuesByBar(cues);
    final List<_MeasuredBar> measured = <_MeasuredBar>[];
    for (final section in song.sections) {
      for (int index = 0; index < section.bars.length; index++) {
        final Bar bar = section.bars[index];
        // The staff text is measured once here and handed to both the width that reserves room for
        // it and the placement that draws it, so the bar cannot be sized for one string and drawn
        // with another.
        final List<_MeasuredStaffText> staffText = _measureStaffText(bar);
        measured.add(
          _MeasuredBar(
            sectionId: section.id,
            barIndex: index,
            bar: bar,
            key: song.key,
            width: _barWidth(bar, song.key, staffText),
            staffText: staffText,
            textCues: _measureTextCues(
              cuesByBar[_barKey(section.id, index)] ?? const <TextCue>[],
            ),
            startsSection: index == 0,
            sectionLabel: index == 0 ? section.label.toString() : null,
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
            anchor: cue.place.anchor,
            text: cue.text,
            size: style.textMetrics.measure(cue.text, ChartTextRole.textCue),
          ),
      ];

  // PURPOSE: Pack bars into systems, starting a new system at every section boundary and
  //          otherwise breaking only when the next bar would not fit.
  // INPUTS: measured — the bars in reading order with their widths. availableWidth — the width a
  //         system may occupy.
  // OUTPUTS: One plan per system. A section always begins a system, so a section heading is never
  //          separated from the music it names, and a section is never split by a heading that
  //          belongs to a later one.
  // KEYWORDS: system-building, greedy-packing, section-break, line-breaking
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
      final bool mustBreak = current.isNotEmpty && bar.startsSection;
      final bool doesNotFit =
          current.isNotEmpty && currentWidth + bar.width > availableWidth;
      if (mustBreak || doesNotFit) {
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
      // the most there is. It is then placed with its STAVE's bottom on the content box's bottom, so
      // the overflow comes off its TOP — its section label and its cue rows — and the music stays on
      // the page. That is the same priority the whole feature rests on: a cue is a remark that gives
      // way to the chart, never the other way round. A page too short for even one stave is the one
      // case this cannot help, and there the system keeps its ordinary place and overflows the
      // bottom, as it did before cues existed.
      final bool overflowsPage =
          height > contentHeight && style.barHeight <= contentHeight;
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

  // PURPOSE: Report how tall a system is, which is the band reserved for its cues plus its heading
  //          plus one stave.
  // INPUTS: plan — the system. drawScale — the page scale the engraved coordinates will be
  //         multiplied by, which is what turns a cue's surface-sized letters into engraved room.
  // OUTPUTS: The system's height. A system with no cue and no heading is exactly the style's stave
  //          height, which is what keeps every cue-free page laid out as it was before cues
  //          existed.
  // KEYWORDS: system-height, cue-band, section-label, stave, unchanged-when-empty
  double _systemHeight(_SystemPlan plan, double drawScale) =>
      (plan.sectionLabel == null ? 0 : style.sectionLabelHeight) +
      _cueBandHeight(plan, drawScale) +
      style.barHeight;

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
      // The cell columns are computed once here and handed to both the cells the hit test reads
      // and the chords drawn inside them. Recomputing them for the hit test would put the two on
      // separate code paths that can drift, and a chord that moved by a pixel while its cell did
      // not is exactly the kind of wrongness that looks right on screen.
      final List<double> offsets = _cellOffsets(
        measured.bar,
        measured.key,
        bounds.size.width,
      );
      bars.add(
        PlacedBar(
          sectionId: measured.sectionId,
          barIndex: measured.barIndex,
          bounds: bounds,
          cells: _placeCells(offsets, bounds),
          chords: _placeChords(measured, bounds, offsets),
          staffText: _placeStaffText(measured.staffText, bounds),
          // A cell-anchored cue needs the cell's own left edge, which only exists once the offsets
          // above are known, which is why the cues are placed here and not while the bars were
          // being measured.
          textCues: _placeTextCues(
            measured.textCues,
            bounds,
            offsets,
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
        labelHeight + cueBand + style.barHeight,
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
  // INPUTS: cues — this bar's cues in document order, with the size each measured to. bounds —
  //         where the bar sits. offsets — the left edge of each cell relative to the bar's left
  //         edge, from [_cellOffsets]. staveTop — the top of the stave, which is also the bottom
  //         of the band. drawScale — the page scale the rows are engraved for.
  // OUTPUTS: One placed cue per measured cue, in the same order, each carrying the words and the
  //          box it occupies. The first sits directly above the stave and each later one above
  //          that. A cue anchored to a cell of the bar starts at that cell's left edge; one
  //          anchored to the bar itself starts at the bar's left edge; one whose beat the bar has
  //          no cell for falls back to the bar's left edge rather than being dropped, matching the
  //          anchor resolver the ink layer uses. An empty input yields an empty list.
  //
  //          The stored offset is NOT applied here. It stays the painter's, exactly as it was, so
  //          a nudge up or down still moves the cue by the number the musician stored and the
  //          layout does not have to interpret a value it does not own.
  // KEYWORDS: cue-placement, stacking, cell-anchor, bar-anchor, origin-only, painter-contract
  List<PlacedTextCue> _placeTextCues(
    List<_MeasuredTextCue> cues,
    LayoutRect bounds,
    List<double> offsets,
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
      final int? beat = cue.anchor.beat;
      final double left = beat != null && beat >= 0 && beat < offsets.length
          ? bounds.left + offsets[beat]
          : bounds.left;
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

  // PURPOSE: Turn the cell offsets of a bar into the columns a hit test needs, so that a touch can
  //          be named as a cell without the hit test re-deriving the bar's division. A cell is
  //          wider than its chord: it owns the gap that follows the chord too, because that gap is
  //          still part of the time the chord is held.
  // INPUTS: offsets — the left edge of each cell relative to the bar's left edge, from
  //         [_cellOffsets]. bounds — where the bar is drawn.
  // OUTPUTS: One cell per offset, in beat order, each spanning the bar's full height and its own
  //          column. The columns tile the bar's interior exactly: the first begins after the left
  //          padding, each later one begins where the previous ended, and the last ends before the
  //          right padding — so the paddings themselves are bar and not cell, which is the state
  //          that makes "a bar with no cell at this point" expressible. An empty offset list
  //          yields no cells, which the engine's minimum cell width makes unreachable in practice.
  // KEYWORDS: cell-column, hit-target, tiling, padding-gap, geometry-single-source
  List<PlacedCell> _placeCells(List<double> offsets, LayoutRect bounds) {
    if (offsets.isEmpty) {
      return const <PlacedCell>[];
    }
    final List<PlacedCell> cells = <PlacedCell>[];
    for (int beat = 0; beat < offsets.length; beat++) {
      final double left = bounds.left + offsets[beat];
      // The last cell ends at the interior's right edge rather than at the next offset, because
      // there is no next offset to read it from.
      final double right = beat + 1 < offsets.length
          ? bounds.left + offsets[beat + 1]
          : bounds.right - style.barPadding;
      cells.add(
        PlacedCell(
          beat: beat,
          bounds: LayoutRect.fromLTWH(
            left,
            bounds.top,
            right - left,
            bounds.size.height,
          ),
        ),
      );
    }
    return cells;
  }

  List<PlacedChord> _placeChords(
    _MeasuredBar measured,
    LayoutRect barBounds,
    List<double> offsets,
  ) {
    final Bar bar = measured.bar;
    if (offsets.isEmpty) {
      return const <PlacedChord>[];
    }
    final Map<int, double> consumedInCell = <int, double>{};
    final List<PlacedChord> placed = <PlacedChord>[];

    // Chords are visited in the order the model stores them, which is by cell and then by step,
    // so a comma-packed pair is drawn left to right in the order it is read.
    for (final BeatChord placement in bar.chords) {
      if (placement.beat < 0 || placement.beat >= offsets.length) {
        continue;
      }
      final String text = placement.chord.render(measured.key, spellingTable);
      final LayoutSize textSize = style.textMetrics.measure(
        text,
        ChartTextRole.chord,
      );
      final double used = consumedInCell[placement.beat] ?? 0;
      final double chordX = barBounds.left + offsets[placement.beat] + used;
      // Chords sit in the middle of the stave's vertical extent, which is where a musician
      // expects a symbol in a chart that has no melody staff beneath it.
      final double chordY =
          barBounds.top + (barBounds.size.height - textSize.height) / 2;
      placed.add(
        PlacedChord(
          chord: placement.chord,
          beat: placement.beat,
          step: placement.step,
          bounds: LayoutRect.fromLTWH(
            chordX,
            chordY,
            textSize.width,
            textSize.height,
          ),
        ),
      );
      consumedInCell[placement.beat] =
          used + textSize.width + style.chordSpacing;
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
    required this.staffText,
    required this.textCues,
    required this.startsSection,
    required this.sectionLabel,
  });

  final String sectionId;
  final int barIndex;
  final Bar bar;

  /// The key the bar's chords are spelled in, carried so that measuring and placing a chord use
  /// the same spelling and a bar cannot be measured as `Bb` and drawn as `A#`.
  final Key key;
  final double width;

  /// The bar's staff text in display form, with the size each line measured to. Measured once and
  /// carried so that the width reserved for it and the box it is placed in are the same value.
  final List<_MeasuredStaffText> staffText;

  /// The document's cues that hang on this bar, in document order, with their measured size.
  /// Measured once and carried so that the row reserved above the bar and the box drawn in it are
  /// the same value.
  final List<_MeasuredTextCue> textCues;
  final bool startsSection;
  final String? sectionLabel;
}

/// One line of a bar's staff text in display form, with the size it measured to.
class _MeasuredStaffText {
  const _MeasuredStaffText({required this.text, required this.size});

  /// The words to draw, with the `*NN` prefix and padding already removed.
  final String text;

  /// The box the line occupies, from the style's text metrics.
  final LayoutSize size;
}

/// One text cue of the document that hangs on a bar, with the size its words measured to.
class _MeasuredTextCue {
  const _MeasuredTextCue({
    required this.id,
    required this.anchor,
    required this.text,
    required this.size,
  });

  /// The identity the document gave the cue, carried through to [PlacedTextCue] so the caller can
  /// pair a placement with the cue it came from even when two cues share one anchor.
  final String id;

  /// The address the cue hangs on, which decides the column it starts at inside its bar.
  final EventAnchor anchor;

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
