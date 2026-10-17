// PURPOSE: Name the fragment a musician has SELECTED — a run of bars inside one section, or a
//          window of x inside one bar — as an ADDRESS in the interface, never as an entity of the
//          document. The owner stated the purpose of the whole product as select, copy, paste
//          and transpose (D35) and then widened the selection to something finer than a bar
//          (D36: "скопировать содержимое по тактам, нескольким тактам, каких-то нот внутри
//          такта"). This type is the one place that answers "which music is selected", so copy,
//          paste, transpose and the label all ask the same question of the same value.
// INPUTS: A section id, two bar indices, and — only for a single bar — the two x values the
//         window spans, in bar-local logical pixels.
// OUTPUTS: An immutable [ChartSelection]. A selection naming several bars carries NO window: a
//          window is only expressible inside one bar, and the constructor DROPS the two x fields
//          (rather than throwing) when the bars differ, so a caller that extends a window selection
//          onto a second bar gets the run of bars it visibly asked for and not a value that claims
//          a window it cannot express.
// KEYWORDS: selection, address, bar-range, window, coordinates, d35, d36, ui-state-not-document-state
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
// WHY THE WINDOW IS AN X RANGE AND NOT A RUN OF BEATS.
//
// A beat was a column inside a bar, and a window of columns had to answer questions the model can no
// longer ask: which column a mark sat in, how many columns a clip was wide, and what to do when the
// target bar's metre differed. The owner removed the grid, so a position inside a bar is a
// coordinate and a window is a RANGE OF THAT COORDINATE — the same number a mark's place is written
// in. Copy and paste then become a TRANSLATION: every mark whose x lies in the source range moves by
// the distance between the two ranges' left ends. Nothing is re-projected onto a grid, no metre is
// consulted, and a window that spans more x than the target bar has room for simply makes the bar
// wider, which is what a bar's width means now.
//
// WHY THE WINDOW STILL STOPS AT ONE BAR.
//
// A bar is the smallest fragment that holds a barline, and a window that began in bar 4 and ended in
// bar 7 would have to be re-projected onto a target whose bars are a different width. Cutting it at
// one bar keeps the translation a single number; a musician who wants several bars selects the bars.
import '../song/bar.dart';
import '../song/section.dart';
import '../song/song.dart';
import 'bar_range.dart';

// PURPOSE: Say how deep a selection goes — whole bars, or a window inside one bar — so a caller can
//          branch on the depth without testing nullable fields twice and disagreeing.
// INPUTS: None; the value is derived from a [ChartSelection].
// OUTPUTS: One of two tokens. There is deliberately no third: a selection always names at least one
//          whole bar, and the finer depth is a narrowing of that, not a different thing.
// KEYWORDS: selection-depth, bars, window, exhaustive, no-third-state
/// How deep a selection goes: whole bars, or a window inside one bar.
enum SelectionDepth {
  /// The selection covers whole bars, and everything written in them.
  bars,

  /// The selection covers a window of x inside ONE bar.
  ///
  /// It was called `beats` until the grid was deleted, and the rename is the change: what a window
  /// spans is a distance along the bar, not a count of the metre's columns.
  window,
}

// PURPOSE: Name the music a musician selected, in the model's own coordinates, without holding any
//          part of the document.
// INPUTS: See the file header. Both validating doors are the two named constructors; the private
//          constructor is what they normalise into.
// OUTPUTS: An immutable value. [firstBar] is never after [lastBar] — the constructors swap a
//          backwards pair rather than throwing, because a musician who dragged from bar 12 up to bar
//          5 selected bars 5..12 and meant it; there is no reading of that gesture in which the
//          answer is "you described it backwards". This is the OPPOSITE of [resolveBarRange], which
//          refuses a reversed run: that door reads two figures a musician TYPED, where a backwards
//          pair is a typing mistake to correct, and this one reads two bars they TOUCHED, where the
//          order is a property of the gesture and not of the intention. A window's two x values are
//          normalised the same way.
// KEYWORDS: selection, bar-run, window, normalised-order, immutable, derived-length
/// The music a musician selected, named in the model's own coordinates.
class ChartSelection {
  /// Builds a normalised selection. Every public door funnels through here.
  const ChartSelection._({
    required this.sectionId,
    required this.firstBar,
    required this.lastBar,
    required this.firstX,
    required this.lastX,
  });

  /// Creates a selection of whole bars [firstBar]..[lastBar] of [sectionId], both ends inclusive.
  ///
  /// The two bar indices are SWAPPED when [lastBar] comes before [firstBar]; see the class contract
  /// for why this door normalises where [resolveBarRange] refuses. No window is named, so the whole
  /// of each bar is selected.
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
      firstX: null,
      lastX: null,
    );
  }

  /// Creates a selection of the x range [firstX]..[lastX] inside one [barIndex].
  ///
  /// The two values are swapped when [lastX] comes before [firstX], for the same reason the bars are.
  /// A window always covers exactly one bar, which is what lets it be described without naming a
  /// second bar's coordinates.
  factory ChartSelection.window({
    required String sectionId,
    required int barIndex,
    required double firstX,
    required double lastX,
  }) {
    final double low = firstX <= lastX ? firstX : lastX;
    final double high = firstX <= lastX ? lastX : firstX;
    return ChartSelection._(
      sectionId: sectionId,
      firstBar: barIndex,
      lastBar: barIndex,
      firstX: low,
      lastX: high,
    );
  }

  /// Creates the selection two touches describe: [firstBar] with its optional [firstX], and
  /// [lastBar] with its optional [lastX], in either order.
  ///
  /// THE RULE, IN ONE PLACE, because the interface's "extend to here" action must not re-derive it:
  /// two points inside ONE bar make a window; two touches on DIFFERENT bars make the run of bars
  /// between them and DROP the x values, because a window cannot span bars (see the file header).
  factory ChartSelection.span({
    required String sectionId,
    required int firstBar,
    double? firstX,
    required int lastBar,
    double? lastX,
  }) {
    if (firstBar == lastBar && firstX != null && lastX != null) {
      return ChartSelection.window(
        sectionId: sectionId,
        barIndex: firstBar,
        firstX: firstX,
        lastX: lastX,
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

  /// The window's left end in bar-local logical pixels, or null when the selection is bar-deep.
  final double? firstX;

  /// The window's right end in bar-local logical pixels, or null when the selection is bar-deep.
  final double? lastX;

  /// Whether this selection is a window inside one bar rather than whole bars.
  bool get isWindow => firstX != null && lastX != null;

  /// Which depth the selection goes to.
  SelectionDepth get depth =>
      isWindow ? SelectionDepth.window : SelectionDepth.bars;

  /// How many bars the selection covers, at least one.
  int get barCount => lastBar - firstBar + 1;

  /// How wide the window is, in bar-local logical pixels; zero for a bar-deep selection.
  ///
  /// A DISTANCE AND NOT A COUNT. It replaces the old "how many beats" for exactly one purpose — a
  /// paste translates a clip by the distance between two windows' left ends — and its zero for a
  /// bar-deep selection is the honest answer rather than the old `1`, because a bar-deep selection
  /// has no width to speak of: it is the whole bar.
  double get windowWidth => isWindow ? lastX! - firstX! : 0;

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
  /// window sits in is the bar that action acts on, and saying so with a value keeps the decision
  /// visible instead of upcasting `firstX` to nothing at the call site.
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
      other.firstX == firstX &&
      other.lastX == lastX;

  @override
  int get hashCode => Object.hash(sectionId, firstBar, lastBar, firstX, lastX);

  @override
  String toString() {
    final String bars = '$sectionId#$firstBar..$lastBar';
    return isWindow
        ? '$bars x ${firstX!.toStringAsFixed(1)}..${lastX!.toStringAsFixed(1)}'
        : bars;
  }
}
