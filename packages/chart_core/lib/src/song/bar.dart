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
import '../anchored_place.dart';
import '../chord.dart';
import 'note.dart';
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

  /// THE MUSICIAN'S OWN LINE BREAK: the next system begins at the bar after this one.
  ///
  /// WHY THIS IS A BAR MARK AND NOT A LAYOUT SETTING. The owner agreed to four line-breaking rules,
  /// and the third of them is that a musician may break a line himself. A break is a decision about
  /// the chart — it belongs to a bar, it survives being saved, reopened and re-engraved on another
  /// device, and it must be undoable — so it travels the same road as the segno and the fermata
  /// rather than living in a screen's state. It is written by `mark.set`, stored as its own name in
  /// the file, and read by the layout engine's system builder ([LayoutEngine._buildSystems]), which
  /// is the only consumer: it is an instruction to the PAGE, so no glyph stands for it. A system
  /// that ends because the musician said so is the whole of how it is seen.
  ///
  /// IT IS NOT IMPORTED AND CANNOT BE. iReal writes no such sign; the importer's letters map to the
  /// four musical marks above, so a chart that arrives from `.irealb` never carries a break — which
  /// is right, because a break is a decision made about a page that does not exist until this
  /// application lays one out.
  lineBreak,
}

/// The size a chord is engraved at, which persists until changed.
enum ChordSize {
  /// Normal size, written `l`.
  normal,

  /// Small size, written `s`.
  small,
}

/// How much room one bar is given on the page, as a multiple of the room its own content needs.
///
/// WHY A BAR'S WIDTH IS A PROPERTY OF THE BAR AND NOT OF THE VIEW. A jazz chart's bars are not
/// equal: one bar holds a single chord and four beats, and the next holds six chords, a run of
/// eighths and an accidental. An engraving that gives every bar the width its own content measures
/// therefore starves the busy bar and wastes the empty one — and a bar is where this application
/// writes chords, notes AND handwriting, so the shortage is felt three times in the same rectangle.
/// The owner asked for the room to follow the music, in his own words: «менять видимый размер
/// каждого конкретного такта, чтобы уместить больше внутри». The value is stored on the bar, in
/// the document, and not in the screen's state, because it is the musician's decision about the
/// chart: a chart opened on another device, or reopened next week, must look the way he set it.
///
/// WHY IT IS A MULTIPLE AND NOT A NUMBER OF PIXELS. The natural width is not a constant: it is
/// measured from the chords' own text, in the key they are spelled in, with the style's own metrics
/// — so it changes when the chart is transposed and when the engraving's proportions change. A
/// stored absolute width would be a second opinion about a number the engraver already decides, and
/// the first time the two disagreed the bar would be drawn at one width and measured at another.
/// A multiple of the measurement cannot disagree with it, and it is what "this bar needs more room
/// than the one next to it" actually means.
///
/// WHY THE FACTOR NEVER GOES BELOW 1. The surplus room a bar has is distributed evenly over its
/// cells, so a factor below 1 would take room away from EVERY cell — including the ones holding
/// chords — and a chord wider than the column it was measured into is drawn over its neighbour on
/// the chord line. Making a narrower bar safe would need a second rule for how a deficit is shared
/// out, which is exactly the second source of truth this coordinate system cannot afford; so the
/// bar's own content is the floor and this property only ever ADDS room. A bar that is too wide is
/// put back by stepping down the ladder, and the ladder's bottom rung IS the natural bar.
class BarSize {
  /// Creates a size [factor] times the bar's natural width.
  ///
  /// The [factor] must be at least 1: see the class's note on why a bar is never engraved narrower
  /// than its own content needs. The check is an assert because this is the model's invariant and a
  /// violation is a programmer's error, not a musician's; a value arriving from a file or a typed
  /// form is checked by the reader that decodes it, because a decode path must not depend on
  /// asserts being enabled.
  const BarSize(this.factor)
    : assert(
        factor >= 1,
        'a bar cannot be narrower than its own '
        'content: the factor must be at least 1',
      );

  /// The size of a bar nobody has resized: exactly the width its own content needs.
  ///
  /// This is the default every bar carries, and it is what makes a chart that never used this
  /// property engrave exactly the page it engraved before the property existed.
  static const BarSize natural = BarSize(1);

  /// The rungs the surface's control steps through, narrowest first.
  ///
  /// THE RUNGS ARE PART OF THE PROPERTY'S DOMAIN rather than of one screen's taste: the model
  /// accepts any factor at or above 1, and this list is what a musician can reach with a press.
  /// The steps grow (1, 1.25, 1.5, 2, 2.5, 3) rather than being evenly spaced, because the first
  /// step is the one that has to be small enough to be an adjustment and the last ones only have to
  /// be reachable: a bar at ×3 is 216 page pixels of chord line where a 5-cell bar was 88.
  ///
  /// Every value is an exact binary fraction, so a factor written to a file and read back is the
  /// SAME double and `BarSize(1.25) == BarSize(1.25)` holds after a round trip with no tolerance.
  static const List<BarSize> ladder = <BarSize>[
    natural,
    BarSize(1.25),
    BarSize(1.5),
    BarSize(2),
    BarSize(2.5),
    BarSize(3),
  ];

  /// The multiple of the bar's natural width this bar is drawn at.
  final double factor;

  /// Whether this bar is engraved at its natural width, which is the state of every bar that was
  /// never resized and the state a reset returns it to.
  bool get isNatural => factor == 1;

  /// The next rung up the [ladder], or null when this bar is already at the top.
  BarSize? get wider {
    for (int index = 0; index + 1 < ladder.length; index++) {
      if (ladder[index].factor >= factor) {
        return ladder[index + 1];
      }
    }
    return null;
  }

  /// The next rung down the [ladder], or null when this bar is already as narrow as it may be.
  BarSize? get narrower {
    for (int index = ladder.length - 1; index > 0; index--) {
      if (ladder[index].factor <= factor) {
        return ladder[index - 1];
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is BarSize && other.factor == factor;

  @override
  int get hashCode => factor.hashCode;

  @override
  String toString() => isNatural ? 'BarSize(natural)' : 'BarSize(x$factor)';
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

/// A chord written at a place in a bar.
///
/// ITS HORIZONTAL OFFSET IS ITS TIME. The owner removed the grid as a class — a chord is not "on
/// beat two", it is "written here" — so this value carries an [AnchoredPlace] instead of a beat
/// index and a step. The place's anchor names the bar the mark lives in; the bar it is stored in
/// and the anchor that says so must agree, which the operation log enforces when it inserts,
/// replaces or deletes one.
///
/// WHY THE ANCHOR IS STILL STORED, ALTHOUGH THE BAR ALREADY HOLDS THE MARK. A bar's address is an
/// INDEX inside its section, so `measure.insert` renumbers every bar after it. A mark that carried
/// only an offset would have no way to say which bar it was written against when a bar is
/// duplicated or a section is reordered; with the anchor on the mark, the reducer can rewrite it
/// from the position the mark was FOUND at (see `DocumentReducer._anchoredBars`), which turns "the
/// address is right" from a thing to remember into a thing the model enforces. The redundancy is
/// therefore checkable, and it is checked on every mutation rather than trusted.
class ChordMark {
  /// Creates a placement of [chord] at [place], engraved [size].
  const ChordMark({
    required this.place,
    required this.chord,
    this.size = ChordSize.normal,
  });

  /// Where the chord is written: its bar, and its distance along that bar.
  final AnchoredPlace place;

  /// The chord that sounds.
  final Chord chord;

  /// The size this chord is engraved at.
  final ChordSize size;

  /// Where the chord sits along its bar, in bar-local logical pixels. This is its time.
  double get offsetX => place.offsetX;

  /// Returns a copy of this mark with the given fields replaced.
  ChordMark copyWith({AnchoredPlace? place, Chord? chord, ChordSize? size}) =>
      ChordMark(
        place: place ?? this.place,
        chord: chord ?? this.chord,
        size: size ?? this.size,
      );

  @override
  bool operator ==(Object other) =>
      other is ChordMark &&
      other.place == place &&
      other.chord == chord &&
      other.size == size;

  @override
  int get hashCode => Object.hash(place, chord, size);

  @override
  String toString() =>
      'x${place.offsetX.toStringAsFixed(1)}: $chord'
      '${size == ChordSize.small ? ' (small)' : ''}';
}

/// One bar of a chart, as written.
class Bar {
  /// Creates a bar in [timeSignature] with the given contents and signs.
  const Bar({
    this.timeSignature = TimeSignature.fourFour,
    this.size = BarSize.natural,
    this.chords = const <ChordMark>[],
    this.openingBarline = Barline.single,
    this.closingBarline = Barline.single,
    this.volta,
    this.repeatPrevious = RepeatPrevious.none,
    this.slashRepeat = false,
    this.noChord = false,
    this.marks = const <BarMark>{},
    this.staffText = const <String>[],
    this.melody = const <NoteMark>[],
    this.percussion = const <PercussionMark>[],
  });

  /// The meter in force for this bar.
  final TimeSignature timeSignature;

  /// How much room this bar is given on the page, relative to the room its content needs.
  ///
  /// The musician's own decision, stored in the document rather than in a screen's state, because a
  /// chart opened on another device must look the way he set it. Every bar starts at
  /// [BarSize.natural], which is the width the engraver measured before this property existed, so a
  /// chart that never sets it is engraved exactly as it was. See [BarSize] for why it is a multiple
  /// of the natural width and why it never goes below 1.
  final BarSize size;

  /// Chord placements, ordered by their place along the bar. Empty means the previous chord
  /// sustains.
  final List<ChordMark> chords;

  /// Pitched notes on the melodic staff, each at its own place along the bar.
  ///
  /// Empty when the song has no melodic staff, which is every imported chart. The two lists are
  /// independent on purpose: owner decision D16 puts the pitched staff and the chord line in the
  /// same document simultaneously, so a bar carries both rather than one replacing the other.
  final List<NoteMark> melody;

  /// Percussion hits on the drum staff, each at its own place along the bar.
  ///
  /// Empty when the song has no drum part. A hit's instrument is a drum-map key, never transposed.
  final List<PercussionMark> percussion;

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
        other.size != size ||
        other.openingBarline != openingBarline ||
        other.closingBarline != closingBarline ||
        other.volta != volta ||
        other.repeatPrevious != repeatPrevious ||
        other.slashRepeat != slashRepeat ||
        other.noChord != noChord ||
        other.staffText.length != staffText.length ||
        other.chords.length != chords.length ||
        other.melody.length != melody.length ||
        other.percussion.length != percussion.length ||
        !other.marks.containsAll(marks) ||
        !marks.containsAll(other.marks)) {
      return false;
    }
    for (int index = 0; index < chords.length; index++) {
      if (other.chords[index] != chords[index]) {
        return false;
      }
    }
    for (int index = 0; index < melody.length; index++) {
      if (other.melody[index] != melody[index]) {
        return false;
      }
    }
    for (int index = 0; index < percussion.length; index++) {
      if (other.percussion[index] != percussion[index]) {
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
    size,
    Object.hashAll(chords),
    Object.hashAll(melody),
    Object.hashAll(percussion),
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
      'Bar($openingBarline, ${chords.length} chord(s)'
      '${melody.isEmpty ? '' : ', ${melody.length} note(s)'}'
      '${percussion.isEmpty ? '' : ', ${percussion.length} hit(s)'}, $closingBarline'
      '${size.isNatural ? '' : ', $size'}'
      '${volta == null ? '' : ', $volta'}'
      '${repeatPrevious == RepeatPrevious.none ? '' : ', $repeatPrevious'}'
      '${slashRepeat ? ', slash' : ''}${noChord ? ', N.C.' : ''})';
}
