// PURPOSE: Describe a musical key well enough to spell notes in it, which is the one thing
//          transposition actually needs from a key. It deliberately does not model scales,
//          modes or harmony: those are later concerns, and giving this class more responsibility
//          than the spelling decision would invite the spelling decision to depend on them.
// INPUTS: A tonic as a WrittenNote (letter and alteration, not a bare pitch class) and a Mode.
// OUTPUTS: A Key whose [signatureFifths] reports its position on the circle of fifths, negative
//          for flat keys and positive for sharp keys, and whose [direction] reports which way
//          the key prefers its chromatic notes to be spelled.
// KEYWORDS: key, tonic, key-signature, circle-of-fifths, mode, spelling-direction
//
// Why the tonic is a WrittenNote and not a pitch class: the pitch class alone cannot tell
// C-sharp major from D-flat major. They sound identical (seven sharps versus five flats) and
// they spell every chromatic note differently, so a key that stored only the pitch class would
// force the spelling table to guess.

import 'pitch.dart';

/// Whether a key is major or minor.
///
/// The mode matters to spelling because it decides the relationship to the key signature: A
/// minor and C major share a signature, and a note spelled as Ab in A minor is spelled as G# in
/// E major even though both keys are entered from different tonics.
enum Mode {
  /// Major mode.
  major,

  /// Minor mode.
  minor,
}

/// A musical key, identified by its spelled tonic and its mode.
class Key {
  /// Creates the key with the given spelled [tonic] and [mode].
  const Key({required this.tonic, required this.mode});

  /// C major, the reference key against which every spelling decision is described.
  static const Key cMajor = Key(
    tonic: WrittenNote(NoteLetter.c, 0),
    mode: Mode.major,
  );

  /// A minor, the relative minor of [cMajor] and therefore the same key signature.
  static const Key aMinor = Key(
    tonic: WrittenNote(NoteLetter.a, 0),
    mode: Mode.minor,
  );

  /// The spelled tonic of this key.
  final WrittenNote tonic;

  /// Whether this key is major or minor.
  final Mode mode;

  /// The sounding pitch class of the tonic, in `[0, 11]`.
  int get tonicPitchClass => tonic.pitchClass;

  // PURPOSE: Place the key on the circle of fifths, which is how the spelling table learns
  //          whether the key is a sharp key or a flat key. The position is computed rather than
  //          stored so that a key cannot be constructed in a self-contradictory state, such as a
  //          D-flat tonic claiming a sharp signature.
  // INPUTS: None.
  // OUTPUTS: The number of fifths above C, negative for flat keys. C major and A minor are 0,
  //          G major and E minor are 1, F major and D minor are -1. A tonic spelling that no
  //          position on the practical circle produces yields 0 rather than throwing, which
  //          degrades to C-major spelling instead of failing a whole import.
  // KEYWORDS: circle-of-fifths, key-signature, sharps, flats, derivation
  /// Returns this key's position on the circle of fifths, negative for flat keys.
  int get signatureFifths => _fifthsOf(_circleReference) ?? 0;

  // PURPOSE: Report whether this key's tonic is one of the spellings the practical circle of
  //          fifths produces, so a transposition control can refuse to offer a key it cannot
  //          name conventionally instead of showing a spelling no musician would write.
  // INPUTS: None.
  // OUTPUTS: True for every tonic that sits at a position from -7 to +7 on the circle: C, Db, D,
  //          Eb, E, F, F#, G, Ab, A, Bb, B and their parallel minors — the keys a chart is
  //          actually written in. False for a spelling beyond that range, such as D# major
  //          (nine sharps) or Db minor (eight flats), whose interval from the circle cannot be
  //          named by [signatureFifths] and reaches 0 there.
  //
  //          The distinction matters because [signatureFifths] returns 0 both for a key with no
  //          signature and for a key it cannot place, and a caller that has to choose which
  //          enharmonic to display must be able to tell those apart.
  // KEYWORDS: key-signature, practical-circle, enharmonic-choice, spellability
  /// Returns whether this key is a spelling the practical circle of fifths produces.
  bool get isPracticallySpelled => _fifthsOf(_circleReference) != null;

  // PURPOSE: Give both [signatureFifths] and [isPracticallySpelled] the one note they place on
  //          the circle, so the two cannot disagree about which spelling they are looking for.
  // INPUTS: None.
  // OUTPUTS: The tonic itself for a major key. For a minor key, its relative major — a minor
  //          third above the tonic, spelled by letter so that A minor maps to C major rather
  //          than to a pitch-class coincidence.
  // KEYWORDS: circle-of-fifths, relative-major, derivation
  WrittenNote get _circleReference => mode == Mode.major
      ? tonic
      : WrittenNote(
          tonic.letter.step(2),
          shortestAlter(
            normalizePitchClass(tonicPitchClass + 3),
            tonic.letter.step(2),
          ),
        );

  // PURPOSE: Invert the circle of fifths for one spelled note, which is the arithmetic both
  //          getters above are stated in.
  // INPUTS: reference — the note to place, normally a key's tonic or its relative major.
  // OUTPUTS: The number of fifths above C, negative for flat keys, or null when no position in
  //          the practical range -7..+7 spells that note.
  //
  //          A key a given number of fifths above C has its tonic on the letter that many
  //          letter-steps of four up, and its pitch class seven semitones up per fifth. Searching
  //          the practical range and comparing the spelled result keeps the inversion honest
  //          without a lookup table that could disagree with the arithmetic.
  // KEYWORDS: circle-of-fifths, inversion, search, nullable-result
  int? _fifthsOf(WrittenNote reference) {
    for (int fifths = -7; fifths <= 7; fifths++) {
      final NoteLetter letter = NoteLetter.c.step(4 * fifths);
      final int pitchClass = normalizePitchClass(7 * fifths);
      final WrittenNote candidate = WrittenNote(
        letter,
        shortestAlter(pitchClass, letter),
      );
      if (candidate == reference) {
        return fifths;
      }
    }
    return null;
  }

  // PURPOSE: Report which accidental direction this key prefers for a note that is not one of
  //          its seven diatonic degrees, so the spelling table has one place to consult instead
  //          of deciding per note.
  // INPUTS: None.
  // OUTPUTS: True for sharp-preferring keys, false for flat-preferring ones. A key with no
  //          signature, C major or A minor, reports false.
  //
  //          That last case is a deliberate, documented simplification. Convention in C major is
  //          mixed — bII, bIII, bV, bVI and bVII are written with flats while #IV is written
  //          with a sharp — so a single direction cannot be right for all six chromatic notes.
  //          Flat is chosen because it is correct for five of them and wrong only for #IV, where
  //          sharp would be correct for one and wrong for five. A per-chord override on the
  //          chord itself is the escape hatch; making this fully context-sensitive needs the
  //          harmonic analysis this project has not built, and a guess dressed as a rule would
  //          be harder to notice than a limitation that is written down.
  // KEYWORDS: spelling-direction, chromatic-notes, sharp, flat, documented-simplification
  /// Returns whether this key prefers sharps for a note outside its seven degrees.
  bool get prefersSharps => signatureFifths > 0;

  // PURPOSE: Compare keys by tonic spelling and mode, so that C-sharp major and D-flat major are
  //          distinct keys and a test failure names which one was expected.
  // INPUTS: other — any object.
  // OUTPUTS: True only for a Key with the same spelled tonic and the same mode.
  // KEYWORDS: equality, enharmonic-keys, mode
  @override
  bool operator ==(Object other) =>
      other is Key && other.tonic == tonic && other.mode == mode;

  @override
  int get hashCode => Object.hash(tonic, mode);

  // PURPOSE: Name the key the way a chart prints it, which is the form the engraving needs: a page
  //          states the key it is written in at the point where the music begins, and what it
  //          states there is this string.
  // INPUTS: None.
  // OUTPUTS: The spelled tonic followed by " major" or " minor", e.g. "Eb major" or "A minor". The
  //          trailing word is spelled out rather than abbreviated (no "m", no triangle) because
  //          this is also read where there is no room for a legend, and because a bold `A minor`
  //          set beside the chords is unambiguous while `Am` beside a chord `Am` is not.
  //
  //          It is NOT translated, and that is a decision rather than an omission (owner decision
  //          D27): a key is notation, `A minor` is how it is written in every country, and a chart
  //          printed as `A минор` is not recognised as notation by anyone but a Russian speaker.
  //          The application's catalogue therefore carries the same words in both of its languages
  //          for the places an interface needs them (`keyNameMajor`, `keyNameMinor`), and the two
  //          cannot disagree in any language the application ships. They are two implementations
  //          because this package must not depend on a translation catalogue, and the domain must
  //          be able to print a key with nothing but the model.
  // KEYWORDS: key-name, notation, d27, not-translated, engraving, single-definition
  /// Returns the key's own letter name and mode word, for example `Eb major`.
  String get name => '$tonic ${mode == Mode.major ? 'major' : 'minor'}';

  // PURPOSE: Render the key for spike logs and test failure messages.
  // INPUTS: None.
  // OUTPUTS: Exactly [name]. It is not a separate formatting rule: a log line and a page state the
  //          same fact, and two formats would be two answers to "what is this key called". The
  //          override exists only so that interpolating a key into a string needs no call.
  // KEYWORDS: rendering, diagnostics, formatting, single-definition
  @override
  String toString() => name;
}
