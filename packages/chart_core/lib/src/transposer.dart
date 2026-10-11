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
import 'song/note.dart';
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

  // PURPOSE: Move a single written note to another key, preserving its MUSICAL FUNCTION — its scale
  //          degree — rather than its letter. This is what makes a transposed melody agree with the
  //          transposed chord beside it: the chord's root is moved by an interval and then spelled
  //          in the target key by [SpellingTable], and a note moved the same way and spelled the
  //          same way belongs to the same key as the chord it sounds under.
  // INPUTS: note — the note as WRITTEN, whose pitch class and octave both matter. semitones — the
  //         interval, positive upward. sourceKey — the key [note] is written in, which is a
  //         TIE-BREAK rather than a filter: it decides the direction of an alteration only when the
  //         two candidate spellings are equally short (see below). targetKey — the key the result is
  //         written in, which chooses the spelling of every sounding pitch.
  // OUTPUTS: The note moved by [semitones] and written in [targetKey]. The octave is adjusted when
  //          the move carries the note across the C boundary, so B3 up a semitone is C4 and not C3:
  //          the sounding pitch is preserved exactly, which is the one thing a transposition may not
  //          change.
  //
  //          WHAT IS PRESERVED AND WHAT IS NOT, because the two are different claims.
  //          PRESERVED: the sounding pitch, the octave relationship and the note's scale degree
  //          wherever the target key contains that pitch class — so E in C major becomes F# in D
  //          major, which is the same degree raised with the key. NOT PRESERVED: a spelling the
  //          target key does not contain. F# in C major moves up a semitone to the G-flat pitch
  //          class, and it is returned as F#, because no key signature writes that pitch as Gb in a
  //          key on the sharp side. This is what `spellChromatic` documents for chords as well, and
  //          the alternative — preferring the SOURCE key's accidental direction here — is worse
  //          rather than merely different: it would make the interval round-trip unstable, since
  //          `Preference.flat` on the G-flat pitch class spells Ab (alter -1) where the sharp
  //          direction spells G (alter 0), and a note spelled Ab and moved back down comes out as G.
  //          The direction is therefore resolved ONCE per call, from the source key, so both
  //          candidate spellings of one transposition are compared under the same rule.
  // KEYWORDS: note-transposition, spelling-preservation, scale-degree, octave-adjustment,
  //           display-key, tie-break-rationale
  /// Returns [note] moved by [semitones] and written in [targetKey].
  PitchedNote transposeNote(
    PitchedNote note,
    int semitones, {
    required Key sourceKey,
    required Key targetKey,
  }) {
    final int pitchClass = normalizePitchClass(
      note.note.pitchClass + semitones,
    );
    // The written letter names a pitch CLASS, so a move that crosses C raises (or lowers) the
    // octave number as well. C is the boundary because the octave number changes there — the same
    // convention `PitchedNote` documents for scientific pitch notation.
    final int octave =
        note.octave + _octaveShift(note.note.pitchClass, semitones);
    return PitchedNote(
      note: _spellNotePitch(pitchClass, sourceKey, targetKey),
      octave: octave,
    );
  }

  // PURPOSE: Choose how a sounding pitch is written in the target key without letting the source
  //          key's accidental direction win over the target key's signature — the rule that keeps
  //          the result inside the key it is written in.
  // INPUTS: pitchClass — the sounding pitch class, already normalised. sourceKey — the key the note
  //         came from, used only to settle a tie. targetKey — the key the result is written in.
  // OUTPUTS: A [WrittenNote]. A pitch class inside [targetKey]'s own scale returns that scale
  //          degree, so an accidental appears only where the key signature does not already supply
  //          it. A pitch class outside it is answered by [SpellingTable.spellChromatic], and the
  //          two possible directions are tried IN A FIXED ORDER — the source key's, then the
  //          opposite one — with the first result that needs no more than one accidental winning.
  //          That rule is what turns the G-flat pitch class into F# rather than into Gb: F# is a
  //          single sharp, Gb a single flat, so both survive the accidentals test and the source
  //          key's direction is what settles it. Where neither direction is that cheap the first
  //          attempt is returned rather than a double accidental being hunted for.
  // KEYWORDS: spelling-policy, target-key-first, tie-break, one-accidental, determinism
  WrittenNote _spellNotePitch(int pitchClass, Key sourceKey, Key targetKey) {
    for (final WrittenNote degree in spellingTable.scaleOf(targetKey)) {
      if (degree.pitchClass == pitchClass) {
        return degree;
      }
    }
    final SpellingPreference natural = sourceKey.prefersSharps
        ? SpellingPreference.sharp
        : SpellingPreference.flat;
    final WrittenNote first = spellingTable.spellChromatic(
      pitchClass,
      targetKey,
      natural,
    );
    if (first.alter.abs() <= 1) {
      return first;
    }
    final SpellingPreference other = natural == SpellingPreference.sharp
        ? SpellingPreference.flat
        : SpellingPreference.sharp;
    final WrittenNote second = spellingTable.spellChromatic(
      pitchClass,
      targetKey,
      other,
    );
    return second.alter.abs() < first.alter.abs() ? second : first;
  }

  // PURPOSE: Report how many octaves a semitone movement carries with it, so the octave arithmetic
  //          is stated once instead of being re-derived beside it.
  // INPUTS: sourcePitchClass — the written letter's sounding pitch class, in `[0, 11]`. semitones —
  //         the interval.
  // OUTPUTS: The number of twelve-semitone blocks the move crosses: +1 for B moved up a semitone
  //          (the C boundary above it), -1 for C moved down one, and the interval's own octaves for
  //          a move of a twelfth. Both operands are reduced into their own block by a FLOOR division,
  //          because `PitchedNote.note` is always a member of the twelve and the raw sum is not: with
  //          truncating division, C moved down a semitone would report no crossing at all, and that
  //          is the only direction in which the two divisions disagree.
  // KEYWORDS: octave-boundary, scientific-pitch-notation, crossing-c, floor-division, total-function
  int _octaveShift(int sourcePitchClass, int semitones) {
    final int raw = sourcePitchClass + semitones;
    // A floor division, written out because `~/` truncates toward zero: with truncation, C moved
    // down a semitone would report no crossing at all.
    int floorDiv(int value, int divisor) =>
        value >= 0 ? value ~/ divisor : (value - divisor + 1) ~/ divisor;
    return floorDiv(raw, 12) - floorDiv(sourcePitchClass, 12);
  }
}
