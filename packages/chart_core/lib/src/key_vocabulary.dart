// PURPOSE: Name a key the way a musician writes it. This is a DIFFERENT QUESTION from how a
//          sounding pitch is written — the one [SpellingTable] answers — and the difference is the
//          whole reason this file exists. A pitch class has two enharmonic spellings and both sound
//          the same; only one of them can be a KEY NAME, because a key name is a position on the
//          circle of fifths and a spelling off that circle names a key signature nobody writes:
//          "D# major" is nine sharps, and "Gb minor" is a key whose relative major would be Bbb
//          major, which does not exist.
// INPUTS: A tonic pitch class in [0, 11], a [Mode], and — only when a caller insists — which side of
//         the circle to spell on.
// OUTPUTS: A [Key] whose tonic is a spelling a key signature expresses, and which is the spelling a
//          musician writes wherever the notation offers a choice. Every one of the twelve pitch
//          classes is nameable in both modes, so the function is total.
// KEYWORDS: key-name, vocabulary, enharmonic-choice, circle-of-fifths, relative-major, minor-key,
//           key-signature, practical-spelling, transposition
//
// WHY A MINOR KEY IS NAMED BY ITS RELATIVE MAJOR, WHICH IS THE MUSICAL ANSWER AND NOT A SPECIAL
// CASE. A minor key's key signature is its relative major's — F# minor and A major are three
// sharps, Eb minor and Gb major are six flats — so the question "which of Gb and F# is this minor
// tonic called" is the question "which major signature does it belong to". That relationship is
// already written down ONCE in this domain, in `Key._circleReference`, which derives a minor key's
// circle position from its relative major; `Key.isPracticallySpelled` and `Key.signatureFifths`
// are both stated in terms of it. So this file carries NO minor-key arithmetic of its own: it asks
// each candidate spelling whether its key — minor included — sits on the practical circle, and the
// relative-major rule answers. Gb minor is impossible here for exactly that reason: the model
// already knows its relative major would be Bbb major, and the name never survives.
//
// WHY "FEWEST ACCIDENTALS" RATHER THAN "KEEP THE CHART'S DIRECTION". The direction is the right
// rule for a CHORD: a flat chart that transposes a semitone should not start writing sharps, and
// there are five chromatic notes where the choice is free. It is the wrong rule for a KEY NAME,
// because the two spellings of one pitch class are not equally usable: Db major has five flats and
// C# major has seven, Eb major three and D# major nine. A musician writes the one with the fewer
// accidentals, which is why the twelve majors in every theory book are
// C Db D Eb E F F#/Gb G Ab A Bb B.
//
// WHY THE ONE TIE GOES TO THE FLAT SIDE, WHICH IS AN ASYMMETRY IN MUSIC RATHER THAN A PREFERENCE.
// Six accidentals is the only signature readable from both ends of the circle: F# major (six sharps)
// and Gb major (six flats) are the same signature, and their relative minors are D# minor and Eb
// minor. Both majors are written in real charts, so the tie costs nothing there. Both MINORS are
// not: Eb minor is a key musicians play in, and the same four notes are written Eb-Gb-Bb-Db by
// everyone who plays them, while D# minor is a name that appears essentially never. And a minor
// key's name is fixed by its relative major's, so naming the minor well forces Gb major. One
// decision at the signature, both modes inherit it, and each of the two names produced is one a
// musician would write.
//
// AND THE SHARP SIDE IS STILL REACHABLE, DELIBERATELY. A caller that asks for it gets F# major and
// D# minor — both real key signatures, neither of them what this rule produces on its own. That is
// what an explicit [SpellingPreference] is for, exactly as it is for a chord whose root the key's
// own direction would misspell: the automatic answer is the one that is right for the repertoire,
// and the override exists for the case the model cannot know.
import 'key.dart';
import 'pitch.dart';
import 'spelling_table.dart';

/// One spelling proposed for a key, with the two facts that decide whether it is the name a
/// musician writes.
///
/// A candidate is the answer to "could the key be called this", and both facts are read from the
/// [Key] rather than stored beside it: [isPractical] is the model's own circle-of-fifths test, and
/// [signatureAccidentals] is the model's own signature position. A candidate that carried its own
/// copy of either could disagree with the key it describes.
class KeyNameCandidate {
  /// Creates a candidate naming [key], produced by the [direction] that asked for it.
  const KeyNameCandidate({required this.key, required this.direction});

  /// The key this candidate would name.
  final Key key;

  /// The accidental direction whose spelling produced this candidate.
  ///
  /// It is how the candidate was PRODUCED, not a description of the note: the sharp direction
  /// answers C for the pitch class of C, because no sharp spelling of it is shorter. When both
  /// directions produce the same note the candidate is listed once and reports
  /// [SpellingPreference.sharp], since anything else would invent a distinction the notation does
  /// not have.
  final SpellingPreference direction;

  /// Whether this key sits on the practical circle of fifths, so that a key signature expresses it.
  ///
  /// For a minor key this is its RELATIVE MAJOR's position — see the file header — which is what
  /// makes "Gb minor" false and "F# minor" true.
  bool get isPractical => key.isPracticallySpelled;

  /// How many accidentals the key signature carries, which is how a musician chooses between two
  /// spellings that are both usable.
  ///
  /// Read from [Key.signatureFifths], whose value is 0 both for C major and for a key it cannot
  /// place. A caller comparing two PRACTICAL candidates never meets the second case, and a caller
  /// that compares an impractical one against a practical one has already broken the rule above.
  int get signatureAccidentals => key.signatureFifths.abs();

  @override
  bool operator ==(Object other) =>
      other is KeyNameCandidate &&
      other.key == key &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(key, direction);

  @override
  String toString() =>
      'KeyNameCandidate(${key.name}${isPractical ? '' : ', off the circle'}'
      ', $signatureAccidentals accidental(s), ${direction.name} direction)';
}

/// The rule that turns a sounding pitch class and a mode into the key name a musician writes.
///
/// Stateless and const-constructible, like the [SpellingTable] it reads, so one instance may serve
/// every caller and two callers cannot hold different vocabularies.
class KeyVocabulary {
  /// Creates a vocabulary that spells its candidates with [spellingTable].
  const KeyVocabulary({this.spellingTable = const SpellingTable()});

  /// The rule the two candidate spellings of a pitch class are produced by.
  ///
  /// It is the same table the chords are spelled with, deliberately: a key name and the chord roots
  /// printed inside that key are read together, and two spelling rules in one chart would let the
  /// label and the music disagree about which of two twins a pitch is.
  final SpellingTable spellingTable;

  // PURPOSE: List the spellings a pitch class could be named with, before deciding which one a
  //          musician writes, so the decision is a visible comparison of facts rather than a
  //          branch inside a constructor.
  // INPUTS: pitchClass — any integer; values outside [0, 11] are reduced, as everywhere in this
  //         package. mode — major or minor, which changes what a spelling has to be on the circle
  //         FOR (a minor key's signature is its relative major's).
  // OUTPUTS: One or two candidates. Two when the sharp and flat directions produce different
  //          spellings of the pitch class, which is the ordinary case; ONE when both directions
  //          agree, which is any pitch class whose shortest spelling is a natural note. Both
  //          candidates may be off the practical circle; that is a fact about the pitch class and
  //          the mode, and [keyFor] is what refuses them.
  // KEYWORDS: candidate-list, enharmonic-pair, spelling-table, mode, total-function
  /// Returns the spellings [pitchClass] could be named with in [mode].
  List<KeyNameCandidate> candidatesFor(int pitchClass, Mode mode) {
    final int normalized = normalizePitchClass(pitchClass);
    final List<KeyNameCandidate> candidates = <KeyNameCandidate>[];
    for (final SpellingPreference direction in <SpellingPreference>[
      SpellingPreference.sharp,
      SpellingPreference.flat,
    ]) {
      final Key key = Key(
        tonic: spellingTable.spellChromatic(normalized, Key.cMajor, direction),
        mode: mode,
      );
      // A direction that produces a spelling already listed says nothing new, and listing it twice
      // would let one spelling be compared against itself.
      if (candidates.any((KeyNameCandidate listed) => listed.key == key)) {
        continue;
      }
      candidates.add(KeyNameCandidate(key: key, direction: direction));
    }
    return candidates;
  }

  // PURPOSE: Answer the question every caller actually asks — what is this key called — so that
  //          the transposer, the key grid and the new-chart dialog cannot name the same key three
  //          different ways.
  // INPUTS: pitchClass — the tonic's sounding pitch, any integer, reduced into [0, 11]. mode —
  //         major or minor. preference — [SpellingPreference.automatic] asks for the name a
  //         musician writes, which is the answer every caller in this tree wants;
  //         [SpellingPreference.sharp] or [.flat] insists on one side of the circle and is an
  //         override, not a refinement — see [the tie] below.
  // OUTPUTS: A [Key] whose tonic is A SPELLING A KEY SIGNATURE EXPRESSES, chosen by this rule, in
  //          order:
  //
  //            1. A candidate off the practical circle is never returned while one on it exists. That
  //               single clause is what makes `Gb minor` and `D# major` unreachable, because the
  //               model's own relative-major test knows both are impossible: their relative major
  //               would be Bbb major and their own signature is nine sharps.
  //            2. Among the candidates that ARE usable, the one with fewer accidentals in its key
  //               signature wins — Db major over C# major, Eb major over D# major, G# minor over
  //               Ab minor. This is the rule that produces the twelve keys of a theory book.
  //            3. When the two are equally usable — the six-accidental signature, F#/Gb major and
  //               its relative D#/Eb minor — the FLAT side wins, and the file header states why:
  //               because a minor key's name is its relative major's, and Eb minor is a name
  //               musicians write while D# minor is not.
  //            4. An explicit [SpellingPreference.sharp] or [.flat] replaces rules 2 and 3 with the
  //               side it names, still filtered by rule 1: asking for the sharp side gives F# major
  //               and never G# major, because the second one does not exist.
  //            5. A pitch class with no practical candidate at all returns the spelling asked for
  //               rather than throwing, so a drawing path cannot die on a name. This is
  //               UNREACHABLE for the twelve pitch classes in either mode — every one has a practical
  //               spelling — and it is kept so the function is total, exactly as
  //               `SpellingTable.spellChromatic` keeps its own fallback for the same reason.
  // KEYWORDS: key-naming, practical-circle, fewest-accidentals, tie-break, override, total-function
  /// Returns the key a musician writes for [pitchClass] in [mode].
  Key keyFor(
    int pitchClass,
    Mode mode, {
    SpellingPreference preference = SpellingPreference.automatic,
  }) {
    final int normalized = normalizePitchClass(pitchClass);
    final List<KeyNameCandidate> candidates = candidatesFor(normalized, mode);
    final List<KeyNameCandidate> practical = <KeyNameCandidate>[
      for (final KeyNameCandidate candidate in candidates)
        if (candidate.isPractical) candidate,
    ];
    if (practical.isEmpty) {
      // Rule 5. Reachable only for a spelling test the model cannot place, which the twelve pitch
      // classes never produce; the fallback keeps the function total for a caller that builds a
      // pitch class some other way.
      return candidates
          .firstWhere(
            (KeyNameCandidate candidate) =>
                candidate.direction ==
                (preference == SpellingPreference.sharp
                    ? SpellingPreference.sharp
                    : SpellingPreference.flat),
            orElse: () => candidates.first,
          )
          .key;
    }
    if (preference != SpellingPreference.automatic) {
      // Rule 4: an explicit side, still filtered by rule 1 above. A side that is not among the
      // practical candidates cannot be honoured, so the musical rule answers instead.
      for (final KeyNameCandidate candidate in practical) {
        if (candidate.direction == preference) {
          return candidate.key;
        }
      }
    }
    practical.sort((KeyNameCandidate a, KeyNameCandidate b) {
      final int byAccidentals = a.signatureAccidentals.compareTo(
        b.signatureAccidentals,
      );
      if (byAccidentals != 0) {
        return byAccidentals;
      }
      // Rule 3: equal signatures. The flat side is the one whose relative minor is a name musicians
      // write, and `KeyNameCandidate.direction` already records which side produced each spelling,
      // so the comparison needs no second copy of that fact.
      final bool aFlat = a.direction == SpellingPreference.flat;
      final bool bFlat = b.direction == SpellingPreference.flat;
      if (aFlat == bFlat) {
        return 0;
      }
      return aFlat ? -1 : 1;
    });
    return practical.first.key;
  }
}
