// PURPOSE: State, where the music begins, what the music is IN — its key and its meter — as part of
//          the ENGRAVING rather than as chrome. A musician holding a chart at a stand reads the key
//          and the meter off the page. This value is that statement, and it is placed, measured and
//          published by the layout engine so it moves and scales with the page and prints with it.
// INPUTS: The key the chart is shown in and the meter its first bar is counted in.
// OUTPUTS: A [PlacedChartHeader] carrying the words and the band they occupy on the FIRST page, or
//          no header at all on every later page — [PageLayout.header] is null there. The band's
//          height is the measured line box of the words in the chart's own chord style, so the cost
//          is derived from the text rather than picked.
// KEYWORDS: chart-header, key, meter, opening-statement, engraving, notation, lead-sheet,
//           first-page-only
//
// WHY A HEADER LINE AND NOT A BLOCK AT THE FIRST BAR, WHICH IS WHERE A PRINTED CHART PUTS IT. A
// printed chart puts the key signature and the time signature at the start of the first staff,
// inside the system, because a staff carries pitch and a key signature is a mark on five lines. This
// renderer has neither: the chord row is where the music is drawn, and the first bar's own band is
// already carrying the chart's opening chord. So the two options were:
//
//   * A BLOCK AT THE FIRST BAR, which is where the eye looks — and it is the wrong place here for a
//     reason that is not aesthetic. The first bar's band holds the chart's opening chord, at an x
//     the model stores; a key-and-meter block written there would either collide with that chord or
//     have to move it, and moving a chord would be drawing a symbol somewhere the file does not say.
//   * A HEADER LINE ABOVE THE FIRST SYSTEM, which says the same thing at the same point of the
//     reading order — before any music — in the chart's own ink, without touching any bar and
//     without touching the section letter's band. It is what this file publishes.
//
// WHAT IT DELIBERATELY DOES NOT SAY. Not the transposition in semitones, which is a property of the
// VIEW and not of the chart: a chart printed from this application is in the key printed on it. Not
// the tempo or the style, which are performance instructions rather than notation. And not a key
// signature: this renderer has no music font and cannot draw one, and a wrong sign is worse than a
// word — so the key is written as a word, `C major`, which is notation in every language the owner
// reads and is what the scene bar already writes.
//
// WHY THE TITLE AND THE COMPOSER ARE NOT HERE, stated as a decision with its price. They are the
// document's identity, and on this surface the identity is already written twice above the chart —
// in the app bar and in the song list — while a second printed line above the music costs the music
// `lineHeight + chartHeaderGap` of a 568-point page, which is about four per cent off every chord on
// the page at the owner's own fitted scale. The owner asked for the key and the meter to come back,
// and a chart that has to be read at a stand is the one place where a title nobody looks at is paid
// for by the symbols everybody does. The cost is named rather than hidden: a screenshot of the page
// alone does not say which tune it is.
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
  /// Composed by the layout rather than by the painter for the reason every placed value is placed
  /// by the layout: the engine measured these words and reserved the room they need, so a painter
  /// that composed its own string could reserve one line and draw another. Both parts are NOTATION
  /// and are not translated; the separator is punctuation, not a word.
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
// INPUTS: key — the key the chart is shown in, whose name is notation and is never translated.
//         meter — the meter the chart's first bar is counted in, which is the meter the reader
//         assumes from then on.
// OUTPUTS: The string the header draws, such as `C major · 4/4`. Never empty, for any key and any
//          meter the model can hold: a Key always has a name and a meter always has a text form.
// KEYWORDS: chart-header, text-composition, notation, separator
//
// WHY THIS ORDER AND THIS SEPARATOR. The KEY comes first because it is what changes the meaning of
// every chord on the page; the METER second, because it is what the bar lines count in and is read
// as one fact with the first bar. `·` separates them, which is the separator this interface already
// uses between two facts about one thing (the song list reads `79 тактов · A minor`), so the chart
// and the chrome read as one voice rather than as two systems of punctuation.
//
// WHY `Key.name` AND NOT `Key.toString`. They return the same string today, and that is the reason
// the getter is used: the engraving depends on a NAME, not on a diagnostics format that would then
// be free to change while the printed chart silently changed with it.
/// Returns the line a chart prints at the start of its music, such as `C major · 4/4`.
String chartOpeningText(Key key, TimeSignature meter) => '${key.name} · $meter';
