// PURPOSE: Move a whole chart to another key for the screen, and name the twelve keys a chart can
//          be shown in. The model stores the WRITTEN form, so a display transposition is a pure
//          function from the written song and an interval to the song that is shown — nothing here
//          mutates or replaces the written chart, and clearing the interval returns the written
//          one unchanged.
// INPUTS: A Song as written, a signed interval in semitones, the Key to label the result with,
//         and a written Key whose twelve display keys are wanted.
// OUTPUTS: A new Song with every chord root, slash bass and alternate chord moved and the key
//          relabelled, plus the twelve [TranspositionTarget]s with the practical spelling chosen
//          for each.
// KEYWORDS: transposition, display-key, editor-key, key-grid, spelling-policy, pure-function
//
// WHICH TRANSPOSITION THIS IS. Owner decision D14 gives transposition two meanings: in the EDITOR
// it is the song's own key, and in the SCENE it is an offset applied to one position in a setlist.
// This file implements the EDITOR meaning (the chart's key changes and every chord is re-spelled),
// which is what the viewer shows. The SCENE meaning lives in `setlist_scene.dart`: `setlistSceneFor`
// takes a `SetlistItem`, applies its `transposeSem` through [transposeSong] with the practical key
// for the target pitch class, and returns the shown chart while the written one is returned
// unchanged — which is why a chart-level transposition here is the right unit after all, once a
// caller owns the entry that carries the interval.
//
// THE MELODY GAP, carried over rather than invented here. Only the chord line moves. A written
// pitched note cannot be transposed and returned exactly — spelling runs through the key signature,
// so F# in C major comes back as Gb — and there is no note transposer that preserves spelling, as
// the op-log's `key.transpose` event already records. Every imported iReal chart has an empty
// melody staff, so this is a gap rather than a defect for the reader; a song with a melody keeps
// its written notes and its chords move.

import 'key.dart';
import 'pitch.dart';
import 'song/bar.dart';
import 'song/section.dart';
import 'song/song.dart';
import 'spelling_table.dart';
import 'transposer.dart';

/// One key a written chart can be shown in, with the interval that reaches it.
class TranspositionTarget {
  /// Creates a target at [semitones] from the written key showing [key].
  const TranspositionTarget({
    required this.semitones,
    required this.key,
    required this.available,
  });

  /// The signed interval from the WRITTEN key, in `[-5, 6]`: the shortest distance to the target
  /// pitch class, with a tritone shown as `+6` rather than `-6`. Path-independent, so returning
  /// to a pitch class always reports the same interval however the musician got there.
  final int semitones;

  /// The key the chart is shown in.
  final Key key;

  /// Whether [key] is a spelling the practical circle of fifths produces.
  ///
  /// False only for a pitch class that neither accidental direction can write conventionally; a
  /// control must mark such a target unavailable rather than transpose into a key it cannot name.
  final bool available;

  /// Whether this target is the written key itself, which the interval alone decides.
  bool get isWrittenKey => semitones == 0;

  @override
  bool operator ==(Object other) =>
      other is TranspositionTarget &&
      other.semitones == semitones &&
      other.key == key &&
      other.available == available;

  @override
  int get hashCode => Object.hash(semitones, key, available);

  @override
  String toString() =>
      'TranspositionTarget($key, ${semitones >= 0 ? '+' : ''}$semitones'
      '${available ? '' : ', unavailable'})';
}

/// The twelve keys a written key can be shown in.
class TranspositionGrid {
  /// Creates a grid that spells its keys with [spellingTable].
  const TranspositionGrid({this.spellingTable = const SpellingTable()});

  /// The rule new tonics are spelled with.
  final SpellingTable spellingTable;

  // PURPOSE: Offer every key a chart can be moved to, so a musician can pick one by name instead
  //          of picking an interval and hoping the spelling comes out right.
  // INPUTS: written — the key the chart is written in, which sets the accidental direction the
  //         automatic spelling starts from.
  // OUTPUTS: Exactly twelve targets, ordered by pitch class from C so the grid has fixed
  //          positions a musician can learn. The tonic is spelled in the practical direction:
  //          the transposer's automatic choice is kept when it lands on the circle of fifths, and
  //          the opposite direction is tried when it does not. That is what turns the transposer's
  //          documented "Gb minor where a musician writes F# minor" case into F# minor here,
  //          without a key-name vocabulary. A target whose pitch class neither direction can
  //          spell is marked unavailable rather than transposed into.
  // KEYWORDS: key-grid, twelve-keys, practical-spelling, enharmonic-choice, total-function
  /// Returns the twelve keys [written] can be shown in.
  List<TranspositionTarget> targets(Key written) {
    final List<TranspositionTarget> targets = <TranspositionTarget>[];
    for (int pitchClass = 0; pitchClass < 12; pitchClass++) {
      targets.add(_targetFor(written, pitchClass));
    }
    return targets;
  }

  // PURPOSE: Choose the displayed key for one target pitch class, preferring the spelling that
  //          sits on the practical circle so a chart is not labelled with a key nobody writes.
  // INPUTS: written — the written key. pitchClass — the target tonic's sounding pitch.
  // OUTPUTS: A target carrying the interval from [written], the chosen key and whether a
  //          practical spelling was found. The first attempt keeps the written key's accidental
  //          direction; when that spelling is off the circle the opposite direction is tried; if
  //          both are off it, the first spelling is reported as unavailable.
  // KEYWORDS: spelling-policy, practical-circle, fallback, availability
  TranspositionTarget _targetFor(Key written, int pitchClass) {
    final int semitones = _shortestInterval(
      written.tonicPitchClass,
      pitchClass,
    );
    final Transposer transposer = Transposer(spellingTable: spellingTable);
    final Key automatic = transposer.transposeKey(written, semitones);
    if (automatic.isPracticallySpelled) {
      return TranspositionTarget(
        semitones: semitones,
        key: automatic,
        available: true,
      );
    }
    // The first attempt followed the WRITTEN key's accidental direction, so the mirror must
    // reverse that direction — not the direction of [automatic], whose off-circle tonic reports
    // no direction at all ([Key.prefersSharps] is false when a key cannot be placed) and would
    // therefore retry the same spelling and report a practical key as unavailable.
    final Key mirrored = transposer.transposeKey(
      written,
      semitones,
      preference: written.prefersSharps
          ? SpellingPreference.flat
          : SpellingPreference.sharp,
    );
    if (mirrored.isPracticallySpelled) {
      return TranspositionTarget(
        semitones: semitones,
        key: mirrored,
        available: true,
      );
    }
    return TranspositionTarget(
      semitones: semitones,
      key: automatic,
      available: false,
    );
  }
}

// PURPOSE: Report how far one pitch class is above another in the way a musician counts it, so a
//          transposition control labels an interval with the number the musician would say rather
//          than with an unwrapped one.
// INPUTS: from and to — sounding pitch classes in `[0, 11]`.
// OUTPUTS: An interval in `[-5, 6]`. A tritone is reported as `+6`, not `-6`, because the grid
//          reads the six-step move as upward; every other distance is the shortest signed one.
// KEYWORDS: interval, semitones, pitch-class, shortest-signed, tritone-convention
int _shortestInterval(int from, int to) {
  final int upward = normalizePitchClass(to - from);
  return upward > 6 ? upward - 12 : upward;
}

// PURPOSE: Produce the chart that is shown for a requested key, so the viewer can render a
//          transposed song without the written one being touched.
// INPUTS: song — the chart as written. semitones — the interval to move every chord by. toKey —
//         the key the result is labelled with, which must be the target the interval reaches;
//         taking it as an argument rather than deriving it keeps the spelling choice (A1's
//         spelling table) at the call site that made it.
// OUTPUTS: A new Song whose sections, bars, barlines, repeats, voltas, marks and staff text are
//          copied unchanged and whose every chord root, slash bass and alternate chord is moved
//          by [semitones], labelled with [toKey]. The input is not mutated. Transposing by 0 and
//          passing the song's own key returns an equal song, so clearing a transposition is the
//          same operation as applying one.
// KEYWORDS: song-transposition, chord-line, display-key, immutable, editor-key
/// Returns [song] with its chord line moved by [semitones] and its key relabelled [toKey].
Song transposeSong(Song song, int semitones, {required Key toKey}) {
  const Transposer transposer = Transposer();
  final List<Section> sections = <Section>[
    for (final Section section in song.sections)
      Section(
        id: section.id,
        label: section.label,
        bars: <Bar>[
          for (final Bar bar in section.bars)
            Bar(
              timeSignature: bar.timeSignature,
              chords: <BeatChord>[
                for (final BeatChord placed in bar.chords)
                  BeatChord(
                    chord: transposer.transposeChord(placed.chord, semitones),
                    beat: placed.beat,
                    step: placed.step,
                    size: placed.size,
                  ),
              ],
              melody: bar.melody,
              percussion: bar.percussion,
              openingBarline: bar.openingBarline,
              closingBarline: bar.closingBarline,
              volta: bar.volta,
              repeatPrevious: bar.repeatPrevious,
              slashRepeat: bar.slashRepeat,
              noChord: bar.noChord,
              marks: bar.marks,
              staffText: bar.staffText,
            ),
        ],
      ),
  ];
  return Song(
    id: song.id,
    title: song.title,
    composer: song.composer,
    style: song.style,
    key: toKey,
    tempo: song.tempo,
    sections: sections,
    staffSet: song.staffSet,
  );
}
