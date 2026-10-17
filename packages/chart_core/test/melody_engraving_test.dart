// PURPOSE: Pin what the melody staff ENGRAVES against music theory rather than against the code
//          that engraves it: which letter each of a staff's five lines names, which line or space a
//          written pitch must occupy, how many ledger lines a pitch outside the staff needs and
//          where they stand, that an accidental belongs to the letter of its note, which way a stem
//          points, that the staff publishes its clef without drawing one, WHICH NOTES ONE BEAM JOINS
//          AND WHERE THAT BEAM LIES, and what a glyph's box means.
//
//          WHY THIS FILE EXISTS, IN ONE SENTENCE OF HISTORY. The engraver counted a pitch's position
//          from `7 * (octave - 4)`, which puts a written C4 on the treble staff's BOTTOM LINE where
//          a musician reads E4, and it then drew every accidentals' sign on the space that names the
//          wrong letter. Seventy tests were green while the staff drew the wrong note on the wrong
//          line, and the owner found it by looking. A test that says `melodyStepOf(C4) == -2` would
//          not have found it either: that number came out of the code, so asserting it only writes
//          the bug down twice.
//
//          THE RULE EVERY EXPECTATION HERE FOLLOWS. A position is derived from the LETTERS the staff
//          names — a treble staff's five lines are E4 G4 B4 D5 F5, a bass staff's are G2 B2 D3 F3 A3
//          — together with the two facts that make the coordinate a musical coordinate at all: the
//          bottom line is step 0, and one letter is one staff step (so a line is an even step and
//          the space above it an odd one). Where a distance is asserted — a third, an octave, the
//          twelfth between the two clefs' bottom lines — it is counted from the letters and octaves
//          themselves by [Written.stepsAbove], which is the arithmetic a musician does reading from
//          line to space to line.
//
//          AND THE BEAMING CASES FOLLOW THE SAME RULE, because a beam is a musical statement and not
//          a stroke: the number of beams is the written VALUE (one for an eighth, two for a
//          sixteenth), the group is one BEAT, and the direction the group's stems take is the one a
//          note farthest from the middle line dictates. Each expectation names the notation it comes
//          from — "a beat boundary breaks the beam", "a group of one pitch is level" — so a change in
//          the engraver fails a sentence about music rather than a sentence about the engraver.
// INPUTS: None. The staff the geometry cases are engraved on is declared below with the
//         application's own staff-space proportion, so the case needs no device, no font and no
//         fixture file. The one case that asks about a PAGE — whether a beam crosses a barline —
//         engraves a two-bar song through the layout engine, because a barline is a fact of a page.
// OUTPUTS: Pass/fail per musical fact, plus `notation.*` lines on stdout naming every letter, step,
//          ledger-line distance, beam span, slope and thickness the assertions rest on, so a failure
//          shows the staff rather than only a boolean.
// KEYWORDS: test, melody-staff, engraving, music-theory, treble-clef, bass-clef, ledger-line,
//           accidental, stem, beam, beaming, rhythm-grouping, beat-boundary, glyph-box,
//           clef-published-not-drawn, falsifiable
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The distance between two staff lines in the geometry below.
///
/// It is the application's own `LayoutStyle.melodyStaffSpace` of 13, so every coordinate asserted
/// here is a coordinate a page produces; but it is stated here rather than read from the style,
/// because a test that follows the style would move with an engraving change instead of failing on
/// it.
const double _staffSpace = 13;

/// The y of the staff's middle line, chosen so that the arithmetic of the cases is readable.
const double _middleLineY = 200;

/// The left edge and width of the bar the cases engrave, in page coordinates.
const double _barLeft = 100;
const double _barWidth = 200;

/// The x of each of the bar's four cells, relative to [_barLeft], as the layout engine publishes
/// them. Only the first is used by these cases; four are given because a 4/4 bar has four beats and
/// the engraver drops a note whose beat has no cell.
const List<double> _cellX = <double>[8, 56, 104, 152];

/// The vertical centre of [glyph]'s box, which is the height the element is drawn at.
///
/// A notehead's centre is its line or space; a ledger line's or an accidental's centre is the
/// height it must agree with its note about, which is what these cases compare.
double _cy(MelodyGlyph glyph) =>
    glyph.bounds.top + glyph.bounds.size.height / 2;

/// One written pitch, named the way a musician names it: a letter, an octave and the alteration of
/// the sign beside it.
///
/// The step is asked from [melodyStepOf] — the thing under test — and the DISTANCES between two
/// pitches are counted from the letters and octaves instead, so a test can say "a third apart"
/// without borrowing the implementation's arithmetic.
class Written {
  /// Names [letter] in [octave], with [alter] semitones of accidental.
  const Written(this.letter, this.octave, {this.alter = 0});

  /// The letter the note is written on, which is what decides its line.
  final NoteLetter letter;

  /// The octave in scientific pitch notation, where middle C is C4.
  final int octave;

  /// Semitones of alteration: -1 is a flat and +1 a sharp.
  final int alter;

  /// The staff step this pitch occupies on [clef], as the engraver reports it.
  int stepOn(String clef) =>
      melodyStepOf(WrittenNote(letter, alter), octave: octave, clef: clef);

  /// How many staff steps this pitch lies ABOVE [other], counted from the letters and octaves.
  ///
  /// A negative result means this pitch is below [other]. One letter is one staff step, and an
  /// octave is seven letters, which is why the factor is seven — this is the count a musician makes
  /// reading up a staff, not a count taken from the engraver.
  int stepsAbove(Written other) =>
      7 * (octave - other.octave) + letter.index - other.letter.index;

  @override
  String toString() => '${WrittenNote(letter, alter)}$octave';
}

/// The written notes the two-clef agreement is measured over.
///
/// Every one of them is far enough from the engraver's writable limit that neither clef clamps it:
/// a clamped pitch would make the difference between the clefs a number the clamp chose, and the
/// claim is about the clefs, not about the limit.
const List<Written> _pitchesForBothClefs = <Written>[
  Written(NoteLetter.c, 3),
  Written(NoteLetter.d, 3),
  Written(NoteLetter.e, 3),
  Written(NoteLetter.f, 3),
  Written(NoteLetter.g, 3),
  Written(NoteLetter.a, 3),
  Written(NoteLetter.b, 3),
  Written(NoteLetter.c, 4),
  Written(NoteLetter.d, 4),
  Written(NoteLetter.e, 4),
  Written(NoteLetter.f, 4),
  Written(NoteLetter.g, 4),
  Written(NoteLetter.a, 4),
  Written(NoteLetter.b, 4),
  Written(NoteLetter.c, 5),
  Written(NoteLetter.d, 5),
];

/// One model note at [pitch], on beat [beat] of the bar.
///
/// [value] is a quarter note unless a case is about the written value, and [step] is the stacking
/// offset of a second note on the SAME beat, which is a chord on the staff rather than a later note.
BeatNote _note(
  Written pitch, {
  int beat = 0,
  int step = 0,
  NoteValue value = const NoteValue.plain(NoteBase.quarter),
}) => BeatNote(
  pitch: PitchedNote(
    note: WrittenNote(pitch.letter, pitch.alter),
    octave: pitch.octave,
  ),
  value: value,
  beat: beat,
  step: step,
);

/// The melody staff of a one-bar song holding [melody], engraved on the geometry declared above.
///
/// [timeSignature] is the bar's meter. It matters to beaming, which is grouped by BEAT, and in a
/// compound meter the beat is not the note the numerator counts: 6/8 has two beats of three eighths.
PlacedMelodyStaff _engrave(
  List<BeatNote> melody, {
  String clef = 'treble',
  bool includeClef = false,
  TimeSignature timeSignature = TimeSignature.fourFour,
}) => placeMelodyStaff(
  bar: Bar(timeSignature: timeSignature, melody: melody),
  left: _barLeft,
  width: _barWidth,
  staffMiddleLineY: _middleLineY,
  staffSpace: _staffSpace,
  clef: clef,
  cellX: _cellX,
  includeClef: includeClef,
);

/// Every glyph of [kind] the staff drew, in draw order.
List<MelodyGlyph> _glyphsOf(PlacedMelodyStaff staff, MelodyGlyphKind kind) =>
    <MelodyGlyph>[
      for (final MelodyGlyph glyph in staff.glyphs)
        if (glyph.kind == kind) glyph,
    ];

/// An eighth note's written value, spelled once so a beam case reads as `_eighth` instead of as a
/// constructor call between the notes whose values it is comparing.
const NoteValue _eighth = NoteValue.plain(NoteBase.eighth);

/// A run of [count] notes of [base] in ONE beat, one note per entry of [pitches], in the order given.
///
/// The notes land at ([beat], 0), ([beat], 1) … which is how a run inside a beat is addressed: one
/// cell, one note after another. [pitches] is read from its start, so a case that names four pitches
/// and asks for four notes says exactly what it means.
List<BeatNote> _run(
  int count,
  NoteBase base,
  List<Written> pitches, {
  int beat = 0,
}) => <BeatNote>[
  for (int index = 0; index < count; index++)
    _note(
      pitches[index],
      beat: beat,
      step: index,
      value: NoteValue.plain(base),
    ),
];

/// A song of one section whose bars carry [melodies], one bar per entry.
///
/// It exists for the claims that are about a PAGE rather than about one bar — whether a beam crosses
/// a barline is one of those, and it cannot be answered by engraving a bar on its own.
Song _beamSong(List<List<BeatNote>> melodies) => Song(
  title: 'Beam cases',
  key: Key.cMajor,
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'B',
      label: const SectionLabel.letter('B'),
      bars: <Bar>[
        for (final List<BeatNote> melody in melodies) Bar(melody: melody),
      ],
    ),
  ],
);

/// The one glyph of [kind] the staff drew.
///
/// A `single` rather than a first-or-null because every case that uses it engraves exactly one note:
/// a second glyph of the same kind means the engraver drew something the case did not ask for, and
/// that is a failure worth seeing.
MelodyGlyph _oneOf(PlacedMelodyStaff staff, MelodyGlyphKind kind) =>
    _glyphsOf(staff, kind).single;

/// The beams the staff drew, ordered left to right, because that is the direction a beam is read in.
List<MelodyGlyph> _beamsOf(PlacedMelodyStaff staff) =>
    _glyphsOf(staff, MelodyGlyphKind.beam)..sort(
      (MelodyGlyph a, MelodyGlyph b) => _beamStart(a).compareTo(_beamStart(b)),
    );

/// The x where a beam begins, whichever way round its two ends were published.
double _beamStart(MelodyGlyph beam) =>
    beam.from.x <= beam.to.x ? beam.from.x : beam.to.x;

/// The x where a beam ends.
double _beamEnd(MelodyGlyph beam) =>
    beam.from.x <= beam.to.x ? beam.to.x : beam.from.x;

/// The y of a beam's own line at [x], which is the line its two published ends define.
///
/// A beam is drawn as one straight stroke between its ends, so this is the whole of its geometry: a
/// case that asks where the beam is at a stem does not have to guess at a thickness or a slope.
double _beamYAt(MelodyGlyph beam, double x) {
  final double span = beam.to.x - beam.from.x;
  if (span.abs() < 1e-9) {
    return beam.from.y;
  }
  return beam.from.y + (beam.to.y - beam.from.y) * (x - beam.from.x) / span;
}

/// How many notes one beam joins, counted by the STEMS it reaches.
///
/// A beam joins stems, not noteheads: it starts and ends at the outer stems of its group, and the
/// noteheads hang beside those stems, inside the group but outside the beam's own x range. So the
/// count a reader makes — "this beam joins four notes" — is the number of stems whose axis the beam
/// covers, and taking it from where the notes are DRAWN means a beam that spans the wrong notes fails
/// however it was computed.
int _headsUnder(PlacedMelodyStaff staff, MelodyGlyph beam) {
  final double start = _beamStart(beam) - 1e-6;
  final double end = _beamEnd(beam) + 1e-6;
  return <MelodyGlyph>[
    for (final MelodyGlyph stem in _glyphsOf(staff, MelodyGlyphKind.stem))
      if (_stemAxis(stem) >= start && _stemAxis(stem) <= end) stem,
  ].length;
}

/// The x the stem is drawn on, which is the centre of its own box.
double _stemAxis(MelodyGlyph stem) =>
    stem.bounds.left + stem.bounds.size.width / 2;

/// The stem that belongs to [head]: the one drawn at the head's right edge.
///
/// A stem's box starts at the head's right edge less its own weight (the stroke is inside the head on
/// one side and clears it on the other), so the vertical stroke nearest that x is the head's own. It
/// is found by x rather than by position in the list because a chord's stems and a beat's run are
/// both emitted in the model's order, which is not the reading order of the notes.
MelodyGlyph _stemOf(PlacedMelodyStaff staff, MelodyGlyph head) {
  final List<MelodyGlyph> stems = _glyphsOf(staff, MelodyGlyphKind.stem);
  MelodyGlyph? nearest;
  double best = double.infinity;
  for (final MelodyGlyph stem in stems) {
    final double distance = (stem.bounds.left - head.bounds.right).abs();
    if (distance < best) {
      best = distance;
      nearest = stem;
    }
  }
  return nearest!;
}

/// The x of a glyph's centre.
double _cx(MelodyGlyph glyph) =>
    glyph.bounds.left + glyph.bounds.size.width / 2;

void main() {
  group('the staff a musician reads', () {
    test('a treble staff reads E4 G4 B4 D5 F5 on its lines and F4 A4 C5 E5 in its spaces', () {
      // THE STAFF'S OWN NAMES. A musician is taught the treble lines from the bottom up as E, G, B,
      // D, F and the four spaces between them as F, A, C, E. The coordinate counts one letter per
      // step from the bottom line, so a line is an EVEN step (0, 2, 4, 6, 8) and a space an odd one
      // (1, 3, 5, 7). Both halves are asserted: the even half is the fact the defect broke, and the
      // odd half is the fact a fix made by "shift everything one line" would break.
      const List<Written> lines = <Written>[
        Written(NoteLetter.e, 4),
        Written(NoteLetter.g, 4),
        Written(NoteLetter.b, 4),
        Written(NoteLetter.d, 5),
        Written(NoteLetter.f, 5),
      ];
      for (int index = 0; index < lines.length; index++) {
        final int step = lines[index].stepOn('treble');
        stdout.writeln(
          'notation.treble line=${index + 1} letter=${lines[index]} step=$step',
        );
        expect(
          step,
          2 * index,
          reason:
              'line ${index + 1} of a treble staff is ${lines[index]}: the lines are E4 G4 B4 D5 '
              'F5, the coordinate starts at its bottom line, and two lines are two letters apart',
        );
      }
      const List<Written> spaces = <Written>[
        Written(NoteLetter.f, 4),
        Written(NoteLetter.a, 4),
        Written(NoteLetter.c, 5),
        Written(NoteLetter.e, 5),
      ];
      for (int index = 0; index < spaces.length; index++) {
        final int step = spaces[index].stepOn('treble');
        stdout.writeln(
          'notation.treble space=${index + 1} letter=${spaces[index]} step=$step',
        );
        expect(
          step,
          2 * index + 1,
          reason:
              'space ${index + 1} of a treble staff is ${spaces[index]}: the spaces are F4 A4 C5 '
              'E5, and a space is one letter ABOVE the line below it',
        );
      }
      // AND THE OCTAVE, which is the other distance the defect had to get right: seven letters is
      // seven steps on a staff, which is three and a half spaces — not fourteen.
      expect(
        const Written(NoteLetter.c, 5).stepOn('treble') -
            const Written(NoteLetter.c, 4).stepOn('treble'),
        7,
        reason: 'an octave is seven letters, so C4 and C5 are seven staff steps apart',
      );
    });

    test('a bass staff reads G2 B2 D3 F3 A3, and the two clefs place a pitch a twelfth apart', () {
      // The bass clef circles F3, the fourth line, and its bottom line is G2. The letters from the
      // bottom up are G, B, D, F, A — one third per line, as on every staff.
      const List<Written> lines = <Written>[
        Written(NoteLetter.g, 2),
        Written(NoteLetter.b, 2),
        Written(NoteLetter.d, 3),
        Written(NoteLetter.f, 3),
        Written(NoteLetter.a, 3),
      ];
      for (int index = 0; index < lines.length; index++) {
        final int step = lines[index].stepOn('bass');
        stdout.writeln(
          'notation.bass line=${index + 1} letter=${lines[index]} step=$step',
        );
        expect(
          step,
          2 * index,
          reason:
              'line ${index + 1} of a bass staff is ${lines[index]}: the bass lines are G2 B2 D3 '
              'F3 A3, and the coordinate starts at its bottom line',
        );
      }

      // THE TEST THE SECOND HALF OF THE DEFECT NEEDED: the two clefs must place the same SOUNDING
      // pitch at positions that differ by exactly the interval between the two bottom lines. A
      // musician counts twelve letters from G2 up to E4 (G A B C D E F G A B C D E), so every pitch
      // must sit twelve steps higher on a bass staff than on a treble one. The defect shifted the
      // bass staff by an octave instead — seven steps — so the two clefs contradicted each other and
      // a bass chart was a fifth out against a treble one.
      final int twelfth = const Written(
        NoteLetter.e,
        4,
      ).stepsAbove(const Written(NoteLetter.g, 2));
      expect(
        twelfth,
        12,
        reason:
            'G2 up to E4 is two octaves less a sixth: twelve letters, and twelve is the number '
            'this test asserts the clefs differ by',
      );
      for (final Written pitch in _pitchesForBothClefs) {
        final int treble = pitch.stepOn('treble');
        final int bass = pitch.stepOn('bass');
        stdout.writeln(
          'notation.clefs pitch=$pitch treble=$treble bass=$bass '
          'difference=${bass - treble}',
        );
        expect(
          bass - treble,
          twelfth,
          reason:
              '$pitch must sit $twelfth steps higher on a bass staff than on a treble one, '
              'because their bottom lines G2 and E4 are a twelfth apart — a clef that shifts the '
              'music by any other interval draws every note on the wrong line',
        );
      }
    });

    test('a written C4 is one ledger line below a treble staff and one above a bass staff', () {
      // TREBLE. The bottom line is E4, and the space immediately below it is a D, because a space
      // is one letter from the line beside it. Middle C is the ledger line below that space.
      final int e4 = const Written(NoteLetter.e, 4).stepOn('treble');
      expect(
        e4,
        0,
        reason: 'the bottom line of a treble staff is E4, and the coordinate is measured from it',
      );
      final int d4 = const Written(NoteLetter.d, 4).stepOn('treble');
      expect(
        d4,
        e4 - 1,
        reason: 'the space just below a treble staff holds D4: one letter below the bottom line E4',
      );
      final int c4Treble = const Written(NoteLetter.c, 4).stepOn('treble');
      stdout.writeln(
        'notation.middle-c clef=treble e4=$e4 d4=$d4 c4=$c4Treble',
      );
      expect(
        c4Treble,
        d4 - 1,
        reason:
            'a written C4 is the first ledger line BELOW a treble staff — one step below the '
            'space that holds D4. It is NOT the bottom line, which every musician reads as E4, '
            'and drawing it there is the defect that made the whole staff one line high',
      );
      expect(
        c4Treble,
        isNot(e4),
        reason:
            'C4 and E4 are a third apart and cannot be drawn in the same place without naming '
            'the wrong note',
      );
      expect(
        melodyLedgerLineOffsets(c4Treble).length,
        1,
        reason: 'middle C is written on exactly one ledger line below a treble staff',
      );
      expect(
        melodyLedgerLineOffsets(d4),
        isEmpty,
        reason:
            'D4 is the space below the staff and needs no ledger line: a ledger line exists for '
            'a pitch that lies ON a line outside the five',
      );

      // BASS. The bottom line is G2, so middle C lies above the staff — ten letters up, which is
      // the first ledger line above it.
      final int g2 = const Written(NoteLetter.g, 2).stepOn('bass');
      expect(
        g2,
        0,
        reason: 'the bottom line of a bass staff is G2, and the coordinate is measured from it',
      );
      final int c4Bass = const Written(NoteLetter.c, 4).stepOn('bass');
      expect(
        c4Bass,
        const Written(
          NoteLetter.c,
          4,
        ).stepsAbove(const Written(NoteLetter.g, 2)),
        reason:
            'middle C is ten letters above the bass staff bottom line G2, and every letter is a '
            'step from that line',
      );
      stdout.writeln(
        'notation.middle-c clef=bass g2=$g2 c4=$c4Bass '
        'ledger=${melodyLedgerLineOffsets(c4Bass)}',
      );
      expect(
        melodyLedgerLineOffsets(c4Bass).length,
        1,
        reason:
            'middle C is written on exactly one ledger line above a bass staff',
      );
      expect(
        melodyLedgerLineOffsets(c4Bass).single,
        greaterThan(0),
        reason: 'the ledger line of middle C on a bass staff is ABOVE the five lines',
      );
      expect(
        melodyLedgerLineOffsets(c4Treble).single,
        lessThan(0),
        reason:
            'and on a treble staff the same written C4 is BELOW the five lines: one pitch, two '
            'clefs, two positions',
      );
    });
  });

  group('ledger lines and accidentals', () {
    test('a ledger line is drawn on the staff grid and through the note it belongs to', () {
      // A ledger line has two jobs, and a musician uses both: it must lie ON a line of the staff's
      // own grid (a whole number of staff spaces from the bottom line, because that is where lines
      // are), and it must be at the notehead it names. A line half a space out sits in the SPACE
      // beside the staff and names nothing; a line a whole space away from its note belongs to a
      // different pitch. Both were exactly what the engraver did before the fix.
      //
      // THE TOLERANCE IS A QUARTER OF A STAFF SPACE, AND IT IS NAMED RATHER THAN HIDDEN. A ledger
      // glyph's box is as thick as its stroke, the layout places that box's TOP at the line's y,
      // and the painter draws the line down its CENTRE — so what is drawn sits half a stroke below
      // the notehead's centre: 0.78 page pixels at this 13-point space, measured below. That is a
      // sixth of the smallest error a reader could see; the defect these assertions exist for was a
      // WHOLE space, thirteen times more, and a line drawn in the space beside the staff is half a
      // space, six times more. The offset is printed so the number can be read off the run instead
      // of being taken on trust.
      const double tolerance = _staffSpace / 4;
      final PlacedMelodyStaff c4 = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.c, 4)),
      ]);
      final MelodyGlyph head = _oneOf(c4, MelodyGlyphKind.notehead);
      final MelodyGlyph ledger = _oneOf(c4, MelodyGlyphKind.ledgerLine);
      final double bottomLineY = c4.bounds.bottom;
      stdout.writeln(
        'notation.ledger pitch=C4 head_y=${_cy(head)} ledger_y=${_cy(ledger)} '
        'offset_from_head=${(_cy(ledger) - _cy(head)).toStringAsFixed(3)} '
        'bottom_line_y=$bottomLineY space=$_staffSpace',
      );
      expect(
        _cy(ledger),
        closeTo(_cy(head), tolerance),
        reason:
            'a note written on a ledger line sits ON that line: the line runs through its '
            'notehead, not a space away from it',
      );
      expect(
        (_cy(ledger) - bottomLineY) - _staffSpace,
        closeTo(0, tolerance),
        reason:
            'the first ledger line below the staff stands one staff space below the bottom line, '
            'because that is the distance between any two lines',
      );

      // A note two lines outside the staff needs TWO ledger lines, and each of them lies on the
      // grid: A3 is the second ledger line below a treble staff.
      final PlacedMelodyStaff a3 = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.a, 3)),
      ]);
      final List<MelodyGlyph> ledgers = _glyphsOf(
        a3,
        MelodyGlyphKind.ledgerLine,
      );
      final MelodyGlyph a3Head = _oneOf(a3, MelodyGlyphKind.notehead);
      expect(
        ledgers.length,
        2,
        reason:
            'A3 is the second ledger line below a treble staff: a pitch two lines outside the '
            'staff is drawn with two ledger lines',
      );
      for (final MelodyGlyph glyph in ledgers) {
        // Positive is BELOW the staff, which is the direction these two lines lie in: y grows down
        // the page, so a ledger under the staff has the larger y.
        final double spaces = (_cy(glyph) - bottomLineY) / _staffSpace;
        stdout.writeln(
          'notation.ledger pitch=A3 line_y=${_cy(glyph)} spaces_below_bottom=$spaces',
        );
        expect(
          (spaces - spaces.roundToDouble()).abs(),
          lessThan(tolerance / _staffSpace),
          reason:
              'a ledger line lies on the staff grid: its distance from the bottom line must be a '
              'whole number of staff spaces, and $spaces is not — a line half a space out stands '
              'where a space is, not where a line is',
        );
      }
      final double noteSpaces = (_cy(a3Head) - bottomLineY) / _staffSpace;
      expect(
        noteSpaces,
        closeTo(2, 1e-9),
        reason:
            'A3 is two staff spaces below the bottom line of a treble staff',
      );

      // AND A NOTE IN THE SPACE OUTSIDE THE STAFF gets a line NEARER THE STAFF than itself, never a
      // line through it: B3 is the space between the first and second ledger lines below.
      final PlacedMelodyStaff b3 = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.b, 3)),
      ]);
      final MelodyGlyph b3Ledger = _oneOf(b3, MelodyGlyphKind.ledgerLine);
      final MelodyGlyph b3Head = _oneOf(b3, MelodyGlyphKind.notehead);
      stdout.writeln(
        'notation.ledger pitch=B3 head_y=${_cy(b3Head)} ledger_y=${_cy(b3Ledger)} '
        'ledger_is_nearer=${(_cy(b3Ledger) - bottomLineY).abs() < (_cy(b3Head) - bottomLineY).abs()}',
      );
      expect(
        (_cy(b3Ledger) - bottomLineY).abs(),
        lessThan((_cy(b3Head) - bottomLineY).abs()),
        reason:
            'B3 is in a space below the staff, so its ledger line stands between it and the staff: '
            'a ledger line is nearer the staff than the note that needs it',
      );
      expect(
        _cy(b3Ledger),
        isNot(closeTo(_cy(b3Head), 1e-9)),
        reason: 'a note in a space is not written ON a line, so no ledger line passes through it',
      );
    });

    test('an accidental belongs to the letter of its note, not to the sound it makes', () {
      // AN ACCIDENTAL NEVER MOVES A NOTE OFF ITS LINE. The letter decides the position and the sign
      // decides the sound, so Db4 is written where D4 is and C#4 where C4 is — two different places
      // for one sounding pitch. That is what notation is: a reader who is given the position is given
      // the letter.
      final int d4 = const Written(NoteLetter.d, 4).stepOn('treble');
      final int db4 = const Written(
        NoteLetter.d,
        4,
        alter: -1,
      ).stepOn('treble');
      final int c4 = const Written(NoteLetter.c, 4).stepOn('treble');
      final int cSharp4 = const Written(
        NoteLetter.c,
        4,
        alter: 1,
      ).stepOn('treble');
      stdout.writeln(
        'notation.accidental d4=$d4 db4=$db4 c4=$c4 cSharp4=$cSharp4',
      );
      expect(
        db4,
        d4,
        reason: 'a flat changes what the note sounds, not which line it is written on',
      );
      expect(
        cSharp4,
        c4,
        reason: 'a sharp changes what the note sounds, not which line it is written on',
      );
      expect(
        db4,
        isNot(cSharp4),
        reason:
            'Db4 and C#4 sound alike and are written in different places — the space below the '
            'staff and the first ledger line below it — because notation spells by letter',
      );

      // And the SIGN is drawn at its notehead's own height and clear of it, which is how a reader
      // pairs a sign with a note when a chord or a fast passage has several on one beat.
      final PlacedMelodyStaff flat = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.d, 4, alter: -1)),
      ]);
      final MelodyGlyph flatHead = _oneOf(flat, MelodyGlyphKind.notehead);
      final MelodyGlyph sign = _oneOf(flat, MelodyGlyphKind.accidental);
      expect(
        sign.text,
        'b',
        reason: 'a flat is written with the letter a chart uses for it',
      );
      expect(
        _cy(sign),
        closeTo(_cy(flatHead), 1e-9),
        reason:
            'the sign of a Db belongs on the space that holds D — the same height as the notehead '
            'it alters, never on the space beside it',
      );
      expect(
        sign.bounds.right,
        lessThanOrEqualTo(flatHead.bounds.left),
        reason: 'a sign drawn over its notehead reads as a different note',
      );
      // AND THE NOTE IS OUTSIDE THE STAFF, which is where a musician reads a Db4 in treble clef: the
      // space immediately below the five lines. This is the assertion that would have caught the
      // defect's own signature — the owner saw the sign of a Db standing on the space that names F,
      // one line INSIDE the staff. A case that only compared the sign with its own notehead would
      // pass with the head and the sign both wrong together, which is exactly what the engraver did.
      expect(
        _cy(flatHead),
        greaterThan(flat.bounds.bottom),
        reason:
            'the space of D4 is BELOW a treble staff, so a Db4 is drawn below the bottom line — a '
            'Db whose sign stands on the space that names F has been engraved from the wrong letter',
      );

      // The flat is at D's height and NOT at C's, which is the geometry of the letter fact above:
      // a C#4 sits on a ledger line a whole space lower than the Db4 that sounds the same.
      final PlacedMelodyStaff sharp = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.c, 4, alter: 1)),
      ]);
      final double flatHeadY = _cy(flatHead);
      final double sharpHeadY = _cy(_oneOf(sharp, MelodyGlyphKind.notehead));
      stdout.writeln(
        'notation.accidental db4_head_y=$flatHeadY c#4_head_y=$sharpHeadY '
        'same_sound_different_place=${flatHeadY != sharpHeadY}',
      );
      expect(
        sharpHeadY,
        isNot(closeTo(flatHeadY, 1e-9)),
        reason:
            'a Db4 and a C#4 are one pitch and two positions: an engraver that placed a note by '
            'its sound would draw them on top of each other',
      );
    });
  });

  group('the conventions of the engraving', () {
    test('stems turn at the middle line, and a half or a whole note is hollow', () {
      // THE MIDDLE LINE IS THE THIRD OF FIVE, so it is the fourth step above the bottom line: B4 on
      // a treble staff and D3 on a bass staff. A note BELOW it takes a stem up; on it or above, the
      // stem goes down. A reader uses the stem to find the note's beat in a dense bar, so the
      // direction is not decoration.
      expect(
        const Written(NoteLetter.b, 4).stepOn('treble'),
        4,
        reason:
            'the middle line of a treble staff is B4: the third of five lines, four steps above the '
            'bottom one',
      );
      expect(
        const Written(NoteLetter.d, 3).stepOn('bass'),
        4,
        reason: 'the middle line of a bass staff is D3, and it is the same fourth step',
      );
      const List<(Written, bool)> stemCases = <(Written, bool)>[
        (Written(NoteLetter.c, 4), true),
        (Written(NoteLetter.e, 4), true),
        (Written(NoteLetter.a, 4), true),
        (Written(NoteLetter.b, 4), false),
        (Written(NoteLetter.c, 5), false),
        (Written(NoteLetter.f, 5), false),
      ];
      for (final (Written pitch, bool up) in stemCases) {
        final PlacedMelodyStaff staff = _engrave(<BeatNote>[_note(pitch)]);
        final MelodyGlyph head = _oneOf(staff, MelodyGlyphKind.notehead);
        final MelodyGlyph stem = _oneOf(staff, MelodyGlyphKind.stem);
        stdout.writeln(
          'notation.stem pitch=$pitch step=${pitch.stepOn('treble')} '
          'up=${stem.stemUp} expected_up=$up',
        );
        expect(
          stem.stemUp,
          up,
          reason:
              '$pitch ${up ? 'lies below' : 'lies on or above'} the middle line B4, so its stem '
              'points ${up ? 'up' : 'down'}',
        );
        expect(
          up ? stem.bounds.top : stem.bounds.bottom,
          up ? lessThan(head.bounds.top) : greaterThan(head.bounds.bottom),
          reason: 'the stem leaves the notehead on the side it points to, not through it',
        );
      }

      // HOLLOW AND FILLED. A whole note and a half note are engraved hollow; a quarter and anything
      // shorter is filled. This is how a musician reads the duration before reading anything else.
      for (final NoteBase base in <NoteBase>[NoteBase.whole, NoteBase.half]) {
        final PlacedMelodyStaff staff = _engrave(<BeatNote>[
          _note(const Written(NoteLetter.e, 4), value: NoteValue.plain(base)),
        ]);
        expect(
          _oneOf(staff, MelodyGlyphKind.notehead).filled,
          isFalse,
          reason: 'a ${base.name} note is engraved hollow',
        );
      }
      for (final NoteBase base in <NoteBase>[
        NoteBase.quarter,
        NoteBase.eighth,
        NoteBase.sixteenth,
      ]) {
        final PlacedMelodyStaff staff = _engrave(<BeatNote>[
          _note(const Written(NoteLetter.e, 4), value: NoteValue.plain(base)),
        ]);
        expect(
          _oneOf(staff, MelodyGlyphKind.notehead).filled,
          isTrue,
          reason: 'a ${base.name} note is engraved filled',
        );
      }
    });

    test('the staff publishes the clef it was engraved in and draws no clef sign', () {
      // THE CLEF IS A FACT OF THE ENGRAVING AND NOT OF THE PICTURE. `PlacedMelodyStaff.clef` still
      // says which clef the notes were placed by — a fact another renderer, or a test, may read —
      // but nothing on the staff is DRAWN as a clef. The owner removed the letter `G` that stood in
      // its place, in his words «зачем то буква G в начале. Если это просто убрать - уже будет
      // лучше»: a staff that looks signed and says nothing readable is worse than one with no clef.
      // This test exists so the next person cannot add one back as an improvement without meeting
      // the decision.
      final PlacedMelodyStaff treble = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.c, 4)),
      ], includeClef: true);
      expect(
        treble.clef,
        'G',
        reason:
            'the clef is still published: every note on the staff was placed by it, and a bass '
            'staff would say F',
      );
      final List<MelodyGlyph> text = <MelodyGlyph>[
        for (final MelodyGlyph glyph in treble.glyphs)
          if (glyph.text != null) glyph,
      ];
      stdout.writeln(
        'notation.clef published=${treble.clef} text_glyphs=${text.length} '
        'kinds=${treble.glyphs.map((MelodyGlyph glyph) => glyph.kind.name).toSet()}',
      );
      expect(
        text,
        isEmpty,
        reason:
            'nothing on the staff is drawn as text unless it is a note’s accidental: the letter '
            'that stood in the clef’s place was removed by the owner (A68), and a clef drawn as a '
            'glyph is the first shape that removal would come back in',
      );

      // The one kind of glyph that carries text is the accidental, and it carries its own note's
      // sign — so "text on the staff" cannot come to mean anything else by accident.
      final PlacedMelodyStaff withFlat = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.d, 4, alter: -1)),
      ]);
      final List<MelodyGlyph> texts = <MelodyGlyph>[
        for (final MelodyGlyph glyph in withFlat.glyphs)
          if (glyph.text != null) glyph,
      ];
      expect(
        texts.length,
        1,
        reason: 'one accidentals’ sign, and nothing else on the staff is text',
      );
      expect(texts.single.kind, MelodyGlyphKind.accidental);

      // A bar that opens no system prints no clef at all, which is the model half of the same rule:
      // one clef per system, and never a letter on every bar.
      expect(
        _engrave(<BeatNote>[_note(const Written(NoteLetter.c, 4))]).clef,
        isNull,
        reason: 'a bar that does not open a system does not print the clef',
      );
    });
  });

  group('beaming, which is the rhythm and not a decoration', () {
    test('one beam joins eighths and two join sixteenths, inside one beat', () {
      // THE NUMBER OF BEAMS IS THE VALUE, AND A MUSICIAN READS IT BEFORE HE READS A PITCH: one beam
      // is an eighth, two are sixteenths, three are thirty-seconds, and a group of notes written
      // without them is read as a different rhythm. The RUN is what a beat holds: in 4/4 a beat is a
      // quarter, so it holds two eighths or four sixteenths, and each case below is exactly one beat
      // — the number of notes is therefore part of the musical fact being asserted, not a fixture
      // detail.
      const List<Written> pitches = <Written>[
        Written(NoteLetter.c, 4),
        Written(NoteLetter.e, 4),
        Written(NoteLetter.f, 4),
        Written(NoteLetter.g, 4),
      ];
      const Map<NoteBase, (int, int)> beatOf = <NoteBase, (int, int)>{
        NoteBase.eighth: (2, 1),
        NoteBase.sixteenth: (4, 2),
        NoteBase.thirtySecond: (4, 3),
      };
      for (final MapEntry<NoteBase, (int, int)> entry in beatOf.entries) {
        final int runLength = entry.value.$1;
        final int expectedBeams = entry.value.$2;
        final PlacedMelodyStaff staff = _engrave(
          _run(runLength, entry.key, pitches),
        );
        final List<MelodyGlyph> beams = _beamsOf(staff);
        stdout.writeln(
          'notation.beam value=${entry.key.name} notes=$runLength beams=${beams.length} '
          'stems_per_beam=${beams.map((MelodyGlyph b) => _headsUnder(staff, b)).join(",")} '
          'thickness=${beams.isEmpty ? 0 : beams.first.strokeWidth} space=$_staffSpace',
        );
        expect(
          beams.length,
          expectedBeams,
          reason:
              'a run of ${entry.key.name} notes is written with $expectedBeams '
              '${expectedBeams == 1 ? 'beam' : 'beams'} — that is the sign that tells the reader the '
              'value, and it is why the owner named beaming rather than any other missing shape',
        );
        for (final MelodyGlyph beam in beams) {
          expect(
            _headsUnder(staff, beam),
            runLength,
            reason:
                'every beam of the group runs the whole group: the notes all take the first beam, '
                'and a shorter note\'s extra beams arrive beside it rather than instead of it',
          );
        }
        // AND A BEAMED NOTE CARRIES NO FLAG. A flag on a beamed note tells the reader the note is
        // alone in its beat, which is the opposite of what the beam says.
        for (final MelodyGlyph stem in _glyphsOf(staff, MelodyGlyphKind.stem)) {
          expect(
            stem.flagLength,
            0,
            reason: 'a beamed note is joined, so it is not flagged',
          );
        }
        expect(
          _glyphsOf(staff, MelodyGlyphKind.flag),
          isEmpty,
          reason: 'a flag is drawn from a stem and never published on its own',
        );
      }

      // A LONE EIGHTH KEEPS ITS FLAG, because there is no other note of its beat to join: an
      // engraver who beamed it to nothing would draw a single-note group, and one who beamed it to
      // the next beat would join two different beats.
      final PlacedMelodyStaff lone = _engrave(<BeatNote>[
        _note(
          const Written(NoteLetter.e, 4),
          value: const NoteValue.plain(NoteBase.eighth),
        ),
      ]);
      stdout.writeln(
        'notation.beam lone_eighth beams=${_beamsOf(lone).length} '
        'flag=${_oneOf(lone, MelodyGlyphKind.stem).flagLength}',
      );
      expect(
        _beamsOf(lone),
        isEmpty,
        reason: 'one note is not a group, so it carries a flag and no beam',
      );
      expect(
        _oneOf(lone, MelodyGlyphKind.stem).flagLength,
        greaterThan(0),
        reason: 'an eighth note alone in its beat is flagged, which is how it is read as an eighth',
      );
    });

    test('a beat boundary breaks the beam, and a beam never crosses a barline', () {
      // BEAMS GROUP BY BEAT AND NOT BY THE BAR. In 4/4 a run of four eighth notes is two beams of
      // two and not one beam of four, because the beat is the quarter and a reader's eye is looking
      // for the beat. The two cases below are the same four notes: the first in two beats, the
      // second in one — and the engraving must not be the same picture for both.
      const List<Written> pitches = <Written>[
        Written(NoteLetter.c, 4),
        Written(NoteLetter.e, 4),
        Written(NoteLetter.f, 4),
        Written(NoteLetter.g, 4),
      ];
      final List<BeatNote> acrossTwoBeats = <BeatNote>[
        _note(pitches[0], beat: 0, step: 0, value: _eighth),
        _note(pitches[1], beat: 0, step: 1, value: _eighth),
        _note(pitches[2], beat: 1, step: 0, value: _eighth),
        _note(pitches[3], beat: 1, step: 1, value: _eighth),
      ];
      final PlacedMelodyStaff split = _engrave(acrossTwoBeats);
      final List<MelodyGlyph> splitBeams = _beamsOf(split);
      stdout.writeln(
        'notation.beam across_two_beats beams=${splitBeams.length} '
        'sizes=${splitBeams.map((MelodyGlyph b) => _headsUnder(split, b)).join(",")} '
        'spans=${splitBeams.map((MelodyGlyph b) => '[${_beamStart(b)}..${_beamEnd(b)}]').join(" ")}',
      );
      expect(
        splitBeams.length,
        2,
        reason:
            'four eighth notes in two beats are two beams of two: a beat boundary breaks the beam, '
            'and a single beam across both beats would tell the reader the run is one group',
      );
      for (final MelodyGlyph beam in splitBeams) {
        expect(
          _headsUnder(split, beam),
          2,
          reason: 'each beam joins the two notes of one beat and no note of the other',
        );
      }
      expect(
        _beamEnd(splitBeams[0]),
        lessThan(_beamStart(splitBeams[1])),
        reason:
            'the two groups do not overlap, so no reader can take them for one',
      );

      // AND A BEAM STAYS INSIDE ITS BAR. Engraved through the layout engine, because "does it cross
      // the barline" is a question about a page: two bars whose last beat is a sixteenth run, and
      // every beam of the page must lie inside the bar that owns it.
      final Song song = _beamSong(<List<BeatNote>>[
        for (int bar = 0; bar < 2; bar++)
          _run(4, NoteBase.sixteenth, pitches, beat: 3),
      ]);
      final List<PageLayout> pages = const LayoutEngine().layout(
        song,
        pageWidth: 1200,
        pageHeight: 3000,
      );
      final PageLayout page = pages.single;
      int inspected = 0;
      for (final PlacedBar placed in page.bars) {
        final List<MelodyGlyph> beams = _beamsOf(placed.melody);
        for (final MelodyGlyph beam in beams) {
          stdout.writeln(
            'notation.beam bar=${placed.barIndex} '
            'barX=[${placed.melody.bounds.left.toStringAsFixed(1)}..'
            '${placed.melody.bounds.right.toStringAsFixed(1)}] '
            'beamX=[${_beamStart(beam).toStringAsFixed(1)}..${_beamEnd(beam).toStringAsFixed(1)}]',
          );
          expect(
            _beamStart(beam),
            greaterThanOrEqualTo(placed.melody.bounds.left),
            reason:
                'a beam begins inside the bar that owns it: a beam reaching past a barline joins '
                'notes of two bars, which no musician wrote',
          );
          expect(
            _beamEnd(beam),
            lessThanOrEqualTo(placed.melody.bounds.right),
            reason:
                'a beam ends inside its own bar. The barline is the one line that says a measure '
                'has ended, and a beam drawn across it says the opposite',
          );
          inspected++;
        }
      }
      expect(
        inspected,
        greaterThanOrEqualTo(2),
        reason: 'both bars must contribute a beam, or the containment above proves nothing',
      );

      // AND IN A COMPOUND METER THE BEAT IS THE DOTTED ONE, so the same rule writes eighths in
      // THREES. 6/8 has two beats, each a dotted quarter long; six eighth notes are therefore two
      // beams of three and not three beams of two. This is the assertion that a rule counting the
      // meter's numerator instead of its beats would fail — and it is the difference between an
      // engraving a jazz musician reads as 6/8 and one he reads as 3/4 written oddly.
      final PlacedMelodyStaff compound = _engrave(<BeatNote>[
        for (int beat = 0; beat < 2; beat++)
          for (int step = 0; step < 3; step++)
            _note(pitches[0], beat: beat, step: step, value: _eighth),
      ], timeSignature: TimeSignature.sixEight);
      final List<MelodyGlyph> compoundBeams = _beamsOf(compound);
      stdout.writeln(
        'notation.beam compound=6/8 beams=${compoundBeams.length} '
        'sizes=${compoundBeams.map((MelodyGlyph b) => _headsUnder(compound, b)).join(",")}',
      );
      expect(
        compoundBeams.length,
        2,
        reason:
            'six eighths in 6/8 are two groups, one per dotted-quarter beat',
      );
      for (final MelodyGlyph beam in compoundBeams) {
        expect(
          _headsUnder(compound, beam),
          3,
          reason:
              'a beat of 6/8 holds THREE eighths, so the beam joins three notes: a beam of two '
              'would be the grouping of 3/4, which is a different meter read the same way',
        );
      }
    });

    test('the shorter value\'s extra beam sits inside the longer one\'s span', () {
      // A MIXED GROUP STACKS ITS BEAMS. An eighth and a sixteenth in one group share the first beam,
      // because both are eighths or shorter, and the sixteenth's second beam covers only the notes
      // that need it — inside the group, between the first beam and the noteheads, which is the side
      // a reader's eye searches for the extra stroke.
      //
      // THE GROUP IS A 6/8 BEAT, and that is a musical fact rather than a convenience: the beat in
      // 6/8 is the dotted quarter, so it holds an eighth, two sixteenths and an eighth — six
      // sixteenths exactly — which is a mixed group with a longer note at BOTH ends. In 4/4 a beat
      // holds only an eighth and two sixteenths, and the shorter value's beam would then run to the
      // group's own edge on one side, which is a weaker picture of the same rule.
      final PlacedMelodyStaff staff = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.c, 4), beat: 0, step: 0, value: _eighth),
        _note(
          const Written(NoteLetter.e, 4),
          beat: 0,
          step: 1,
          value: const NoteValue.plain(NoteBase.sixteenth),
        ),
        _note(
          const Written(NoteLetter.f, 4),
          beat: 0,
          step: 2,
          value: const NoteValue.plain(NoteBase.sixteenth),
        ),
        _note(const Written(NoteLetter.g, 4), beat: 0, step: 3, value: _eighth),
      ], timeSignature: TimeSignature.sixEight);
      final List<MelodyGlyph> beams = _beamsOf(staff);
      expect(
        beams.length,
        2,
        reason:
            'the group carries the first beam that every one of its notes takes, and one more for '
            'the sixteenths — an eighth has one beam, so the group has exactly two',
      );
      final MelodyGlyph primary = beams[0];
      final MelodyGlyph secondary = beams[1];
      stdout.writeln(
        'notation.beam mixed beams=${beams.length} '
        'primary_heads=${_headsUnder(staff, primary)} '
        'secondary_heads=${_headsUnder(staff, secondary)} '
        'primary_x=[${_beamStart(primary)}..${_beamEnd(primary)}] '
        'secondary_x=[${_beamStart(secondary)}..${_beamEnd(secondary)}]',
      );
      expect(
        _headsUnder(staff, primary),
        4,
        reason: 'the first beam runs over every note of the group',
      );
      expect(
        _headsUnder(staff, secondary),
        2,
        reason:
            'the second beam covers the two sixteenths and stops: drawn over the eighths it would '
            'say the eighths are sixteenths',
      );
      expect(
        _beamStart(secondary),
        greaterThan(_beamStart(primary)),
        reason:
            'the extra beam begins inside the group rather than at its edge',
      );
      expect(
        _beamEnd(secondary),
        lessThan(_beamEnd(primary)),
        reason: 'and it ends inside the group, so it is a stroke WITHIN the longer one\'s span',
      );
      // INSIDE, WHICH IS A SIDE AND NOT ONLY A SPAN: the notes here sit low on the staff, so every
      // stem points up and the extra beam hangs below the first one, toward the noteheads.
      final double probeX = _beamStart(secondary);
      final double primaryY = _beamYAt(primary, probeX);
      final double secondaryY = _beamYAt(secondary, probeX);
      stdout.writeln(
        'notation.beam mixed primary_y=$primaryY secondary_y=$secondaryY '
        'stem_up=${_stemOf(staff, _glyphsOf(staff, MelodyGlyphKind.notehead).first).stemUp}',
      );
      expect(
        secondaryY,
        greaterThan(primaryY),
        reason:
            'with the stems up the beams hang above the notes, and the shorter value\'s beam is the '
            'one NEARER the notes — outside the first beam it would read as a longer note instead',
      );
    });

    test('a beam is half a staff space thick, slopes toward the higher side, and is level for one pitch', () {
      // A BEAM'S WEIGHT AND ITS SLOPE ARE CONVENTIONS A MUSICIAN READS, so both are asserted against
      // the measure a musician knows rather than against the number the code uses: half a staff
      // space is the ordinary thickness, and it is several times a stem's weight, which is what makes
      // two joined notes look joined instead of adjacent.
      final PlacedMelodyStaff pair = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.g, 4), beat: 0, step: 0, value: _eighth),
        _note(const Written(NoteLetter.a, 4), beat: 0, step: 1, value: _eighth),
      ]);
      final MelodyGlyph beam = _beamsOf(pair).single;
      final MelodyGlyph stem = _glyphsOf(pair, MelodyGlyphKind.stem).first;
      stdout.writeln(
        'notation.beam thickness=${beam.strokeWidth} '
        'in_spaces=${beam.strokeWidth / _staffSpace} stem_weight=${stem.strokeWidth} '
        'ratio=${beam.strokeWidth / stem.strokeWidth}',
      );
      expect(
        beam.strokeWidth,
        closeTo(_staffSpace / 2, 1e-9),
        reason:
            'a beam is half a staff space thick — an eighth of the staff\'s height over four lines '
            '— which is the proportion printed music uses and the reason a beam reads as a joining',
      );
      expect(
        beam.strokeWidth / stem.strokeWidth,
        greaterThan(3),
        reason:
            'a beam must be several times a stem\'s weight: at a stem\'s weight the group reads as '
            'two notes with a rule between them rather than as one rhythmic group',
      );

      // LEVEL FOR ONE PITCH, EXACTLY. Four notes of one pitch are written with a beam that is level:
      // not "nearly level", because a tilt computed from a contour with no direction is a tilt a
      // reader can see and cannot explain.
      final PlacedMelodyStaff repeated = _engrave(
        _run(4, NoteBase.sixteenth, const <Written>[
          Written(NoteLetter.b, 4),
          Written(NoteLetter.b, 4),
          Written(NoteLetter.b, 4),
          Written(NoteLetter.b, 4),
        ]),
      );
      for (final MelodyGlyph level in _beamsOf(repeated)) {
        expect(
          level.from.y,
          closeTo(level.to.y, 1e-12),
          reason:
              'a group of one pitch is drawn with a LEVEL beam: there is no higher side to slope '
              'toward, and a tilt would invent a contour the music does not have',
        );
      }

      // AND A GROUP THAT DOES RISE SLOPES UP, GENTLY. Written low-to-high, the beam's far end is
      // higher on the page — that is the side whose notes are higher — and the slope is limited, so a
      // leap is drawn as a beam a reader can follow rather than as a diagonal scribble.
      final PlacedMelodyStaff rising = _engrave(
        _run(4, NoteBase.sixteenth, const <Written>[
          Written(NoteLetter.c, 4),
          Written(NoteLetter.e, 4),
          Written(NoteLetter.g, 4),
          Written(NoteLetter.b, 4),
        ]),
      );
      final MelodyGlyph upward = _beamsOf(rising).first;
      final double slope =
          (upward.to.y - upward.from.y) / (upward.to.x - upward.from.x);
      stdout.writeln(
        'notation.beam rising from_y=${upward.from.y} to_y=${upward.to.y} '
        'slope=$slope levels=${_beamsOf(rising).length}',
      );
      expect(
        upward.to.y,
        lessThan(upward.from.y),
        reason:
            'the group rises, so its beam rises with it: y grows DOWN the page, so the end over the '
            'higher notes has the smaller y',
      );
      expect(
        slope.abs(),
        lessThanOrEqualTo(0.5 + 1e-9),
        reason:
            'a beam slopes gently — no more than half a staff space of rise per space of run — so '
            'that a leap inside the group is still a beam and not a diagonal line',
      );

      // AND THE DESCENDING CASE MIRRORS IT, which is the assertion a one-way tilt would pass by
      // accident on either case alone.
      final PlacedMelodyStaff falling = _engrave(
        _run(4, NoteBase.sixteenth, const <Written>[
          Written(NoteLetter.b, 4),
          Written(NoteLetter.g, 4),
          Written(NoteLetter.e, 4),
          Written(NoteLetter.c, 4),
        ]),
      );
      final MelodyGlyph downward = _beamsOf(falling).first;
      stdout.writeln(
        'notation.beam falling from_y=${downward.from.y} to_y=${downward.to.y}',
      );
      expect(
        downward.to.y,
        greaterThan(downward.from.y),
        reason: 'a falling group is drawn with a falling beam',
      );
    });

    test('a group\'s stems all turn one way, and the beam sits at their ends', () {
      // THE DIRECTION IS THE GROUP'S, NOT THE NOTE'S. A beamed group has one beam, so it has one place
      // for the stems to arrive: every stem of the group points the same way. The note FARTHEST FROM
      // THE MIDDLE LINE decides, which is the engraved rule — and the pair below is chosen so that a
      // per-note rule (the one A70 pins for a single note) gives a WRONG answer for the second note:
      // F4 is below the middle line B4 and takes a stem up, D5 is above it and would take a stem
      // down, and one group cannot have both.
      final PlacedMelodyStaff staff = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.f, 4), beat: 0, step: 0, value: _eighth),
        _note(const Written(NoteLetter.d, 5), beat: 0, step: 1, value: _eighth),
      ]);
      final MelodyGlyph beam = _beamsOf(staff).single;
      final List<MelodyGlyph> heads = _glyphsOf(
        staff,
        MelodyGlyphKind.notehead,
      );
      final List<MelodyGlyph> stems = _glyphsOf(staff, MelodyGlyphKind.stem);
      stdout.writeln(
        'notation.beam group_f3_d5 stems_up=${stems.map((MelodyGlyph s) => s.stemUp).join(",")} '
        'steps=${<int>[const Written(NoteLetter.f, 4).stepOn('treble'), const Written(NoteLetter.d, 5).stepOn('treble')].join(",")} '
        'beam_y=[${beam.from.y}..${beam.to.y}]',
      );
      for (final MelodyGlyph stem in stems) {
        expect(
          stem.stemUp,
          isTrue,
          reason:
              'F4 lies three steps below the middle line and D5 two above it, so the group is a LOW '
              'group and every stem in it points up — the note farthest from the middle line decides '
              'for the whole group, which is the rule a per-note decision gets wrong',
        );
      }
      // AND THE BEAM IS AT THEIR ENDS: for every note, the stem's free end is the beam's own line at
      // that stem, so the beam touches the stems rather than floating above them or cutting through
      // them.
      for (int index = 0; index < heads.length; index++) {
        final MelodyGlyph stem = _stemOf(staff, heads[index]);
        final double beamY = _beamYAt(beam, _stemAxis(stem));
        expect(
          stem.stemUp ? stem.bounds.top : stem.bounds.bottom,
          closeTo(beamY, 1e-9),
          reason:
              'the stem of a beamed note ends ON the beam: the beam is what the stems run to, and a '
              'stem that stopped short or ran through would leave the group unjoined',
        );
      }
      // THE BEAM IS ON THE STEM SIDE OF EVERY NOTEHEAD, which is what "stems up" means when the beam
      // is drawn: above the highest head of the group.
      for (final MelodyGlyph head in heads) {
        expect(
          beam.bounds.top,
          lessThan(head.bounds.top),
          reason: 'with the stems up the beam is drawn above every note of the group',
        );
      }
    });

    test('a rest breaks the group, and a beam does not reach across one', () {
      // A REST IS A SILENCE AND A BEAM IS A CLAIM THAT NOTES BELONG TOGETHER. Two eighths on beat one
      // are a pair; the second half of beat two is a rest, so the eighth on beat two is NOT joined to
      // them — it is written with its own flag, which is exactly how a musician sees that it stands
      // alone.
      final PlacedMelodyStaff staff = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.c, 4), beat: 0, step: 0, value: _eighth),
        _note(const Written(NoteLetter.d, 4), beat: 0, step: 1, value: _eighth),
        _note(const Written(NoteLetter.e, 4), beat: 1, step: 0, value: _eighth),
      ]);
      final List<MelodyGlyph> beams = _beamsOf(staff);
      final List<MelodyGlyph> heads = _glyphsOf(
        staff,
        MelodyGlyphKind.notehead,
      );
      final MelodyGlyph afterTheRest = _stemOf(staff, heads.last);
      stdout.writeln(
        'notation.beam rest beams=${beams.length} '
        'heads=${beams.map((MelodyGlyph b) => _headsUnder(staff, b)).join(",")} '
        'flagged=${afterTheRest.flagLength > 0} '
        'beam_end=${beams.isEmpty ? 0 : _beamEnd(beams.single)} '
        'rest_note_x=${_cx(heads.last)}',
      );
      expect(
        beams.length,
        1,
        reason: 'the two notes of beat one are joined; nothing else is',
      );
      expect(
        _headsUnder(staff, beams.single),
        2,
        reason: 'the beam covers beat one and stops at the rest',
      );
      expect(
        _beamEnd(beams.single),
        lessThan(_cx(heads.last)),
        reason:
            'the beam ends before the note that follows the rest: a beam across a silence claims a '
            'grouping the music does not have',
      );
      expect(
        afterTheRest.flagLength,
        greaterThan(0),
        reason: 'the note after the rest keeps its flag',
      );

      // AND TWO NOTES SEPARATED BY A WHOLE REST ARE NOT A GROUP AT ALL: eighths on beats one and
      // three are two single notes, so neither is beamed.
      final PlacedMelodyStaff separated = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.c, 4), beat: 0, value: _eighth),
        _note(const Written(NoteLetter.e, 4), beat: 2, value: _eighth),
      ]);
      stdout.writeln(
        'notation.beam separated beams=${_beamsOf(separated).length}',
      );
      expect(
        _beamsOf(separated),
        isEmpty,
        reason: 'two eighth notes with a beat of silence between them are two notes and not a pair',
      );
    });
  });

  group('what a glyph box means', () {
    test('a ledger line box is the ink of the line, so its centre is the line it names', () {
      // THE DECISION THIS CASE PINS, AND WHY IT IS STATED AS A DECISION. A glyph's box on this staff
      // is THE INK IT DRAWS: a notehead's box is its ellipse and a stem's box is its stroke, and the
      // painter draws a stroked glyph down the centre of the box it is handed. The ledger line was
      // the one exception — its box put its TOP on the line's y and the painter then drew its centre
      // half a stroke below that — so what a reader saw stood 0.78 page pixels low at a 13-point
      // space (measured, named and left open when these tests were written; A70 §3). The fix is that
      // the box means the ink, which makes the offset zero EXACTLY rather than small: the other
      // reading — move the painter's arithmetic for one kind of glyph — would have left one kind
      // drawn from a different rule than every other kind.
      final PlacedMelodyStaff staff = _engrave(<BeatNote>[
        _note(const Written(NoteLetter.c, 4)),
      ]);
      final MelodyGlyph head = _oneOf(staff, MelodyGlyphKind.notehead);
      final MelodyGlyph ledger = _oneOf(staff, MelodyGlyphKind.ledgerLine);
      final double bottomLineY = staff.bounds.bottom;
      stdout.writeln(
        'notation.ledger-box head_y=${_cy(head)} ledger_y=${_cy(ledger)} '
        'offset=${_cy(ledger) - _cy(head)} '
        'box_height=${ledger.bounds.size.height} stroke=${ledger.strokeWidth} '
        'spaces_below_bottom=${(_cy(ledger) - bottomLineY) / _staffSpace}',
      );
      expect(
        _cy(ledger),
        _cy(head),
        reason:
            'the line a note is written ON runs through the notehead: the ledger glyph\'s centre is '
            'the line\'s own y, so the two heights agree exactly and not merely to within a '
            'tolerance',
      );
      expect(
        (_cy(ledger) - bottomLineY) / _staffSpace,
        closeTo(1, 1e-9),
        reason:
            'the first ledger line below the staff is exactly one staff space below the bottom line, '
            'because that is the distance between any two lines',
      );
      expect(
        ledger.bounds.size.height,
        ledger.strokeWidth,
        reason:
            'a ledger line\'s box is as tall as its stroke and no taller: the box is the ink, which '
            'is what lets the painter draw its centre and every caller read a musical height',
      );
    });
  });
}
