// PURPOSE: Pin where the key and the meter are stated on the page, what the statement costs, and
//          what it must NOT touch. The owner asked for the metre to be written at the start of the
//          composition together with the key, because neither was on the page at all: the key lived
//          in the scene bar and the metre appeared only on a bar that changed it. This file holds
//          both halves of the change honest — the line exists and is placed, AND the first bar's
//          chord, columns and section letter are exactly what they were.
// INPUTS: None. The charts are built here, and the style is the engine's default, whose fixed
//         metrics make every number below arithmetic rather than a font measurement.
// OUTPUTS: Pass/fail per claim, plus `header.*` lines on stdout naming the text, the band, the first
//          system's top and the digitised cost, so a failure quotes the geometry it was given.
// KEYWORDS: test, chart-header, key, meter, engraving-cost, no-collision, first-page-only,
//           fitted-page, d27
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A section of [count] identical bars, so that a bar on page 1 and a bar on page 2 have the same
/// content and their geometry is comparable number for number.
Section sectionOf(String id, String label, int count, TimeSignature meter) =>
    Section(
      id: id,
      label: SectionLabel.letter(label),
      bars: <Bar>[
        for (int index = 0; index < count; index++)
          Bar(
            timeSignature: meter,
            chords: <BeatChord>[
              BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
              BeatChord(chord: Chord(root: ChordRoot(7)), beat: 2),
            ],
          ),
      ],
    );

/// A chart of [bars] bars of [meter] in [key], and nothing else.
Song chartOf({
  Key key = Key.cMajor,
  TimeSignature meter = TimeSignature.fourFour,
  int bars = 8,
}) => Song(
  title: 'Header',
  key: key,
  sections: <Section>[sectionOf('A', 'A', bars, meter)],
);

void main() {
  const LayoutEngine engine = LayoutEngine();
  const LayoutStyle style = LayoutStyle();
  // Two numbers the default style fixes, restated so a change to either is visible here rather than
  // mysterious: the chord role's line height and the gap below the header.
  const double chordLine = 18;
  final double gap = style.chartHeaderGap;

  group('what it says', () {
    test('a chart in C major 4/4 states exactly that, in notation', () {
      final PageLayout page = engine
          .layout(chartOf(), pageWidth: 400, pageHeight: 600)
          .single;
      final PlacedChartHeader header = page.header!;
      stdout.writeln('header.text "${header.text}" bounds=${header.bounds}');
      // NOT TRANSLATED (D27): the key is a name and the meter is a fraction, and both are written the
      // same way in every language this application ships.
      expect(header.text, 'C major · 4/4');
      expect(header.bounds.left, style.pageMargin);
      // The band is as tall as the line it holds, in the engine's chord role — the engine reports
      // A_KEY_AND_METER_LINE_HEIGHT for it, so the reservation and the drawing are one number.
      expect(header.bounds.size.height, chordLine);
      // It spans the content width, so nothing about the page's left or right margin moves.
      expect(header.bounds.size.width, 400 - 2 * style.pageMargin);
    });

    test('a minor chart states its own key, and a 3/4 chart its own meter', () {
      const Key fSharpMinor = Key(
        tonic: WrittenNote(NoteLetter.f, 1),
        mode: Mode.minor,
      );
      final PageLayout page = engine
          .layout(
            chartOf(key: fSharpMinor, meter: TimeSignature.threeFour),
            pageWidth: 400,
            pageHeight: 600,
          )
          .single;
      stdout.writeln('header.minor "${page.header!.text}"');
      expect(page.header!.text, 'F# minor · 3/4');
    });
  });

  group('what it costs', () {
    test('its own line plus a gap, on the first page and on no other', () {
      // A page short enough that eight bars need two of them, so the second page's top edge can be
      // measured: it must be the page margin and nothing else.
      final List<PageLayout> pages = engine.layout(
        chartOf(bars: 24),
        pageWidth: 400,
        pageHeight: 300,
      );
      expect(pages.length, greaterThan(1));
      final double firstTop = pages.first.systems.first.bounds.top;
      final double laterTop = pages[1].systems.first.bounds.top;
      stdout.writeln(
        'header.cost header_height=${pages.first.header!.bounds.size.height} '
        'gap=$gap band=${pages.first.header!.bounds.size.height + gap} '
        'page1_system_top=$firstTop page2_system_top=$laterTop '
        'content_height=${300 - 2 * style.pageMargin}',
      );
      expect(pages.first.header, isNotNull);
      expect(pages[1].header, isNull);
      expect(
        firstTop,
        style.pageMargin + chordLine + gap,
        reason: 'the first system starts below the band the header reserved',
      );
      expect(
        laterTop,
        style.pageMargin,
        reason: 'a page after the first gives up nothing for a header it does not carry',
      );
    });

    test('the page keeps its size; what changes is the room on page one', () {
      // The cost is stated as CONTENT HEIGHT rather than as a bigger page: the paper is the size the
      // caller asked for, and the band comes out of what the systems may occupy on page one.
      final PageLayout page = engine
          .layout(chartOf(), pageWidth: 400, pageHeight: 600)
          .single;
      expect(page.size.width, 400);
      expect(page.size.height, 600);
      final double contentBottom =
          style.pageMargin + 600 - 2 * style.pageMargin;
      expect(
        page.systems.last.bounds.bottom,
        lessThanOrEqualTo(contentBottom),
        reason: 'nothing is pushed off the page by the header',
      );
    });

    test(
      'the header moves and scales with the page, because it is engraving',
      () {
        // A fitted page is engraved larger and drawn smaller. The header's published box is in the
        // SAME coordinate system as every other rectangle, so `surfacePointOf` — the page's own one
        // bridge to the glass — places it, and it therefore scales, pans and prints with the music
        // rather than staying put like chrome would.
        final FitOutcome fit = engine.fitToPage(
          chartOf(bars: 120),
          pageWidth: 600,
          pageHeight: 800,
        );
        expect(fit.fits, isTrue);
        final PageLayout page = fit.page!;
        final PlacedChartHeader header = page.header!;
        final LayoutOffset surface = page.surfacePointOf(header.bounds.origin);
        stdout.writeln(
          'header.fit scale=${page.scale} drawn_scale=${page.drawnScale} '
          'engraved_origin=${header.bounds.origin} surface_origin=$surface',
        );
        expect(
          page.scale,
          lessThan(1),
          reason: 'a fitted page must actually be scaled',
        );
        expect(surface.x, closeTo(header.bounds.left * page.drawnScale, 1e-9));
        expect(
          surface.y,
          closeTo(header.bounds.top * page.drawnScale + page.pan.y, 1e-9),
        );
        // And the same inverse the pen and the hit test use puts it back.
        expect(page.pagePointOf(surface), header.bounds.origin);
      },
    );
  });

  group('what it must not touch', () {
    test('it sits above the section letter and above the first bar', () {
      final PageLayout page = engine
          .layout(chartOf(), pageWidth: 400, pageHeight: 600)
          .single;
      final PlacedSystem system = page.systems.first;
      final PlacedBar bar = system.bars.first;
      final PlacedChartHeader header = page.header!;
      stdout.writeln(
        'header.collision header=${header.bounds} '
        'system=${system.bounds} label_band=${system.labelBand} bar=${bar.bounds}',
      );
      // The section letter keeps its own band at the top of the system, and the header is ABOVE it.
      expect(system.labelBand, isNotNull);
      expect(system.labelBand!.top, greaterThanOrEqualTo(header.bounds.bottom));
      // The first bar — its chord, its cells, its rectangle — is entirely below both.
      expect(bar.bounds.top, greaterThanOrEqualTo(system.labelBand!.bottom));
      expect(bar.bounds.top, greaterThan(header.bounds.bottom));
      expect(header.bounds.bottom, lessThan(system.bounds.top));
    });

    test('the first bar keeps its chord and its column widths', () {
      // The reason the header is a page band and not a block in the first bar: a chart's first bar
      // may hold a chord, and a cell is a tap target whose column the hit test names. Nothing here
      // may move. Page 2's bars are identical to page 1's by construction (`sectionOf` builds one
      // kind of bar), so their RELATIVE geometry is the comparison.
      final List<PageLayout> pages = engine.layout(
        chartOf(bars: 24),
        pageWidth: 400,
        pageHeight: 300,
      );
      final PlacedBar first = pages.first.bars.first;
      final PlacedBar later = pages[1].bars.first;
      expect(pages.first.header, isNotNull);
      expect(pages[1].header, isNull);
      expect(first.bounds.left, later.bounds.left);
      expect(first.bounds.size.width, later.bounds.size.width);
      // Every cell column, relative to the bar's left edge.
      expect(first.cells, hasLength(later.cells.length));
      for (int index = 0; index < first.cells.length; index++) {
        expect(
          first.cells[index].bounds.left - first.bounds.left,
          later.cells[index].bounds.left - later.bounds.left,
          reason: 'cell $index column',
        );
        expect(
          first.cells[index].bounds.size.width,
          later.cells[index].bounds.size.width,
          reason: 'cell $index width',
        );
      }
      // And the chord's own box, relative to the bar it sits in.
      expect(first.chords, hasLength(2));
      for (int index = 0; index < first.chords.length; index++) {
        expect(
          first.chords[index].bounds.left - first.bounds.left,
          later.chords[index].bounds.left - later.bounds.left,
          reason: 'chord $index x',
        );
        expect(
          first.chords[index].bounds.top - first.bounds.top,
          later.chords[index].bounds.top - later.bounds.top,
          reason: 'chord $index y',
        );
      }
    });

    test('the meter is stated once: the header has already said it', () {
      // A chart that does not open in 4/4 used to sign its first bar in the bar's own corner. On a
      // page whose header states the opening meter that would put `3/4` on two lines within a
      // centimetre, so the header's statement replaces the sign — on the first page only.
      final Song waltz = chartOf(meter: TimeSignature.threeFour, bars: 24);
      final List<PageLayout> pages = engine.layout(
        waltz,
        pageWidth: 400,
        pageHeight: 300,
      );
      expect(pages.length, greaterThan(1));
      final Map<String, String> onFirst = meterSignsOnPage(waltz, pages.first);
      final Map<String, String> onSecond = meterSignsOnPage(waltz, pages[1]);
      stdout.writeln(
        'header.meter header="${pages.first.header!.text}" '
        'first_page_signs=$onFirst second_page_signs=$onSecond',
      );
      expect(
        onFirst.keys,
        isNot(contains('A#0')),
        reason: 'the bar the header speaks for is not signed again',
      );
      expect(
        onSecond.values,
        contains('3/4'),
        reason: 'a later page has no header, so its system start is signed as it always was',
      );
    });
  });
}
