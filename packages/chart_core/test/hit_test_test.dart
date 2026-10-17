// PURPOSE: Pin the hit test's answers with exact geometry that can be derived by hand, because the
//          whole point of a hit test is that a human can point at something and know what they
//          pointed at. The engine's text metrics are fixed advances here, so every coordinate below
//          is arithmetic rather than a font measurement, and a failure names a real regression
//          instead of a font version. The round trip is printed to stdout as well as asserted, so
//          the numbers a reader would check by hand are in the transcript and not only in a
//          boolean.
//
//          THE PROPERTY THIS FILE EXISTS FOR IS ONE SENTENCE: A TAP NAMES THE BAR IT LOOKS LIKE IT
//          NAMES. It has failed on hardware twice — once when the staff's target was built out of
//          the beat captions and switching the captions off made a tap name nothing, and once when
//          the chord line's answer was narrowed by a column test whose columns could be absent. The
//          first case below therefore walks EVERY bar of a page and taps its own centre, which is
//          the check that would have caught both: an answer derived from a rectangle can be checked
//          against that rectangle, and an answer derived from anything else cannot.
//
//          ONE SURFACE, ONE ANSWER. The owner's rule named three bands — above the staff a chord, on
//          the staff a note, below the bar neither — and this build carries only the first: the bars
//          and their chord rows, with the staff and the notes removed. So `hitTestPage` answers for
//          the bar's own rectangle and for nothing else, and a point below a bar names nothing.
//          There are no columns in the answer either — a hit carries the point in the bar's own
//          coordinates, which is the frame a mark's place is written in.
// INPUTS: None.
// OUTPUTS: Pass/fail per behaviour, plus `hit ...` and `hit.staff ...` lines on stdout naming the
//          point tested and the address it returned.
// KEYWORDS: test, hit-testing, round-trip, page-scale, fit, edge-case, hand-derived, evidence,
//           chord-band, no-grid, tap-names-the-bar
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

import '../support/place_fixture.dart';

/// A bar holding one major triad at the first fixture slot and nothing else.
Bar oneChordBar(int rootPitchClass) => Bar(
  chords: <ChordMark>[
    ChordMark(
      place: placeAt(0),
      chord: Chord(root: ChordRoot(rootPitchClass)),
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
  final Song song = Song(
    title: 'Hit',
    sections: <Section>[sectionOf('sec-a', 'A', 4), sectionOf('sec-b', 'B', 2)],
  );
  final PageLayout page = engine
      .layout(song, pageWidth: 400, pageHeight: 600)
      .single;

  group('hitTestPage', () {
    test('every bar of a page answers with its own address', () {
      // THE CHECK THE TABLET FOUND TWICE. The old case walked `bar.cells` and asked for the middle
      // of each column — `the getter 'cells' isn't defined for the type 'PlacedBar'` is what it says
      // now, and the column it walked was the grid. What replaces it is the property itself, stated
      // without a grid: a point in a bar's own rectangle names that bar, and the hit's local x is the
      // distance from the bar's left edge. Checked for EVERY bar rather than one convenient example,
      // because a hit test that works for the first bar and lies for the last is exactly the failure
      // a single example hides.
      int checked = 0;
      for (final PlacedBar bar in page.bars) {
        final LayoutOffset point = centreOf(bar.bounds);
        final ChartHit? hit = hitTestPage(page, point);
        final double expectedX = point.x - bar.bounds.left;
        stdout.writeln(
          'hit point=(${point.x.toStringAsFixed(2)},'
          '${point.y.toStringAsFixed(2)}) '
          'answered=${hit == null ? 'null' : '${hit.sectionId}[${hit.barIndex}]'
                    ' x=${hit.local.x.toStringAsFixed(2)}'} '
          'expected=${bar.sectionId}[${bar.barIndex}] x=${expectedX.toStringAsFixed(2)}',
        );
        expect(
          hit,
          isNotNull,
          reason:
              'a tap in the middle of ${bar.sectionId}[${bar.barIndex}] must name that bar',
        );
        expect(hit!.sectionId, bar.sectionId);
        expect(hit.barIndex, bar.barIndex);
        expect(
          hit.local.x,
          closeTo(expectedX, 1e-9),
          reason:
              'the local x is the distance from the bar own left edge, which is the frame a '
              'mark place is measured in',
        );
        checked++;
      }
      expect(checked, page.bars.length);
      expect(checked, 6, reason: 'four bars of section A and two of section B');
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

    test('BELOW THE BAR IS NEITHER: the chord line answers nothing there', () {
      // THE OWNER'S RULE, AS AN ASSERTION: above the staff is a chord, on the staff is a note, below
      // the bar is neither. The bar's own rectangle IS the chord band, so a point under it must not
      // be answered by the chord line's hit test — that answer, on a chart with no staff, is the one
      // that would tell a musician he had selected a bar when he had pointed at blank paper.
      final PlacedBar bar = page.bars.first;
      final LayoutOffset below = LayoutOffset(
        bar.bounds.left + bar.bounds.size.width / 2,
        bar.bounds.bottom + 1,
      );
      stdout.writeln(
        'hit.below-bar point=(${below.x},${below.y}) '
        'bar_bottom=${bar.bounds.bottom}',
      );
      expect(hitTestPage(page, below), isNull);
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

    test('a point one pixel inside a bar is ON the bar', () {
      // This case used to assert the opposite for a point in a bar's leading padding: "over the bar
      // and over no cell", because a cell began one padding inside the edge. There is no cell to be
      // outside of any more, so the padding is the bar's own writing space and a touch there names
      // it — the state the viewer uses to select a whole bar is now every point in it.
      final PlacedBar bar = page.bars.first;
      final LayoutOffset inside = LayoutOffset(
        bar.bounds.left + 1,
        bar.bounds.top + bar.bounds.size.height / 2,
      );
      final ChartHit? hit = hitTestPage(page, inside);
      expect(hit, isNotNull);
      expect(hit!.sectionId, 'sec-a');
      expect(hit.barIndex, 0);
      expect(hit.local.x, closeTo(1, 1e-9));
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
      // scale below 1. The conversion is the inverse of the painter's `canvas.scale(scale, scale)`,
      // so it DIVIDES the surface point back into the larger engraved space. It used to say that it
      // "multiplies the surface point UP" here; that was the same false claim that made the pen
      // capture path multiply, and the two disagreed by a factor of the scale.
      final Song long = Song(
        title: 'Long',
        sections: <Section>[sectionOf('sec-a', 'A', 300)],
      );
      final FitOutcome fit = engine.fitToPage(
        long,
        pageWidth: 1200,
        pageHeight: 700,
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
      'a surface point round-trips back to the bar a fitted page drew there',
      () {
        // The bug this exists to catch: a hit test that assumes scale 1 answers correctly on every
        // ordinary page and wrongly only when FIT has shrunk one. The last bar is the strongest case,
        // because its engraved x is near the far edge of the much larger virtual page.
        final Song long = Song(
          title: 'Long',
          sections: <Section>[sectionOf('sec-a', 'A', 300)],
        );
        final PageLayout fitted = engine
            .fitToPage(long, pageWidth: 1200, pageHeight: 700)
            .page!;
        final PlacedBar last = fitted.bars.last;
        final LayoutOffset engraved = centreOf(last.bounds);
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
        expect(correct.local.x, closeTo(engraved.x - last.bounds.left, 1e-6));

        // And the naive reading of the same surface point — the one a hit test that forgot the scale
        // would take — is a different place on the page, so the conversion is load-bearing here.
        final ChartHit? naive = hitTestPage(fitted, surface);
        stdout.writeln(
          'hit.fit-scale scale=${fitted.scale} surface=(${surface.x},'
          '${surface.y}) correct=${correct.barIndex}:'
          '${correct.local.x.toStringAsFixed(1)} '
          'naive=${naive == null ? 'null' : '${naive.barIndex}:'
                    '${naive.local.x.toStringAsFixed(1)}'}',
        );
        expect(
          naive == null ||
              naive.barIndex != correct.barIndex ||
              (naive.local.x - correct.local.x).abs() > 1,
          isTrue,
          reason:
              'the unscaled reading must differ, or this test proves nothing',
        );
      },
    );
  });
}
