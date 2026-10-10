// PURPOSE: Record a transposition of a whole chart as one event, so that moving a tune to a
//          singer's key is a single undoable step rather than one edit per chord.
// INPUTS: The interval in semitones, and the key the chart was in and the key it moves to.
// OUTPUTS: An immutable event whose inverse is another transposition of the same magnitude in the
//          opposite direction, carrying the two keys swapped. The chord line moves by pure
//          semitone arithmetic, which is exactly reversible; the recorded keys are what make the
//          label reversible too.
// KEYWORDS: transpose, key-change, semitones, chart-wide, inverse, reversible, melody-gap
//
// WHY BOTH KEYS ARE RECORDED RATHER THAN ONE KEY AND A NEGATED INTERVAL.
//
// A key is a spelled tonic, not a pitch class: C# major and Db major sound alike and are
// different keys. Re-deriving the old key from the new one by subtracting the interval runs the
// pitch class back through the spelling table, which is free to name it on a different letter —
// so undo would restore a chart that sounds right and is written in the enharmonic twin of the
// key it started in. Recording the key the chart came from makes undo restore the exact key.
//
// WHAT THIS EVENT DOES NOT MOVE, AND WHY.
//
// The melodic line is left alone. Transposing a written note means choosing a letter and an
// accidental for its new sounding pitch, and that choice is only reversible when it is the
// spelling table's own choice: a note written F# in C major comes back from a round trip spelled
// Gb, because C major's signature prefers the flat. The model has no spelling-preserving note
// transposer — ChordRoot keeps its unreduced semitones and its spelling preference, a
// PitchedNote keeps only the resolved letter and alteration — so this event moves what it can
// reverse exactly and reports the rest as a gap rather than silently producing a chart whose
// melody is in the old key or whose undo is lossy.
part of 'oplog.dart';

/// Moves the chord line and the key label of a chart by a number of semitones.
class KeyTransposeEvent extends ChartEvent {
  /// Creates a transposition by [semitones] from [fromKey] to [toKey].
  const KeyTransposeEvent({
    required super.docId,
    required super.seq,
    required this.semitones,
    required this.fromKey,
    required this.toKey,
  });

  /// The interval, in semitones; negative moves downward and zero is an identity edit.
  final int semitones;

  /// The key the chart was written in before the transposition.
  ///
  /// Carried for the inverse's sake and for the record: a reader can tell a chart transposed for
  /// a singer from one written in that key to begin with.
  final Key fromKey;

  /// The key the chart is written in after the transposition.
  final Key toKey;
  @override
  String get type => 'key.transpose';
  @override
  Map<String, Object?> payloadJson() => <String, Object?>{
    'semitones': semitones,
    'fromKey': ModelJson.key(fromKey),
    'toKey': ModelJson.key(toKey),
  };
  @override
  KeyTransposeEvent inverse() => KeyTransposeEvent(
    docId: docId,
    seq: seq,
    semitones: -semitones,
    fromKey: toKey,
    toKey: fromKey,
  );
  @override
  KeyTransposeEvent withSeq(int seq) => KeyTransposeEvent(
    docId: docId,
    seq: seq,
    semitones: semitones,
    fromKey: fromKey,
    toKey: toKey,
  );
  @override
  bool operator ==(Object other) =>
      other is KeyTransposeEvent &&
      other.docId == docId &&
      other.seq == seq &&
      other.semitones == semitones &&
      other.fromKey == fromKey &&
      other.toKey == toKey;
  @override
  int get hashCode => Object.hash(docId, seq, semitones, fromKey, toKey);
}
