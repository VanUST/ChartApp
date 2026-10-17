// PURPOSE: Pin the two halves of the note reader that a regression could silently break, and pin
//          them against answers that do not come from the code: the staff positions of written
//          pitches, which are a fact of musical notation, and the cell width the layout must keep
//          between two noteheads on adjacent beats, which is the spacing defect this change
//          repairs.
//
//          WHY THE EXPECTATIONS ARE DERIVED BY HAND. A test that reads its expectation out of
//          `melodyStepOf` cannot fail when `melodyStepOf` is wrong, and this repository has already
//          paid for that mistake once: a note on the wrong staff line lived through seventy green
//          tests. So the treble staff's lines are written down as E4 G4 B4 D5 F5, the bass staff's
//          as G2 B2 D3 F3 A3, and the steps below are counted from those by hand.
//
//          THE INK IS TRACED FROM THE ENGRAVER'S OWN GLYPH BOXES rather than from a formula here,
//          so the reader is asked to recover a position the layout produced and not one this file
//          computed.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, note-reader, pitch, staff-step, spacing, notehead, cell-width, writer, undoable
import 'dart:math' as math;

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The page the fixtures are engraved on, matching the application's own proportions.
const double _pageWidth = 824;

/// The page height the fixtures are engraved on.
const double _pageHeight = 1318;

// PURPOSE: A layout style that differs from the engine's defaults only where a case needs it to, so
//          that a test measuring the DEFAULT spacing gets the default.
// INPUTS: minCellWidth — the cell width under test.
// OUTPUTS: The style.
// KEYWORDS: layout-style, cell-width, spacing-under-test
LayoutStyle _style({double? minCellWidth}) =>
    LayoutStyle(minCellWidth: minCellWidth ?? const LayoutStyle().minCellWidth);

// PURPOSE: Build a one-section song of one bar holding [pitches] on its first beats, so a case can
//          state a melody as written pitches and let the real engraver place it.
// INPUTS: pitches — one (octave, letter index) pair per beat, letter index as C=0 … B=6.
// OUTPUTS: The song, with a declared pitched treble staff so the layout draws a staff at all (D29).
// KEYWORDS: fixture, melody, engraver, declared-staff
Song _songOf(List<(int, int)> pitches) => Song(
  id: 'note-reader-test',
  title: '',
  composer: '',
  style: '',
  key: Key.cMajor,
  tempo: 120,
  staffSet: const StaffSet(pitched: StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'sec-1',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(
          melody: <NoteMark>[
            for (int beat = 0; beat < pitches.length; beat++)
              NoteMark(
                place: cellAt(beat),
                pitch: PitchedNote(
                  note: WrittenNote(NoteLetter.values[pitches[beat].$2], 0),
                  octave: pitches[beat].$1,
                ),
                value: const NoteValue.plain(NoteBase.quarter),
              ),
          ],
        ),
      ],
    ),
  ],
);

// PURPOSE: The same song with its melody STRIPPED, which is the document a recognition run writes
//          into: the ink exists and the structure does not. The engraving that produced the ink
//          comes from the song WITH its notes, because that is what drew the glyphs it was traced
//          from.
// INPUTS: None.
// OUTPUTS: A one-bar song with a declared pitched staff and no note at all.
// KEYWORDS: fixture, blank-structure, recognition-target
Song _blankSong() => Song(
  id: 'note-reader-test',
  title: '',
  composer: '',
  style: '',
  key: Key.cMajor,
  tempo: 120,
  staffSet: const StaffSet(pitched: StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'sec-1',
      label: const SectionLabel.letter('A'),
      bars: const <Bar>[Bar()],
    ),
  ],
);

// PURPOSE: Turn one engraved glyph into a pen stroke, which is the input the reader is written for:
//          a notehead becomes a closed ring one nib narrower than its box so that the ink's extent
//          is the box, a stem and a ledger line become a line along their own axis.
// INPUTS: glyph — a glyph the engraver published; nib — the pen width; origin — the bar's top-left
//         corner, which the stored coordinates are measured from.
// OUTPUTS: The points in bar-anchor-local pixels, or an empty list for a glyph a pen would not
//          draw as a single stroke.
// KEYWORDS: trace, glyph-to-ink, nib, anchor-local
List<LayoutOffset> _trace(
  MelodyGlyph glyph, {
  required double nib,
  required LayoutOffset origin,
}) {
  final LayoutRect box = glyph.bounds;
  final double cx = box.left + box.size.width / 2;
  final double cy = box.top + box.size.height / 2;
  final List<LayoutOffset> page;
  switch (glyph.kind) {
    case MelodyGlyphKind.notehead:
      final double rx = math.max(0.5, (box.size.width - nib) / 2);
      final double ry = math.max(0.5, (box.size.height - nib) / 2);
      page = <LayoutOffset>[
        for (int i = 0; i <= 24; i++)
          LayoutOffset(
            cx + rx * math.cos(i * math.pi / 12),
            cy + ry * math.sin(i * math.pi / 12),
          ),
      ];
    case MelodyGlyphKind.stem:
    case MelodyGlyphKind.ledgerLine:
      final bool vertical = box.size.height > box.size.width;
      page = <LayoutOffset>[
        LayoutOffset(vertical ? cx : box.left, vertical ? box.top : cy),
        LayoutOffset(vertical ? cx : box.right, vertical ? box.bottom : cy),
      ];
    case MelodyGlyphKind.beam:
      page = <LayoutOffset>[glyph.from, glyph.to];
    case MelodyGlyphKind.accidental:
    case MelodyGlyphKind.dot:
    case MelodyGlyphKind.flag:
    case MelodyGlyphKind.tie:
      return const <LayoutOffset>[];
  }
  return <LayoutOffset>[
    for (final LayoutOffset point in page)
      LayoutOffset(point.x - origin.x, point.y - origin.y),
  ];
}

// PURPOSE: Copy one engraved bar into ink, one stroke per glyph it draws, anchored to the BAR — the
//          anchor the capture path chooses for ink written on the staff, which lies below every
//          cell.
// INPUTS: bar — the placed bar; nib — the pen width.
// OUTPUTS: The strokes, in bar-anchor-local coordinates.
// KEYWORDS: ink-fixture, staff-ink, bar-anchor
List<InkStroke> _inkOfBar(PlacedBar bar, {double nib = 2.2}) {
  final EventAnchor anchor = EventAnchor(
    sectionId: bar.sectionId,
    bar: bar.barIndex,
  );
  final List<InkStroke> strokes = <InkStroke>[];
  int index = 0;
  for (final MelodyGlyph glyph in bar.melody.glyphs) {
    final List<LayoutOffset> points = _trace(
      glyph,
      nib: nib,
      origin: bar.bounds.origin,
    );
    if (points.isEmpty) {
      continue;
    }
    strokes.add(
      InkStroke(
        id: 'ink-${index++}',
        tool: StrokeTool.pen,
        color: '#102a43',
        size: nib,
        anchor: anchor,
        points: <InkPoint>[
          for (int i = 0; i < points.length; i++)
            InkPoint(x: points[i].x, y: points[i].y, w: 1, t: i.toDouble()),
        ],
      ),
    );
  }
  return strokes;
}

// PURPOSE: Lay a fixture out, read its one bar, and hand back the reading — the whole path from a
//          modelled melody through the real engraver, its glyphs, ink, the page's frames and the
//          reader.
// INPUTS: pitches — the melody as written; style — the layout style, for the spacing cases.
// OUTPUTS: The reading and the page, so a case can ask about both a head and the geometry it came
//          from.
// KEYWORDS: end-to-end, engrave-then-read, fixture
({MelodyNoteReading reading, PageLayout page}) _engraveAndRead(
  List<(int, int)> pitches, {
  LayoutStyle? style,
}) {
  final Song song = _songOf(pitches);
  final PageLayout page = LayoutEngine(style: style ?? _style())
      .layout(song, pageWidth: _pageWidth, pageHeight: _pageHeight)
      .first;
  final PlacedBar bar = page.bars.first;
  return (
    reading: readMelodyNotesOfBar(
      page: page,
      strokes: _inkOfBar(bar),
      sectionId: bar.sectionId,
      barIndex: bar.barIndex,
    ),
    page: page,
  );
}

void main() {
  group('the pitch of a staff step, derived from notation', () {
    test('the five treble lines are E4 G4 B4 D5 F5', () {
      // A staff step is HALF a space, so the five lines are the even steps 0, 2, 4, 6 and 8. On a
      // treble staff the bottom line is E4 and the middle line B4 — which is written down here from
      // the notation, not read out of any function.
      expect(
        melodyPitchOfStep(0),
        const PitchedNote(note: WrittenNote(NoteLetter.e, 0), octave: 4),
      );
      expect(melodyPitchOfStep(2).toString(), 'G4');
      expect(melodyPitchOfStep(4).toString(), 'B4');
      expect(melodyPitchOfStep(6).toString(), 'D5');
      expect(melodyPitchOfStep(8).toString(), 'F5');
    });

    test('the spaces between them are F4 A4 C5 E5', () {
      expect(melodyPitchOfStep(1).toString(), 'F4');
      expect(melodyPitchOfStep(3).toString(), 'A4');
      expect(melodyPitchOfStep(5).toString(), 'C5');
      expect(melodyPitchOfStep(7).toString(), 'E5');
    });

    test(
      'a written C4 is two steps BELOW a treble staff, on its own ledger line',
      () {
        // This is the case that keeps the reader honest about ledger notes: C4 is not on the staff at
        // all, it is the ledger line beneath it.
        expect(melodyPitchOfStep(-2).toString(), 'C4');
        expect(melodyPitchOfStep(-2).toString(), isNot('E4'));
      },
    );

    test('the five bass lines are G2 B2 D3 F3 A3, twelve steps below the treble ones', () {
      // The same written sound stands twelve diatonic steps higher on a bass staff because the two
      // staves' bottom lines are a twelfth apart — G2 against E4.
      expect(melodyPitchOfStep(0, clef: 'bass').toString(), 'G2');
      expect(melodyPitchOfStep(4, clef: 'bass').toString(), 'D3');
      expect(melodyPitchOfStep(8, clef: 'bass').toString(), 'A3');
    });

    test('every step in the writable range round-trips back to itself', () {
      for (final String clef in <String>['treble', 'bass']) {
        for (int step = melodyLowestStep; step <= melodyHighestStep; step++) {
          final PitchedNote pitch = melodyPitchOfStep(step, clef: clef);
          expect(
            melodyStepOf(pitch.note, octave: pitch.octave, clef: clef),
            step,
            reason: 'step $step on $clef',
          );
        }
      }
    });
  });

  group('reading a bar of four notes on adjacent beats', () {
    test('recovers all four pitches at the application\'s own spacing', () {
      // C4 D4 E4 F4 — the ledger line below the staff, the space below it, its bottom line, the
      // space above. Steps -2, -1, 0, 1 by hand.
      final ({MelodyNoteReading reading, PageLayout page}) result =
          _engraveAndRead(<(int, int)>[(4, 0), (4, 1), (4, 2), (4, 3)]);
      expect(result.reading.heads, hasLength(4));
      expect(
        <String>[
          for (final MelodyNoteHead head in result.reading.heads)
            head.pitch.toString(),
        ],
        <String>['C4', 'D4', 'E4', 'F4'],
      );
      expect(
        <int>[
          for (final MelodyNoteHead head in result.reading.heads) head.step,
        ],
        <int>[-2, -1, 0, 1],
      );
      expect(
        <int>[
          for (final MelodyNoteHead head in result.reading.heads) head.beat,
        ],
        <int>[0, 1, 2, 3],
      );
    });

    test('a descending run keeps its beats in order', () {
      final ({MelodyNoteReading reading, PageLayout page}) result =
          _engraveAndRead(<(int, int)>[(5, 0), (4, 6), (4, 5), (4, 4)]);
      expect(
        <String>[
          for (final MelodyNoteHead head in result.reading.heads)
            head.pitch.toString(),
        ],
        <String>['C5', 'B4', 'A4', 'G4'],
      );
      expect(
        <int>[
          for (final MelodyNoteHead head in result.reading.heads) head.beat,
        ],
        <int>[0, 1, 2, 3],
      );
    });

    test('two notes in ONE beat come back in the order they were drawn', () {
      // A4 then B4, both written inside beat 0's column. The ink is built here rather than traced
      // from the engraver because the ENGRAVER draws a beat's k-th note at `k * 1.6 staff spaces`,
      // which at 18 pixels is 20.8 and therefore lands in the NEXT column - an overflow A74 §4
      // measured and did not fix, and not something a reader can undo: a head is at a place, and the
      // place decides the beat. A musician's own ink for two sixteenths in one beat is drawn inside
      // the column, which is the case below.
      //
      // The engraver draws step k at the k-th position across the cell (A75), so the left head is
      // the earlier note and its ordinal is what the model stores as `NoteMark.step`.
      const double middle = 100;
      const MelodyStaffFrame frame = MelodyStaffFrame(
        middleLineY: middle,
        staffSpace: 13,
        headTop: 0,
        headBottom: 200,
        beatColumns: <MelodyBeatColumn>[
          MelodyBeatColumn(beat: 0, left: 0, right: 40),
        ],
      );
      List<LayoutOffset> ringAt(double x, double y) => <LayoutOffset>[
        for (int i = 0; i <= 24; i++)
          LayoutOffset(
            x + 6.7 * math.cos(i * math.pi / 12),
            y + 4.75 * math.sin(i * math.pi / 12),
          ),
      ];
      final MelodyNoteReading reading = const MelodyNoteReader().read(
        sectionId: 'sec-1',
        barIndex: 0,
        ink: <PageInkStroke>[
          // A4 is staff step 3 and B4 is step 4, so their centres are half a space apart.
          PageInkStroke(
            id: 'a',
            nib: 2.2,
            points: ringAt(12, middle + (4 - 3) * 6.5),
          ),
          PageInkStroke(id: 'b', nib: 2.2, points: ringAt(30, middle)),
        ],
        frame: frame,
      );
      expect(reading.heads, hasLength(2));
      expect(
        <int>[for (final MelodyNoteHead head in reading.heads) head.beat],
        <int>[0, 0],
      );
      expect(
        <int>[
          for (final MelodyNoteHead head in reading.heads) head.orderInBeat,
        ],
        <int>[0, 1],
      );
      expect(
        <String>[
          for (final MelodyNoteHead head in reading.heads)
            head.pitch.toString(),
        ],
        <String>['A4', 'B4'],
      );
    });
  });
  group('the spacing the read depends on', () {
    test('the render that used to merge four notes into one blob', () {
      // AT 14 — the width `LayoutStyle.minCellWidth` used to default to — a notehead is WIDER than
      // the cell, so four notes on adjacent beats are drawn overlapping and the reader cannot
      // separate them. This is the measured defect the default was raised for, and it is asserted
      // here so that lowering the default again fails the suite rather than a musician's page.
      final ({MelodyNoteReading reading, PageLayout page}) result =
          _engraveAndRead(<(int, int)>[
            (4, 0),
            (4, 1),
            (4, 2),
            (4, 3),
          ], style: _style(minCellWidth: 14));
      expect(
        result.reading.heads.length,
        lessThan(4),
        reason: 'at 14 the four heads overlap and fewer than four can be read',
      );
    });

    test('the default leaves the noteheads apart, and the margin is checked', () {
      const LayoutStyle defaults = LayoutStyle();
      const MelodyMetrics metrics = MelodyMetrics();
      final double headWidth =
          metrics.noteheadWidth * defaults.melodyStaffSpace;
      final double clearance = defaults.minCellWidth - headWidth;
      // The numbers, named: a head is 1.2 x 13 = 15.6 and the default cell is 18, so the clear
      // space between two adjacent-beat noteheads is 2.4 logical pixels.
      expect(headWidth, closeTo(15.6, 1e-9));
      expect(defaults.minCellWidth, 18);
      expect(clearance, closeTo(2.4, 1e-9));
      // The rule rather than the number: a default cell narrower than a notehead merges two notes
      // into one shape, so this is the floor under every future edit to either value.
      expect(
        clearance,
        greaterThanOrEqualTo(2.4),
        reason:
            'a cell narrower than a notehead makes two adjacent notes one blob',
      );
    });
  });

  group('what the reader refuses', () {
    test('a stem with no notehead is too narrow to be one', () {
      // A stem is a hairline: 1.56 pixels of `MelodyMetrics.strokeWidth` against a 15.6-wide head.
      // The case uses a hand-built frame so the refusal is about the ink and nothing else.
      const MelodyStaffFrame frame = MelodyStaffFrame(
        middleLineY: 100,
        staffSpace: 13,
        headTop: 0,
        headBottom: 200,
        beatColumns: <MelodyBeatColumn>[
          MelodyBeatColumn(beat: 0, left: 0, right: 40),
        ],
      );
      final MelodyNoteReading reading = const MelodyNoteReader().read(
        sectionId: 'sec-1',
        barIndex: 0,
        ink: const <PageInkStroke>[
          PageInkStroke(
            id: 'stem',
            nib: 1.56,
            points: <LayoutOffset>[LayoutOffset(20, 80), LayoutOffset(20, 125)],
          ),
        ],
        frame: frame,
      );
      expect(reading.heads, isEmpty);
      expect(reading.refusals, hasLength(1));
      expect(reading.refusals.first.reason, MelodyNoteRejection.tooNarrow);
    });

    test('a mark above the melody staff is not a note of it', () {
      // THE PLACE GATE, which is the rule that separates a chord symbol written in the chord row
      // from a note written on the staff: the page reserves the two bands separately, and ink above
      // the row is not on the staff however notehead-shaped it is. The blob here is exactly one
      // notehead by shape, and it is refused only because of where it stands.
      const MelodyStaffFrame frame = MelodyStaffFrame(
        middleLineY: 100,
        staffSpace: 13,
        headTop: 90,
        headBottom: 200,
        beatColumns: <MelodyBeatColumn>[
          MelodyBeatColumn(beat: 0, left: 0, right: 40),
        ],
      );
      const List<PageInkStroke> head = <PageInkStroke>[
        PageInkStroke(
          id: 'head',
          nib: 2.2,
          points: <LayoutOffset>[
            LayoutOffset(13, 26),
            LayoutOffset(20, 20),
            LayoutOffset(27, 26),
            LayoutOffset(20, 32),
            LayoutOffset(13, 26),
          ],
        ),
      ];
      final MelodyNoteReading above = const MelodyNoteReader().read(
        sectionId: 'sec-1',
        barIndex: 0,
        ink: head,
        frame: frame,
      );
      expect(above.heads, isEmpty);
      expect(above.refusals.single.reason, MelodyNoteRejection.outsideTheStaff);

      // The same ink inside the staff IS a note, which is what makes the refusal above a statement
      // about place and not about shape.
      const MelodyStaffFrame inside = MelodyStaffFrame(
        middleLineY: 100,
        staffSpace: 13,
        headTop: 0,
        headBottom: 200,
        beatColumns: <MelodyBeatColumn>[
          MelodyBeatColumn(beat: 0, left: 0, right: 40),
        ],
      );
      final MelodyNoteReading onStaff = const MelodyNoteReader().read(
        sectionId: 'sec-1',
        barIndex: 0,
        ink: head,
        frame: inside,
      );
      expect(onStaff.heads, hasLength(1));
    });
  });

  group('what a recognised note becomes', () {
    test('one note.insert per note, a quarter long, undoable', () {
      final Song song = _songOf(<(int, int)>[(4, 2), (4, 3)]);
      final PageLayout page = LayoutEngine(style: _style())
          .layout(song, pageWidth: _pageWidth, pageHeight: _pageHeight)
          .first;
      final PlacedBar bar = page.bars.first;
      final MelodyNoteReading reading = readMelodyNotesOfBar(
        page: page,
        strokes: _inkOfBar(bar),
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
      );
      // THE SESSION STARTS ON A BAR WITH NO NOTE, which is the state a recognition run writes into:
      // the ink exists and the structure does not. The engraving above came from the song WITH its
      // notes, because that is what drew the glyphs the ink was traced from.
      final EditSession session = EditSession(
        document: DocumentState(song: _blankSong()),
      );
      final MelodyNoteWrite write = writeRecognisedNotes(
        session: session,
        reading: reading,
      );
      expect(write.written, hasLength(2));
      // THE VALUE IS A PLACEHOLDER AND NOT A READING: a recognised note's rhythm is not measured, so
      // it takes the value the note palette starts from.
      expect(write.value, recognisedNoteValue);
      expect(write.value.base, NoteBase.quarter);
      expect(
        <String>[
          for (final NoteMark note
              in session.song.sections.first.bars.first.melody)
            '${note.pseudoBeat}.${note.pseudoStep}:${note.pitch} ${note.value.base.name}',
        ],
        <String>['0.0:E4 quarter', '1.0:F4 quarter'],
      );
      // Every added note is one operation of the log, so the ordinary undo takes it back.
      expect(session.undoDepth, 2);
      expect(session.undo(), isTrue);
      expect(session.song.sections.first.bars.first.melody, hasLength(1));
    });

    test('reading the same ink twice writes nothing the second time', () {
      final Song song = _songOf(<(int, int)>[(4, 2), (4, 3)]);
      final PageLayout page = LayoutEngine(style: _style())
          .layout(song, pageWidth: _pageWidth, pageHeight: _pageHeight)
          .first;
      final PlacedBar bar = page.bars.first;
      final MelodyNoteReading reading = readMelodyNotesOfBar(
        page: page,
        strokes: _inkOfBar(bar),
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
      );
      final EditSession session = EditSession(
        document: DocumentState(song: _blankSong()),
      );
      writeRecognisedNotes(session: session, reading: reading);
      final int depth = session.undoDepth;
      final MelodyNoteWrite again = writeRecognisedNotes(
        session: session,
        reading: reading,
      );
      expect(again.written, isEmpty);
      expect(again.alreadyPresent, hasLength(2));
      expect(session.undoDepth, depth);
    });

    test('a note the musician already placed at an address is left alone', () {
      // A palette note on beat 0 must not be overwritten by ink the reader also reads there — the
      // correction he makes by hand has to survive the next recognition run.
      final Song song = _songOf(<(int, int)>[(4, 2), (4, 3)]);
      final PageLayout page = LayoutEngine(style: _style())
          .layout(song, pageWidth: _pageWidth, pageHeight: _pageHeight)
          .first;
      final PlacedBar bar = page.bars.first;
      final MelodyNoteReading reading = readMelodyNotesOfBar(
        page: page,
        strokes: _inkOfBar(bar),
        sectionId: bar.sectionId,
        barIndex: bar.barIndex,
      );
      final EditSession session = EditSession(
        document: DocumentState(song: _blankSong()),
      );
      session.insertNote(
        sectionId: 'sec-1',
        barIndex: 0,
        beat: 0,
        pitch: const PitchedNote(note: WrittenNote(NoteLetter.a, 0), octave: 3),
        value: const NoteValue.plain(NoteBase.half),
      );
      final MelodyNoteWrite write = writeRecognisedNotes(
        session: session,
        reading: reading,
      );
      expect(write.written, hasLength(1));
      expect(write.written.single.pitch.toString(), 'F4');
      final NoteMark first = session.song.sections.first.bars.first.melody
          .firstWhere((NoteMark note) => note.pseudoBeat == 0);
      expect(first.pitch.toString(), 'A3');
      expect(first.value.base, NoteBase.half);
    });
  });
}
