// PURPOSE: Model a chord the way a chart writes one — a root, a quality suffix, optional added
//          tensions, an optional slash bass and an optional parenthesised marking — so that the
//          transposer can move a chord without understanding what its quality means.
// INPUTS: A ChordRoot (sounding pitch plus an optional spelling override), a ChordQuality, a
//         list of tension tokens, an optional ChordRoot for the slash bass, and a parenthesised
//         flag.
// OUTPUTS: Immutable values. [Chord.render] turns one into the text a chart shows, in a given
//          key. Chord equality compares every part including the tension list by value, so two
//          chords built separately from the same data are equal.
// KEYWORDS: chord, chord-root, chord-quality, slash-chord, alterations, chart-notation
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
  final String token;

  @override
  bool operator ==(Object other) =>
      other is ChordQuality && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => token.isEmpty ? 'major triad' : token;
}

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
class Chord {
  /// Creates a chord from its [root], [quality], tension [alterations], optional slash [bass]
  /// and [parenthesised] marking.
  const Chord({
    required this.root,
    this.quality = ChordQuality.majorTriad,
    this.alterations = const <String>[],
    this.bass,
    this.parenthesised = false,
  });

  /// The root of the chord.
  final ChordRoot root;

  /// The quality suffix.
  final ChordQuality quality;

  /// Added tensions in chart order, such as `b9` or `#11`. Stored as their written tokens
  /// because they do not participate in transposition — a `b9` stays a `b9` when the root moves.
  final List<String> alterations;

  /// The slash bass, or null when the chord is in root position.
  final ChordRoot? bass;

  /// Whether the chart writes this chord in parentheses.
  final bool parenthesised;

  // PURPOSE: Render the chord as chart text in a given key, which is what a golden test or a
  //          spike log compares and what a musician finally reads.
  // INPUTS: key — the key in force. table — the spelling rule to apply.
  // OUTPUTS: Root, quality, tensions and slash bass concatenated in chart order; the slash bass
  //          is omitted when absent. A parenthesised chord is wrapped in round brackets.
  // KEYWORDS: rendering, chart-notation, slash-chord, golden
  /// Returns this chord as the text a chart shows in [key].
  String render(Key key, SpellingTable table) {
    final StringBuffer buffer = StringBuffer();
    if (parenthesised) {
      buffer.write('(');
    }
    buffer.write(root.spellIn(key, table).toString());
    buffer.write(quality.token);
    for (final String alteration in alterations) {
      buffer.write(alteration);
    }
    final ChordRoot? slash = bass;
    if (slash != null) {
      buffer.write('/');
      buffer.write(slash.spellIn(key, table).toString());
    }
    if (parenthesised) {
      buffer.write(')');
    }
    return buffer.toString();
  }

  // PURPOSE: Compare chords by value so that a transposition test can assert equality of whole
  //          chords rather than of rendered strings, which would hide a spelling change behind
  //          a formatting coincidence.
  // INPUTS: other — any object.
  // OUTPUTS: True when every part matches and the tension lists are equal element by element.
  //          Implemented directly rather than with a collection helper because chart_core's
  //          dependency list is empty by design and equality of two short string lists does not
  //          justify the first one.
  // KEYWORDS: equality, value-semantics, list-equality
  @override
  bool operator ==(Object other) {
    if (other is! Chord) {
      return false;
    }
    if (other.root != root ||
        other.quality != quality ||
        other.bass != bass ||
        other.parenthesised != parenthesised ||
        other.alterations.length != alterations.length) {
      return false;
    }
    for (int index = 0; index < alterations.length; index++) {
      if (other.alterations[index] != alterations[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    root,
    quality,
    bass,
    parenthesised,
    Object.hashAll(alterations),
  );

  @override
  String toString() =>
      'Chord($root${quality.token.isEmpty ? '' : quality.token}'
      '${alterations.join()}${bass == null ? '' : '/$bass'})';
}
