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
//          IT COVERS BOTH SURFACES OVER THE SAME BARS, and the two are the owner's rule made
//          geometry: `hitTestPage` answers for the chord band, which is the bar's own rectangle;
//          `hitTestMelodyStaff` answers for the staff below it; and a point below the staff is over
//          neither. There are no columns in either answer — a hit carries the point in the bar's own
//          coordinates, which is the frame a mark's place is written in.
// INPUTS: None.
// OUTPUTS: Pass/fail per behaviour, plus `hit ...` and `hit.staff ...` lines on stdout naming the
//          point tested and the address it returned.
// KEYWORDS: test, hit-testing, round-trip, page-scale, fit, edge-case, hand-derived, evidence,
//           melody-staff, chord-band, no-grid, tap-names-the-bar
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

/// A song that DECLARES a pitched staff and carries a chord and a note at every fixture slot.
///
/// The declaration is the point: D29 makes the staff exist because the chart asked for it, so every
/// bar of this song carries one whether or not a note was written on it, and a tap on its five lines
/// has something to name.
Song staffSong() => Song(
  title: 'Staff',
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'staff-a',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int barIndex = 0; barIndex < 4; barIndex++)
          Bar(
            chords: <ChordMark>[
              for (int slot = 0; slot < 4; slot++)
                ChordMark(
                  place: placeAt(slot),
                  chord: Chord(root: ChordRoot(barIndex + slot)),
                ),
            ],
            melody: <NoteMark>[
              for (int slot = 0; slot < 4; slot++)
                NoteMark(
                  place: placeAt(slot),
                  pitch: const PitchedNote(
                    note: WrittenNote(NoteLetter.e, 0),
                    octave: 4,
                  ),
                  value: const NoteValue.plain(NoteBase.quarter),
                ),
            ],
          ),
      ],
    ),
  ],
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
            .fitToPage(long, pageWidth: 1200, pageHeight: 900)
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

  group('hitTestMelodyStaff', () {
    // THE SECOND SURFACE, AND THE DEFECT THAT MADE THESE CASES NECESSARY. The staff's touch target
    // used to be built out of the beat CAPTIONS: the band ran down to the caption row and each
    // beat's column was that beat's marker. The owner read the captions and the tick marks as noise
    // and asked for them to go; switching them off then switched off NOTE ENTRY, because a tap on
    // the five lines named nothing. The tablet found it in one tap — `viewer.select staff ... hit=none`
    // — after seventy tests stayed green. There are no captions to switch off any more (the engine
    // publishes no markers at all), so the pair below instead proves the band itself answers, and
    // that the answer carries the point rather than a column.
    final Song staffChart = staffSong();
    final PageLayout staffPage = engine
        .layout(staffChart, pageWidth: 400, pageHeight: 600)
        .first;

    test('a tap anywhere on a bar staff names that bar and the point tapped', () {
      int tapped = 0;
      for (final PlacedBar bar in staffPage.bars) {
        expect(
          bar.melody.isEmpty,
          isFalse,
          reason: 'D29: the chart declared a staff, so the bar carries one',
        );
        // Four x positions across the staff, so the case cannot pass by one lucky middle.
        for (int step = 0; step < 4; step++) {
          final double x =
              bar.melody.bounds.left +
              bar.melody.bounds.size.width * (step + 1) / 5;
          final LayoutOffset point = LayoutOffset(
            x,
            bar.melody.bounds.top + bar.melody.bounds.size.height / 2,
          );
          final ChartHit? hit = hitTestMelodyStaff(staffPage, point);
          stdout.writeln(
            'hit.staff bar=${bar.barIndex} step=$step '
            'point=(${point.x.toStringAsFixed(2)},${point.y.toStringAsFixed(2)}) '
            'answered=${hit == null ? 'null' : '${hit.sectionId}[${hit.barIndex}] '
                      'x=${hit.local.x.toStringAsFixed(2)}'}',
          );
          expect(
            hit,
            isNotNull,
            reason:
                'a tap on the five lines of bar ${bar.barIndex} must name that bar: a staff whose '
                'lines cannot be touched is a staff notes cannot be written on',
          );
          expect(hit!.sectionId, bar.sectionId);
          expect(hit.barIndex, bar.barIndex);
          expect(
            hit.local.x,
            closeTo(x - bar.bounds.left, 1e-9),
            reason:
                'the x a tap names is the tap own place in the bar, which is the number a note '
                'would be written at',
          );
          tapped++;
        }
      }
      expect(tapped, 16, reason: 'four 4/4 bars, four points across each');
    });

    test('the touch band is the five lines and half a space below them', () {
      final PlacedBar bar = staffPage.bars.first;
      final double space = bar.melody.bounds.size.height / 4;
      final double columnX = bar.melody.bounds.left + 12;
      final ChartHit? onTheLines = hitTestMelodyStaff(
        staffPage,
        LayoutOffset(columnX, bar.melody.bounds.top + 1),
      );
      // Half a space under the bottom line is where a notehead on the ledger line below the staff
      // sits, so that band is staff; a whole space below it is blank paper and is not.
      final ChartHit? onTheLedgerNote = hitTestMelodyStaff(
        staffPage,
        LayoutOffset(columnX, bar.melody.bounds.bottom + space / 4),
      );
      final ChartHit? onBlankPaper = hitTestMelodyStaff(
        staffPage,
        LayoutOffset(columnX, bar.melody.bounds.bottom + space),
      );
      // Above the top line, inside the band the system reserved, there is nothing to touch either:
      // the reserved band is not the staff, and a tap on it must not be told it named a note.
      final ChartHit? aboveTheStaff = hitTestMelodyStaff(
        staffPage,
        LayoutOffset(columnX, bar.melody.bounds.top - 12),
      );
      stdout.writeln(
        'hit.staff-band on_lines=${onTheLines?.local.x.toStringAsFixed(1)} '
        'on_ledger=${onTheLedgerNote?.local.x.toStringAsFixed(1)} '
        'below_band=${onBlankPaper?.local.x} above_staff=${aboveTheStaff?.local.x} '
        'staff=(${bar.melody.bounds.top}..${bar.melody.bounds.bottom}) space=$space',
      );
      expect(onTheLines, isNotNull);
      expect(
        onTheLedgerNote,
        isNotNull,
        reason:
            'half a staff space under the bottom line is where a note on the ledger line below the '
            'staff is drawn, so a touch there is still on the staff',
      );
      expect(
        onBlankPaper,
        isNull,
        reason:
            'below the staff and its ledger room is blank paper: a touch there has not chosen a '
            'note, and answering anyway would put one where nothing was touched',
      );
      expect(
        aboveTheStaff,
        isNull,
        reason:
            'the band the system reserves above the staff is not the staff: a tap on the paper '
            'above the five lines names nothing',
      );
    });
  });
}
