// PURPOSE: Pin how a sounding pitch is written in a key — the scale each key produces from its
//          arithmetic, which pitches are answered by the signature rather than by preference,
//          and exactly which spelling the chromatic rule picks. This is the one rule whose
//          output a musician reads, so its expectations are derived by hand from the documented
//          ordering (fewest accidentals, then key direction, then letter order).
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, spelling, enharmonic, key-signature, chromatic-spelling, hand-derived
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The spelled major keys of the chromatic scale, in pitch-class order from C.
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

void main() {
  const SpellingTable table = SpellingTable();

  group('the spelled major keys of the chromatic scale', () {
    test('cover all twelve pitch classes exactly once, in order', () {
      // The transposition round-trip depends on this list being a genuine cycle: if two entries
      // shared a pitch class, one step of the cycle would not be a semitone.
      expect(_chromaticKeys.length, 12);
      expect(
        _chromaticKeys.map((Key key) => key.tonicPitchClass).toList(),
        <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
      );
    });
  });

  group('scaleOf', () {
    test('derives C major, E major and F major from the arithmetic', () {
      expect(
        table.scaleOf(Key.cMajor).map((WrittenNote n) => n.toString()).toList(),
        <String>['C', 'D', 'E', 'F', 'G', 'A', 'B'],
      );
      expect(
        table
            .scaleOf(
              const Key(tonic: WrittenNote(NoteLetter.e, 0), mode: Mode.major),
            )
            .map((WrittenNote n) => n.toString())
            .toList(),
        <String>['E', 'F#', 'G#', 'A', 'B', 'C#', 'D#'],
      );
      expect(
        table
            .scaleOf(
              const Key(tonic: WrittenNote(NoteLetter.f, 0), mode: Mode.major),
            )
            .map((WrittenNote n) => n.toString())
            .toList(),
        <String>['F', 'G', 'A', 'Bb', 'C', 'D', 'E'],
      );
    });

    test('derives a flat key without a lookup table', () {
      expect(
        table
            .scaleOf(
              const Key(tonic: WrittenNote(NoteLetter.d, -1), mode: Mode.major),
            )
            .map((WrittenNote n) => n.toString())
            .toList(),
        <String>['Db', 'Eb', 'F', 'Gb', 'Ab', 'Bb', 'C'],
      );
    });

    test('gives a minor key the natural minor scale of its signature', () {
      expect(
        table.scaleOf(Key.aMinor).map((WrittenNote n) => n.toString()).toList(),
        <String>['A', 'B', 'C', 'D', 'E', 'F', 'G'],
      );
      expect(
        table
            .scaleOf(
              const Key(tonic: WrittenNote(NoteLetter.e, 0), mode: Mode.minor),
            )
            .map((WrittenNote n) => n.toString())
            .toList(),
        <String>['E', 'F#', 'G', 'A', 'B', 'C', 'D'],
      );
    });
  });

  group('diatonic spelling is answered by the key signature', () {
    test('a scale degree is spelled as the scale spells it', () {
      expect(
        table
            .spell(
              8,
              const Key(tonic: WrittenNote(NoteLetter.a, 0), mode: Mode.major),
            )
            .toString(),
        'G#',
      );
      expect(
        table
            .spell(
              6,
              const Key(tonic: WrittenNote(NoteLetter.g, 0), mode: Mode.major),
            )
            .toString(),
        'F#',
      );
      expect(
        table
            .spell(
              10,
              const Key(tonic: WrittenNote(NoteLetter.f, 0), mode: Mode.major),
            )
            .toString(),
        'Bb',
      );
      expect(
        table
            .spell(
              8,
              const Key(tonic: WrittenNote(NoteLetter.e, -1), mode: Mode.major),
            )
            .toString(),
        'Ab',
      );
    });

    test('a preference cannot override a note the key signature fixes', () {
      // Asking for a flat spelling of G# in A major would put a note in the chart that
      // contradicts the key it is written in, so the preference is scoped to chromatic notes.
      expect(
        table
            .spell(
              8,
              const Key(tonic: WrittenNote(NoteLetter.a, 0), mode: Mode.major),
              preference: SpellingPreference.flat,
            )
            .toString(),
        'G#',
      );
    });
  });

  group(
    'chromatic spelling follows fewest accidentals, then the key direction',
    () {
      test('a key with no signature spells its chromatic notes with flats', () {
        // bII, bIII, bVI and bVII as a musician writes them in C major.
        expect(table.spell(1, Key.cMajor).toString(), 'Db');
        expect(table.spell(3, Key.cMajor).toString(), 'Eb');
        expect(table.spell(8, Key.cMajor).toString(), 'Ab');
        expect(table.spell(10, Key.cMajor).toString(), 'Bb');
      });

      test('the tritone above the tonic is a documented deviation', () {
        // Convention in C major is F# for #IV. A single accidental direction cannot be right for
        // all six chromatic notes, and flat is right for five of them; the deviation is recorded
        // here so that a later change to the rule is a deliberate decision rather than a surprise.
        expect(table.spell(6, Key.cMajor).toString(), 'Gb');
      });

      test('a sharp key spells its chromatic notes with sharps', () {
        expect(
          table
              .spell(
                1,
                const Key(
                  tonic: WrittenNote(NoteLetter.d, 0),
                  mode: Mode.major,
                ),
              )
              .toString(),
          'C#',
        );
        expect(
          table
              .spell(
                3,
                const Key(
                  tonic: WrittenNote(NoteLetter.g, 0),
                  mode: Mode.major,
                ),
              )
              .toString(),
          'D#',
        );
      });

      test('a natural spelling beats an altered one', () {
        // Pitch class 0 is not in D major. A# would be wrong here in every sense: C is one
        // accidental cheaper and is the lowered seventh a chart would actually write.
        expect(
          table
              .spell(
                0,
                const Key(
                  tonic: WrittenNote(NoteLetter.d, 0),
                  mode: Mode.major,
                ),
              )
              .toString(),
          'C',
        );
        expect(
          table
              .spell(
                0,
                const Key(
                  tonic: WrittenNote(NoteLetter.c, 1),
                  mode: Mode.major,
                ),
              )
              .toString(),
          // Pitch class 0 is the seventh degree of C# major, which the signature writes as B#.
          // C would be the same key on a piano and the wrong note on the page.
          'B#',
        );
      });

      test(
        'a preference overrides the key direction for chromatic notes only',
        () {
          expect(
            table
                .spell(6, Key.cMajor, preference: SpellingPreference.sharp)
                .toString(),
            'F#',
          );
          expect(
            table
                .spell(8, Key.cMajor, preference: SpellingPreference.sharp)
                .toString(),
            'G#',
          );
          // Pitch class 3 is chromatic in D major, so the preference applies: D# by the key's
          // sharp signature, Eb when the caller asks for flats.
          const Key dMajor = Key(
            tonic: WrittenNote(NoteLetter.d, 0),
            mode: Mode.major,
          );
          expect(table.spell(3, dMajor).toString(), 'D#');
          expect(
            table
                .spell(3, dMajor, preference: SpellingPreference.flat)
                .toString(),
            'Eb',
          );
        },
      );

      test('never produces an alteration beyond a double accidental', () {
        for (final Key key in _chromaticKeys) {
          for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
            expect(
              table.spell(pitchClass, key).alter.abs(),
              lessThanOrEqualTo(2),
              reason: 'pitch class $pitchClass in $key',
            );
          }
        }
      });

      test(
        'is deterministic: the same three inputs always give the same answer',
        () {
          // The property the round-trip rests on. Checked directly rather than inferred, because a
          // future change that made spelling depend on call order would still pass every other test
          // in this file.
          for (final Key key in _chromaticKeys) {
            for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
              final WrittenNote first = table.spell(pitchClass, key);
              final WrittenNote second = table.spell(pitchClass, key);
              expect(second, first, reason: 'pitch class $pitchClass in $key');
            }
          }
        },
      );
    },
  );
}
