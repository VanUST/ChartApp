// PURPOSE: Pin the hit test's answers with exact geometry that can be derived by hand, because the
//          whole point of a hit test is that a human can point at something and know what they
//          pointed at. The engine's text metrics are fixed advances here, so every coordinate below
//          is arithmetic rather than a font measurement, and a failure names a real regression
//          instead of a font version. The round trip is printed to stdout as well as asserted, so
//          the numbers a reader would check by hand are in the transcript and not only in a
//          boolean.
//
//          IT COVERS BOTH SURFACES OVER THE SAME BARS. `hitTestPage` answers for the chord line and
//          `hitTestMelodyStaff` for the staff below it, whose columns name beats. The staff cases
//          are laid out with the engine's own style, which prints no beat captions, because the
//          target used to be built out of those captions and switching them off switched note entry
//          off with them (A68 §7) — so the cases assert that the answer does not depend on anything
//          that can be switched off, with and without the captions printed.
// INPUTS: None.
// OUTPUTS: Pass/fail per behaviour, plus `hit.cell ...` and `hit.staff ...` lines on stdout naming
//          the point tested and the address it returned.
// KEYWORDS: test, hit-testing, round-trip, page-scale, fit, edge-case, hand-derived, evidence,
//           melody-staff, beat-column, captions-off
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A 4/4 bar holding one major triad on beat 0 and nothing else.
Bar oneChordBar(int rootPitchClass) => Bar(
  chords: <ChordMark>[
    ChordMark(
      place: cellAt(0),
      chord: Chord(root: ChordRoot(rootPitchClass)),
    ),
  ],
);

/// A 4/4 bar holding one chord on the given beat.
Bar chordOnBeat(int rootPitchClass, int beat) => Bar(
  chords: <ChordMark>[
    ChordMark(
      place: cellAt(beat),
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

/// A song that DECLARES a pitched staff and carries a chord and a note on every beat.
///
/// The declaration is the point: D29 makes the staff exist because the chart asked for it, so every
/// bar of this song carries one whether or not a note was written on it, and a tap on its five lines
/// has something to name. Four bars of 4/4 gives sixteen columns to touch.
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
              for (int beat = 0; beat < 4; beat++)
                ChordMark(
                  place: cellAt(beat),
                  chord: Chord(root: ChordRoot(barIndex + beat)),
                ),
            ],
            // A note on every beat, so the column a tap names is also the column a notehead stands
            // in: the beat the hit test answers can be checked against the note that beat holds.
            melody: <NoteMark>[
              for (int beat = 0; beat < 4; beat++)
                NoteMark(
                  place: cellAt(beat),
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

/// The point in [bar]'s staff that a musician would touch to choose [beat]: the beat's own column,
/// at the height of the staff's middle line.
///
/// The column comes from the bar's cells and the height from the staff's published box, which are
/// the two things the caller of the hit test is allowed to know; the captions under the staff are
/// deliberately not consulted, because a tap must not depend on them.
LayoutOffset staffTapPoint(PlacedBar bar, PlacedCell cell) => LayoutOffset(
  cell.bounds.left + cell.bounds.size.width / 2,
  bar.melody.bounds.top + bar.melody.bounds.size.height / 2,
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

  group('hitTestMelodyStaff', () {
    // THE SECOND SURFACE, AND THE DEFECT THAT MADE THESE CASES NECESSARY. The staff's touch target
    // used to be built out of the beat CAPTIONS: the touch band ran down to the caption row and each
    // beat's column was that beat's marker. The owner read the captions and the tick marks as noise
    // and asked for them to go; switching them off then switched off NOTE ENTRY, because a tap on the
    // five lines named nothing. The tablet found it in one tap — `viewer.select staff ... hit=none` —
    // after seventy tests stayed green, because the palette tests opened the palette directly instead
    // of touching the staff. Every case below therefore lays the chart out with the engine's own
    // style, which is the style that prints no captions.
    final Song staffChart = staffSong();
    final PageLayout staffPage = engine
        .layout(staffChart, pageWidth: 400, pageHeight: 600)
        .first;
    // The same chart engraved by a style that DOES print the captions, for the comparison below.
    final PageLayout captionedPage = LayoutEngine(
      style: const LayoutStyle(showBeatCaptions: true),
    ).layout(staffChart, pageWidth: 400, pageHeight: 600).first;

    test('a tap on a staff column names that beat, with the beat captions OFF', () {
      int tapped = 0;
      for (final PlacedBar bar in staffPage.bars) {
        expect(
          bar.melody.isEmpty,
          isFalse,
          reason: 'D29: the chart declared a staff, so the bar carries one',
        );
        expect(
          bar.beatMarkers,
          isEmpty,
          reason:
              'the style prints no captions and no ticks under the staff — this is the state in '
              'which note entry died, so the taps below are made in exactly it',
        );
        for (final PlacedCell cell in bar.cells) {
          final LayoutOffset point = staffTapPoint(bar, cell);
          final ChartHit? hit = hitTestMelodyStaff(staffPage, point);
          stdout.writeln(
            'hit.staff bar=${bar.barIndex} beat=${cell.beat} '
            'point=(${point.x.toStringAsFixed(2)},${point.y.toStringAsFixed(2)}) '
            'answered=${hit == null ? 'null' : '${hit.sectionId}[${hit.barIndex}] '
                      'beat=${hit.beat}'}',
          );
          expect(
            hit,
            isNotNull,
            reason:
                'a tap on the five lines of beat ${cell.beat} of bar ${bar.barIndex} must name '
                'that beat: a staff whose columns cannot be touched is a staff notes cannot be '
                'written on',
          );
          expect(hit!.sectionId, bar.sectionId);
          expect(hit.barIndex, bar.barIndex);
          expect(
            hit.beat,
            cell.beat,
            reason: 'the column touched is the beat named, not a neighbour',
          );
          tapped++;
        }
      }
      expect(tapped, 16, reason: 'four 4/4 bars, every beat touched once');
    });

    test('the same taps name the same beats whether the captions print or not', () {
      // THE ANSWER MUST NOT DEPEND ON ANYTHING THAT CAN BE SWITCHED OFF. This is the pair that
      // states the rule rather than one side of it: the same column of the same bar, touched at the
      // same musical height, must answer the same address in both layouts. The captioned page is
      // proved to have printed its captions first, so the comparison cannot pass by both pages
      // being caption-less.
      expect(
        captionedPage.bars.first.beatMarkers,
        isNotEmpty,
        reason: 'the comparison is worthless unless one of the two layouts prints them',
      );
      int compared = 0;
      for (int index = 0; index < staffPage.bars.length; index++) {
        final PlacedBar silent = staffPage.bars[index];
        final PlacedBar captioned = captionedPage.bars[index];
        for (int cell = 0; cell < silent.cells.length; cell++) {
          final ChartHit? off = hitTestMelodyStaff(
            staffPage,
            staffTapPoint(silent, silent.cells[cell]),
          );
          final ChartHit? on = hitTestMelodyStaff(
            captionedPage,
            staffTapPoint(captioned, captioned.cells[cell]),
          );
          expect(
            off?.beat,
            cell,
            reason: 'captions off, bar $index cell $cell',
          );
          expect(
            on?.beat,
            off?.beat,
            reason:
                'bar $index cell $cell answered ${on?.beat} with the captions printed and '
                '${off?.beat} without them: the beat a touch names must not move when a label '
                'under the staff is switched off',
          );
          compared++;
        }
      }
      stdout.writeln(
        'hit.staff-captions compared=$compared '
        'markers_off=${staffPage.bars.first.beatMarkers.length} '
        'markers_on=${captionedPage.bars.first.beatMarkers.length} identical=true',
      );
    });

    test('the touch band is the five lines and half a space below them', () {
      final PlacedBar bar = staffPage.bars.first;
      final PlacedCell firstCell = bar.cells.first;
      final double space = bar.melody.bounds.size.height / 4;
      final double columnX = centreOf(firstCell.bounds).x;
      final ChartHit? onTheLines = hitTestMelodyStaff(
        staffPage,
        staffTapPoint(bar, firstCell),
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
      // the reserved band is not the staff, and a tap on it must not be told it named a beat.
      final ChartHit? aboveTheStaff = hitTestMelodyStaff(
        staffPage,
        LayoutOffset(columnX, bar.melody.bounds.top - 12),
      );
      stdout.writeln(
        'hit.staff-band on_lines=${onTheLines?.beat} '
        'on_ledger_note=${onTheLedgerNote?.beat} '
        'below_band=${onBlankPaper?.beat} above_staff=${aboveTheStaff?.beat} '
        'staff=(${bar.melody.bounds.top}..${bar.melody.bounds.bottom}) space=$space',
      );
      expect(onTheLines, isNotNull);
      expect(
        onTheLedgerNote?.beat,
        firstCell.beat,
        reason:
            'half a staff space under the bottom line is where a note on the ledger line below the '
            'staff is drawn, so a touch there still names the beat of that column',
      );
      expect(
        onBlankPaper,
        isNull,
        reason:
            'below the staff and its ledger room is blank paper: a touch there has not chosen a '
            'beat, and answering anyway would put a note where nothing was touched',
      );
      expect(
        aboveTheStaff,
        isNull,
        reason:
            'the band the system reserves for the melody is not the staff: a tap on the paper above '
            'the five lines names nothing',
      );
      // And a touch in the bar's own leading padding is over the bar and over no beat, which is the
      // same answer the chord line gives for its own padding rather than a silent guess at beat 0.
      final ChartHit? inPadding = hitTestMelodyStaff(
        staffPage,
        LayoutOffset(bar.bounds.left + 1, staffTapPoint(bar, firstCell).y),
      );
      expect(inPadding, isNotNull);
      expect(inPadding!.barIndex, bar.barIndex);
      expect(
        inPadding.cell,
        isNull,
        reason: 'the padding before the first column names the bar and no beat',
      );
    });
  });
}
