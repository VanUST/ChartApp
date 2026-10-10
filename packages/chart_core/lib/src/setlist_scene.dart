// PURPOSE: Give the SCENE meaning of owner decision D14 a home: an interval hanging on one setlist
//          entry, applied to the chart that entry names while the chart document keeps its written
//          key. It is the counterpart of `transposeSong`, which implements the EDITOR meaning — the
//          song's own key changed — and the two are deliberately different functions, because they
//          answer to different documents.
// INPUTS: A [SetlistItem] carrying the interval, and the chart as written (the document value, not
//         the entry).
// OUTPUTS: A [SetlistScene] holding the written chart, the chart to show, the interval that moved
//          it and the key it is shown in. Transposing by zero returns the written chart itself, so
//          `transposeSem == 0` and the written key are the same state. Nothing here mutates or
//          replaces the written chart, and nothing here writes a document: it is a pure function
//          from the two values to what the stage should draw.
// KEYWORDS: setlist, scene-transposition, D14, display-key, written-key, pure-function
//
// WHY THE KEY IS RESOLVED BY PITCH CLASS AND NOT BY THE INTERVAL ALONE.
//
// A key label is a pitch class — `+7` and `-5` from D reach the same key — so an entry may carry any
// integer and still name exactly one practical spelling. The twelve-key grid only offers `[-5, 6]`,
// but an imported playlist can carry an interval outside that window, and refusing it here would
// make an imported entry undisplayable. The practical spelling is therefore chosen by the target
// pitch class, while the CHORDS are moved by the interval the entry actually carries; the two agree
// because a transposition by `+7` and one by `-5` produce the same sounding pitches.
//
// WHY THIS DOES NOT TOUCH THE CHART'S OWN KEY.
//
// D14 says the editor holds the song's key and the scene holds an offset on a position. The chart
// document handed in is returned unchanged, and only the returned [SetlistScene.shown] carries the
// label. A caller that kept `shown` as the document would have destroyed the written chart the
// editor shows; the point of the scene meaning is that the same document is read in two keys without
// either being written over the other.
import 'key.dart';
import 'oplog/oplog.dart';
import 'pitch.dart';
import 'song/song.dart';
import 'transposition.dart';

/// One setlist entry resolved against the chart it names: what is written, what is shown, and why.
class SetlistScene {
  /// Creates the resolution of [entry] over [written].
  const SetlistScene({
    required this.entry,
    required this.written,
    required this.shown,
    required this.semitones,
    required this.shownKey,
  });

  /// The entry that was resolved, whose transposition and notes the resolution carries.
  final SetlistItem entry;

  /// The chart as written: the document value, whose key never moves here.
  final Song written;

  /// The chart to show for this entry. Equal to [written] when [semitones] is zero.
  final Song shown;

  /// The interval the entry carries, in semitones, exactly as stored.
  final int semitones;

  /// The key [shown] is labelled with, spelled practically for the chart's written key.
  final Key shownKey;

  /// Whether this entry moves the chart, which is the interval alone.
  bool get isTransposed => semitones != 0;

  @override
  String toString() =>
      'SetlistScene(${entry.documentId}, written=${written.key}, '
      'shown=$shownKey, ${semitones >= 0 ? '+' : ''}$semitones st)';
}

// PURPOSE: Resolve what the stage draws for one setlist entry, which is the operation the scene
//          meaning of D14 is: an interval on a position applied to a chart whose own key is left
//          alone.
// INPUTS: entry — the setlist entry, carrying the interval and the chart's document id. written —
//         the chart that entry names, as the document holds it.
// OUTPUTS: A [SetlistScene]. At `transposeSem == 0` the written chart is returned unchanged and the
//          shown key is the written key, so "no transposition" and "written" are one state. At any
//          other interval every chord root, slash bass and alternate chord is moved and the result
//          is relabelled with the practical spelling for the target pitch class; the written chart
//          is not mutated. A written key with no practical spelling for the target pitch class
//          still resolves: the target the grid marks unavailable is used as the label rather than
//          throwing, because a chart that cannot be labelled correctly is still a chart that can be
//          shown.
// KEYWORDS: scene-resolution, setlist-entry, practical-spelling, pitch-class, written-preserved
/// Resolves the chart [entry] plays from [written], moving the shown chart by its interval.
SetlistScene setlistSceneFor({
  required SetlistItem entry,
  required Song written,
}) {
  final int semitones = entry.transposeSem;
  if (semitones == 0) {
    return SetlistScene(
      entry: entry,
      written: written,
      shown: written,
      semitones: 0,
      shownKey: written.key,
    );
  }
  // The target's pitch class is the written tonic moved by the interval; the grid's twelve targets
  // cover every pitch class exactly once, so the lookup is total in practice. The `orElse` keeps it
  // total in fact: a written key the spelling rule cannot place at all falls back to the written
  // key rather than throwing from a drawing path.
  final int targetPitchClass = normalizePitchClass(
    written.key.tonicPitchClass + semitones,
  );
  final TranspositionTarget target = const TranspositionGrid()
      .targets(written.key)
      .firstWhere(
        (TranspositionTarget candidate) =>
            candidate.key.tonicPitchClass == targetPitchClass,
        orElse: () => TranspositionTarget(
          semitones: semitones,
          key: written.key,
          available: false,
        ),
      );
  return SetlistScene(
    entry: entry,
    written: written,
    shown: transposeSong(written, semitones, toKey: target.key),
    semitones: semitones,
    shownKey: target.key,
  );
}
