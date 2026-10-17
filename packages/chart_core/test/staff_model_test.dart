// PURPOSE: Pin the staff-set, note-value and note-placement model that owner decision D16
//          introduces: that a melody and a drum part live alongside the chord line rather than
//          replacing it, that only the pitched staff transposes, and that durations are exact
//          rationals so a bar can be checked for being full without a tick grid.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation. Every duration and octave below is derived by hand from the
//          documented arithmetic.
// KEYWORDS: test, staff-set, note-value, tuplet, exact-duration, drum-map, bar-fill, hand-derived
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A quarter-note middle C.
NoteMark middleCQuarter = NoteMark(
  place: cellAt(0),
  pitch: PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 4),
  value: NoteValue.plain(NoteBase.quarter),
);

/// A bar of one middle C quarter note.
final Bar barWithOneNote = Bar(melody: <NoteMark>[middleCQuarter]);

/// A bar with a kick and a snare on beats one and three.
Bar barWithDrums = Bar(
  percussion: <PercussionMark>[
    PercussionMark(
      place: cellAt(0),
      instrument: 36,
      value: NoteValue.plain(NoteBase.quarter),
    ),
    PercussionMark(
      place: cellAt(2),
      instrument: 38,
      value: NoteValue.plain(NoteBase.quarter),
    ),
  ],
);

void main() {
  group('StaffSpec', () {
    test('a pitched staff carries no drum map', () {
      const StaffSpec staff = StaffSpec.pitched();
      expect(staff.kind, StaffKind.pitched);
      expect(staff.drumMap, isNull);
      expect(staff.clef, 'treble');
    });

    test('a percussion staff carries the map it reads through', () {
      const StaffSpec staff = StaffSpec.percussion(
        drumMap: <int, String>{36: 'Kick', 38: 'Snare'},
      );
      expect(staff.kind, StaffKind.percussion);
      expect(staff.drumMap, <int, String>{36: 'Kick', 38: 'Snare'});
    });

    test('the drum map is part of equality', () {
      const StaffSpec one = StaffSpec.percussion(
        drumMap: <int, String>{36: 'Kick'},
      );
      const StaffSpec other = StaffSpec.percussion(
        drumMap: <int, String>{36: 'Kick', 38: 'Snare'},
      );
      expect(one == other, isFalse);
      expect(
        one == const StaffSpec.percussion(drumMap: <int, String>{36: 'Kick'}),
        isTrue,
      );
    });
  });

  group('StaffSet', () {
    test('chords only is the empty set and has nothing to transpose', () {
      expect(StaffSet.chordsOnly.isEmpty, isTrue);
      expect(StaffSet.chordsOnly.pitched, isNull);
      expect(StaffSet.chordsOnly.percussion, isNull);
      expect(StaffSet.chordsOnly.hasTransposableContent, isFalse);
    });

    test('a pitched staff makes the song transposable', () {
      const StaffSet staves = StaffSet(pitched: StaffSpec.pitched());
      expect(staves.isEmpty, isFalse);
      expect(staves.hasTransposableContent, isTrue);
    });

    test('a drum part alone does NOT make the song transposable', () {
      // The rule the editor reads to disable the transpose control: a kick drum is not a whole
      // tone higher because the chart moved up a tone.
      const StaffSet staves = StaffSet(
        percussion: StaffSpec.percussion(drumMap: <int, String>{36: 'Kick'}),
      );
      expect(staves.isEmpty, isFalse);
      expect(staves.percussion, isNotNull);
      expect(staves.hasTransposableContent, isFalse);
    });

    test('melody and percussion coexist rather than replacing one another', () {
      // The whole point of D16 over the earlier draft: both staves at once.
      const StaffSet staves = StaffSet(
        pitched: StaffSpec.pitched(),
        percussion: StaffSpec.percussion(drumMap: <int, String>{36: 'Kick'}),
      );
      expect(staves.pitched, isNotNull);
      expect(staves.percussion, isNotNull);
      expect(staves.hasTransposableContent, isTrue);
      expect(staves.toString(), 'StaffSet(chords + pitched + percussion)');
    });

    test('the validated factory rejects a staff in the wrong slot', () {
      // The const constructor cannot check this — a const initialiser may not call the kind
      // getter — so the factory is the path that does, and it must fail loudly.
      expect(
        () => StaffSet.of(
          pitched: StaffSpec.percussion(drumMap: <int, String>{36: 'Kick'}),
        ),
        throwsArgumentError,
      );
      expect(
        () => StaffSet.of(percussion: const StaffSpec.pitched()),
        throwsArgumentError,
      );
      expect(
        StaffSet.of(pitched: const StaffSpec.pitched()).pitched,
        isNotNull,
      );
    });
  });

  group('NoteValue', () {
    test('a plain note is one over its denominator of a whole note', () {
      expect(const NoteValue.plain(NoteBase.whole).wholeNumerator, 1);
      expect(const NoteValue.plain(NoteBase.whole).wholeDenominator, 1);
      expect(const NoteValue.plain(NoteBase.quarter).wholeNumerator, 1);
      expect(const NoteValue.plain(NoteBase.quarter).wholeDenominator, 4);
      expect(const NoteValue.plain(NoteBase.thirtySecond).wholeDenominator, 32);
    });

    test(
      'a dot multiplies by three halves and a second dot by seven quarters',
      () {
        // (2^(dots+1) - 1) / 2^dots: one dot is 3/2, two dots are 7/4.
        const NoteValue dottedQuarter = NoteValue(
          base: NoteBase.quarter,
          dots: 1,
        );
        expect(dottedQuarter.wholeNumerator, 3);
        expect(dottedQuarter.wholeDenominator, 8);

        const NoteValue doubleDottedQuarter = NoteValue(
          base: NoteBase.quarter,
          dots: 2,
        );
        expect(doubleDottedQuarter.wholeNumerator, 7);
        expect(doubleDottedQuarter.wholeDenominator, 16);
      },
    );

    test('a triplet shortens to two thirds', () {
      // A quarter in a 3:2 tuplet lasts a sixth of a whole note, which is two thirds of a quarter.
      const NoteValue quarterTriplet = NoteValue(
        base: NoteBase.quarter,
        tuplet: Tuplet.triplet,
      );
      expect(quarterTriplet.wholeNumerator, 2);
      expect(quarterTriplet.wholeDenominator, 12);
    });

    test('a septuplet is exact, which a tick grid for triplets cannot be', () {
      // Seven eighths in the time of four is 1/14 of a whole note each, and seven of them make
      // exactly a half. On a 1920-tick grid this would quantise; here it does not.
      const NoteValue seventh = NoteValue(
        base: NoteBase.eighth,
        tuplet: Tuplet.septuplet,
      );
      expect(seventh.wholeNumerator, 4);
      expect(seventh.wholeDenominator, 56);
      // Each is 1/14 of a whole note, so one is shorter than a half.
      expect(
        seventh.compareDuration(const NoteValue.plain(NoteBase.half)),
        isNegative,
      );
      // And seven of them are exactly a half: 7 x 4/56 = 28/56, which cross-multiplies against
      // 1/2 as 28 * 2 == 1 * 56.
      const NoteValue half = NoteValue.plain(NoteBase.half);
      expect(
        7 * seventh.wholeNumerator * half.wholeDenominator,
        half.wholeNumerator * seventh.wholeDenominator,
      );
    });

    test('comparison orders by exact duration', () {
      const NoteValue quarter = NoteValue.plain(NoteBase.quarter);
      const NoteValue eighth = NoteValue.plain(NoteBase.eighth);
      const NoteValue dottedQuarter = NoteValue(
        base: NoteBase.quarter,
        dots: 1,
      );
      const NoteValue quarterTriplet = NoteValue(
        base: NoteBase.quarter,
        tuplet: Tuplet.triplet,
      );

      expect(
        eighth.compareDuration(quarter),
        isNegative,
        reason: 'an eighth is shorter',
      );
      expect(quarter.compareDuration(dottedQuarter), isNegative);
      expect(
        quarterTriplet.compareDuration(eighth),
        isPositive,
        reason: 'a quarter triplet is longer',
      );
      expect(
        quarter.compareDuration(const NoteValue.plain(NoteBase.quarter)),
        0,
      );
    });

    test('two spellings of the same length are recognised as equal', () {
      // A dotted quarter and a quarter-plus-eighth are the same duration written differently.
      const NoteValue dotted = NoteValue(base: NoteBase.quarter, dots: 1);
      const NoteValue tripletTwice = NoteValue(
        base: NoteBase.quarter,
        tuplet: Tuplet.triplet,
      );
      expect(
        dotted.hasSameDurationAs(
          const NoteValue(base: NoteBase.quarter, dots: 1),
        ),
        isTrue,
      );
      expect(dotted.hasSameDurationAs(tripletTwice), isFalse);
    });
  });

  group('PitchedNote', () {
    test('octaves are scientific, so middle C is C4 and MIDI 60', () {
      const PitchedNote middleC = PitchedNote(
        note: WrittenNote(NoteLetter.c, 0),
        octave: 4,
      );
      expect(middleC.midiNumber, 60);
      expect(middleC.toString(), 'C4');
    });

    test('the octave changes at C, not at A', () {
      // The convention every pitch-range check depends on: A4 is 69, and B3 is 59, one below the
      // C that starts octave 4.
      expect(
        const PitchedNote(
          note: WrittenNote(NoteLetter.a, 0),
          octave: 4,
        ).midiNumber,
        69,
      );
      expect(
        const PitchedNote(
          note: WrittenNote(NoteLetter.b, 0),
          octave: 3,
        ).midiNumber,
        59,
      );
      expect(
        const PitchedNote(
          note: WrittenNote(NoteLetter.c, 0),
          octave: 5,
        ).midiNumber,
        72,
      );
    });

    test('an altered pitch keeps its spelling and its sounding number', () {
      const PitchedNote bFlat3 = PitchedNote(
        note: WrittenNote(NoteLetter.b, -1),
        octave: 3,
      );
      expect(bFlat3.midiNumber, 58);
      expect(bFlat3.toString(), 'Bb3');
      expect(
        bFlat3 ==
            const PitchedNote(note: WrittenNote(NoteLetter.a, 1), octave: 3),
        isFalse,
      );
    });
  });

  group('melodyFillsBar', () {
    test('four quarters fill 4/4', () {
      expect(
        melodyFillsBar(TimeSignature.fourFour, <NoteMark>[
          for (int beat = 0; beat < 4; beat++)
            NoteMark(
              place: cellAt(beat),
              pitch: middleCQuarter.pitch,
              value: const NoteValue.plain(NoteBase.quarter),
            ),
        ]),
        isTrue,
      );
    });

    test('three quarters do not fill 4/4 but do fill 3/4', () {
      final List<NoteMark> three = <NoteMark>[
        for (int beat = 0; beat < 3; beat++)
          NoteMark(
            place: cellAt(beat),
            pitch: middleCQuarter.pitch,
            value: const NoteValue.plain(NoteBase.quarter),
          ),
      ];
      expect(melodyFillsBar(TimeSignature.fourFour, three), isFalse);
      expect(melodyFillsBar(TimeSignature.threeFour, three), isTrue);
    });

    test('an empty bar is not a full one', () {
      // Stated rather than left implicit: an empty melody could mean "not written yet" and a bar
      // that is genuinely full is a different claim.
      expect(
        melodyFillsBar(TimeSignature.fourFour, const <NoteMark>[]),
        isFalse,
      );
    });

    test('three half-note triplets fill 4/4 exactly', () {
      // Three in the time of two halves is a whole note. This is the case a tick grid chosen for
      // binary values reports as short: the sum is 1/3 + 1/3 + 1/3, exact only as a rational.
      const NoteValue halfTriplet = NoteValue(
        base: NoteBase.half,
        tuplet: Tuplet.triplet,
      );
      final List<NoteMark> notes = <NoteMark>[
        for (int beat = 0; beat < 3; beat++)
          NoteMark(
            place: cellAt(beat),
            pitch: middleCQuarter.pitch,
            value: halfTriplet,
          ),
      ];
      expect(melodyFillsBar(TimeSignature.fourFour, notes), isTrue);
      // And the same three notes do not fill 3/4, whose length is three quarters, not a whole.
      expect(melodyFillsBar(TimeSignature.threeFour, notes), isFalse);
    });

    test('a whole note fills 4/4 but overfills 6/8, which is only three quarters long', () {
      final List<NoteMark> whole = <NoteMark>[
        NoteMark(
          place: cellAt(0),
          pitch: middleCQuarter.pitch,
          value: const NoteValue.plain(NoteBase.whole),
        ),
      ];
      expect(melodyFillsBar(TimeSignature.fourFour, whole), isTrue);
      // 6/8 is six eighths, which is 3/4 of a whole note, so a whole note is too long.
      expect(melodyFillsBar(TimeSignature.sixEight, whole), isFalse);
    });
  });

  group('a bar carries all three staves', () {
    test('melody and percussion are part of bar identity', () {
      expect(barWithOneNote == const Bar(), isFalse);
      expect(barWithDrums == const Bar(), isFalse);
      expect(barWithDrums == barWithOneNote, isFalse);
      // A bar with both differs from either one alone.
      final Bar both = Bar(
        melody: <NoteMark>[middleCQuarter],
        percussion: <PercussionMark>[
          PercussionMark(
            place: cellAt(0),
            instrument: 36,
            value: NoteValue.plain(NoteBase.quarter),
          ),
        ],
      );
      expect(both == barWithOneNote, isFalse);
      expect(both == barWithDrums, isFalse);
    });

    test(
      'a chord, a note and a hit can share the same beat and remain distinct',
      () {
        // The addressing is common on purpose so that one anchor scheme covers every object a user
        // can point at; the objects themselves stay different kinds.
        final Bar bar = Bar(
          chords: <ChordMark>[
            ChordMark(
              place: cellAt(0),
              chord: Chord(root: ChordRoot(0)),
            ),
          ],
          melody: <NoteMark>[middleCQuarter],
          percussion: <PercussionMark>[
            PercussionMark(
              place: cellAt(0),
              instrument: 36,
              value: NoteValue.plain(NoteBase.quarter),
            ),
          ],
        );
        expect(bar.chords.single.pseudoBeat, 0);
        expect(bar.melody.single.pseudoBeat, 0);
        expect(bar.percussion.single.pseudoBeat, 0);
        expect(bar.toString(), contains('1 chord(s)'));
        expect(bar.toString(), contains('1 note(s)'));
        expect(bar.toString(), contains('1 hit(s)'));
      },
    );

    test('a tie points forward from the earlier note', () {
      final NoteMark tied = NoteMark(
        place: cellAt(0),
        pitch: PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 4),
        value: NoteValue.plain(NoteBase.quarter),
        tiedToNext: true,
      );
      expect(tied.tiedToNext, isTrue);
      expect(tied == middleCQuarter, isFalse);
    });
  });

  group('Song.staffSet', () {
    test('defaults to chords only, which is every imported chart', () {
      const Song song = Song(title: 'Imported');
      expect(song.staffSet, StaffSet.chordsOnly);
      expect(song.staffSet.isEmpty, isTrue);
    });

    test('is part of song identity', () {
      const Song chordsOnly = Song(title: 'Same');
      const Song withMelody = Song(
        title: 'Same',
        staffSet: StaffSet(pitched: StaffSpec.pitched()),
      );
      expect(withMelody == chordsOnly, isFalse);
      expect(const Song(title: 'X') == const Song(title: 'X'), isTrue);
    });
  });
}
