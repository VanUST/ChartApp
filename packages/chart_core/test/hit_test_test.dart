// PURPOSE: Pin the hit test's answers with exact geometry that can be derived by hand, because the
//          whole point of a hit test is that a human can point at something and know what they
//          pointed at. The engine's text metrics are fixed advances here, so every coordinate below
//          is arithmetic rather than a font measurement, and a failure names a real regression
//          instead of a font version. The round trip is printed to stdout as well as asserted, so
//          the numbers a reader would check by hand are in the transcript and not only in a
//          boolean.
// INPUTS: None.
// OUTPUTS: Pass/fail per behaviour, plus `hit.cell ...` lines on stdout naming the point tested and
//          the address it returned.
// KEYWORDS: test, hit-testing, round-trip, page-scale, fit, edge-case, hand-derived, evidence
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A 4/4 bar holding one major triad on beat 0 and nothing else.
Bar oneChordBar(int rootPitchClass) => Bar(
  chords: <BeatChord>[
    BeatChord(chord: Chord(root: ChordRoot(rootPitchClass)), beat: 0),
  ],
);

/// A 4/4 bar holding one chord on the given beat.
Bar chordOnBeat(int rootPitchClass, int beat) => Bar(
  chords: <BeatChord>[
    BeatChord(
      chord: Chord(root: ChordRoot(rootPitchClass)),
      beat: beat,
    ),
  ],
);

/// A section of [count] one-chord bars, all rooted on C.
Section sectionOf(String id, String label, int count) => Section(
  id: id,
  label: SectionLabel.letter(label),
  bars: <Bar>[for (int i = 0; i < count; i++) oneChordBar(0)],
);

/// The centre of a rectangle, which is the point a finger is least likely to miss.
LayoutOffset centreOf(LayoutRect rect) => LayoutOffset(
  rect.left + rect.size.width / 2,
  rect.top + rect.size.height / 2,
);

void main() {
  const LayoutEngine engine = LayoutEngine();

  // Two sections, so a page has more than one system and therefore a real margin between them.
  // Section A is four bars — exactly one system at a 400-point page. Section B is two.
  final Song song = Song(
    title: 'Hit',
    sections: <Section>[sectionOf('sec-a', 'A', 4), sectionOf('sec-b', 'B', 2)],
  );
  final PageLayout page = engine
      .layout(song, pageWidth: 400, pageHeight: 600)
      .single;

  group('hitTestPage', () {
    test('every cell of every bar answers with its own bar address', () {
      // The round trip the whole feature rests on: take a bar and cell the layout produced, ask
      // for the point at the middle of that cell, and get that same bar and cell back. Checked for
      // every cell of every bar rather than one convenient example, because a hit test that works
      // for the first bar and lies for the last is exactly the failure a single example hides.
      int checked = 0;
      for (final PlacedBar bar in page.bars) {
        for (final PlacedCell cell in bar.cells) {
          final LayoutOffset point = centreOf(cell.bounds);
          final ChartHit? hit = hitTestPage(page, point);
          stdout.writeln(
            'hit.cell point=(${point.x.toStringAsFixed(2)},'
            '${point.y.toStringAsFixed(2)}) '
            'answered=${hit == null ? 'null' : '${hit.sectionId}[${hit.barIndex}]'
                      ' beat=${hit.beat}'} '
            'expected=${bar.sectionId}[${bar.barIndex}] beat=${cell.beat}',
          );
          expect(hit, isNotNull);
          expect(hit!.sectionId, bar.sectionId);
          expect(hit.barIndex, bar.barIndex);
          expect(hit.beat, cell.beat);
          checked++;
        }
      }
      expect(checked, 24, reason: 'four 4/4 bars plus two 4/4 bars');
    });

    test('a point in the margin between two systems is over no bar', () {
      // Systems are separated by style.systemSpacing = 12, so there is a real band no stave covers.
      // It names no bar: a touch there has not chosen anything, and answering with the nearest bar
      // would silently move the musician's edit one system up or down.
      final PlacedSystem first = page.systems.first;
      final PlacedSystem second = page.systems[1];
      final LayoutOffset inMargin = LayoutOffset(
        page.bars.first.bounds.left + 5,
        (first.bounds.bottom + second.bounds.top) / 2,
      );
      stdout.writeln(
        'hit.margin point=(${inMargin.x},${inMargin.y}) '
        'gap=(${first.bounds.bottom}..${second.bounds.top})',
      );
      expect(hitTestPage(page, inMargin), isNull);
    });

    test('a point in a section-label band is over no bar', () {
      // The system's box includes the 22-point band its label sits in; that band is not music. The
      // point is inside the system and above the stave, which is what makes it a separate case from
      // the system margin.
      final PlacedSystem first = page.systems.first;
      final LayoutOffset inLabel = LayoutOffset(
        first.bars.first.bounds.left + 5,
        first.bounds.top + 2,
      );
      expect(
        hitTestPage(page, inLabel),
        isNull,
        reason:
            'y=${inLabel.y} is above the stave top ${first.bars.first.bounds.top}',
      );
    });

    test('a point past the last bar of a system is over no bar', () {
      // The page is 400 wide and four 76-wide bars end at x = 24 + 304 = 328, so x = 340 shares the
      // stave's height with the music and lies past its right edge.
      final PlacedBar last = page.systems.first.bars.last;
      final LayoutOffset past = LayoutOffset(
        last.bounds.right + 12,
        last.bounds.top + last.bounds.size.height / 2,
      );
      stdout.writeln(
        'hit.past-last point=(${past.x},${past.y}) '
        'last_right=${last.bounds.right} page_width=${page.size.width}',
      );
      expect(hitTestPage(page, past), isNull);
    });

    test('a point in a bar\'s padding is over the bar and over no cell', () {
      // Cell 0 begins one barPadding (8) inside the left edge. A point 1 point inside the bar is
      // therefore on the bar and on no cell — the state the viewer uses to select a whole bar.
      final PlacedBar bar = page.bars.first;
      final LayoutOffset inPadding = LayoutOffset(
        bar.bounds.left + 1,
        bar.bounds.top + bar.bounds.size.height / 2,
      );
      final ChartHit? hit = hitTestPage(page, inPadding);
      stdout.writeln(
        'hit.padding point=(${inPadding.x},${inPadding.y}) '
        'answered=${hit == null ? 'null' : '${hit.sectionId}[${hit.barIndex}] '
                  'beat=${hit.beat}'}',
      );
      expect(hit, isNotNull);
      expect(hit!.sectionId, 'sec-a');
      expect(hit.barIndex, 0);
      expect(hit.cell, isNull);
      expect(hit.beat, isNull);
    });

    test(
      'the shared edge of two bars resolves to the first in reading order',
      () {
        // A rectangle contains its own edge, and neighbouring bars share one, so the rule has to be
        // stated: the left bar wins. Without a rule the answer would depend on iteration order.
        final PlacedBar first = page.bars[0];
        final PlacedBar second = page.bars[1];
        expect(second.bounds.left, first.bounds.right);
        final ChartHit? hit = hitTestPage(
          page,
          LayoutOffset(first.bounds.right, centreOf(first.bounds).y),
        );
        expect(hit, isNotNull);
        expect(hit!.barIndex, 0);
      },
    );

    test('a point on a cell boundary resolves to the cell before it', () {
      // The same rule one level down: the columns tile the interior and each column contains its
      // right edge, so a point exactly on the edge between cell 0 and cell 1 names cell 0. Stating
      // it here is what stops the answer depending on the order the loop happens to use.
      final PlacedBar bar = page.bars.first;
      final LayoutOffset onEdge = LayoutOffset(
        bar.cells[1].bounds.left,
        centreOf(bar.cells[1].bounds).y,
      );
      expect(hitTestPage(page, onEdge)!.beat, 0);
    });
  });

  group('PageLayout.pagePointOf', () {
    test('scale 1 maps a surface point to itself', () {
      const PageLayout ordinary = PageLayout(
        index: 0,
        size: LayoutSize(400, 600),
        systems: <PlacedSystem>[],
      );
      expect(
        ordinary.pagePointOf(const LayoutOffset(123, 456)),
        const LayoutOffset(123, 456),
      );
    });

    test('a fitted page divides by its scale, which is what makes the difference visible', () {
      // 300 bars cannot fit one 1200x900 page at full size, so FIT shrinks it and the page keeps a
      // scale below 1. The conversion is the inverse of the painter's canvas.scale, so it multiplies
      // the surface point UP into the larger engraved space.
      final Song long = Song(
        title: 'Long',
        sections: <Section>[sectionOf('sec-a', 'A', 300)],
      );
      final FitOutcome fit = engine.fitToPage(
        long,
        pageWidth: 1200,
        pageHeight: 900,
      );
      final PageLayout fitted = fit.page!;
      expect(fitted.scale, lessThan(1));
      const LayoutOffset surface = LayoutOffset(400, 300);
      final LayoutOffset pagePoint = fitted.pagePointOf(surface);
      stdout.writeln(
        'hit.scale scale=${fitted.scale} surface=(${surface.x},${surface.y}) '
        'page=(${pagePoint.x},${pagePoint.y})',
      );
      expect(pagePoint.x, closeTo(surface.x / fitted.scale, 1e-9));
      expect(pagePoint.y, closeTo(surface.y / fitted.scale, 1e-9));
      expect(pagePoint, isNot(surface));
    });

    test(
      'a surface point round-trips back to the cell a fitted page drew there',
      () {
        // The bug this exists to catch: a hit test that assumes scale 1 answers correctly on every
        // ordinary page and wrongly only when FIT has shrunk one. The last bar is the strongest case,
        // because its engraved x is near the far edge of the much larger virtual page.
        final Song long = Song(
          title: 'Long',
          sections: <Section>[sectionOf('sec-a', 'A', 300)],
        );
        final PageLayout fitted = engine
            .fitToPage(long, pageWidth: 1200, pageHeight: 900)
            .page!;
        final PlacedBar last = fitted.bars.last;
        final PlacedCell lastCell = last.cells.last;
        final LayoutOffset engraved = centreOf(lastCell.bounds);
        final LayoutOffset surface = LayoutOffset(
          engraved.x * fitted.scale,
          engraved.y * fitted.scale,
        );

        final ChartHit? correct = hitTestPage(
          fitted,
          fitted.pagePointOf(surface),
        );
        expect(correct, isNotNull);
        expect(correct!.barIndex, last.barIndex);
        expect(correct.beat, lastCell.beat);

        // And the naive reading of the same surface point — the one a hit test that forgot the scale
        // would take — is a different place on the page, so the conversion is load-bearing here.
        final ChartHit? naive = hitTestPage(fitted, surface);
        stdout.writeln(
          'hit.fit-scale scale=${fitted.scale} surface=(${surface.x},'
          '${surface.y}) correct=${correct.barIndex}:${correct.beat} '
          'naive=${naive == null ? 'null' : '${naive.barIndex}:${naive.beat}'}',
        );
        expect(
          naive == null ||
              naive.barIndex != correct.barIndex ||
              naive.beat != correct.beat,
          isTrue,
          reason:
              'the unscaled reading must differ, or this test proves nothing',
        );
      },
    );
  });
}
