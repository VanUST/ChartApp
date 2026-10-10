// PURPOSE: Name the chords a musician can put in a selected cell, as a value the UI can render
//          without knowing anything about keys — the roots this key's chart would write, their
//          degree labels, and the qualities a chart actually uses. This is the domain half of the
//          edit loop: it decides WHAT a musician may choose, and the sheet that draws it decides
//          only where the buttons go.
// INPUTS: A written [Key], which fixes the accidental direction every root is spelled in and
//         therefore the letters a musician reads; and a [SpellingTable], injected so measurement
//         and rendering share one speller.
// OUTPUTS: Twelve [ChordRootChoice] values per key, one per pitch class, ordered so that the key's
//          own seven degrees come first and its alterations follow in pitch order. Every choice
//          carries the spelled root and its scale-degree label (1, 2, b3, …). Twelve is not a
//          limit of the model but of the ear: there are twelve pitch classes, and a palette that
//          offered the same sounding root twice in two spellings would be offering a choice with
//          no audible difference.
// KEYWORDS: chord-palette, chord-root, scale-degree, spelling, editing, vocabulary, d2
//
// WHY ONLY THE KEY'S OWN DEGREES COME FIRST.
//
// Owner decision D2 asks for a "diatonic predictive row": the chords a musician is most likely to
// write next, offered before the ones they are not. Within one cell the honest predictor is the
// key, because that is the only context the document carries — there is no harmonic analysis in
// this project, and a guess dressed up as a prediction would be harder to notice than an order
// that is merely a convention. So the key's seven degrees are the first seven cells, in scale
// order, and the five chromatic roots follow: the musicians's hand reaches the common case first
// without the uncommon case being hidden behind another tap.
//
// WHY THE STICKY QUALITY IS NOT IN THIS FILE.
//
// D2 also asks for "sticky parameters": a quality chosen for one cell staying chosen for the next.
// That is interaction state — it belongs to the sheet, which remembers it for its own lifetime —
// and putting it here would make a pure function of the key depend on what the user did last.

import '../chord.dart';
import '../key.dart';
import '../pitch.dart';
import '../spelling_table.dart';

/// One root a musician can put in the selected cell, as this key would write it.
class ChordRootChoice {
  /// Creates the choice whose written root is [written], labelled [degreeLabel], sounding
  /// [pitchClass] semitones above C.
  const ChordRootChoice({
    required this.written,
    required this.degreeLabel,
    required this.pitchClass,
  });

  /// The root as a chart writes it in the key being edited, such as `Eb`.
  ///
  /// This is the label the palette shows. It is a [WrittenNote] and not a pitch class because a
  /// palette that showed `D#` for the third of C minor would be harder to read than the `Eb` a
  /// musician writes, and because the same pitch class must be spelled the way the chip that
  /// carries it does.
  final WrittenNote written;

  /// The scale-degree label a musician reads, such as `1`, `2`, `b3` or `#4`.
  final String degreeLabel;

  /// The sounding pitch class of the root, in `[0, 11]`.
  final int pitchClass;

  // PURPOSE: Compare roots by what they say, so a sheet can mark the chord already in the cell
  //          without comparing spellings and pitch classes separately at every call site.
  // INPUTS: other — any object.
  // OUTPUTS: True for a choice with the same written root and the same degree label. Two choices
  //          of one pitch class in one key are the same cell, and the key guarantees it.
  // KEYWORDS: equality, value-semantics, selection-state
  @override
  bool operator ==(Object other) =>
      other is ChordRootChoice &&
      other.written == written &&
      other.degreeLabel == degreeLabel &&
      other.pitchClass == pitchClass;

  @override
  int get hashCode => Object.hash(written, degreeLabel, pitchClass);

  @override
  String toString() => '$written ($degreeLabel)';
}

/// The qualities a chord palette offers, in the order a sheet should draw them.
///
/// Six, chosen so that every one is a symbol a chart of standards actually prints rather than a
/// theoretical possibility, and so that the most common comes first: a major triad and a minor
/// triad are the two every tune is built from, `7` and `m7` are the two the repertoire is built
/// from, and `^7`, `m7b5` and `dim` cover the tonic major, the half-diminished and the diminished
/// that a jazz chart writes constantly. Deliberately absent: `aug` and `sus4`, which are rare
/// enough that a quality row carrying them would cost a row of the sheet on a phone for something
/// a musician meets once in a set. This is a decision about the PALETTE's content and not about
/// the model, which accepts any token.
///
/// The list is the one place the palette and the sheet agree on the vocabulary, so a quality added
/// here appears in the UI without a second edit and cannot appear twice.
const List<ChordQuality> chordPaletteQualities = <ChordQuality>[
  ChordQuality.majorTriad,
  ChordQuality.minorTriad,
  ChordQuality.dominantSeventh,
  ChordQuality.minorSeventh,
  ChordQuality.majorSeventh,
  ChordQuality.halfDiminished,
  ChordQuality.diminished,
];

/// The sounding intervals of the seven degrees of a major scale, in semitones above the tonic.
const List<int> _majorDegreeIntervals = <int>[0, 2, 4, 5, 7, 9, 11];

/// The sounding intervals of the seven degrees of a natural minor scale, in semitones.
const List<int> _naturalMinorDegreeIntervals = <int>[0, 2, 3, 5, 7, 8, 10];

/// The chromatic degrees, in pitch order, as the pair of a semitone above the tonic and the label
/// a chart writes.
///
/// A flattened degree is preferred to a raised one everywhere it exists — `b3` rather than `#2`,
/// `b5` rather than `#4` — because that is the direction the key's own spelling rule takes for a
/// chromatic note in a key with no signature (see [Key.prefersSharps]) and because these are the
/// labels a player of the repertoire reads, where the borrowed chord is a flattened degree of the
/// key far more often than a raised one.
const List<(int, String)> _chromaticDegrees = <(int, String)>[
  (1, 'b2'),
  (3, 'b3'),
  (6, 'b5'),
  (8, 'b6'),
  (10, 'b7'),
];

// PURPOSE: Offer the twelve roots a musician can write in one cell of a chart in [key], spelled
//          the way that key spells them, so the palette and the page cannot disagree about what a
//          chord is called.
// INPUTS: key — the key the chart is written in. table — the spelling rule to use; injected so a
//         caller that measures text with an instance other than the default still gets the same
//         spellings.
// OUTPUTS: Exactly twelve choices, the key's own seven degrees first in scale order and its five
//          chromatic degrees after them in pitch order. The list is keyed by pitch class, so no
//          sounding root appears twice; a key whose tonic is spelled beyond the seven letters of
//          staff notation — which the spelling table can produce but the model is not limited to —
//          still returns twelve, because the degree letters are walked from the tonic by letter
//          and the pitch class is reduced.
// KEYWORDS: chord-palette, root-set, diatonic-first, key-spelling, total-function
/// Returns the twelve chord roots [key] offers, its own degrees first.
List<ChordRootChoice> chordRootChoicesFor(
  Key key, {
  SpellingTable table = const SpellingTable(),
}) {
  final List<ChordRootChoice> diatonic = <ChordRootChoice>[];
  final List<int> degreeIntervals = key.mode == Mode.major
      ? _majorDegreeIntervals
      : _naturalMinorDegreeIntervals;
  for (int degree = 0; degree < degreeIntervals.length; degree++) {
    final NoteLetter letter = key.tonic.letter.step(degree);
    final int pitchClass = normalizePitchClass(
      key.tonicPitchClass + degreeIntervals[degree],
    );
    diatonic.add(
      ChordRootChoice(
        // The degree is written on the letter the key's own scale puts it on, so its alteration is
        // the key signature's, not the spelling table's chroma attempt: in A minor the third is C,
        // written on C, not on B.
        written: WrittenNote(letter, shortestAlter(pitchClass, letter)),
        degreeLabel: '${degree + 1}',
        pitchClass: pitchClass,
      ),
    );
  }

  final Set<int> taken = <int>{
    for (final ChordRootChoice choice in diatonic) choice.pitchClass,
  };
  final List<ChordRootChoice> chromatic = <ChordRootChoice>[
    for (final (int interval, String label) in _chromaticDegrees)
      if (!taken.contains(normalizePitchClass(key.tonicPitchClass + interval)))
        ChordRootChoice(
          written: table.spell(
            normalizePitchClass(key.tonicPitchClass + interval),
            key,
            preference: SpellingPreference.flat,
          ),
          degreeLabel: label,
          pitchClass: normalizePitchClass(key.tonicPitchClass + interval),
        ),
  ];

  return <ChordRootChoice>[...diatonic, ...chromatic];
}

// PURPOSE: Build the chord a musician asked for out of a root choice and a quality, so the sheet
//          and the document cannot disagree about which chord a tap produced.
// INPUTS: root — the root choice, whose pitch class is the sounding root. quality — the suffix.
// OUTPUTS: A [Chord] in root position with no alternate. The root is built from the PITCH CLASS and
//          not from the written letter, because [ChordRoot] is a sounding value: the written form
//          is chosen later, by [Chord.render], in whatever key the chart is shown in. Nothing about
//          this constructor depends on the key the palette was drawn in.
// KEYWORDS: chord-construction, palette-application, sounding-versus-written
/// Returns the chord made of [root] and [quality].
Chord chordOf(ChordRootChoice root, ChordQuality quality) =>
    Chord(root: ChordRoot(root.pitchClass), quality: quality);
