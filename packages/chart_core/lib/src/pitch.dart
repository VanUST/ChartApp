// PURPOSE: Represent written pitch — a letter with an alteration — separately from sounding
//          pitch, because a chart is notated, not sounded: Ab and G# are the same key on a
//          piano and different instructions to a musician. Keeping the two apart is what allows
//          a transposed chart to preserve the composer's spelling intent instead of flattening
//          every note to a canonical pitch class.
// INPUTS: None at declaration. WrittenNote takes a letter and an alteration in semitones;
//         normalizePitchClass takes any integer.
// OUTPUTS: WrittenNote instances whose pitchClass is always in [0, 11], whatever alteration was
//          supplied — including alterations beyond a double sharp or double flat, which are
//          representable but are never produced by the spelling table. String rendering writes
//          the letter followed by one character per alteration, so a double flat is "Abb".
// KEYWORDS: pitch, pitch-class, spelling, accidental, enharmonic, notation, music-theory
//
// The distinction this file exists to preserve:
//
//   WrittenNote(NoteLetter.a, -1).pitchClass == WrittenNote(NoteLetter.g, 1).pitchClass == 8
//
// Both sound the same. In the key of C major a musician writes the first (bVI, a flattened
// sixth); in A major they write the second (the leading tone, diatonic). A model that stored
// only the pitch class could not express either, and a transposition would have to guess.

/// The seven letter names of Western staff notation, ordered from C upward.
///
/// The order is the order of the letters on the staff, not their order by sounding pitch from
/// A; [step] walks this order, which is what makes a letter distance computable.
enum NoteLetter {
  /// The letter C.
  c(0, 'C'),

  /// The letter D.
  d(2, 'D'),

  /// The letter E.
  e(4, 'E'),

  /// The letter F.
  f(5, 'F'),

  /// The letter G.
  g(7, 'G'),

  /// The letter A.
  a(9, 'A'),

  /// The letter B.
  b(11, 'B');

  const NoteLetter(this.naturalPitchClass, this.symbol);

  /// The pitch class of this letter's natural form, with C as 0.
  final int naturalPitchClass;

  /// The letter as it is written in a chart.
  final String symbol;

  // PURPOSE: Walk [steps] letters along the letter sequence, wrapping within the seven letters.
  // INPUTS: steps — any integer; negative walks downward, values beyond 7 wrap.
  // OUTPUTS: The letter that many positions away. A multiple of 7 returns this letter, so the
  //          operation is total and never throws.
  // KEYWORDS: letter-distance, modulo, diatonic-step
  /// Returns the letter [steps] positions above this one.
  NoteLetter step(int steps) {
    final int wrapped = ((index + steps) % 7 + 7) % 7;
    return NoteLetter.values[wrapped];
  }
}

// PURPOSE: Bring any semitone value into the range [0, 11], so every caller of the pitch layer
//          can rely on a canonical pitch class without repeating a modulo and getting the
//          negative-operand case wrong.
// INPUTS: semitone — any integer, including negative values from downward transposition.
// OUTPUTS: A value in [0, 11]. Dart's remainder operator already returns a non-negative result
//          for a positive divisor, so the second modulo is redundant; it is kept because the
//          rule is load-bearing and cheap to state explicitly.
// KEYWORDS: pitch-class, normalization, modulo, octave
/// Reduces [semitone] to a pitch class in the range `[0, 11]`.
int normalizePitchClass(int semitone) => ((semitone % 12) + 12) % 12;

// PURPOSE: Choose the smallest alteration that writes [pitchClass] on [letter], so that a scale
//          degree can be spelled from its sounding pitch without the caller deciding between a
//          double sharp and a flat.
// INPUTS: pitchClass — a value in [0, 11] (other values are reduced). letter — the letter the
//         note must be written on.
// OUTPUTS: An alteration in `[-6, 6]`. The result is the representative closest to zero, so the
//          seven diatonic degrees of any key produce alterations in `[-2, 2]` and never a
//          triple accidental; an enharmonic pitch that cannot be written on the given letter
//          without at least six accidentals still returns a usable value rather than throwing.
// KEYWORDS: accidental, alteration, enharmonic-spelling, scale-degree
/// Returns the alteration in `[-6, 6]` that writes [pitchClass] on [letter].
int shortestAlter(int pitchClass, NoteLetter letter) {
  int alter = normalizePitchClass(pitchClass) - letter.naturalPitchClass;
  while (alter > 6) {
    alter -= 12;
  }
  while (alter < -6) {
    alter += 12;
  }
  return alter;
}

/// A note as a musician writes it: a letter plus an alteration in semitones.
class WrittenNote {
  /// Creates the written note [letter] with [alter] semitones of alteration, where -1 is a
  /// flat and 1 is a sharp.
  const WrittenNote(this.letter, this.alter);

  /// This note's letter.
  final NoteLetter letter;

  /// Semitones of alteration: negative for flats, positive for sharps, zero for natural.
  final int alter;

  /// This note's sounding pitch class, always in `[0, 11]`.
  int get pitchClass => normalizePitchClass(letter.naturalPitchClass + alter);

  // PURPOSE: Compare two written notes by letter AND alteration, so that Ab and G# are not equal
  //          even though they sound alike. This is the comparison the transposition round-trip
  //          property is stated in: preserving the spelling means preserving this equality.
  // INPUTS: other — any object.
  // OUTPUTS: True only for a WrittenNote with the same letter and the same alteration. A pitch
  //          class or a string never compares equal.
  // KEYWORDS: equality, enharmonic, spelling-preservation
  @override
  bool operator ==(Object other) =>
      other is WrittenNote && other.letter == letter && other.alter == alter;

  @override
  int get hashCode => Object.hash(letter, alter);

  // PURPOSE: Render the note the way it appears on a chart, so a failure message in a test or a
  //          spike log names the actual spelling rather than an object identity.
  // INPUTS: None.
  // OUTPUTS: The letter followed by one '#' per sharp or one 'b' per flat; a natural note is
  //          just the letter. A double flat renders as "Abb".
  // KEYWORDS: rendering, formatting, accidental, diagnostics
  @override
  String toString() {
    if (alter == 0) {
      return letter.symbol;
    }
    final String accidental = alter > 0 ? '#' * alter : 'b' * (-alter);
    return '${letter.symbol}$accidental';
  }
}
