// PURPOSE: Place pitches and drum hits inside a bar. A melody note and a percussion hit are
//          located the way a chord now is — a coordinate in the bar, not an index in a grid — so
//          that one place scheme covers every object a user can point at, and a bar can hold a
//          chord line, a melody and a drum part without three different coordinate systems.
// INPUTS: A pitched note or an instrument number, a written duration, and an [AnchoredPlace].
// OUTPUTS: Immutable values. [melodyFillsBar] answers whether a list of notes adds up to the length
//          a meter states, using exact rational arithmetic so that a triplet-based fill is not
//          reported short by a rounding error; it is a question about the written page and it
//          places nothing, so the meter remains a label.
// KEYWORDS: melody, note, percussion, drum-hit, anchored-place, coordinate, no-grid, bar-fill
import '../anchored_place.dart';
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

/// A pitch written at a place in a bar, with the duration it is written to last.
///
/// ITS HORIZONTAL OFFSET IS ITS TIME. There is no beat, no cell and no step: the musician writes a
/// notehead where he wants it to sound, and the engraver draws it at that x. The vertical offset of
/// the place is always zero, because a note's height IS its pitch — the melody staff derives the y
/// from [pitch], and storing a second y here would allow a note whose glyph and whose sound
/// disagreed.
class NoteMark {
  /// Creates a note of [value] at [place].
  const NoteMark({
    required this.place,
    required this.pitch,
    required this.value,
    this.tiedToNext = false,
  });

  /// Where the note is written: its bar, and its distance along that bar.
  final AnchoredPlace place;

  /// The note that sounds.
  final PitchedNote pitch;

  /// How long it is written to last.
  final NoteValue value;

  /// Whether this note is tied into the next one, which is how a single sound is written across a
  /// barline. Stored on the earlier note rather than as a pair identifier because a tie always
  /// points forward, and a backward pointer would have to be repaired whenever the bar before it
  /// changed.
  final bool tiedToNext;

  /// Where the note sits along its bar, in bar-local logical pixels. This is its time.
  double get offsetX => place.offsetX;

  /// Returns a copy of this note with the given fields replaced.
  NoteMark copyWith({
    AnchoredPlace? place,
    PitchedNote? pitch,
    NoteValue? value,
    bool? tiedToNext,
  }) => NoteMark(
    place: place ?? this.place,
    pitch: pitch ?? this.pitch,
    value: value ?? this.value,
    tiedToNext: tiedToNext ?? this.tiedToNext,
  );

  @override
  bool operator ==(Object other) =>
      other is NoteMark &&
      other.place == place &&
      other.pitch == pitch &&
      other.value == value &&
      other.tiedToNext == tiedToNext;

  @override
  int get hashCode => Object.hash(place, pitch, value, tiedToNext);

  @override
  String toString() =>
      'x${place.offsetX.toStringAsFixed(1)}: $pitch ${value.toString()}'
      '${tiedToNext ? '~' : ''}';
}

/// A percussion hit written at a place in a bar.
///
/// THE SAME PLACE SCHEME AS A NOTE, for the same reason: the drum staff is a staff, and a hit is at
/// the x it was written at. Its vertical position is its instrument, not a stored y.
class PercussionMark {
  /// Creates a hit on [instrument] of [value] at [place].
  const PercussionMark({
    required this.place,
    required this.instrument,
    required this.value,
  });

  /// Where the hit is written.
  final AnchoredPlace place;

  /// The struck instrument, as a MIDI percussion note number.
  ///
  /// This is a key into the staff's drum map, not a pitch: it is never transposed and it is never
  /// compared musically. Keeping it an integer rather than a name is what lets a chart carry a kit
  /// this model has never heard of.
  final int instrument;

  /// How long the hit is written to last. For most percussion this is a notational fact about how
  /// the note is drawn rather than one about how long it rings.
  final NoteValue value;

  /// Where the hit sits along its bar, in bar-local logical pixels.
  double get offsetX => place.offsetX;

  /// Returns a copy of this hit with the given fields replaced.
  PercussionMark copyWith({
    AnchoredPlace? place,
    int? instrument,
    NoteValue? value,
  }) => PercussionMark(
    place: place ?? this.place,
    instrument: instrument ?? this.instrument,
    value: value ?? this.value,
  );

  @override
  bool operator ==(Object other) =>
      other is PercussionMark &&
      other.place == place &&
      other.instrument == instrument &&
      other.value == value;

  @override
  int get hashCode => Object.hash(place, instrument, value);

  @override
  String toString() =>
      'x${place.offsetX.toStringAsFixed(1)}: drum $instrument ${value.toString()}';
}

// PURPOSE: Answer whether a run of written durations adds up to one bar of a meter, using the
//          exact written durations rather than a tick conversion.
// INPUTS: timeSignature — the meter whose length is compared with. notes — the notes as written.
// OUTPUTS: True when the durations sum to the bar's length exactly.
//
//          False for an empty list, because an empty bar is not a full one; the caller that wants
//          to allow it should check for emptiness itself rather than have this answer mean two
//          things. Durations are summed as an exact fraction, so a fill built from triplets is
//          judged correctly rather than being reported short by rounding — which is exactly the
//          case a tick grid chosen for binary values gets wrong.
//
//          THIS FUNCTION PLACES NOTHING AND GATES NOTHING. It reports a sum; the meter is a label
//          on the chart, and no position in this model is derived from it. It is kept because the
//          written duration is still part of a note, and a musician asking "does this bar add up"
//          deserves an answer that is arithmetic rather than an opinion.
// KEYWORDS: bar-fill, validation, exact-arithmetic, triplets, completeness, no-grid
/// Returns whether [notes] add up to exactly one bar of [timeSignature].
bool melodyFillsBar(TimeSignature timeSignature, List<NoteMark> notes) {
  if (notes.isEmpty) {
    return false;
  }
  // The running sum is kept as a fraction; the common denominator is found by cross-multiplication
  // rather than by computing a least common multiple, which would need a factorisation this small
  // calculation does not justify.
  int sumNumerator = 0;
  int sumDenominator = 1;
  for (final NoteMark note in notes) {
    sumNumerator =
        sumNumerator * note.value.wholeDenominator +
        note.value.wholeNumerator * sumDenominator;
    sumDenominator = sumDenominator * note.value.wholeDenominator;
  }
  // Compare sum (sumNumerator / sumDenominator) with the bar length (numerator / denominator).
  return sumNumerator * timeSignature.denominator ==
      timeSignature.numerator * sumDenominator;
}
