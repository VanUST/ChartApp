// PURPOSE: Decide how a sounding pitch is written down in a given key. This is the single place
//          where enharmonic ambiguity is resolved, and it is deliberately a pure function of
//          (pitch class, key, preference): given the same three inputs it always answers the
//          same way. That purity is what makes the twelve-key transposition round-trip hold by
//          construction rather than by luck — after twelve steps the pitch class and the key are
//          both back where they started, so the table returns the spelling it returned before.
// INPUTS: A pitch class in [0, 11] (other integers are reduced), a Key, and an optional
//         SpellingPreference. The table is stateless and const-constructible.
// OUTPUTS: A WrittenNote. Seven of the twelve pitch classes in any key are diatonic and are
//          answered with the key's own scale degree, which is exact and not a preference. The
//          remaining five are answered from a candidate set by the rule documented on
//          [spellChromatic]. Every answer is a single or double accidental; a pitch class that
//          cannot be written on any letter within two accidentals still returns the closest
//          available spelling rather than throwing.
// KEYWORDS: spelling-table, enharmonic, accidental, scale-degree, determinism, music-notation
import 'key.dart';
import 'pitch.dart';

/// Overrides which accidental direction a chord's root is spelled with.
///
/// The default, [automatic], lets the key decide. An explicit value exists because a key's
/// convention cannot be right for every chord: in C major the key's flat preference spells the
/// tritone above the tonic as Gb where a chart would normally write F# (#IV), and a chord is the
/// only place that knows which was meant.
enum SpellingPreference {
  /// Let the key's signature decide the direction.
  automatic,

  /// Spell with sharps regardless of the key.
  sharp,

  /// Spell with flats regardless of the key.
  flat,
}

/// Resolves a pitch class to a written note for a key.
class SpellingTable {
  /// Creates a spelling table. The table holds no state, so one instance serves every key.
  const SpellingTable();

  /// The seven written notes of [key]'s diatonic scale, starting at the tonic.
  ///
  /// Each degree takes the next letter above the tonic and the smallest alteration that reaches
  /// the required sounding pitch, which is how conventional key signatures arise from the
  /// arithmetic rather than from a table that could disagree with it. For C major the result is
  /// C D E F G A B; for E major it is E F# G# A B C# D#; for A minor it is A B C D E F G.
  ///
  /// A minor key takes the natural minor pattern rather than the major one. Applying the major
  /// pattern from a minor tonic would return that tonic's PARALLEL major — E F# G# A B C# D# for
  /// E minor instead of E F# G A B C D — and a chord belonging to the key would then be checked
  /// against a scale the key does not contain.
  List<WrittenNote> scaleOf(Key key) {
    const List<int> majorIntervals = <int>[0, 2, 4, 5, 7, 9, 11];
    const List<int> naturalMinorIntervals = <int>[0, 2, 3, 5, 7, 8, 10];
    final List<int> degreeIntervals = key.mode == Mode.major
        ? majorIntervals
        : naturalMinorIntervals;
    final List<WrittenNote> degrees = <WrittenNote>[];
    for (int degree = 0; degree < degreeIntervals.length; degree++) {
      final NoteLetter letter = key.tonic.letter.step(degree);
      final int pitchClass = normalizePitchClass(
        key.tonicPitchClass + degreeIntervals[degree],
      );
      degrees.add(WrittenNote(letter, shortestAlter(pitchClass, letter)));
    }
    return degrees;
  }

  // PURPOSE: Answer how [pitchClass] is written in [key], preferring the key's own scale degree
  //          when the pitch belongs to it.
  // INPUTS: pitchClass — the sounding pitch. key — the key the chart is written in. preference —
  //         an override of the key's accidental direction; [SpellingPreference.automatic] lets
  //         the key decide.
  // OUTPUTS: A WrittenNote. A diatonic pitch always returns the scale degree, and the preference
  //          is ignored in that case: overriding the spelling of a note the key signature
  //          already determines would produce a chart that contradicts its own key. A chromatic
  //          pitch returns the result of [spellChromatic].
  // KEYWORDS: spelling, diatonic, chromatic, key-signature, override-scope
  /// Returns how [pitchClass] is written in [key].
  WrittenNote spell(
    int pitchClass,
    Key key, {
    SpellingPreference preference = SpellingPreference.automatic,
  }) {
    final int normalized = normalizePitchClass(pitchClass);
    for (final WrittenNote degree in scaleOf(key)) {
      if (degree.pitchClass == normalized) {
        return degree;
      }
    }
    return spellChromatic(normalized, key, preference);
  }

  // PURPOSE: Spell a pitch that is not one of the key's seven scale degrees — a borrowed,
  //          secondary-dominant or chromatic root.
  // INPUTS: pitchClass — a value in [0, 11]. key — the key in force. preference — an override of
  //         the key's direction; [SpellingPreference.automatic] uses [Key.prefersSharps].
  // OUTPUTS: A WrittenNote, chosen by this rule, in this order:
  //
  //            1. Fewest accidentals. A natural spelling always beats any altered one, which is
  //               why the lowered seventh in D major is written C and not B#.
  //            2. Then the direction: sharp if the key is a sharp key, flat if it is a flat key
  //               or has no signature. This is what distinguishes Db from C# in C major. See
  //               [Key.prefersSharps] for the documented limitation of that case.
  //            3. Then letter order, so ties resolve the same way on every run.
  //
  //          Only spellings within two accidentals are considered, so a double sharp is possible
  //          but a triple one never is.
  // KEYWORDS: chromatic-spelling, accidental-count, tie-break, determinism
  /// Spells a pitch that is not one of [key]'s seven scale degrees.
  WrittenNote spellChromatic(
    int pitchClass,
    Key key,
    SpellingPreference preference,
  ) {
    final bool wantSharps = switch (preference) {
      SpellingPreference.sharp => true,
      SpellingPreference.flat => false,
      SpellingPreference.automatic => key.prefersSharps,
    };

    final List<WrittenNote> candidates = <WrittenNote>[];
    for (final NoteLetter letter in NoteLetter.values) {
      final int alter = shortestAlter(pitchClass, letter);
      if (alter.abs() <= 2) {
        candidates.add(WrittenNote(letter, alter));
      }
    }
    if (candidates.isEmpty) {
      // Unreachable for the twelve pitch classes: every one is writable on at least one letter
      // within two accidentals. Kept as a total fallback so the function cannot throw inside an
      // import loop, where a thrown error would be far harder to diagnose than an odd spelling.
      final NoteLetter letter = NoteLetter.c;
      return WrittenNote(letter, shortestAlter(pitchClass, letter));
    }

    WrittenNote best = candidates.first;
    for (final WrittenNote candidate in candidates) {
      if (_isBetter(candidate, best, wantSharps)) {
        best = candidate;
      }
    }
    return best;
  }

  // PURPOSE: Order two candidate spellings so the loop above picks the documented one, keeping
  //          the comparison in a named function instead of an inline cascade that is hard to
  //          check.
  // INPUTS: candidate and incumbent — spellings of the same pitch class. wantSharps — the
  //         resolved direction.
  // OUTPUTS: True when [candidate] should replace [incumbent].
  // KEYWORDS: comparison, accidental-count, direction, tie-break
  bool _isBetter(
    WrittenNote candidate,
    WrittenNote incumbent,
    bool wantSharps,
  ) {
    final int candidateAccidentals = candidate.alter.abs();
    final int incumbentAccidentals = incumbent.alter.abs();
    if (candidateAccidentals != incumbentAccidentals) {
      return candidateAccidentals < incumbentAccidentals;
    }
    final int candidateDirection = candidate.alter > 0
        ? 1
        : candidate.alter < 0
        ? -1
        : 0;
    final int incumbentDirection = incumbent.alter > 0
        ? 1
        : incumbent.alter < 0
        ? -1
        : 0;
    final int preferred = wantSharps ? 1 : -1;
    if (candidateDirection != incumbentDirection) {
      return candidateDirection == preferred;
    }
    return candidate.letter.index < incumbent.letter.index;
  }
}
