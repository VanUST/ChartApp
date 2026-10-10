// PURPOSE: Turn a song into positioned pages. This is the pipeline the design describes — plan
//          the bars, measure each one from its content, pack bars into systems, pack systems into
//          pages — implemented as pure functions over the song model so that a page can be
//          engraved, and its cost measured, without a device and without a rendering stack.
// INPUTS: A Song, a page size in logical pixels, and a LayoutStyle carrying the spacing constants
//         and the text metrics.
// OUTPUTS: A list of PageLayout values with every bar and chord positioned. An empty song yields
//          an empty list rather than a blank page, so a caller cannot mistake "nothing to draw"
//          for "a page that came out empty".
// KEYWORDS: layout-engine, engraving, system-building, pagination, measure, pure-function,
//           spike-s4
//
// Two properties of this pipeline are load-bearing for the rest of the system:
//
//   1. It is PURE. Same song, same style, same page size gives the same geometry on every machine
//      and every run. That is what makes a layout assertion exact, and it is why the engine takes
//      text metrics as an input rather than reaching for a font.
//   2. It is ADDRESSABLE. Every placed bar carries the (sectionId, barIndex) that names it in the
//      song, and every placed chord carries its (beat, step). An annotation anchored in the song
//      model can therefore be drawn at the right place without either side knowing the other's
//      coordinates.
//
// What it deliberately does not do: rasterisation, glyph shaping, and play-order expansion. The
// first two belong to the renderer, and the third is not yet written (see the song model notes in
// docs/sdd.md). The engine lays out the bars as WRITTEN, which is the edit view.
import '../key.dart';
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
  //         logical pixels, including the margins the style reserves.
  // OUTPUTS: The pages, in reading order, each with its systems and bars positioned. An empty
  //          song yields an empty list.
  //
  //          If a single bar is wider than the content width it still forms a system of its own
  //          and overflows the page rather than being dropped or shrinking to nothing. That is a
  //          deliberate failure mode: a chord that runs off the edge is visible and reported, and
  //          a layout that silently omitted it would look correct while losing music.
  // KEYWORDS: pagination, system-building, overflow-behaviour, reading-order
  /// Returns the pages [song] is engraved into.
  List<PageLayout> layout(
    Song song, {
    required double pageWidth,
    required double pageHeight,
  }) {
    if (song.sections.isEmpty) {
      return const <PageLayout>[];
    }
    final double contentWidth = pageWidth - 2 * style.pageMargin;
    final double contentHeight = pageHeight - 2 * style.pageMargin;
    final List<_MeasuredBar> measured = _measureBars(song);
    final List<_SystemPlan> systems = _buildSystems(measured, contentWidth);
    return _buildPages(
      systems,
      contentWidth,
      contentHeight,
      pageWidth,
      pageHeight,
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
  //         default is [minLegibleScale].
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
  //          found by a fixed-count bisection, so the result is the same on every run.
  // KEYWORDS: fit-page, one-page, auto-scale, bisection, legibility-floor, page-mode
  /// Returns the single page [song] fits on, or why it does not.
  FitOutcome fitToPage(
    Song song, {
    required double pageWidth,
    required double pageHeight,
    double minScale = minLegibleScale,
  }) {
    if (song.sections.isEmpty || minScale <= 0 || minScale > 1) {
      return const FitOutcome(page: null, scale: 1, fits: false);
    }
    final List<PageLayout> asRequested = layout(
      song,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );
    if (asRequested.length == 1) {
      // Already one page at full size, so no shrinking is needed and none is done: a chart is
      // never enlarged past the surface it was given.
      return FitOutcome(page: asRequested.single, scale: 1, fits: true);
    }
    if (asRequested.isEmpty ||
        !_fitsOnOnePage(song, pageWidth, pageHeight, minScale)) {
      return FitOutcome(page: null, scale: minScale, fits: false);
    }
    double low = minScale;
    double high = 1;
    for (int step = 0; step < 24; step++) {
      final double mid = (low + high) / 2;
      if (_fitsOnOnePage(song, pageWidth, pageHeight, mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final PageLayout raw = layout(
      song,
      pageWidth: pageWidth / low,
      pageHeight: pageHeight / low,
    ).single;
    return FitOutcome(
      page: PageLayout(
        index: raw.index,
        size: raw.size,
        systems: raw.systems,
        scale: low,
      ),
      scale: low,
      fits: true,
    );
  }

  // PURPOSE: Answer whether the song would be one page if it were engraved at [scale] and shrunk
  //          back onto the caller's surface.
  // INPUTS: song, the surface size and the scale to test.
  // OUTPUTS: True when the enlarged page needs no more than one page.
  // KEYWORDS: fit-test, virtual-page, single-page
  bool _fitsOnOnePage(
    Song song,
    double pageWidth,
    double pageHeight,
    double scale,
  ) =>
      layout(
        song,
        pageWidth: pageWidth / scale,
        pageHeight: pageHeight / scale,
      ).length ==
      1;

  // PURPOSE: Report the width a bar needs for its content. Exposed because the bar width is the
  //          unit a layout test reasons in, and because a caller sizing a single bar should not
  //          have to lay out a whole song to find out.
  // INPUTS: bar — the bar to measure. key — the key its chords are spelled in, which affects the
  //         width because `Bb` and `A#` are different strings.
  // OUTPUTS: The bar's natural width, never less than the style's minimum bar width. A bar with
  //          no chords measures to the minimum, because an empty cell still reserves room.
  // KEYWORDS: bar-measurement, natural-width, minimum-width, key-dependent-width
  /// Returns the width [bar] needs when its chords are spelled in [key].
  double measureBar(Bar bar, Key key) {
    double content = 0;
    for (final double cellWidth in _cellWidths(bar, key)) {
      content += cellWidth;
    }
    final double natural = content + 2 * style.barPadding;
    return natural < style.barMinWidth ? style.barMinWidth : natural;
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

  List<_MeasuredBar> _measureBars(Song song) {
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
            width: measureBar(bar, song.key),
            startsSection: index == 0,
            sectionLabel: index == 0 ? section.label.toString() : null,
          ),
        );
      }
    }
    return measured;
  }

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
        ),
      );
      pageIndex++;
      currentSystems = <PlacedSystem>[];
      y = style.pageMargin;
      firstOnPage = true;
    }

    for (final _SystemPlan plan in systems) {
      final double height = _systemHeight(plan);
      final double spacing = firstOnPage ? 0 : style.systemSpacing;
      if (!firstOnPage &&
          y + spacing + height > style.pageMargin + contentHeight) {
        flushPage();
      }
      final double top = firstOnPage ? y : y + spacing;
      currentSystems.add(_placeSystem(plan, top));
      y = top + height;
      firstOnPage = false;
    }
    flushPage();
    return pages;
  }

  double _systemHeight(_SystemPlan plan) =>
      (plan.sectionLabel == null ? 0 : style.sectionLabelHeight) +
      style.barHeight;

  PlacedSystem _placeSystem(_SystemPlan plan, double top) {
    final double labelHeight = plan.sectionLabel == null
        ? 0
        : style.sectionLabelHeight;
    final double staveTop = top + labelHeight;
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
          chords: _placeChords(measured, bounds),
        ),
      );
      x += measured.width;
    }
    return PlacedSystem(
      bounds: LayoutRect.fromLTWH(
        style.pageMargin,
        top,
        x - style.pageMargin,
        labelHeight + style.barHeight,
      ),
      bars: bars,
      sectionId: plan.sectionId,
      sectionLabel: plan.sectionLabel,
    );
  }

  List<PlacedChord> _placeChords(_MeasuredBar measured, LayoutRect barBounds) {
    final Bar bar = measured.bar;
    final List<double> offsets = _cellOffsets(
      bar,
      measured.key,
      barBounds.size.width,
    );
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
  final bool startsSection;
  final String? sectionLabel;
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
