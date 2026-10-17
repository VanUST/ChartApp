// PURPOSE: Print the name this project gives every one of the twenty-four keys, with the candidates
//          it chose between, so "the keys display correctly" is a table a reader can check against a
//          theory book rather than a claim. It exists because the owner asked for his keys to be
//          verified and the answer turned out to be "major yes, minor no": `transposeKey` could
//          reach `Gb minor` and `D# major`, names no key signature expresses.
// INPUTS: None. The twelve pitch classes and the two modes are the whole input, and both accidental
//         directions are printed for each so the one case the direction decides is visible.
// OUTPUTS: One `probe.key` line per pitch class and mode — the chosen name in each direction, the
//          candidates with their key signature and whether they sit on the circle of fifths, and the
//          transposition that produces the name from a named source key. Also one `probe.check` line
//          per invariant, so a reader sees what was measured instead of only what was printed.
// KEYWORDS: probe, key-name, vocabulary, circle-of-fifths, relative-major, minor-key, evidence,
//           d27
//
// It is an INSTRUMENT, not a test: it asserts nothing and lives in `tool/`, so neither `dart test`
// nor the gate pays for it. Run it from `packages/chart_core` with:
//
//     dart run tool/probe_key_names.dart
//
// The hand-checked expectations live in `test/key_vocabulary_test.dart`, which is where a wrong
// answer fails the gate; this file is where a reader finds out WHY each answer is what it is.
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// The name a musician writes for each major tonic, by pitch class from C.
///
/// Written here so that the probe compares the code with a musical fact instead of with itself. The
/// unreadable twin of each is in [sharpMajor] / [flatMajor] below.
const List<String> expectedMajor = <String>[
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

/// The name a musician writes for each minor tonic, by pitch class from C.
const List<String> expectedMinor = <String>[
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

/// The four source keys the names are produced FROM, one per mode and accidental side, so that a
/// name is asked for the way a chart asks for it — by transposing a real key — and not with a flag.
///
/// THE TWO SHARP SOURCES ARE KEYS THE TWELVE-NAME TABLE ITSELF WRITES, and that is deliberate. A
/// source such as A# minor is practical but is not one of the twelve names, so asking it for its OWN
/// pitch class is a move of zero semitones, which returns the key unchanged (the identity rule) and
/// would be reported here as a mismatch against the table. The identity rule has its own lines at the
/// end of this probe; these sources are for the table.
const Key flatMajor = Key(
  tonic: WrittenNote(NoteLetter.d, -1),
  mode: Mode.major,
);
const Key sharpMajor = Key(
  tonic: WrittenNote(NoteLetter.b, 0),
  mode: Mode.major,
);
const Key flatMinor = Key(
  tonic: WrittenNote(NoteLetter.b, -1),
  mode: Mode.minor,
);
const Key sharpMinor = Key(
  tonic: WrittenNote(NoteLetter.g, 1),
  mode: Mode.minor,
);

/// The signed distance from [from] to [to] in semitones, which is the interval a chart is
/// transposed by to reach the target key.
int stepsBetween(int from, int to) => normalizePitchClass(to - from) > 6
    ? normalizePitchClass(to - from) - 12
    : normalizePitchClass(to - from);

/// One candidate as a single token: its name, its key signature, and whether it is one a chart can
/// be written in. A separate function because the line is too long for a list literal and because
/// the four facts belong together when a reader compares two candidates.
String _candidateText(KeyNameCandidate candidate) {
  final int fifths = candidate.key.signatureFifths;
  final String practical = candidate.isPractical ? 'practical' : 'off_circle';
  return '${candidate.key.name}'
      '(fifths=$fifths,acc=${fifths.abs()},'
      '$practical,dir=${candidate.direction.name})';
}

void main() {
  const Transposer transposer = Transposer();
  const KeyVocabulary vocabulary = KeyVocabulary();
  int failures = 0;

  for (final Mode mode in <Mode>[Mode.major, Mode.minor]) {
    final Key flat = mode == Mode.major ? flatMajor : flatMinor;
    final Key sharp = mode == Mode.major ? sharpMajor : sharpMinor;
    final List<String> expected = mode == Mode.major
        ? expectedMajor
        : expectedMinor;
    for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
      final List<String> candidates = <String>[
        for (final KeyNameCandidate candidate in vocabulary.candidatesFor(
          pitchClass,
          mode,
        ))
          _candidateText(candidate),
      ];
      final String fromFlat = transposer
          .transposeKey(flat, stepsBetween(flat.tonicPitchClass, pitchClass))
          .name;
      final String fromSharp = transposer
          .transposeKey(sharp, stepsBetween(sharp.tonicPitchClass, pitchClass))
          .name;
      final String want = expected[pitchClass];
      final bool ok = fromFlat == want && fromSharp == want;
      if (!ok) {
        failures++;
      }
      stdout.writeln(
        'probe.key pc=$pitchClass mode=${mode.name} want="$want" '
        'from_flat="$fromFlat" from_sharp="$fromSharp" '
        '${ok ? 'ok' : 'MISMATCH'} candidates=${candidates.join(' ')}',
      );
    }
  }

  // INVARIANT 1: no name this vocabulary produces is off the practical circle.
  int offCircle = 0;
  for (final Mode mode in <Mode>[Mode.major, Mode.minor]) {
    for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
      for (final SpellingPreference direction in <SpellingPreference>[
        SpellingPreference.sharp,
        SpellingPreference.flat,
      ]) {
        final Key named = vocabulary.keyFor(
          pitchClass,
          mode,
          preference: direction,
        );
        if (!named.isPracticallySpelled) {
          offCircle++;
          stdout.writeln(
            'probe.check off_circle pc=$pitchClass mode=${mode.name} '
            'dir=${direction.name} name=${named.name}',
          );
        }
      }
    }
  }
  stdout.writeln('probe.check nameable_off_circle=$offCircle of 48');

  // INVARIANT 2: a minor key's name is its relative major's signature, which is the musical rule
  // the whole vocabulary rests on. Printed as the relative major each chosen minor belongs to — for
  // the AUTOMATIC answer, which is the one the transposer, the key grid and the dialog all take.
  final List<String> relatives = <String>[];
  for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
    final Key minor = vocabulary.keyFor(pitchClass, Mode.minor);
    final Key relativeMajor = Key(
      tonic: WrittenNote(
        minor.tonic.letter.step(2),
        shortestAlter(
          normalizePitchClass(minor.tonicPitchClass + 3),
          minor.tonic.letter.step(2),
        ),
      ),
      mode: Mode.major,
    );
    relatives.add('${minor.name}->${relativeMajor.name}');
  }
  stdout.writeln('probe.check relative_majors ${relatives.join(' ')}');

  // INVARIANT 2b: the ONE signature the circle offers from either end, so the choice is visible
  // rather than implied. Everything else is forced; these two rows are the whole of the decision.
  for (final int pitchClass in <int>[6, 3]) {
    final Mode mode = pitchClass == 6 ? Mode.major : Mode.minor;
    stdout.writeln(
      'probe.check tie pc=$pitchClass mode=${mode.name} '
      'automatic=${vocabulary.keyFor(pitchClass, mode).name} '
      'forced_sharp='
      '${vocabulary.keyFor(pitchClass, mode, preference: SpellingPreference.sharp).name} '
      'forced_flat='
      '${vocabulary.keyFor(pitchClass, mode, preference: SpellingPreference.flat).name}',
    );
  }

  // INVARIANT 3: a move of zero semitones renames nothing, which is the rule that keeps a chart
  // WRITTEN in F# major or C# major from being relabelled Gb/Db the first time the key is asked for.
  // Printed for keys the twelve-name table would NOT choose, because that is where the two questions
  // — "what is written" and "what would we call this pitch" — have different answers.
  for (final Key written in <Key>[
    const Key(tonic: WrittenNote(NoteLetter.f, 1), mode: Mode.major),
    const Key(tonic: WrittenNote(NoteLetter.d, 1), mode: Mode.major),
    const Key(tonic: WrittenNote(NoteLetter.a, 1), mode: Mode.minor),
  ]) {
    final Key unmoved = transposer.transposeKey(written, 0);
    final Key zeroCell = const TranspositionGrid()
        .targets(written)
        .firstWhere((TranspositionTarget target) => target.semitones == 0)
        .key;
    final bool ok = unmoved == written && zeroCell == written;
    if (!ok) {
      failures++;
    }
    stdout.writeln(
      'probe.check identity written=${written.name} unmoved=${unmoved.name} '
      'grid_zero=${zeroCell.name} ${ok ? 'ok' : 'RENAMED'}',
    );
  }

  // INVARIANT 4: the two defect names are unreachable, which is the whole point of the work.
  for (final int semitones in <int>[-12, -11, -6, -1, 1, 6, 11, 12]) {
    for (final Key source in <Key>[
      flatMajor,
      sharpMajor,
      flatMinor,
      sharpMinor,
    ]) {
      final String named = transposer.transposeKey(source, semitones).name;
      final bool bad = named == 'Gb minor' || named == 'D# major';
      if (bad) {
        failures++;
      }
      stdout.writeln(
        'probe.check reachable from=${source.name} by=$semitones named="$named" '
        '${bad ? 'DEFECT' : 'ok'}',
      );
    }
  }
  stdout.writeln(
    'probe.check verdict=${failures == 0 ? 'all names as written' : '$failures problem(s)'}',
  );
  // A non-zero exit when the verdict is not clean, so this instrument can be used as a check and not
  // only as a report: a probe that prints a problem and exits 0 is a claim nobody acts on.
  if (failures != 0) {
    exitCode = 1;
  }
}
