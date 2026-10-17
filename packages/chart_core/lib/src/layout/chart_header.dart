// PURPOSE: State, where the music begins, what the music is IN — its key and its meter — as part of
//          the ENGRAVING rather than as chrome. A musician holding a chart at a stand reads the key
//          and the meter off the page; before this value existed the key lived in the scene bar and
//          the meter appeared only on the rare bar that changed it, so the answer to "what key am I
//          in" required looking away from the music, at the one part of the screen the owner has
//          repeatedly asked to make smaller. A printed lead sheet states both where the music
//          starts; this is that statement, and it is placed, measured and published by the layout
//          engine so it moves and scales with the page and prints with it.
// INPUTS: The key the chart is shown in and the meter its first bar is counted in.
// OUTPUTS: A [PlacedChartHeader] carrying the words and the band they occupy on the FIRST page, or
//          nothing at all on every later page. The band's height is the measured line box of the
//          words in the chart's own chord style, so the cost is derived from the text rather than
//          picked.
// KEYWORDS: chart-header, key, meter, opening-statement, engraving, notation, d27, lead-sheet
//
// WHY A HEADER LINE AND NOT A BLOCK AT THE FIRST BAR, WHICH IS WHERE A PRINTED CHART PUTS IT. A
// printed chart puts the key signature and the time signature at the start of the first staff,
// inside the system, because a staff carries pitch and a key signature is a mark on five lines.
// This renderer has neither: the chord line is a grid of symbol boxes, and the melody staff is
// drawn without a key signature at all (there is no music font — A68 records the owner's verdict on
// the letter that stood in for a clef). So the two options were:
//
//   * A BLOCK AT THE FIRST BAR, which is where the eye looks — and it is the wrong place here for a
//     reason that is not aesthetic. The first cell of the first bar is a CHORD CELL: it may hold the
//     chart's opening chord, it is a tap target whose column is what the hit test names, and
//     `LayoutEngine._cellWidths` already refuses to let anything else (a melody note) widen a cell
//     because moving a column changes what a tap means. Writing `C major · 4/4` inside the bar would
//     either widen the first cell or be drawn over the chord the chart opens with.
//   * A HEADER LINE ABOVE THE FIRST SYSTEM, which says the same thing at the same point of the
//     reading order — before any music — in the chart's own ink, without taking a column from any
//     bar, and without touching the section label's band. It is what this file publishes.
//
// WHAT IT DELIBERATELY DOES NOT SAY. Not the transposition in semitones, which is a property of the
// VIEW and not of the chart: a chart printed from this application is in the key printed on it, and
// the interval from the written key is a fact of how the musician got there, which belongs in the
// control that changes it. Not the title, the composer or the tempo: the first two are the
// document's identity and belong to whatever prints a page's header block, and the third is a
// performance instruction rather than notation. And not a key signature: this renderer cannot draw
// one, and a wrong sign is worse than a word — so the key is written as a word, `C major`, which is
// notation in every language (owner decision D27) and is what the scene bar already writes.
import '../key.dart';
import '../song/time_signature.dart';
import 'geometry.dart';

/// The band the first page gives up to state its key and its meter, at the place the music begins.
///
/// One page's value, not one chart's: only the first page of a chart carries it, because it says
/// what the chart is written in and that is a fact a reader needs once.
class PlacedChartHeader {
  /// Creates a header drawing [text] inside [bounds].
  const PlacedChartHeader({required this.text, required this.bounds});

  /// The words, already composed: the key, a separator, and the meter, such as `C major · 4/4`.
  ///
  /// Composed here rather than by the painter for the reason every placed value is placed here: the
  /// layout measured these words and reserved the room they need, so a painter that composed its
  /// own string could reserve one line and draw another. Both parts are NOTATION and are not
  /// translated (D27); the separator is punctuation, not a word.
  final String text;

  /// The band the words occupy, in the page's engraved coordinates.
  ///
  /// It spans the content width and exactly the measured line box of [text], which is what makes
  /// the height the page gives up equal to the thing that fills it. The painter draws the words at
  /// this band's top-left corner, so the box reserved and the box drawn are one value.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedChartHeader &&
      other.text == text &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(text, bounds);

  @override
  String toString() => 'PlacedChartHeader("$text") at $bounds';
}

// PURPOSE: Compose the one line a chart prints about itself where its music begins, so that the
//          words and the room reserved for them cannot be produced by two different rules.
// INPUTS: key — the key the chart is shown in, whose name is notation and is never translated
//         (D27). meter — the meter the chart's first bar is counted in, which is the meter the
//         reader assumes from then on.
// OUTPUTS: The string the header draws, such as `C major · 4/4`. Never empty, for any key and any
//          meter the model can hold; a meter whose numerator and denominator are both positive
//          always has a string form, and a Key always has a name.
// KEYWORDS: chart-header, text-composition, notation, separator, d27
//
// WHY THIS ORDER AND THIS SEPARATOR. The KEY comes first because it is what changes the meaning of
// every chord on the page; the METER second, because it is what the bar lines count in and is read
// as one fact with the first bar. `·` separates them, which is the separator this interface already
// uses between two facts about one thing (the scene bar's key badge reads `C major · 0 st`, the
// chart title reads `Autumn Leaves · 8 bars`), so the chart and the chrome read as one voice rather
// than as two systems of punctuation.
//
// WHY `Key.name` AND NOT `Key.toString`. They return the same string, and that is why the getter
// exists: the engraving depends on a NAME, not on a diagnostics format that would then be free to
// change while the printed chart silently changed with it.
/// Returns the line a chart prints at the start of its music, such as `C major · 4/4`.
String chartOpeningText(Key key, TimeSignature meter) => '${key.name} · $meter';
