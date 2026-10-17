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
// THE MELODY MOVES WITH THE CHORDS, and the reasoning is stated on [transposeSong]. It used to be a
// gap: `melody: bar.melody` copied the notes untouched, so a transposed chart showed chords in the
// new key over notes in the old one — the two halves of one chart disagreeing. The written spelling
// is not lost by that fix, because this function returns the chart that is SHOWN and nothing writes
// the result back over the written one.

import 'key.dart';
import 'pitch.dart';
import 'song/bar.dart';
import 'song/note.dart';
import 'song/section.dart';
import 'song/song.dart';
import 'spelling_table.dart';
import 'transposer.dart';

// THE MELODY MOVES WITH THE CHORDS, AND THIS IS THE DECISION THAT CLOSES THE GAP A56 NAMED.
//
// The gap, as it stood: only the chord line moved. A transposed chart with a melody therefore
// CONTRADICTED ITSELF — the chords said E major and the notes still spelled D major — and that is a
// defect rather than a missing feature, because the two halves of one chart have to agree about the
// key they are in.
//
// WHERE IT IS FIXED, AND WHY IT IS FIXED HERE RATHER THAN IN THE EDITOR.
//
// `key.transpose` is an EDITOR operation: it rewrites the chart's own written key and its chords,
// and it is the event the reducer routes through this same function. A display transposition — what
// the viewer's key grid does — must move the notes it SHOWS and must not touch the notes the
// musician WROTE, and the whole architecture already says so: `EditSession` edits the written
// document, this function returns a new `Song`, and `setlist_scene.dart` documents the difference as
// "the scene meaning ... returns the shown chart while the written one is returned unchanged".
// So this function transposes notes for exactly the reason it transposes chords — it produces the
// chart that is SHOWN — and the written spelling survives because nothing writes it back.
//
// WHY THIS IS NOT "DISPLAY-ONLY" IN THE SENSE OF A SECOND RENDERER. There is no second renderer:
// the notes are moved in the model, in the same pass and by the same rule as the chords, and every
// consumer of a `Song` — the layout engine, the painter, a page dump, a probe with no Flutter at
// all — receives a melody that already belongs to the key it is labelled with. A spelling chosen at
// paint time would have to be chosen again by every consumer that is not the painter.
//
// WHAT THE MUSICIAN'S WRITTEN PITCH COSTS AND WHY IT IS WORTH IT. A chart whose melody is written
// in a key the reader cannot play is shown to them in their own key (D14), and the chart they see
// has a melody in that key and chords to match. The chart they SAVE is still their own, note for
// note: the key grid never changes what is written, which is what the owner's instruction — the
// written pitch must not be destroyed by looking at it in another key — requires.

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
//          copied unchanged and whose every chord root, slash bass and alternate chord is moved by
//          [semitones], labelled with [toKey]. The MELODY is moved by the same interval and written
//          in [toKey], so the notes and the chords of the result agree about the key — the defect
//          A56 named, closed. The input is not mutated, and the input's notes are not re-spelled, so
//          the written pitch survives on the document the musician saves. Percussion is copied
//          unchanged and that is not an oversight: a drum is not a pitch and a drum part does not
//          transpose, which is the rule `StaffKind.percussion` states.
//
//          Transposing by 0 and passing the song's own key returns an equal song — the note path
//          included, because spelling a pitch in the key it is already written in returns the note
//          that was written (diatonic pitches come back as their own scale degree) — so clearing a
//          transposition is the same operation as applying one.
// KEYWORDS: song-transposition, chord-line, melody, display-key, immutable, editor-key
/// Returns [song] with its chord line and melody moved by [semitones], labelled [toKey].
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
              // THE SIZE TRAVELS WITH THE BAR, and it is carried as the VALUE the musician set
              // rather than re-measured: the factor is a multiple of the bar's own content, so a bar
              // at ×2 stays "twice whatever these chords need" and is neither lost nor doubled by a
              // transposition. Dropping it here would be invisible in the editor — the page would
              // still draw — and would reset the chart's engraving the first time the musician
              // transposed it.
              size: bar.size,
              chords: <BeatChord>[
                for (final BeatChord placed in bar.chords)
                  BeatChord(
                    chord: transposer.transposeChord(placed.chord, semitones),
                    beat: placed.beat,
                    step: placed.step,
                    size: placed.size,
                  ),
              ],
              melody: <BeatNote>[
                for (final BeatNote note in bar.melody)
                  _transposedNote(note, transposer, semitones, song.key, toKey),
              ],
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

// PURPOSE: Move one note of the melody, keeping everything a transposition has no business changing
//          — its address in the bar, how long it is written, and its tie — so that only the pitch
//          moves and the melody stays the melody.
// INPUTS: note — the note as written. transposer — the shared transposer. semitones — the interval.
//         writtenKey — the key the note is written in. shownKey — the key the result is written in.
// OUTPUTS: A [BeatNote] at the same (beat, step) with the same [NoteValue] and the same
//          [BeatNote.tiedToNext], whose pitch has been moved by [semitones] and rewritten in
//          [shownKey].
//
//          WHY THE ADDRESS AND THE TIE ARE COPIED RATHER THAN TAKEN FROM THE MOVE. A tie points
//          FORWARD at a note that is moving by the same interval and is still the note that follows
//          it, and a step within a cell is a place in a dense sequence whose neighbours are all
//          moving with it. Re-deriving either would be this function deciding a fact that has not
//          changed, and the only way to decide it wrongly.
// KEYWORDS: melody-transposition, address-preserved, duration-preserved, tie-preserved
/// Returns [note] moved by [semitones] into [shownKey], keeping its address, value and tie.
BeatNote _transposedNote(
  BeatNote note,
  Transposer transposer,
  int semitones,
  Key writtenKey,
  Key shownKey,
) => BeatNote(
  pitch: transposer.transposeNote(
    note.pitch,
    semitones,
    sourceKey: writtenKey,
    targetKey: shownKey,
  ),
  value: note.value,
  beat: note.beat,
  step: note.step,
  tiedToNext: note.tiedToNext,
);
