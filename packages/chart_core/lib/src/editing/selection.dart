// PURPOSE: Name the fragment a musician has SELECTED — a run of bars inside one section, or a
//          window of beats inside one bar — as an ADDRESS in the interface, never as an entity of
//          the document. The owner stated the purpose of the whole product as select, copy, paste
//          and transpose (D35) and then widened the selection to something finer than a bar
//          (D36: "скопировать содержимое по тактам, нескольким тактам, каких-то нот внутри
//          такта"). This type is the one place that answers "which music is selected", so copy,
//          paste, transpose and the label all ask the same question of the same value.
// INPUTS: A section id, two bar indices, and — only for a single bar — two beat indices.
// OUTPUTS: An immutable [ChartSelection]. A selection naming several bars carries NO beats: a beat
//          window is only expressible inside one bar, and the constructor DROPS the two beat fields
//          (rather than throwing) when the bars differ, so a caller that extends a cell selection
//          onto a second bar gets the run of bars it visibly asked for and not a value that claims
//          a window it cannot express.
// KEYWORDS: selection, address, bar-range, beat-window, d35, d36, ui-state-not-document-state
//
// WHY A SELECTION IS NOT STORED ANYWHERE, AND WHY THAT IS THE POINT.
//
// D36 settles it: the selection "живёт в интерфейсе, пока не станет операцией; в журнал попадает
// только результат". A selection written to the file would be a state to synchronise between
// devices, to undo, and to restore — and it would have to be re-validated on every load, since the
// bars it names may have moved. Nothing in this file is reachable from the event catalogue: there is
// no `selection.*` event, no `ChartSelection` field in [DocumentState], and no codec for it. What
// reaches the log is the RESULT of an operation performed on a selection (a paste, a transposition),
// and the selection itself is gone by then.
//
// WHY THE BEAT WINDOW STOPS AT ONE BAR.
//
// A beat is a column inside a bar. A window that began at beat 3 of bar 4 and ended at beat 2 of bar
// 7 would have to be re-projected onto a target whose bars do not have the same metre, and the only
// ways to do that are to clip it (destroying part of what the musician copied), to spill it across
// bars (inventing a barline the musician did not write) or to refuse targets whose metre differs
// (making the gesture unpredictable). None of those is a copy of what was selected. A window inside
// ONE bar never has to answer that question: the pasted beats land in the target bar's own grid at
// the offset the musician chose, and a window that does not fit is REFUSED rather than reshaped.
//
// WHY THE BARS AND NOT A SET OF NOTES.
//
// "Каких-то нот внутри такта" could be read as an arbitrary set. A set would need an address per
// note, and this model addresses a note by `(section, bar, beat, step)` — a position, not an
// identity — so a set collected at copy time would name positions that the target does not have.
// A window is expressible in the model's own coordinates (the same `beat` field an anchor already
// carries), it is a rectangle the musician can see and touch, and it composes with the bar run
// without a second address space. The set is the finer gesture this model does not have and would
// have to invent identities for; the window is the same intention at the granularity the model
// already has.
import '../song/bar.dart';
import '../song/section.dart';
import '../song/song.dart';
import 'bar_range.dart';

// PURPOSE: Say how deep a selection goes — whole bars, or a window of beats inside one bar — so a
//          caller can branch on the depth without testing nullable fields twice and disagreeing.
// INPUTS: None; the value is derived from a [ChartSelection].
// OUTPUTS: One of two tokens. There is deliberately no third: a selection always names at least one
//          whole bar, and the finer depth is a narrowing of that, not a different thing.
// KEYWORDS: selection-depth, bars, beats, exhaustive, no-third-state
/// How deep a selection goes: whole bars, or a window of beats inside one bar.
enum SelectionDepth {
  /// The selection covers whole bars, and everything written in them.
  bars,

  /// The selection covers a window of beats inside ONE bar.
  beats,
}

// PURPOSE: Name the music a musician selected, in the model's own coordinates, without holding any
//          part of the document.
// INPUTS: See the file header. Both validating doors are the two named constructors; the private
//         constructor is what they normalise into.
// OUTPUTS: An immutable value. [firstBar] is never after [lastBar] — the constructors swap a
//          backwards pair rather than throwing, because a musician who dragged from bar 12 up to bar
//          5 selected bars 5..12 and meant it; there is no reading of that gesture in which the
//          answer is "you described it backwards". This is the OPPOSITE of [resolveBarRange], which
//          refuses a reversed run: that door reads two figures a musician TYPED, where a backwards
//          pair is a typing mistake to correct, and this one reads two bars they TOUCHED, where the
//          order is a property of the gesture and not of the intention.
// KEYWORDS: selection, bar-run, beat-window, normalised-order, immutable, derived-length
/// The music a musician selected, named in the model's own coordinates.
class ChartSelection {
  /// Builds a normalised selection. Every public door funnels through here.
  const ChartSelection._({
    required this.sectionId,
    required this.firstBar,
    required this.lastBar,
    required this.firstBeat,
    required this.lastBeat,
  });

  /// Creates a selection of whole bars [firstBar]..[lastBar] of [sectionId], both ends inclusive.
  ///
  /// The two bar indices are SWAPPED when [lastBar] comes before [firstBar]; see the class contract
  /// for why this door normalises where [resolveBarRange] refuses. No beat is named, so the whole of
  /// each bar is selected.
  factory ChartSelection.bars({
    required String sectionId,
    required int firstBar,
    required int lastBar,
  }) {
    final int low = firstBar <= lastBar ? firstBar : lastBar;
    final int high = firstBar <= lastBar ? lastBar : firstBar;
    return ChartSelection._(
      sectionId: sectionId,
      firstBar: low,
      lastBar: high,
      firstBeat: null,
      lastBeat: null,
    );
  }

  /// Creates a selection of the beats [firstBeat]..[lastBeat] inside one [barIndex].
  ///
  /// The two beat indices are swapped when [lastBeat] comes before [firstBeat], for the same reason
  /// the bars are. A beat window always covers exactly one bar, which is what lets it be pasted into
  /// a bar's own grid without reshaping it.
  factory ChartSelection.beats({
    required String sectionId,
    required int barIndex,
    required int firstBeat,
    required int lastBeat,
  }) {
    final int low = firstBeat <= lastBeat ? firstBeat : lastBeat;
    final int high = firstBeat <= lastBeat ? lastBeat : firstBeat;
    return ChartSelection._(
      sectionId: sectionId,
      firstBar: barIndex,
      lastBar: barIndex,
      firstBeat: low,
      lastBeat: high,
    );
  }

  /// Creates the selection two touches describe: [firstBar] with its optional [firstBeat], and
  /// [lastBar] with its optional [lastBeat], in either order.
  ///
  /// THE RULE, IN ONE PLACE, because the interface's "extend to here" action must not re-derive it:
  /// two beats inside ONE bar make a beat window; two touches on DIFFERENT bars make the run of bars
  /// between them and DROP the beats, because a window cannot span bars (see the file header). A
  /// touch that landed on a bar's padding names no beat at all, so one beat and one bar-level touch
  /// also makes a bar run: a window needs BOTH ends to be cells.
  factory ChartSelection.span({
    required String sectionId,
    required int firstBar,
    int? firstBeat,
    required int lastBar,
    int? lastBeat,
  }) {
    if (firstBar == lastBar && firstBeat != null && lastBeat != null) {
      return ChartSelection.beats(
        sectionId: sectionId,
        barIndex: firstBar,
        firstBeat: firstBeat,
        lastBeat: lastBeat,
      );
    }
    return ChartSelection.bars(
      sectionId: sectionId,
      firstBar: firstBar,
      lastBar: lastBar,
    );
  }

  /// The section the selected music lives in.
  final String sectionId;

  /// Zero-based index of the first bar the selection covers.
  final int firstBar;

  /// Zero-based index of the last bar the selection covers, never before [firstBar].
  final int lastBar;

  /// Zero-based first beat of the window, or null when the selection is bar-deep.
  final int? firstBeat;

  /// Zero-based last beat of the window, or null when the selection is bar-deep.
  final int? lastBeat;

  /// Whether this selection is a window of beats rather than whole bars.
  bool get isBeatWindow => firstBeat != null && lastBeat != null;

  /// Which depth the selection goes to.
  SelectionDepth get depth =>
      isBeatWindow ? SelectionDepth.beats : SelectionDepth.bars;

  /// How many bars the selection covers, at least one.
  int get barCount => lastBar - firstBar + 1;

  /// How many beats the window covers, or one for a bar-deep selection.
  ///
  /// One rather than zero, because every consumer multiplies by it to ask "how much music is this"
  /// and a zero would silently empty the answer.
  int get beatCount => isBeatWindow ? lastBeat! - firstBeat! + 1 : 1;

  /// The bars the selection covers, as the value the metre zone already uses.
  ///
  /// Reusing [BarRange] rather than inventing a second spelling of "a run of bars" is what keeps
  /// the sheet that sets a metre over bars 5..20 and the copy of bars 5..20 describing the same
  /// thing with the same value.
  BarRange get barRange =>
      BarRange(sectionId: sectionId, firstBar: firstBar, lastBar: lastBar);

  /// Returns a copy of this selection covering nothing but whole bars.
  ///
  /// Used when a caller takes a bar-deep action from a selection that is finer than it: the bar a
  /// beat window sits in is the bar that action acts on, and saying so with a value keeps the
  /// decision visible instead of upcasting `firstBeat` to nothing at the call site.
  ChartSelection get asBars => ChartSelection.bars(
    sectionId: sectionId,
    firstBar: firstBar,
    lastBar: lastBar,
  );

  /// The bars this selection covers, read from [song], in reading order.
  ///
  /// Empty when [sectionId] names no section, and clamped to the section's own bars when the
  /// selection reaches past its end: a selection is an address, and an address whose target shrank
  /// (a bar deleted under it) names the bars that are still there rather than throwing inside a
  /// paint pass.
  List<Bar> barsIn(Song song) {
    final int sectionIndex = song.sections.indexWhere(
      (Section section) => section.id == sectionId,
    );
    if (sectionIndex < 0) {
      return const <Bar>[];
    }
    final List<Bar> bars = song.sections[sectionIndex].bars;
    if (bars.isEmpty || firstBar >= bars.length) {
      return const <Bar>[];
    }
    final int high = lastBar >= bars.length ? bars.length - 1 : lastBar;
    return <Bar>[
      for (int index = firstBar; index <= high; index++) bars[index],
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is ChartSelection &&
      other.sectionId == sectionId &&
      other.firstBar == firstBar &&
      other.lastBar == lastBar &&
      other.firstBeat == firstBeat &&
      other.lastBeat == lastBeat;

  @override
  int get hashCode =>
      Object.hash(sectionId, firstBar, lastBar, firstBeat, lastBeat);

  @override
  String toString() {
    final String bars = '$sectionId#$firstBar..$lastBar';
    return isBeatWindow ? '$bars beat $firstBeat..$lastBeat' : bars;
  }
}
