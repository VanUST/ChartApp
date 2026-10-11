// PURPOSE: Model a chord the way a chart writes one — a root, a quality suffix carrying its
//          tensions, an optional slash bass and an optional alternate chord — so that the
//          transposer can move a chord without understanding what its quality means.
// INPUTS: A ChordRoot (sounding pitch plus an optional spelling override), a ChordQuality, an
//         optional ChordRoot for the slash bass, and an optional nested Chord for the alternate.
// OUTPUTS: Immutable values. [Chord.render] turns one into the text a chart shows, in a given
//          key. Chord equality compares every part, including the nested alternate, so two chords
//          built separately from the same data are equal.
// KEYWORDS: chord, chord-root, chord-quality, slash-chord, alternate-chord, chart-notation
import 'key.dart';
import 'pitch.dart';
import 'spelling_table.dart';

/// The quality suffix of a chord, such as `m7` or `maj7`.
///
/// The token is stored rather than an enum because the canonical vocabulary is fixed by the
/// iReal codec, which is not written yet: inventing a closed enum now would either miss
/// qualities real charts use or bake in names that the codec then has to map around. The
/// transposer treats the token as opaque, so nothing outside the codec depends on the list
/// below being complete — it exists so that ordinary call sites do not pass bare strings.
class ChordQuality {
  /// Creates a quality from its canonical [token]. A major triad is the empty token, which is
  /// how charts write it: `C`, not `Cmaj`.
  const ChordQuality(this.token);

  /// A major triad, written with no suffix.
  static const ChordQuality majorTriad = ChordQuality('');

  /// A minor triad.
  static const ChordQuality minorTriad = ChordQuality('m');

  /// A dominant seventh.
  static const ChordQuality dominantSeventh = ChordQuality('7');

  /// A minor seventh.
  static const ChordQuality minorSeventh = ChordQuality('m7');

  /// A major seventh.
  static const ChordQuality majorSeventh = ChordQuality('maj7');

  /// A diminished triad.
  static const ChordQuality diminished = ChordQuality('dim');

  /// A half-diminished seventh.
  static const ChordQuality halfDiminished = ChordQuality('m7b5');

  /// An augmented triad.
  static const ChordQuality augmented = ChordQuality('aug');

  /// A suspended fourth.
  static const ChordQuality suspendedFourth = ChordQuality('sus4');

  /// The canonical suffix as it appears on a chart.
  ///
  /// **EMPTY IS MEANINGFUL: a major triad is written with no suffix**, so this string is what the
  /// chart PRINTS and is not what a button should be LABELLED with. The two were the same value once
  /// and the result was a blank button — see [chordQualityLabel].
  final String token;

  @override
  bool operator ==(Object other) =>
      other is ChordQuality && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => token.isEmpty ? 'major triad' : token;
}

// PURPOSE: Give a chip that SELECTS a chord quality something a musician can read, which the token
//          cannot always be.
// INPUTS: quality — the quality a chip will apply when tapped.
// OUTPUTS: A non-empty label. `maj` for a major triad and the token for everything else. Never empty,
//          because a chip's label is the only thing that says what the chip does.
// KEYWORDS: chord-quality, chip-label, blank-button, notation-not-interface
/// The label a chip shows for [quality], which is NOT always its token.
///
/// **THE TOKEN AND THE LABEL ARE DIFFERENT FIELDS, AND CONFLATING THEM PRODUCED A BLANK BUTTON.** A
/// major triad's token is the EMPTY STRING, and that is right: a chart writes a major triad as the
/// root alone, so `B` is the correct symbol and `Bmaj` is not. But the chip that SELECTS a major
/// triad was labelled with that same empty string, so the first button in the palette's quality row
/// had nothing written on it — a musician tapped a blank chip, the app wrote a major triad, and the
/// chart showed `B`. The data was correct and the INTERFACE lied about what it would write.
///
/// NOT TRANSLATED, on the rule A53 states and D27 records: a chord's spelling is notation, and `m7`
/// reads the same in every language.
String chordQualityLabel(ChordQuality quality) =>
    quality.token.isEmpty ? 'maj' : quality.token;

/// The bass note of a chord: its sounding pitch plus an optional spelling override.
class ChordRoot {
  /// Creates a root at [semitones] above C, with an optional spelling [preference].
  ///
  /// [semitones] is stored unreduced so that a transposition can be expressed as an addition
  /// without an intermediate normalization; [pitchClass] reduces it on read.
  const ChordRoot(
    this.semitones, {
    this.preference = SpellingPreference.automatic,
  });

  /// Semitones above C. Any integer is accepted.
  final int semitones;

  /// Whether this note overrides the key's accidental direction, and which way.
  final SpellingPreference preference;

  /// The sounding pitch class, in `[0, 11]`.
  int get pitchClass => normalizePitchClass(semitones);

  // PURPOSE: Produce the written form of this root in a key, so that rendering a chord and
  //          testing a transposition both go through exactly one spelling rule.
  // INPUTS: key — the key the chart is written in. table — the spelling rule to apply.
  // OUTPUTS: The WrittenNote the table chooses for this pitch class and preference.
  // KEYWORDS: spelling, rendering, key-context
  /// Returns this root's written form in [key], spelled by [table].
  WrittenNote spellIn(Key key, SpellingTable table) =>
      table.spell(pitchClass, key, preference: preference);

  // PURPOSE: Compare roots by SOUNDING pitch and spelling override, not by the raw semitone
  //          count, so that a root of 12 semitones equals one of 0 and a transposition by a full
  //          octave is recognisable as the identity.
  // INPUTS: other — any object.
  // OUTPUTS: True for a ChordRoot with the same pitch class and the same preference.
  // KEYWORDS: equality, pitch-class, normalization, octave
  @override
  bool operator ==(Object other) =>
      other is ChordRoot &&
      other.pitchClass == pitchClass &&
      other.preference == preference;

  @override
  int get hashCode => Object.hash(pitchClass, preference);

  @override
  String toString() => 'root(pc=$pitchClass, $preference)';
}

/// A chord as it appears on a chart.
///
/// The shape is taken from the format rather than invented, and two earlier guesses were removed
/// once the iReal protocol document was read:
///
///   - There is no separate list of tensions. `7b9`, `^7#11` and `add9` are single quality
///     suffixes, and splitting them into a quality plus a list of alterations would mean the
///     codec had to reassemble one token from two fields on every round trip.
///   - Parentheses do not mark a chord as parenthesised. `(Db^7/F)` is an ALTERNATE chord drawn
///     small above the main one, so it is a chord in its own right and carries its own root,
///     quality and bass. A boolean could not have expressed that, and transposing it would have
///     been forgotten.
class Chord {
  /// Creates a chord from its [root], [quality], optional slash [bass] and optional [alternate].
  const Chord({
    required this.root,
    this.quality = ChordQuality.majorTriad,
    this.bass,
    this.alternate,
  });

  /// The root of the chord.
  final ChordRoot root;

  /// The quality suffix, carrying any tensions: `m7`, `7b9`, `^7#11`, or empty for a major triad.
  final ChordQuality quality;

  /// The slash bass, or null when the chord is in root position.
  final ChordRoot? bass;

  /// The alternate chord drawn above this one, or null when there is none.
  ///
  /// Nested rather than flagged, because an alternate is a whole chord: it has its own root, its
  /// own quality and possibly its own bass. It transposes with the chord it sits above, which is
  /// why [Transposer.transposeChord] recurses into it.
  final Chord? alternate;

  // PURPOSE: Render the chord as chart text in a given key, which is what a golden test or a
  //          spike log compares and what a musician finally reads.
  // INPUTS: key — the key in force. table — the spelling rule to apply.
  // OUTPUTS: Root, quality and slash bass concatenated in chart order, and then the alternate
  //          chord wrapped in parentheses when there is one. The rendering round-trips: parsing
  //          the output of a chord imported from a chart returns the same chord.
  // KEYWORDS: rendering, chart-notation, slash-chord, alternate-chord, golden
  /// Returns this chord as the text a chart shows in [key].
  String render(Key key, SpellingTable table) {
    final StringBuffer buffer = StringBuffer();
    buffer.write(root.spellIn(key, table).toString());
    buffer.write(quality.token);
    final ChordRoot? slash = bass;
    if (slash != null) {
      buffer.write('/');
      buffer.write(slash.spellIn(key, table).toString());
    }
    final Chord? above = alternate;
    if (above != null) {
      buffer.write('(');
      buffer.write(above.render(key, table));
      buffer.write(')');
    }
    return buffer.toString();
  }

  // PURPOSE: Compare chords by value so that a transposition test can assert equality of whole
  //          chords rather than of rendered strings, which would hide a spelling change behind a
  //          formatting coincidence.
  // INPUTS: other — any object.
  // OUTPUTS: True when root, quality, bass and alternate all match. Implemented directly rather
  //          than with a collection helper, because the only collection this class ever had is
  //          gone and chart_core's dependency list is empty by design.
  // KEYWORDS: equality, value-semantics, nested-chord
  @override
  bool operator ==(Object other) =>
      other is Chord &&
      other.root == root &&
      other.quality == quality &&
      other.bass == bass &&
      other.alternate == alternate;

  @override
  int get hashCode => Object.hash(root, quality, bass, alternate);

  @override
  String toString() =>
      'Chord($root${quality.token}${bass == null ? '' : '/$bass'}'
      '${alternate == null ? '' : ' ($alternate)'})';
}
