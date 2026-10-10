// PURPOSE: Model one bar as written, carrying both what is played in it and the structural signs
//          drawn around it. Keeping the signs on the bar, rather than in a separate repeat tree,
//          is what makes a bar addressable by its index inside a section — which is exactly the
//          address an annotation anchor uses, so an anchor does not become a path of indices
//          that a single inserted bar would invalidate.
// INPUTS: A meter, a sparse list of chord placements, the structural signs, and any staff text.
// OUTPUTS: An immutable Bar. A bar with no chord placements is valid and common: it means the
//          previous chord sustains, which is how a chart writes two bars of one chord. Bar
//          equality compares every part including the chord list in order.
// KEYWORDS: bar, measure, barline, repeat, volta, ending, segno, coda, staff-text, anchor-address
import '../chord.dart';
import 'time_signature.dart';

/// How a bar is bounded on one side.
enum Barline {
  /// A single barline, written `|`.
  single,

  /// A double barline, written `[` on the left of a group or `]` on its right. The side the bar
  /// sits on says which of the two it is, so one value covers both.
  double,

  /// A repeat start, written `{`.
  repeatStart,

  /// A repeat end, written `}`.
  repeatEnd,

  /// The final thick double barline, written `Z`, ending the tune.
  finalBar,
}

/// The symbol meaning "play the previous bar again", which is stateful: it refers to music the
/// bar itself does not contain.
enum RepeatPrevious {
  /// No repeat-previous symbol.
  none,

  /// Repeat the previous single bar, written `x`.
  oneBar,

  /// Repeat the previous two bars, written `r`.
  twoBars,
}

/// A symbol drawn on a bar that is not a chord.
enum BarMark {
  /// A segno sign, written `S`.
  segno,

  /// A coda sign, written `Q`.
  coda,

  /// A fermata, written `f`.
  fermata,

  /// The player's stop, written `U`.
  playerEnding,
}

/// The size a chord is engraved at, which persists until changed.
enum ChordSize {
  /// Normal size, written `l`.
  normal,

  /// Small size, written `s`.
  small,
}

/// An alternative-ending bracket.
///
/// Number 0 is an UNNUMBERED bracket: iReal writes `N0` for an ending with no figure in it, and
/// that is a different thing from no bracket at all, which is [Bar.volta] being null.
class Volta {
  /// Creates a bracket numbered [number], where 0 means the bracket carries no figure.
  const Volta(this.number);

  /// The figure written in the bracket, or 0 when it carries none.
  final int number;

  @override
  bool operator ==(Object other) => other is Volta && other.number == number;

  @override
  int get hashCode => number.hashCode;

  @override
  String toString() => number == 0 ? 'volta(unnumbered)' : 'volta($number)';
}

/// A chord placed on a beat of a bar.
class BeatChord {
  /// Creates a placement of [chord] on [beat], at [step] within that beat, engraved [size].
  const BeatChord({
    required this.chord,
    required this.beat,
    this.step = 0,
    this.size = ChordSize.normal,
  });

  /// The chord that sounds.
  final Chord chord;

  /// Zero-based cell index inside the bar.
  final int beat;

  /// Order within [beat] when several chords share it.
  ///
  /// A chart writes two chords in one cell with a comma, which packs them without consuming a
  /// second cell. This is why an anchor needs a step as well as a beat: both chords are on the
  /// same beat and they are different places in the bar.
  final int step;

  /// The size this chord is engraved at.
  final ChordSize size;

  @override
  bool operator ==(Object other) =>
      other is BeatChord &&
      other.chord == chord &&
      other.beat == beat &&
      other.step == step &&
      other.size == size;

  @override
  int get hashCode => Object.hash(chord, beat, step, size);

  @override
  String toString() =>
      'beat $beat.$step: $chord${size == ChordSize.small ? ' (small)' : ''}';
}

/// One bar of a chart, as written.
class Bar {
  /// Creates a bar in [timeSignature] with the given contents and signs.
  const Bar({
    this.timeSignature = TimeSignature.fourFour,
    this.chords = const <BeatChord>[],
    this.openingBarline = Barline.single,
    this.closingBarline = Barline.single,
    this.volta,
    this.repeatPrevious = RepeatPrevious.none,
    this.slashRepeat = false,
    this.noChord = false,
    this.marks = const <BarMark>{},
    this.staffText = const <String>[],
  });

  /// The meter in force for this bar.
  final TimeSignature timeSignature;

  /// Chord placements, ordered by beat and then by step. Empty means the previous chord sustains.
  final List<BeatChord> chords;

  /// The barline drawn at the left edge.
  final Barline openingBarline;

  /// The barline drawn at the right edge.
  final Barline closingBarline;

  /// The alternative-ending bracket this bar sits under, or null when it sits under none.
  final Volta? volta;

  /// Whether this bar says "play the previous bar again".
  final RepeatPrevious repeatPrevious;

  /// Whether this bar is marked with the slash repeat, meaning repeat the previous chord in
  /// place rather than repeat a bar.
  final bool slashRepeat;

  /// Whether this bar is marked N.C., silencing chords for its duration.
  final bool noChord;

  /// Signs drawn on this bar.
  final Set<BarMark> marks;

  /// Staff text carried by this bar, preserved verbatim.
  ///
  /// Kept as the literal text rather than parsed into navigation commands, because whether a
  /// given phrase means "go to the coda" depends on a reading of the whole chart that belongs in
  /// the play-order expansion, not in the bar. Preserving it verbatim also means an import can
  /// round-trip text it does not yet understand instead of dropping it.
  final List<String> staffText;

  /// Whether this bar starts a repeated passage.
  bool get startsRepeat => openingBarline == Barline.repeatStart;

  /// Whether this bar closes a repeated passage.
  bool get endsRepeat => closingBarline == Barline.repeatEnd;

  @override
  bool operator ==(Object other) {
    if (other is! Bar) {
      return false;
    }
    if (other.timeSignature != timeSignature ||
        other.openingBarline != openingBarline ||
        other.closingBarline != closingBarline ||
        other.volta != volta ||
        other.repeatPrevious != repeatPrevious ||
        other.slashRepeat != slashRepeat ||
        other.noChord != noChord ||
        other.staffText.length != staffText.length ||
        other.chords.length != chords.length ||
        !other.marks.containsAll(marks) ||
        !marks.containsAll(other.marks)) {
      return false;
    }
    for (int index = 0; index < chords.length; index++) {
      if (other.chords[index] != chords[index]) {
        return false;
      }
    }
    for (int index = 0; index < staffText.length; index++) {
      if (other.staffText[index] != staffText[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    timeSignature,
    Object.hashAll(chords),
    openingBarline,
    closingBarline,
    volta,
    repeatPrevious,
    slashRepeat,
    noChord,
    Object.hashAllUnordered(marks),
    Object.hashAll(staffText),
  );

  @override
  String toString() =>
      'Bar($openingBarline, ${chords.length} chord(s), $closingBarline'
      '${volta == null ? '' : ', $volta'}'
      '${repeatPrevious == RepeatPrevious.none ? '' : ', $repeatPrevious'}'
      '${slashRepeat ? ', slash' : ''}${noChord ? ', N.C.' : ''})';
}
