// PURPOSE: Pin what the melody staff ENGRAVES against music theory rather than against the code
//          that engraves it: which letter each of a staff's five lines names, which line or space a
//          written pitch must occupy, how many ledger lines a pitch outside the staff needs and
//          where they stand, that an accidental belongs to the letter of its note, which way a stem
//          points, and that the staff publishes its clef without drawing one.
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
// INPUTS: None. The staff the geometry cases are engraved on is declared below with the
//         application's own staff-space proportion, so the case needs no device, no font and no
//         fixture file.
// OUTPUTS: Pass/fail per musical fact, plus `notation.*` lines on stdout naming every letter, step
//          and ledger-line distance the assertions rest on, so a failure shows the staff rather
//          than only a boolean.
// KEYWORDS: test, melody-staff, engraving, music-theory, treble-clef, bass-clef, ledger-line,
//           accidental, stem, clef-published-not-drawn, falsifiable
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
PlacedMelodyStaff _engrave(
  List<BeatNote> melody, {
  String clef = 'treble',
  bool includeClef = false,
}) => placeMelodyStaff(
  bar: Bar(melody: melody),
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

/// The one glyph of [kind] the staff drew.
///
/// A `single` rather than a first-or-null because every case that uses it engraves exactly one note:
/// a second glyph of the same kind means the engraver drew something the case did not ask for, and
/// that is a failure worth seeing.
MelodyGlyph _oneOf(PlacedMelodyStaff staff, MelodyGlyphKind kind) =>
    _glyphsOf(staff, kind).single;

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
}
