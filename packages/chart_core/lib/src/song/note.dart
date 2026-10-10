// PURPOSE: Place pitches and drum hits inside a bar. A melody note and a percussion hit share the
//          same addressing as a chord — a cell plus a step within it — so that one anchor scheme
//          covers every object a user can point at, and a bar can hold a chord line, a melody and
//          a drum part without three different coordinate systems.
// INPUTS: A pitched note or an instrument number, a written duration, and a cell and step within
//         the bar.
// OUTPUTS: Immutable values. [melodyFillsBar] answers whether a list of notes exactly fills a
//          bar, using exact rational arithmetic so that a triplet-based fill is not reported as
//          short by a rounding error.
// KEYWORDS: melody, note, percussion, drum-hit, beat-address, anchor, bar-fill
import '../pitch.dart';
import 'note_value.dart';
import 'time_signature.dart';

/// A pitch as written, in a named octave.
class PitchedNote {
  /// Creates a note at [note] in [octave].
  ///
  /// The octave is scientific pitch notation, so middle C is C4 and the octave number changes at
  /// C, not at A. Worth stating because the alternative convention is still in use and the two
  /// disagree about every note from A to B.
  const PitchedNote({required this.note, required this.octave});

  /// The written pitch: a letter and an alteration.
  final WrittenNote note;

  /// The octave, in scientific pitch notation, middle C = C4.
  final int octave;

  /// The MIDI note number, which is what any pitch comparison or transposition range check uses.
  int get midiNumber => 12 * (octave + 1) + note.pitchClass;

  @override
  bool operator ==(Object other) =>
      other is PitchedNote && other.note == note && other.octave == octave;

  @override
  int get hashCode => Object.hash(note, octave);

  @override
  String toString() => '${note.toString()}$octave';
}

/// A pitched note placed on a beat of a bar.
class BeatNote {
  /// Creates a note of [value] at ([beat], [step]).
  const BeatNote({
    required this.pitch,
    required this.value,
    required this.beat,
    this.step = 0,
    this.tiedToNext = false,
  });

  /// The note that sounds.
  final PitchedNote pitch;

  /// How long it is written to last.
  final NoteValue value;

  /// Zero-based cell index inside the bar, the same address a chord uses.
  final int beat;

  /// Order within [beat] when several notes share it.
  final int step;

  /// Whether this note is tied into the next one, which is how a single sound is written across a
  /// barline. Stored on the earlier note rather than as a pair identifier because a tie always
  /// points forward, and a backward pointer would have to be repaired whenever the bar before it
  /// changed.
  final bool tiedToNext;

  @override
  bool operator ==(Object other) =>
      other is BeatNote &&
      other.pitch == pitch &&
      other.value == value &&
      other.beat == beat &&
      other.step == step &&
      other.tiedToNext == tiedToNext;

  @override
  int get hashCode => Object.hash(pitch, value, beat, step, tiedToNext);

  @override
  String toString() =>
      'beat $beat.$step: $pitch ${value.toString()}${tiedToNext ? '~' : ''}';
}

/// A percussion hit placed on a beat of a bar.
class PercussionHit {
  /// Creates a hit on [instrument] of [value] at ([beat], [step]).
  const PercussionHit({
    required this.instrument,
    required this.value,
    required this.beat,
    this.step = 0,
  });

  /// The struck instrument, as a MIDI percussion note number.
  ///
  /// This is a key into the staff's drum map, not a pitch: it is never transposed and it is never
  /// compared musically. Keeping it an integer rather than a name is what lets a chart carry a kit
  /// this model has never heard of.
  final int instrument;

  /// How long the hit is written to last. For most percussion this is a notational fact about how
  /// the note is drawn rather than one about how long it rings.
  final NoteValue value;

  /// Zero-based cell index inside the bar.
  final int beat;

  /// Order within [beat] when several hits share it.
  final int step;

  @override
  bool operator ==(Object other) =>
      other is PercussionHit &&
      other.instrument == instrument &&
      other.value == value &&
      other.beat == beat &&
      other.step == step;

  @override
  int get hashCode => Object.hash(instrument, value, beat, step);

  @override
  String toString() => 'beat $beat.$step: drum $instrument ${value.toString()}';
}

// PURPOSE: Answer whether a run of notes exactly fills one bar of a meter, using the exact written
//          durations rather than a tick conversion.
// INPUTS: timeSignature — the meter in force for the bar. notes — the notes as written.
// OUTPUTS: True when the durations sum to the bar's length exactly.
//
//          False for an empty list, because an empty bar is not a full one; the caller that wants
//          to allow it should check for emptiness itself rather than have this answer mean two
//          things. Durations are summed as an exact fraction, so a fill built from triplets is
//          judged correctly rather than being reported short by rounding — which is exactly the
//          case a tick grid chosen for binary values gets wrong.
// KEYWORDS: bar-fill, validation, exact-arithmetic, triplets, completeness
/// Returns whether [notes] fill exactly one bar of [timeSignature].
bool melodyFillsBar(TimeSignature timeSignature, List<BeatNote> notes) {
  if (notes.isEmpty) {
    return false;
  }
  // The running sum is kept as a fraction; the common denominator is found by cross-multiplication
  // rather than by computing a least common multiple, which would need a factorisation this small
  // calculation does not justify.
  int sumNumerator = 0;
  int sumDenominator = 1;
  for (final BeatNote note in notes) {
    sumNumerator =
        sumNumerator * note.value.wholeDenominator +
        note.value.wholeNumerator * sumDenominator;
    sumDenominator = sumDenominator * note.value.wholeDenominator;
  }
  // Compare sum (sumNumerator / sumDenominator) with the bar length (numerator / denominator).
  return sumNumerator * timeSignature.denominator ==
      timeSignature.numerator * sumDenominator;
}
