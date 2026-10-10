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
