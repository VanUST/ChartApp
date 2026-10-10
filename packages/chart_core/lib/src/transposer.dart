// PURPOSE: Move music between keys. Transposition is defined here as an operation on sounding
//          pitch: every chord root and slash bass gains the requested number of semitones, the
//          quality and tensions are untouched, and the written form is produced later by the
//          spelling table in whatever key the chart ends up in. Separating "move the pitch" from
//          "write the pitch" is what lets one transposition serve a chart displayed in any key.
// INPUTS: A Chord or Key and an integer number of semitones, positive upward.
// OUTPUTS: A new Chord or Key. The input is never mutated — Chord and Key are immutable — so a
//          caller that transposes a song in two directions cannot corrupt the original.
// KEYWORDS: transposition, semitones, key-change, immutability, spelling-preservation
import 'chord.dart';
import 'key.dart';
import 'pitch.dart';
import 'spelling_table.dart';

/// Moves chords and keys by a number of semitones.
class Transposer {
  /// Creates a transposer using [spellingTable] to name new keys.
  const Transposer({this.spellingTable = const SpellingTable()});

  /// The table used to spell a new tonic when a whole key is moved.
  final SpellingTable spellingTable;

  // PURPOSE: Move a chord by [semitones] without deciding how it will be written, so that the
  //          same transposed chord can be displayed in a different key without being moved again.
  // INPUTS: chord — the chord to move. semitones — the interval; negative moves downward, zero
  //         returns an equal chord, and a magnitude of 12 or more is allowed and reduced by the
  //         spelling table rather than here.
  // OUTPUTS: A new Chord with root, slash bass and alternate chord moved, and the quality
  //          preserved. The root's spelling preference is carried across, because a chord the
  //          composer forced to be written with sharps keeps that intent after transposition. The
  //          alternate is transposed by recursion, because it is a chord in its own right rather
  //          than a marking on this one.
  // KEYWORDS: transposition, chord, interval, spelling-preference-preservation, alternate-chord
  /// Returns [chord] moved by [semitones], with its written form left undecided.
  Chord transposeChord(Chord chord, int semitones) {
    final ChordRoot root = ChordRoot(
      chord.root.semitones + semitones,
      preference: chord.root.preference,
    );
    final ChordRoot? slash = chord.bass;
    final Chord? above = chord.alternate;
    return Chord(
      root: root,
      quality: chord.quality,
      bass: slash == null
          ? null
          : ChordRoot(
              slash.semitones + semitones,
              preference: slash.preference,
            ),
      // The alternate chord is transposed by recursion rather than copied, because it is a whole
      // chord with its own root and its own bass. Copying it would leave the small chord printed
      // above the main one in the key the chart used to be in.
      alternate: above == null ? null : transposeChord(above, semitones),
    );
  }

  // PURPOSE: Move a whole key by [semitones], so that transposing a song can also move the key
  //          it is labelled with.
  // INPUTS: key — the key to move. semitones — the interval. preference — how to spell the new
  //         tonic; [SpellingPreference.automatic] keeps the source key's accidental direction,
  //         on the reasoning that transposing a chart by a semitone or two should not flip its
  //         notation from flats to sharps.
  // OUTPUTS: A Key with the moved tonic pitch and the same mode.
  //
  //          LIMITATION, stated rather than hidden: the new tonic is spelled by the chromatic
  //          rule of the spelling table, which produces a twelve-name chromatic set dominated by
  //          the source key's direction. That set is right for major keys and wrong for some
  //          minor ones — it will name the key a minor third below C as "A minor" correctly but
  //          can produce a name such as "Gb minor" where a musician would write "F# minor". The
  //          fix is a key-name vocabulary, which belongs with the chart grammar in spike S1
  //          rather than in the transposer, so it is deferred and reported here instead of being
  //          approximated with another special case.
  // KEYWORDS: key-transposition, key-naming, limitation, documented-gap
  /// Returns [key] moved by [semitones], with its new tonic spelled by [spellingTable].
  Key transposeKey(
    Key key,
    int semitones, {
    SpellingPreference preference = SpellingPreference.automatic,
  }) {
    final int pitchClass = normalizePitchClass(key.tonicPitchClass + semitones);
    final SpellingPreference resolved = switch (preference) {
      SpellingPreference.automatic =>
        key.prefersSharps ? SpellingPreference.sharp : SpellingPreference.flat,
      SpellingPreference.sharp || SpellingPreference.flat => preference,
    };
    return Key(
      tonic: spellingTable.spellChromatic(pitchClass, key, resolved),
      mode: key.mode,
    );
  }

  // PURPOSE: Spell a transposed chord in a target key, which is the operation a renderer
  //          actually needs and the one the round-trip property is stated against.
  // INPUTS: chord — the transposed chord. targetKey — the key the chart is displayed in.
  // OUTPUTS: The written root of the chord in that key. The quality and tensions are not part of
  //          the result because they do not change under transposition.
  // KEYWORDS: rendering, spelling, key-context, round-trip
  /// Returns the written root of [chord] as [targetKey] spells it.
  WrittenNote spellRoot(Chord chord, Key targetKey) =>
      chord.root.spellIn(targetKey, spellingTable);
}
