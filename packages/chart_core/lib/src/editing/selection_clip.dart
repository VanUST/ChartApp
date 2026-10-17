// PURPOSE: Turn a [ChartSelection] into the two values the interface needs without ever writing to
//          the document: the REPORT that says what the selection is made of (structured music, or
//          handwriting that nothing has recognised), and the CLIP that copy hands to paste. Owner
//          decision D37's fourth point is the reason the report exists: an element nothing has
//          recognised must still be copyable, and the application must SAY which of the two levels
//          of quality a fragment carries.
// INPUTS: The song, the document's strokes, and the selection.
// OUTPUTS: A [SelectionReport] describing every bar the selection covers, a [ChartClip] holding the
//          bars and the ink a copy must carry, or null when the selection names no music at all.
//          [InkFragment] gives the minimum structure of one handwritten mark: a centre and an area,
//          derived from its points and never stored anywhere.
// KEYWORDS: selection-report, quality, structured, minimal, clipboard, copy, ink-fragment,
//           centre-and-area, d37, no-recognition-required
//
// WHY THE MINIMUM STRUCTURE IS DERIVED AND NOT STORED.
//
// D37's fourth point says that when nothing recognised a fragment, "каждый отдельный визуальный
// элемент становится МИНИМАЛЬНОЙ СТРУКТУРОЙ: центр и область", and that this is enough to select,
// move, copy and paste. The instinct is to write that structure into the document — and it would be
// wrong, for the reason D37's fifth point gives: the file already holds the thing the minimum would
// be derived FROM. The stroke carries its points; the bar carries its address; the layout carries
// the rectangle. Storing a centre and an area as well would be a second answer to "where is this
// mark", computable from the first, and the two could disagree after a reflow, a zoom or a bar
// insertion — which is exactly the class of defect this project keeps removing.
//
// So a fragment's centre and area are COMPUTED when someone needs to state them, from the points the
// musician's pen produced. That is enough to copy and paste because the paste does not need them: it
// moves the stroke's ANCHOR, and every point stays at the same offset from the bar it hangs on. The
// centre and the area are what makes the fragment legible to the musician and measurable to the
// instrument — see [SelectionReport.inkArea].
//
// WHAT COPY ACTUALLY CARRIES, AND WHAT IT DELIBERATELY DOES NOT.
//
// A bar is copied WHOLE: its chords, its melody, its percussion, its metre, its size, its repeat
// signs, its alternative ending, its marks, its staff text. All of that is inside the [Bar] value, so
// copying it is a copy and there is no list of fields to forget. The ink is copied too, and the ink
// is the part that needs work, because a stroke is not inside the bar: it hangs on an
// [EventAnchor]. The clip REBASES the anchor onto the fragment (bar 0 is the fragment's first bar, and
// for a beat window beat 0 is the window's first beat), so a paste at another address is arithmetic
// and not a search.
//
// A text cue is NOT copied, and that is a decision rather than an omission. A cue says something
// about the bar it hangs on in words a musician typed ("на мосту", "To Coda"); the pasted bars are a
// different place in the form, and asserting the same words there is a claim the application would be
// making on the musician's behalf. The ink is different in kind: it IS what he wrote on the music, and
// he asked for it twice. A cue whose bar moves is still re-addressed by the insertion (see
// [AnchorMove]); it is only the COPY that does not duplicate it.
part of '../oplog/oplog.dart';

// PURPOSE: Say which of the two levels of quality a fragment carries, in the words D37 uses: a
//          fragment with structure supports the automatic operations, and a fragment with only a
//          minimum supports assembly.
// INPUTS: Derived from a bar and the strokes anchored in it by [selectionReportOf].
// OUTPUTS: One of two tokens. [structured] means the bar holds chords or melody — the two things a
//          transposition moves and a size change resizes. [minimal] means it holds neither, so there
//          is nothing for the automatic operations to act on and the bar can still be copied.
// KEYWORDS: fragment-quality, structured, minimal, transposable, copyable-only, d37
/// Which of the two levels of quality a fragment carries: structure, or a minimum.
//
// WHY THE TEST IS "CHORDS OR MELODY" AND NOT "IS THE BAR NON-EMPTY". A bar can carry a metre, a
// repeat sign, an alternative ending, marks and staff text with no chord and no note in it. Every one
// of those travels with a copy and none of them transposes: a metre is a metre in every key, and a
// repeat sign is a sign of a passage. Calling such a bar "structured" would promise a transposition
// that would do nothing, and calling it "minimal" is exactly true — it assembles, it does not
// transpose.
enum FragmentLevel {
  /// The bar holds chords or melody: the automatic operations have something to act on.
  structured,

  /// The bar holds no chord and no note: it is carried whole, and nothing here can be transposed.
  minimal,
}

// PURPOSE: State the minimum structure of ONE handwritten mark — where its centre is and how much
//          room it takes — from the points the pen produced, so a mark nothing recognised is still a
//          thing with a place and an extent.
// INPUTS: One [InkStroke], whose points are already anchor-local, or the aggregates the constructors
//         compute from them.
// OUTPUTS: An immutable value in ANCHOR-LOCAL logical pixels, the same space the stroke's points are
//          stored in, so it moves with its bar and never has to be converted to a page coordinate.
//          The area is INFLATED BY HALF THE NIB, because a dot — a stroke of one sample — has no
//          extent at all otherwise, and a fragment with an area of zero cannot be said to occupy
//          anything.
// KEYWORDS: ink-fragment, minimum-structure, centre, area, anchor-local, nib-inflation, d37
/// The minimum structure of one handwritten mark: an anchor, a centre and an area.
class InkFragment {
  /// Creates a fragment recorded from its bounds.
  const InkFragment({
    required this.anchor,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.strokeCount,
  });

  /// Computes the fragment of [stroke] from its own points.
  ///
  /// A stroke with no points is not a stroke (the reader refuses one), and the one-sample case is
  /// the dot the constructor's nib inflation exists for.
  factory InkFragment.ofStroke(InkStroke stroke) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final InkPoint point in stroke.points) {
      if (point.x < minX) {
        minX = point.x;
      }
      if (point.y < minY) {
        minY = point.y;
      }
      if (point.x > maxX) {
        maxX = point.x;
      }
      if (point.y > maxY) {
        maxY = point.y;
      }
    }
    if (!minX.isFinite) {
      return InkFragment(
        anchor: stroke.anchor,
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        strokeCount: 1,
      );
    }
    final double half = stroke.size / 2;
    return InkFragment(
      anchor: stroke.anchor,
      left: minX - half,
      top: minY - half,
      width: (maxX - minX) + stroke.size,
      height: (maxY - minY) + stroke.size,
      strokeCount: 1,
    );
  }

  /// Computes the fragment covered by a whole group of strokes, treating them as one mark.
  ///
  /// The strokes must already hang on the SAME anchor: their points are anchor-local, and points
  /// measured from two different bars would be added as if they shared an origin. The caller that
  /// groups them is [selectionReportOf], which groups by anchor for exactly this reason.
  factory InkFragment.ofStrokes(List<InkStroke> strokes) {
    if (strokes.length == 1) {
      return InkFragment.ofStroke(strokes.single);
    }
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    double thickest = 0;
    for (final InkStroke stroke in strokes) {
      if (stroke.size > thickest) {
        thickest = stroke.size;
      }
      for (final InkPoint point in stroke.points) {
        if (point.x < minX) {
          minX = point.x;
        }
        if (point.y < minY) {
          minY = point.y;
        }
        if (point.x > maxX) {
          maxX = point.x;
        }
        if (point.y > maxY) {
          maxY = point.y;
        }
      }
    }
    if (!minX.isFinite) {
      return InkFragment(
        anchor: strokes.first.anchor,
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        strokeCount: strokes.length,
      );
    }
    final double half = thickest / 2;
    return InkFragment(
      anchor: strokes.first.anchor,
      left: minX - half,
      top: minY - half,
      width: (maxX - minX) + thickest,
      height: (maxY - minY) + thickest,
      strokeCount: strokes.length,
    );
  }

  /// The anchor every point of this fragment is measured from.
  final EventAnchor anchor;

  /// Left edge in anchor-local logical pixels.
  final double left;

  /// Top edge in anchor-local logical pixels.
  final double top;

  /// Horizontal extent in anchor-local logical pixels, never negative.
  final double width;

  /// Vertical extent in anchor-local logical pixels, never negative.
  final double height;

  /// How many strokes this fragment covers; 1 for [InkFragment.ofStroke].
  final int strokeCount;

  /// Horizontal centre in anchor-local logical pixels.
  double get centreX => left + width / 2;

  /// Vertical centre in anchor-local logical pixels.
  double get centreY => top + height / 2;

  /// The area the fragment occupies in square anchor-local logical pixels.
  double get area => width * height;

  @override
  bool operator ==(Object other) =>
      other is InkFragment &&
      other.anchor == anchor &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height &&
      other.strokeCount == strokeCount;
  @override
  int get hashCode =>
      Object.hash(anchor, left, top, width, height, strokeCount);
  @override
  String toString() =>
      'InkFragment(${anchor.toJson()['bar']}, centre=('
      '${centreX.toStringAsFixed(1)},${centreY.toStringAsFixed(1)}), '
      '${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)}, '
      '$strokeCount stroke(s))';
}

// PURPOSE: Report one bar of a selection: which level of quality it carries and how much
//          handwriting hangs on it, so the label can state the two levels separately rather than
//          averaging them into "12 bars selected".
// INPUTS: The bar's index, the level [selectionReportOf] decided, and the strokes anchored in it.
// OUTPUTS: An immutable value carrying the bar's index, its level, its stroke count and — derived,
//          never stored — the fragment extent of that ink.
// KEYWORDS: bar-fragment, quality, stroke-count, ink-extent, report-row, d37
/// One bar of a selection: its level of quality and how much ink hangs on it.
class BarFragment {
  /// Creates a report row for [barIndex].
  const BarFragment({
    required this.barIndex,
    required this.level,
    required this.strokeCount,
    required this.inkWidth,
    required this.inkHeight,
  });

  /// Zero-based index of the bar inside the selection's section.
  final int barIndex;

  /// Whether this bar carries structure or only a minimum.
  final FragmentLevel level;

  /// How many strokes hang on this bar, at the bar or in any of its cells.
  final int strokeCount;

  /// Horizontal extent of the ink anchored to this bar's own rectangle, in anchor-local pixels.
  ///
  /// Zero when nothing hangs on the bar itself (ink on a CELL is measured from that cell and is not
  /// added here, because two frames do not add).
  final double inkWidth;

  /// Vertical extent of the ink anchored to this bar's own rectangle, in anchor-local pixels.
  final double inkHeight;

  @override
  bool operator ==(Object other) =>
      other is BarFragment &&
      other.barIndex == barIndex &&
      other.level == level &&
      other.strokeCount == strokeCount &&
      other.inkWidth == inkWidth &&
      other.inkHeight == inkHeight;
  @override
  int get hashCode =>
      Object.hash(barIndex, level, strokeCount, inkWidth, inkHeight);
  @override
  String toString() =>
      'BarFragment($barIndex, ${level.name}, $strokeCount stroke(s), '
      '${inkWidth.toStringAsFixed(1)}x${inkHeight.toStringAsFixed(1)})';
}

// PURPOSE: Say what a selection is made of, in numbers, so the selection line can tell a musician
//          which part of what he selected will transpose and which part will only travel.
// INPUTS: A selection, the song it addresses and the document's strokes.
// OUTPUTS: An immutable report holding one [BarFragment] per bar the selection covers, and the
//          counts and extents derived from them. A selection that names no bars reports zero bars
//          rather than throwing: the address outliving its target is an ordinary consequence of a
//          bar being deleted, and a report is a description, not a validation.
// KEYWORDS: selection-report, structured-bars, minimal-bars, ink-extent, legible-quality,
/// What a selection is made of, in numbers a musician can be shown.
//           no-recognition-required, d37
class SelectionReport {
  /// Creates a report from its rows.
  const SelectionReport({
    required this.selection,
    required this.bars,
    required this.fragments,
  });

  /// The selection this report describes.
  final ChartSelection selection;

  /// One row per bar the selection covers, in reading order.
  final List<BarFragment> bars;

  /// One fragment per anchored group of strokes the selection carries, in reading order.
  final List<InkFragment> fragments;

  /// How many bars the selection covers according to the document.
  int get barCount => bars.length;

  /// How many of those bars carry chords or melody, and can therefore be transposed.
  int get structuredBars => bars
      .where((BarFragment row) => row.level == FragmentLevel.structured)
      .length;

  /// How many of those bars carry no chord and no note, and can therefore only be carried.
  int get minimalBars => barCount - structuredBars;

  /// How many of the minimal bars carry handwriting, which is what makes them worth carrying.
  ///
  /// The distinction between this and [emptyBars] is not pedantry: a bar with ink in it is a fragment
  /// a musician can still recognise and want, while a bar with nothing at all is a bar. Reporting both
  /// as "handwriting only" would be the exact lie this project keeps removing — the screen would name
  /// ink that is not there, and the musician would go looking for it.
  int get inkOnlyBars => bars
      .where(
        (BarFragment row) =>
            row.level == FragmentLevel.minimal && row.strokeCount > 0,
      )
      .length;

  /// How many of the minimal bars hold nothing at all — no chord, no note, no handwriting.
  int get emptyBars => minimalBars - inkOnlyBars;

  /// How many strokes the selection carries.
  int get strokeCount =>
      bars.fold(0, (int sum, BarFragment row) => sum + row.strokeCount);

  /// The total area the selection's handwriting covers, in square anchor-local pixels.
  ///
  /// The one NUMBER this whole feature exists to make sayable: a selection of four bars that nothing
  /// recognised is still a fragment of this many strokes covering this much of the page, and that is
  /// what a musician copies. Frames differ between groups, so the numbers are summed as magnitudes
  /// only — an extent, not a shape.
  double get inkArea =>
      fragments.fold(0, (double sum, InkFragment part) => sum + part.area);

  /// Whether there is anything for a transposition to move.
  bool get hasStructuredContent => structuredBars > 0;

  @override
  String toString() =>
      'SelectionReport($selection, $barCount bar(s), structured=$structuredBars, '
      'minimal=$minimalBars, $strokeCount stroke(s))';
}

// PURPOSE: Hold what a copy took, so a paste can put it somewhere else without reading the source
//          bars again — which by then may have been edited, undone or deleted.
// INPUTS: The selection that was copied, the bars it covered, and the ink that travelled.
// OUTPUTS: An immutable value. Its strokes are addressed RELATIVE to the fragment: bar 0 is the
//          fragment's first bar, and for a beat window beat 0 is the window's first beat. Nothing in
//          it is a document address any more, which is what makes pasting into an arbitrary place
//          arithmetic instead of a search for the source.
// KEYWORDS: clipboard, copy, fragment, relative-address, bars-and-ink, not-stored, not-undoable
//
// WHY THE CLIP IS NOT IN THE DOCUMENT, NOT IN THE FILE AND NOT IN THE LOG.
//
// Copying changes nothing, so it writes no event; the engine has no transaction that could hold it
// and the file has no field for it. It lives as long as the musician's intention does, which is what
// a clipboard is. Paste is the single gesture that reaches the log, and it writes what it pasted
// rather than what was copied.
/// What a copy took: the bars and the ink, addressed relative to the fragment itself.
class ChartClip {
  /// Creates a clip of [bars] and [strokes] taken from [source].
  const ChartClip({
    required this.source,
    required this.bars,
    required this.strokes,
  });

  /// The selection the clip was taken from, kept for the log and for the label.
  final ChartSelection source;

  /// The bars the clip carries, in reading order. Whole bars: for a beat window this is the ONE bar
  /// the window sits in, and the window is what decides which of its cells a paste writes.
  final List<Bar> bars;

  /// The strokes the clip carries, with their anchors rebased onto the fragment.
  final List<InkStroke> strokes;

  /// Which depth the copy was taken at.
  SelectionDepth get depth => source.depth;

  /// How many bars the clip carries.
  int get barCount => bars.length;

  /// How many beats the window covers; 1 for a clip of whole bars.
  int get beatCount => source.beatCount;

  @override
  String toString() =>
      'ChartClip(${depth.name}, $barCount bar(s), ${strokes.length} stroke(s), '
      'from ${source.firstBar}@${source.sectionId})';
}

// PURPOSE: Read what a selection is made of, so the interface can state it and so a musician can see
//          which part of his selection has structure and which part is only his handwriting.
// INPUTS: song — the chart. strokes — the document's strokes. selection — the address to describe.
// OUTPUTS: The [SelectionReport]. Every bar the selection covers gets a row; the ink rows are grouped
//          by anchor because points measured from different bars do not share an origin. A selection
//          whose bars no longer exist reports zero rows, which is what "the address names nothing
//          here" looks like as a value.
// KEYWORDS: report, quality-row, stroke-membership, grouped-by-anchor, total-function
/// Reads what a selection is made of, so the interface can state it.
SelectionReport selectionReportOf({
  required Song song,
  required List<InkStroke> strokes,
  required ChartSelection selection,
}) {
  final List<Bar> bars = selection.barsIn(song);
  if (bars.isEmpty) {
    return SelectionReport(
      selection: selection,
      bars: const <BarFragment>[],
      fragments: const <InkFragment>[],
    );
  }
  final List<InkStroke> carried = strokesOf(selection, strokes);
  final Map<EventAnchor, List<InkStroke>> byAnchor =
      <EventAnchor, List<InkStroke>>{};
  for (final InkStroke stroke in carried) {
    byAnchor.putIfAbsent(stroke.anchor, () => <InkStroke>[]).add(stroke);
  }
  final List<InkFragment> fragments = <InkFragment>[
    for (final EventAnchor anchor in byAnchor.keys)
      InkFragment.ofStrokes(byAnchor[anchor]!),
  ];
  final List<BarFragment> rows = <BarFragment>[];
  for (int offset = 0; offset < bars.length; offset++) {
    final int barIndex = selection.firstBar + offset;
    final Bar bar = bars[offset];
    final List<InkStroke> onBar = carried
        .where(
          (InkStroke stroke) =>
              stroke.anchor.sectionId == selection.sectionId &&
              stroke.anchor.bar == barIndex,
        )
        .toList();
    final List<InkStroke> atBarLevel = onBar
        .where((InkStroke stroke) => stroke.anchor.isBarLevel)
        .toList();
    final InkFragment? atBar = atBarLevel.isEmpty
        ? null
        : InkFragment.ofStrokes(atBarLevel);
    rows.add(
      BarFragment(
        barIndex: barIndex,
        level: bar.chords.isNotEmpty || bar.melody.isNotEmpty
            ? FragmentLevel.structured
            : FragmentLevel.minimal,
        strokeCount: onBar.length,
        inkWidth: atBar?.width ?? 0,
        inkHeight: atBar?.height ?? 0,
      ),
    );
  }
  return SelectionReport(
    selection: selection,
    bars: rows,
    fragments: fragments,
  );
}

// PURPOSE: Decide which strokes a selection carries, by ADDRESS, so copy is a pure function of the
//          document and not of the page on screen.
// INPUTS: selection — the address. strokes — the document's strokes.
// OUTPUTS: The strokes whose anchor lies inside the selection, in document render order. A bar-deep
//          selection carries every stroke anchored anywhere in those bars, at the bar or in a cell.
//          A beat window carries only strokes anchored to a CELL inside the window: a stroke
//          anchored to the bar has no beat, and this function does not invent one from its geometry.
//          That refusal is the decision, and it is stated here because it is the only place it can
//          be checked: the alternative — decide membership from the ink's position on the page —
//          would make the same gesture carry different ink at a different zoom or a different page
//          mode, since the rectangle it measured against would have moved.
// KEYWORDS: stroke-membership, address-decides, no-geometry-guess, order-preserving, total-function
/// Returns the strokes a selection carries, decided by their addresses alone.
List<InkStroke> strokesOf(ChartSelection selection, List<InkStroke> strokes) {
  final List<InkStroke> carried = <InkStroke>[];
  for (final InkStroke stroke in strokes) {
    if (stroke.anchor.sectionId != selection.sectionId) {
      continue;
    }
    final int bar = stroke.anchor.bar;
    if (bar < selection.firstBar || bar > selection.lastBar) {
      continue;
    }
    if (selection.isBeatWindow) {
      final int? beat = stroke.anchor.beat;
      if (beat == null ||
          beat < selection.firstBeat! ||
          beat > selection.lastBeat!) {
        continue;
      }
    }
    carried.add(stroke);
  }
  return carried;
}

// PURPOSE: Say what a paste did, in a value, so the surface can report the outcome instead of
//          inferring it from a boolean that cannot distinguish five different refusals.
// INPUTS: Returned by `EditSession.pasteClip`.
// OUTPUTS: One token per outcome. [pasted] is the only one that wrote an event; every other one is a
//          refusal that left the document exactly as it was, which is what makes "the paste refused"
//          and "the paste pasted nothing" two different facts.
// KEYWORDS: paste-outcome, typed-refusal, no-partial-effect, reported-not-inferred
/// What a paste did, as one token per outcome.
enum ClipPasteOutcome {
  /// The run or the window was written; exactly one undo step was appended.
  pasted,

  /// The target names a section the song does not have.
  noSuchSection,

  /// The target names a bar the section does not have.
  noSuchBar,

  /// A window of beats was pasted at a target that names no cell. A bar-level target does not say
  /// which beat a window should land on, and picking beat 1 would be the application choosing.
  needsCell,

  /// The window does not fit inside the target bar's own METRE, so writing it would either spill
  /// past the barline or widen the bar's grid. See the decision record for why the metre and not the
  /// widened grid decides.
  windowDoesNotFit,

  /// A bar-level paste was asked for at an address whose bar count changed under it.
  noSuchRun,
}

// PURPOSE: Say what a selection transposition did — how many bars it moved, how many of them had
//          nothing to move, and how much ink it deliberately left where it was — so the sentence a
//          musician reads is built from numbers rather than from an assumption.
// INPUTS: Returned by `EditSession.transposeSelection`.
// OUTPUTS: An immutable value. [applied] is false when nothing was written (no structure to move, a
//          beat window, or no such section), in which case no undo step was appended either.
// KEYWORDS: selection-transpose, report, counts, ink-left-alone, typed-refusal
/// What a selection transposition did, and how much ink it deliberately left alone.
class SelectionTransposition {
  /// Creates a report of a transposition of [selection] by [semitones].
  const SelectionTransposition({
    required this.selection,
    required this.semitones,
    required this.barsTotal,
    required this.barsChanged,
    required this.strokesKept,
    required this.outcome,
  });

  /// The selection the operation was asked to transpose.
  final ChartSelection selection;

  /// The interval asked for, signed.
  final int semitones;

  /// How many bars the selection covered, as the document counts them.
  final int barsTotal;

  /// How many bars actually changed. A bar with no chord and no note is not counted: transposing it
  /// would append an event that changes nothing, which is the no-op every other edit here refuses.
  final int barsChanged;

  /// How many strokes the selection carried, all of which stay exactly where they were drawn.
  ///
  /// This is the number the surface must say out loud. Handwriting is a picture of what the musician
  /// wrote; a semitone is not a distance in pixels, so no rule can move it, and D37 forbids throwing
  /// it away. It stays, and the musician is told that it stayed.
  final int strokesKept;

  /// What happened.
  final SelectionTransposeOutcome outcome;

  /// Whether an event was appended.
  bool get applied => outcome == SelectionTransposeOutcome.applied;

  /// Whether there was structure in the selection for the interval to move.
  bool get hadStructure => barsChanged > 0;

  @override
  String toString() =>
      'SelectionTransposition(${outcome.name}, $barsChanged/$barsTotal bar(s), '
      'semitones=$semitones, $strokesKept stroke(s) kept)';
}

// PURPOSE: Say why a selection transposition did or did not happen.
// INPUTS: Returned inside a [SelectionTransposition].
// OUTPUTS: One token. [beatsOnly] is the refusal of a window: a bar is the smallest fragment that
//          holds a key, and moving three notes inside a bar would leave one bar in two keys at once.
// KEYWORDS: transpose-outcome, beats-refusal, nothing-to-move, no-section, typed-refusal
/// Why a selection transposition did or did not happen.
enum SelectionTransposeOutcome {
  /// The bars changed and exactly one undo step was appended.
  applied,

  /// Every bar the selection covers carries neither a chord nor a note: there is nothing for an
  /// interval to move, and the ink that is there cannot be moved by one.
  nothingToTranspose,

  /// The selection is a window of beats. See [SelectionTransposeOutcome.beatsOnly].
  beatsOnly,

  /// The selection names a section the song does not have.
  noSuchSection,
}

// INPUTS: song — the chart. strokes — the document's strokes. selection — what to copy.
// OUTPUTS: The [ChartClip], or null when the selection names no bar of the song, because a copy of
//          nothing is not a clip of an empty fragment: it is a gesture with no target.
//
//          THE STROKES IN THE CLIP ARE REBASED. `anchor.bar` becomes the stroke's bar offset from the
//          first bar of the fragment; a beat window additionally subtracts its own first beat. The
//          section id is kept as it was, for the log, and is overwritten by the paste. Copying a
//          second time from the same selection therefore produces an equal clip, and pasting at
//          another address is arithmetic on two integers.
/// Returns the clip a copy of [selection] takes, or null when it names no bar.
// KEYWORDS: copy, clip, rebase, anchor-relative, bars-and-ink, total-or-null
ChartClip? chartClipOf({
  required Song song,
  required List<InkStroke> strokes,
  required ChartSelection selection,
}) {
  final List<Bar> bars = selection.barsIn(song);
  if (bars.isEmpty) {
    return null;
  }
  final List<InkStroke> carried = strokesOf(selection, strokes);
  return ChartClip(
    source: selection,
    bars: bars,
    strokes: <InkStroke>[
      for (final InkStroke stroke in carried)
        InkStroke(
          id: stroke.id,
          tool: stroke.tool,
          color: stroke.color,
          size: stroke.size,
          anchor: EventAnchor(
            sectionId: stroke.anchor.sectionId,
            bar: stroke.anchor.bar - selection.firstBar,
            beat: selection.isBeatWindow
                ? stroke.anchor.beat! - selection.firstBeat!
                : stroke.anchor.beat,
            step: stroke.anchor.step,
          ),
          points: stroke.points,
        ),
    ],
  );
}
