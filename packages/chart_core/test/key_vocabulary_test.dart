// PURPOSE: State, as a musical fact rather than as a reading of the code, the name a musician writes
//          for each of the twenty-four keys, and check the vocabulary against it. The defect this
//          file exists for is named in `transposer.dart`'s own comment: the chromatic spelling rule
//          could label a chart `Gb minor` where a musician writes `F# minor`, because "how is this
//          pitch written" and "what is this key called" are different questions. Twenty-four names,
//          twenty-four verdicts, and the one place where the notation itself offers two names is
//          printed rather than hidden.
// INPUTS: None. The expected names are written out in this file, which is the point: a table read
//         back from the code under test could only prove that the code agrees with itself.
// OUTPUTS: Pass/fail per expectation, plus a `key.*` line per case on stdout so a failure names the
//          pitch class, the mode, the name wanted and the name produced.
// KEYWORDS: test, key-name, vocabulary, twenty-four-keys, musical-fact, d27, circle-of-fifths,
//           relative-major
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The name a musician writes for each MAJOR tonic, by pitch class from C.
///
/// These are not derived here and must not be: they are what a theory book and a printed chart say.
/// Eleven of the twelve sit on the circle of fifths at the position with the FEWEST accidentals —
/// Db five against C#'s seven, Eb three against D#'s nine, Ab four against G#'s eight — and the
/// sixth is the one signature the circle offers from either end, written here as [Gb] because its
/// relative minor is a name musicians use (see [musicianMinor] and the group below).
const List<String> musicianMajor = <String>[
  'C major',
  'Db major',
  'D major',
  'Eb major',
  'E major',
  'F major',
  'Gb major',
  'G major',
  'Ab major',
  'A major',
  'Bb major',
  'B major',
];

/// The name a musician writes for each MINOR tonic, by pitch class from C.
///
/// A minor key is named by its RELATIVE MAJOR's signature — A minor and C major are no accidentals,
/// F# minor and A major are three sharps, Eb minor and Gb major are six flats — so every name here
/// belongs to a key signature that exists. There is no relative major for `Gb minor` (it would be
/// Bbb major), which is exactly why that name was wrong, and `F# minor` is forced for its pitch
/// class for the same reason: F# minor's relative major is A major, which exists.
const List<String> musicianMinor = <String>[
  'C minor',
  'C# minor',
  'D minor',
  'Eb minor',
  'E minor',
  'F minor',
  'F# minor',
  'G minor',
  'G# minor',
  'A minor',
  'Bb minor',
  'B minor',
];

/// The two names of the SIX-ACCIDENTAL signature, which is the only one the circle offers twice.
///
/// F# major is six sharps and Gb major is six flats; their relative minors are D# minor and Eb
/// minor. Both majors are written in real charts, so nothing is lost by choosing either. Both
/// minors are NOT: Eb minor is a key musicians play in and D# minor is a name that essentially never
/// appears. Because a minor key's name is its relative major's, the tie is broken once, at the
/// signature, and it is broken toward the side whose relative minor a musician writes.
const List<String> theSixAccidentalSignature = <String>[
  'major, pitch class 6: automatic Gb major · explicit sharp F# major',
  'minor, pitch class 3: automatic Eb minor · explicit sharp D# minor',
];

/// A source key on the flat side of the circle, in each mode.
///
/// Used instead of a direction flag so that the name is asked for the way a chart asks for it: by
/// transposing a real key. Db major carries five flats and Bb minor six, so both are unambiguously
/// flat-side and neither can be accused of being the neutral case.
const Key flatMajor = Key(
  tonic: WrittenNote(NoteLetter.d, -1),
  mode: Mode.major,
);
const Key flatMinor = Key(
  tonic: WrittenNote(NoteLetter.b, -1),
  mode: Mode.minor,
);

/// A source key on the sharp side of the circle, in each mode: B major five sharps, G# minor five.
///
/// G# MINOR AND NOT A# MINOR, and that is a choice about the claim rather than about the key. A# minor
/// is practical — its relative major is C# major, seven sharps — but it is NOT one of the twelve names
/// this project writes, so asking the table THROUGH it would meet the identity rule at that key's own
/// pitch class and the twenty-four rows would need an exception. This source is a key the table itself
/// writes, so the rows can be asserted from it without one; the identity rule is proved separately, on
/// the keys it exists for.
const Key sharpMajor = Key(
  tonic: WrittenNote(NoteLetter.b, 0),
  mode: Mode.major,
);
const Key sharpMinor = Key(
  tonic: WrittenNote(NoteLetter.g, 1),
  mode: Mode.minor,
);

/// The signed interval from [from] to [to], as a musician counts it: the shortest way round, with a
/// tritone reported upward because that is how the key grid labels it.
int intervalTo(int from, int to) {
  final int upward = normalizePitchClass(to - from);
  return upward > 6 ? upward - 12 : upward;
}

void main() {
  const Transposer transposer = Transposer();
  const KeyVocabulary vocabulary = KeyVocabulary();
  const SpellingTable table = SpellingTable();

  group('the twenty-four keys a musician writes', () {
    test('every major pitch class is named as written', () {
      for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
        // Asked through the TRANSPOSER, not through the vocabulary directly, because the transposer
        // is where a transposed chart's key comes from: a vocabulary that answered correctly and was
        // never called would leave the defect in place.
        final Key named = transposer.transposeKey(
          flatMajor,
          intervalTo(flatMajor.tonicPitchClass, pitchClass),
        );
        stdout.writeln(
          'key.name pc=$pitchClass mode=major '
          'want="${musicianMajor[pitchClass]}" got="${named.name}"',
        );
        expect(
          named.name,
          musicianMajor[pitchClass],
          reason: 'pitch class $pitchClass in major, from ${flatMajor.name}',
        );
        expect(named.mode, Mode.major);
        expect(named.tonicPitchClass, pitchClass);
        expect(
          named.isPracticallySpelled,
          isTrue,
          reason: 'a key a musician writes has a key signature',
        );
      }
    });

    test('every minor pitch class is named as written, which is the half that was wrong', () {
      for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
        final Key named = transposer.transposeKey(
          flatMinor,
          intervalTo(flatMinor.tonicPitchClass, pitchClass),
        );
        stdout.writeln(
          'key.name pc=$pitchClass mode=minor '
          'want="${musicianMinor[pitchClass]}" got="${named.name}"',
        );
        expect(
          named.name,
          musicianMinor[pitchClass],
          reason: 'pitch class $pitchClass in minor, from ${flatMinor.name}',
        );
        expect(named.mode, Mode.minor);
        expect(named.tonicPitchClass, pitchClass);
        expect(
          named.isPracticallySpelled,
          isTrue,
          reason:
              'a minor key is nameable only when its RELATIVE MAJOR has a signature, '
              'which is why Gb minor is not a key and F# minor is',
        );
      }
    });

    test('the same twenty-four names come out of a chart written on the sharp side', () {
      // The stronger claim, and the one that makes the table a table rather than two: the name of a
      // key does not depend on which key the chart was transposed FROM. Both sides produce it.
      for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
        final Key namedMajor = transposer.transposeKey(
          sharpMajor,
          intervalTo(sharpMajor.tonicPitchClass, pitchClass),
        );
        final Key namedMinor = transposer.transposeKey(
          sharpMinor,
          intervalTo(sharpMinor.tonicPitchClass, pitchClass),
        );
        stdout.writeln(
          'key.sharp_side pc=$pitchClass '
          'major=${namedMajor.name} minor=${namedMinor.name}',
        );
        expect(
          namedMajor.name,
          musicianMajor[pitchClass],
          reason: 'major pc $pitchClass from a sharp key',
        );
        expect(
          namedMinor.name,
          musicianMinor[pitchClass],
          reason: 'minor pc $pitchClass from a sharp key',
        );
      }
    });
  });

  group('the six-accidental signature, which is the only choice between equals', () {
    test('the automatic answer is the side whose relative minor a musician writes', () {
      expect(theSixAccidentalSignature, hasLength(2));
      int majorTies = 0;
      int minorTies = 0;
      for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
        final Key major = vocabulary.keyFor(pitchClass, Mode.major);
        final Key minor = vocabulary.keyFor(pitchClass, Mode.minor);
        final Key majorSharp = vocabulary.keyFor(
          pitchClass,
          Mode.major,
          preference: SpellingPreference.sharp,
        );
        final Key minorSharp = vocabulary.keyFor(
          pitchClass,
          Mode.minor,
          preference: SpellingPreference.sharp,
        );
        stdout.writeln(
          'key.override pc=$pitchClass '
          'major=${major.name}(${major.signatureFifths})/'
          '${majorSharp.name}(${majorSharp.signatureFifths}) '
          'minor=${minor.name}(${minor.signatureFifths})/'
          '${minorSharp.name}(${minorSharp.signatureFifths})',
        );
        // The automatic answer is always the table's, from either starting key.
        expect(major.name, musicianMajor[pitchClass]);
        expect(minor.name, musicianMinor[pitchClass]);
        // Whatever a caller asks for, the answer is a key signature — never an off-circle name.
        expect(majorSharp.isPracticallySpelled, isTrue);
        expect(minorSharp.isPracticallySpelled, isTrue);
        // And where the two sides of the circle give DIFFERENT names, the automatic answer is the
        // one that costs fewer accidentals — the property "the name a musician writes" reduces to.
        // A pitch class whose two directions agree has nothing to compare and is skipped; a TIE
        // here is the six-accidental signature and nowhere else.
        if (major != majorSharp) {
          expect(
            major.signatureFifths.abs(),
            lessThanOrEqualTo(majorSharp.signatureFifths.abs()),
            reason: 'major pc $pitchClass: ${major.name} vs ${majorSharp.name}',
          );
          if (major.signatureFifths.abs() == majorSharp.signatureFifths.abs()) {
            majorTies++;
            expect(
              pitchClass,
              6,
              reason: 'only one signature is written two ways',
            );
          }
        }
        if (minor != minorSharp) {
          expect(
            minor.signatureFifths.abs(),
            lessThanOrEqualTo(minorSharp.signatureFifths.abs()),
            reason: 'minor pc $pitchClass: ${minor.name} vs ${minorSharp.name}',
          );
          if (minor.signatureFifths.abs() == minorSharp.signatureFifths.abs()) {
            minorTies++;
            expect(
              pitchClass,
              3,
              reason: 'and its relative minor is the same one decision',
            );
          }
        }
      }
      expect(
        majorTies,
        1,
        reason: 'one major signature is offered by both ends',
      );
      expect(
        minorTies,
        1,
        reason: 'and one minor signature, a minor third below it',
      );
      // The one signature, both modes, and both names are real key signatures — which is why the
      // override is honoured rather than refused.
      expect(vocabulary.keyFor(6, Mode.major).name, 'Gb major');
      expect(
        vocabulary
            .keyFor(6, Mode.major, preference: SpellingPreference.sharp)
            .name,
        'F# major',
      );
      expect(vocabulary.keyFor(3, Mode.minor).name, 'Eb minor');
      expect(
        vocabulary
            .keyFor(3, Mode.minor, preference: SpellingPreference.sharp)
            .name,
        'D# minor',
      );
      // ... and the override is still filtered by the circle: asking for the sharp side of a pitch
      // class whose sharp name has nine sharps gives the flat name, because nine is not a signature.
      expect(
        vocabulary
            .keyFor(3, Mode.major, preference: SpellingPreference.sharp)
            .name,
        'Eb major',
      );
      expect(
        vocabulary
            .keyFor(8, Mode.major, preference: SpellingPreference.sharp)
            .name,
        'Ab major',
      );
    });
  });

  group('the names that were wrong are now unreachable', () {
    test(
      'the chromatic rule still answers Gb, and the key vocabulary refuses it',
      () {
        // THE OLD RULE, quoted in the form it still has: asked how the pitch class of Gb is WRITTEN in
        // a flat key, the spelling table answers Gb — and it is right, because that is how the note is
        // written. The transposer then used that answer as a KEY NAME, which is the defect: Gb minor's
        // relative major would be Bbb major, a signature no musician writes.
        final WrittenNote written = table.spellChromatic(
          6,
          flatMinor,
          SpellingPreference.flat,
        );
        expect(written.toString(), 'Gb');
        expect(
          const Key(
            tonic: WrittenNote(NoteLetter.g, -1),
            mode: Mode.minor,
          ).isPracticallySpelled,
          isFalse,
          reason:
              'Gb minor is not a key, which is what the old code printed it as',
        );
        // The name this project produces for that pitch class in minor is F# minor, from either side
        // of the circle, because F# minor is the only spelling of it with a relative major at all.
        expect(vocabulary.keyFor(6, Mode.minor).name, 'F# minor');
        expect(
          transposer.transposeKey(flatMinor, 8).name,
          'F# minor',
          reason: 'Bb minor up eight semitones is the pitch class of Gb/F#',
        );
      },
    );

    test(
      'no combination of source key and interval names an off-circle key',
      () {
        // The property behind the twenty-four rows, over every interval a musician can ask for and all
        // four source keys: a name is only produced when a key signature expresses it. D# major (nine
        // sharps) was reachable from a sharp key before this change; nothing here may produce it.
        int checked = 0;
        for (final Key source in <Key>[
          flatMajor,
          sharpMajor,
          flatMinor,
          sharpMinor,
        ]) {
          for (int semitones = -12; semitones <= 12; semitones++) {
            final Key named = transposer.transposeKey(source, semitones);
            checked++;
            expect(
              named.isPracticallySpelled,
              isTrue,
              reason: '${source.name} by $semitones named ${named.name}',
            );
            expect(named.name, isNot('Gb minor'));
            expect(named.name, isNot('D# major'));
          }
        }
        stdout.writeln('key.sweep sampled=$checked off_circle=0');
      },
    );

    test('every minor name belongs to a signature an actual major key has', () {
      // The musical rule the whole vocabulary rests on, checked as a rule and not as a table: a
      // minor key's name is its relative major's signature. For each name the automatic answer
      // produces, the note a minor third above it must itself be one of the twelve major names.
      //
      // THE AUTOMATIC ANSWER ONLY, and that is the point rather than a convenience: a caller that
      // FORCES the flat side can reach `Ab minor`, whose relative major is `Cb major` — a real
      // seven-flat signature that no chart in this repertoire is written in. That is what an
      // override is for and why nothing in this tree asks for one; the automatic answer is the one
      // that has to stay inside the twelve keys a musician writes.
      for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
        final Key minor = vocabulary.keyFor(pitchClass, Mode.minor);
        final WrittenNote relativeMajor = WrittenNote(
          minor.tonic.letter.step(2),
          shortestAlter(
            normalizePitchClass(minor.tonicPitchClass + 3),
            minor.tonic.letter.step(2),
          ),
        );
        final Key relativeMajorKey = Key(
          tonic: relativeMajor,
          mode: Mode.major,
        );
        stdout.writeln(
          'key.relative_minor ${minor.name} -> ${relativeMajorKey.name} '
          'fifths=${relativeMajorKey.signatureFifths}',
        );
        expect(
          relativeMajorKey.isPracticallySpelled,
          isTrue,
          reason:
              '${minor.name} would have to belong to ${relativeMajorKey.name}',
        );
        expect(
          musicianMajor[relativeMajorKey.tonicPitchClass],
          relativeMajorKey.name,
          reason: 'a minor key cannot belong to a major key nobody writes',
        );
      }
    });
  });

  group('the vocabulary is the one the application calls', () {
    test('the twelve keys a chart can be shown in are all nameable, and minor charts get minor names', () {
      // The key grid and the new-chart dialog both ask for twelve keys from a written key. Before
      // this change a minor chart's grid was built from the MAJOR chromatic spellings and could
      // offer a tonic nobody writes; the vocabulary is asked in the written key's MODE.
      final List<TranspositionTarget> minorTargets = const TranspositionGrid()
          .targets(Key.aMinor);
      expect(minorTargets, hasLength(12));
      final List<String> names = <String>[
        for (final TranspositionTarget target in minorTargets) target.key.name,
      ];
      stdout.writeln('key.grid a_minor=${names.join(' ')}');
      expect(names, musicianMinor);
      for (final TranspositionTarget target in minorTargets) {
        expect(target.key.mode, Mode.minor);
        expect(target.available, isTrue);
      }
      final List<String> majorNames = <String>[
        for (final TranspositionTarget target
            in const TranspositionGrid().targets(Key.cMajor))
          target.key.name,
      ];
      stdout.writeln('key.grid c_major=${majorNames.join(' ')}');
      expect(majorNames, musicianMajor);
      // The grid offers the SAME twelve names whatever key the chart is written in, which is what
      // makes them names of the notation rather than of the chart — with ONE cell excepted, and the
      // exception is the written key itself. See the identity case below.
      const Key gSharpMinor = Key(
        tonic: WrittenNote(NoteLetter.g, 1),
        mode: Mode.minor,
      );
      final List<String> fromSharp = <String>[
        for (final TranspositionTarget target
            in const TranspositionGrid().targets(gSharpMinor))
          target.key.name,
      ];
      stdout.writeln('key.grid g_sharp_minor=${fromSharp.join(' ')}');
      expect(fromSharp, musicianMinor);
    });

    test('a transposition of nothing does not rename the chart', () {
      // THE COST OF THE TWELVE-NAME RULE, PUT RIGHT WHERE IT WOULD BE VISIBLE TO A MUSICIAN. The
      // vocabulary prefers Gb major and Db major to their sharp twins, so a chart WRITTEN in F# major
      // or C# major would be relabelled the moment anything asked for "the key, please" — including
      // the key grid's own cell for the written key. A transposition of zero semitones is not a
      // transposition, so `transposeKey` returns its argument and the grid's written cell is the
      // written key.
      const Key fSharpMajor = Key(
        tonic: WrittenNote(NoteLetter.f, 1),
        mode: Mode.major,
      );
      const Key cSharpMajor = Key(
        tonic: WrittenNote(NoteLetter.d, 1),
        mode: Mode.major,
      );
      const Key aSharpMinor = Key(
        tonic: WrittenNote(NoteLetter.a, 1),
        mode: Mode.minor,
      );
      for (final Key written in <Key>[fSharpMajor, cSharpMajor, aSharpMinor]) {
        final Key unmoved = transposer.transposeKey(written, 0);
        final List<TranspositionTarget> grid = const TranspositionGrid()
            .targets(written);
        final TranspositionTarget own = grid.firstWhere(
          (TranspositionTarget target) => target.semitones == 0,
        );
        stdout.writeln(
          'key.identity written=${written.name} unmoved=${unmoved.name} '
          'grid_zero=${own.key.name} available=${own.available} '
          'practical=${written.isPracticallySpelled}',
        );
        expect(
          unmoved,
          written,
          reason: 'nothing moved, so nothing is renamed',
        );
        expect(
          own.key,
          written,
          reason: 'the grid offers the chart its own key as "written"',
        );
        expect(
          own.available,
          written.isPracticallySpelled,
          reason: 'a written key beyond the circle is reported, not renamed',
        );
        // Every OTHER cell is still one of the twelve names, so the exception is this one cell.
        for (final TranspositionTarget target in grid) {
          if (target.semitones == 0) {
            continue;
          }
          final List<String> names = target.key.mode == Mode.major
              ? musicianMajor
              : musicianMinor;
          expect(
            target.key.name,
            names[target.key.tonicPitchClass],
            reason: '${written.name} by ${target.semitones}',
          );
        }
      }
      // And the ordinary case is unaffected: a chart written in a key the twelve-name rule WOULD have
      // chosen is not renamed either, because the answer and the identity agree.
      expect(transposer.transposeKey(Key.aMinor, 0), Key.aMinor);
      expect(transposer.transposeKey(Key.cMajor, 0), Key.cMajor);
    });

    test('E minor down a semitone is Eb minor, not D# minor', () {
      // A musician's own move, and the one that shows the cost of getting the tie wrong: E minor has
      // one sharp and is a sharp key by signature, and a direction-first rule would still label the
      // result D# minor — a name nobody writes for the four notes Eb Gb Bb Db.
      const Key eMinor = Key(
        tonic: WrittenNote(NoteLetter.e, 0),
        mode: Mode.minor,
      );
      final Key down = transposer.transposeKey(eMinor, -1);
      stdout.writeln(
        'key.move from=${eMinor.name} by=-1 to=${down.name} '
        'practically=${down.isPracticallySpelled}',
      );
      expect(down.name, 'Eb minor');
    });
  });
}
