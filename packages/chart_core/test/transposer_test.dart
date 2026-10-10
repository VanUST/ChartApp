// PURPOSE: State and check the claim spike S3 exists to answer — that transposing a chart
//          through all twelve keys returns the spelling it started with — plus the individual
//          moves a musician would notice if they were wrong.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation. The round-trip is checked twice: once as a single move of
//          twelve semitones, and once as twelve successive one-semitone moves that also advance
//          the key, which is how a musician actually transposes through the cycle.
// KEYWORDS: test, transposition, round-trip, twelve-keys, property, spelling-preservation
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The spelled major keys of the chromatic scale, in pitch-class order from C.
///
/// Listed explicitly rather than generated, so that the cycle the round-trip is measured against
/// is visible in the test instead of being an assumption about how a key is named.
const List<Key> _chromaticKeys = <Key>[
  Key(tonic: WrittenNote(NoteLetter.c, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.d, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.e, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.e, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.f, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.f, 1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.g, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.a, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.a, 0), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.b, -1), mode: Mode.major),
  Key(tonic: WrittenNote(NoteLetter.b, 0), mode: Mode.major),
];

/// Chords covering the shapes a chart contains: every triad, a seventh, a tension, a slash bass
/// and a parenthesised marking. Every root pitch class appears at least once across the set.
const List<Chord> _probeChords = <Chord>[
  Chord(root: ChordRoot(0)),
  Chord(root: ChordRoot(1)),
  Chord(root: ChordRoot(2)),
  Chord(root: ChordRoot(3)),
  Chord(root: ChordRoot(4)),
  Chord(root: ChordRoot(5)),
  Chord(root: ChordRoot(6)),
  Chord(root: ChordRoot(7)),
  Chord(root: ChordRoot(8)),
  Chord(root: ChordRoot(9)),
  Chord(root: ChordRoot(10)),
  Chord(root: ChordRoot(11)),
  Chord(root: ChordRoot(0), quality: ChordQuality.minorTriad),
  Chord(root: ChordRoot(2), quality: ChordQuality.minorSeventh),
  Chord(
    root: ChordRoot(7),
    quality: ChordQuality.dominantSeventh,
    alterations: <String>['b9'],
  ),
  Chord(root: ChordRoot(0), bass: ChordRoot(4)),
  Chord(
    root: ChordRoot(5),
    quality: ChordQuality.majorSeventh,
    parenthesised: true,
  ),
];

void main() {
  const SpellingTable table = SpellingTable();
  const Transposer transposer = Transposer();

  group('a single move a musician would notice', () {
    test('a major triad up two semitones in the target key', () {
      // C up a whole tone is D, and Bb major's scale contains D.
      final Chord moved = transposer.transposeChord(
        const Chord(root: ChordRoot(0)),
        2,
      );
      expect(
        moved.render(
          const Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major),
          table,
        ),
        'D',
      );
    });

    test('a flat chord stays flat in a flat target key', () {
      // Ab up a whole tone is Bb. The target key, Bb major, spells it as its own tonic.
      final Chord moved = transposer.transposeChord(
        const Chord(root: ChordRoot(8)),
        2,
      );
      expect(
        moved.render(
          const Key(tonic: WrittenNote(NoteLetter.b, -1), mode: Mode.major),
          table,
        ),
        'Bb',
      );
    });

    test('a sharp chord follows a sharp target key', () {
      // F# up a semitone is G, the tonic of the target key.
      final Chord moved = transposer.transposeChord(
        const Chord(root: ChordRoot(6)),
        1,
      );
      expect(
        moved.render(
          const Key(tonic: WrittenNote(NoteLetter.g, 0), mode: Mode.major),
          table,
        ),
        'G',
      );
    });

    test('the quality, the tensions and the marking survive the move', () {
      final Chord moved = transposer.transposeChord(
        const Chord(
          root: ChordRoot(0),
          quality: ChordQuality.dominantSeventh,
          alterations: <String>['b9'],
          parenthesised: true,
        ),
        2,
      );
      // Root C up a whole tone is D; nothing else changes.
      expect(
        moved.render(
          const Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major),
          table,
        ),
        '(D7b9)',
      );
    });

    test('a slash bass is transposed with its root', () {
      final Chord moved = transposer.transposeChord(
        const Chord(root: ChordRoot(0), bass: ChordRoot(4)),
        2,
      );
      // C/E up a whole tone is D/F#: E is pitch class 4, plus 2 is 6, which D major spells F#.
      expect(
        moved.render(
          const Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major),
          table,
        ),
        'D/F#',
      );
    });

    test('transposing down is the inverse of transposing up', () {
      const Chord original = Chord(
        root: ChordRoot(3),
        quality: ChordQuality.minorSeventh,
      );
      final Chord there = transposer.transposeChord(original, 5);
      final Chord back = transposer.transposeChord(there, -5);
      expect(back, original);
      expect(
        back.render(Key.cMajor, table),
        original.render(Key.cMajor, table),
      );
    });
  });

  group('round trip', () {
    test('twelve semitones in the same key changes nothing at all', () {
      for (final Chord chord in _probeChords) {
        for (final Key key in _chromaticKeys) {
          final Chord moved = transposer.transposeChord(chord, 12);
          expect(
            moved.render(key, table),
            chord.render(key, table),
            reason: '${chord.root} in $key',
          );
        }
      }
    });

    test('twelve one-semitone moves that advance the key return the original chart', () {
      // The claim of spike S3. Each step moves the chord and the key together, so the chart is
      // re-spelled in twelve different keys before arriving back at C major.
      for (final Chord chord in _probeChords) {
        Chord current = chord;
        int keyIndex = 0;
        for (int step = 0; step < 12; step++) {
          current = transposer.transposeChord(current, 1);
          keyIndex = (keyIndex + 1) % _chromaticKeys.length;
        }
        expect(keyIndex, 0, reason: 'the key cycle must return to C major');
        expect(
          current.render(_chromaticKeys[keyIndex], table),
          chord.render(_chromaticKeys[0], table),
          reason: 'starting from ${chord.root}',
        );
      }
    });

    test('an intermediate step is spelled in the intermediate key, not the original', () {
      // Guards against a round trip that only appears to work because spelling ignored the key.
      // F up one semitone while the key moves to F# major, whose tonic is pitch class 6.
      final Chord moved = transposer.transposeChord(
        const Chord(root: ChordRoot(5)),
        1,
      );
      expect(moved.render(_chromaticKeys[6], table), 'F#');
      // The same sounding note read in the key it started in is Gb: C major has no signature and
      // prefers flats. One pitch, two instructions, and the key is what decides between them.
      expect(moved.render(_chromaticKeys[0], table), 'Gb');
    });

    test('no combination of chord and target key produces an unspellable note', () {
      for (final Chord chord in _probeChords) {
        for (int semitones = -12; semitones <= 12; semitones++) {
          final Chord moved = transposer.transposeChord(chord, semitones);
          for (final Key key in _chromaticKeys) {
            final WrittenNote spelled = moved.root.spellIn(key, table);
            expect(
              spelled.pitchClass,
              moved.root.pitchClass,
              reason:
                  'spelling of ${chord.root} moved by $semitones must sound the same',
            );
          }
        }
      }
    });
  });

  group('transposeKey', () {
    test('a whole tone above C major is D major', () {
      final Key moved = transposer.transposeKey(Key.cMajor, 2);
      expect(moved.tonicPitchClass, 2);
      expect(moved.mode, Mode.major);
      expect(moved.toString(), 'D major');
    });

    test('keeps the source key direction rather than flipping notation', () {
      // A flat key moved a whole tone stays a flat key.
      const Key eFlatMajor = Key(
        tonic: WrittenNote(NoteLetter.e, -1),
        mode: Mode.major,
      );
      final Key moved = transposer.transposeKey(eFlatMajor, 2);
      expect(moved.tonicPitchClass, 5);
      expect(moved.tonic.toString(), 'F');
      expect(moved.prefersSharps, isFalse);
    });

    test('preserves the mode', () {
      final Key moved = transposer.transposeKey(Key.aMinor, 3);
      expect(moved.mode, Mode.minor);
      expect(moved.tonicPitchClass, 0);
    });
  });
}
