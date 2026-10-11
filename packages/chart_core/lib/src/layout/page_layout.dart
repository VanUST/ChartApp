// PURPOSE: Describe where everything landed, in a form that answers the two questions the rest of
//          the system asks of a layout: where is this chord drawn, and which chord is under this
//          touch. Every element carries both its identity in the song model and its rectangle on
//          the page, so neither question requires re-running the engine.
// INPUTS: Produced by the layout engine; not constructed by callers.
// OUTPUTS: Immutable values with value equality, which is what makes a layout comparable — a
//          cached layout can be recognised as unchanged without re-engraving it.
// KEYWORDS: layout-result, placed-chord, hit-testing, value-equality, cache-key, anchor-address
import '../chord.dart';
import 'geometry.dart';
import 'melody_staff.dart';

/// A chord drawn at a position, with the address that identifies it in the song.
class PlacedChord {
  /// Creates a placed chord for [chord] at ([beat], [step]) with the given [bounds].
  const PlacedChord({
    required this.chord,
    required this.beat,
    required this.step,
    required this.bounds,
  });

  /// The chord that is drawn.
  final Chord chord;

  /// The cell of the bar the chord sits on.
  final int beat;

  /// The order of this chord within its cell, matching the song model's step.
  final int step;

  /// Where the chord is drawn, in page coordinates.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedChord &&
      other.chord == chord &&
      other.beat == beat &&
      other.step == step &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(chord, beat, step, bounds);

  @override
  String toString() => 'placed($chord) at $bounds';
}

/// One cell of a bar: the slice of the bar's width that one beat occupies.
///
/// A cell is not a chord. An empty cell is where a chord written before it keeps sounding, and it
/// still owns a column of the bar, so an answer to "what did the musician touch" must be able to
/// say "this cell, no chord" as readily as "this cell, this chord". The engine already divides the
/// bar into these columns in order to place its chords; publishing those columns as layout values
/// is what lets a hit test read the geometry that was engraved instead of re-deriving it, which is
/// the same reason [PlacedChord.bounds] exists rather than being recomputed by the painter.
class PlacedCell {
  /// Creates a cell for [beat] with the given [bounds].
  const PlacedCell({required this.beat, required this.bounds});

  /// The cell's index inside its bar, in the song model's beat numbering.
  ///
  /// It is the `beat` half of an annotation anchor, so a cell named by a touch and a cell named by
  /// an annotation are the same value and can be compared without a conversion.
  final int beat;

  /// Where the cell is drawn, in page coordinates.
  ///
  /// The rectangle spans the bar's full stave height and the cell's own column of its width, so a
  /// point anywhere in the column — above, on or below the chord symbol — hits the same cell.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedCell && other.beat == beat && other.bounds == bounds;

  @override
  int get hashCode => Object.hash(beat, bounds);

  @override
  String toString() => 'PlacedCell($beat) at $bounds';
}

/// One line of the words a bar carries, placed where it is drawn.
///
/// The bar model stores staff text as the chart wrote it — with the `*NN` layout prefix and the
/// exporter's padding — because that is what makes the stored form round-trip. What is drawn is the
/// DISPLAY form, which the engine derives once through `displayStaffText`. Carrying the derived
/// words and their box here, rather than leaving the painter to strip and measure the stored string
/// again, is what makes the room the engine reserved and the text the painter puts on the page the
/// same value by construction instead of two code paths that happen to agree.
class PlacedStaffText {
  /// Creates a placed line for [text] with the given [bounds].
  const PlacedStaffText({required this.text, required this.bounds});

  /// The words to draw, with the position prefix and padding already removed.
  ///
  /// Never empty: the engine does not place a stored entry that has nothing to say, so a consumer
  /// need not test this before drawing.
  final String text;

  /// Where the line is drawn, in page coordinates. Its width is the width the line was measured at.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedStaffText && other.text == text && other.bounds == bounds;

  @override
  int get hashCode => Object.hash(text, bounds);

  @override
  String toString() => 'PlacedStaffText("$text") at $bounds';
}

/// One text cue placed above its bar, in the row the layout reserved for it.
///
/// A cue is NOT a [PlacedStaffText]. Staff text belongs to the song and hangs at the bottom of the
/// bar it is stored on; a cue belongs to the document and hangs above the bar it is anchored to,
/// in a row the page gives up out of its own height. What the two share is the reason this value
/// exists at all: the layout measured the words and decided the box, so the painter draws the box
/// it was handed instead of measuring a string a second time and hoping the two agree. Without a
/// reserved row the cue's plate would fall back onto the chord beneath it, which is the defect a
/// measured-and-published box closes.
class PlacedTextCue {
  /// Creates a placed cue for [text] with the given [origin] and [size].
  const PlacedTextCue({
    required this.id,
    required this.text,
    required this.origin,
    required this.size,
  });

  /// The identity the document gave this cue.
  ///
  /// It travels with the placement because two cues may share one anchor — the model keeps both
  /// rather than arbitrating — so an address cannot tell them apart and the caller needs the name.
  final String id;

  /// The words to draw, exactly as the document stores them.
  final String text;

  /// The top-left of the reserved row, in the page's engraved coordinates.
  ///
  /// The cue's own stored offset is measured from here, so this is the point that takes the place
  /// of the anchor corner the painter used to resolve for itself: its x is the anchor's own left
  /// edge, unchanged, and its y is the row the layout reserved above the stave.
  final LayoutOffset origin;

  /// The box the cue occupies, in the page's engraved coordinates.
  ///
  /// It is the PLATE's box, padding included, because the padding is part of how much room the cue
  /// takes. It is expressed at the scale the page was engraved for, so multiplying it by
  /// `PageLayout.scale` — the same one transform every other rectangle goes through — lands it on
  /// the surface exactly. That is why a cue's row grows in engraved pixels as a fitted page
  /// shrinks: the letters have their own legibility floor, so their box must be divided by the
  /// page scale to stay the same size on the glass.
  final LayoutSize size;

  @override
  bool operator ==(Object other) =>
      other is PlacedTextCue &&
      other.id == id &&
      other.text == text &&
      other.origin == origin &&
      other.size == size;

  @override
  int get hashCode => Object.hash(id, text, origin, size);

  @override
  String toString() => 'PlacedTextCue($id, "$text") at $origin size $size';
}

/// One beat of a bar, named where the musician counts it: under the staff, in the beat's own
/// column.
///
/// WHY THIS IS A LAYOUT VALUE AND NOT A PAINTER'S ARITHMETIC. The defect it exists against is that
/// a musician could not tell WHICH BEAT he was choosing, so the mark has to land on the column the
/// hit test will name — the same column the chord and the cell of that beat already occupy. Only
/// the engine knows where a cell begins, so the engine publishes the mark's identity and box and
/// the painter draws what it was handed; a painter that centred a number in a cell it re-derived
/// would be the second arithmetic that drifts.
///
/// IT LIVES UNDER THE STAFF, in the space the staff's centring leaves above the next system. A
/// marker carries the beat's ordinal as [label] when the engine decided the column is wide enough
/// to print one, and an empty string when it is not — in which case the painter draws the tick
/// alone. Both cases are drawn the same way: a short tick at the bottom of [bounds], so a crowded
/// bar shows the beat GRID even when it cannot show the numbers.
class PlacedBeatMarker {
  /// Creates a marker naming [beat] with [label] in the given [bounds].
  const PlacedBeatMarker({
    required this.beat,
    required this.label,
    required this.bounds,
  });

  /// The cell index inside its bar, in the song model's zero-based numbering — the `beat` half of
  /// an annotation anchor and of a [PlacedCell].
  final int beat;

  /// The beat numbered the way the musician counts it, or the empty string when the engine decided
  /// the column is too narrow to print it. Never null: "no number here" is an ordinary state of a
  /// crowded bar.
  final String label;

  /// The box the marker occupies, spanning its cell's column. Its bottom edge is where the tick is
  /// drawn, so the marker reads against the column rather than against the bar.
  final LayoutRect bounds;

  @override
  bool operator ==(Object other) =>
      other is PlacedBeatMarker &&
      other.beat == beat &&
      other.label == label &&
      other.bounds == bounds;

  @override
  int get hashCode => Object.hash(beat, label, bounds);

  @override
  String toString() =>
      'PlacedBeatMarker($beat${label.isEmpty ? '' : ' "$label"'}) at $bounds';
}

/// A bar drawn at a position, together with its cells and the chords inside it.
class PlacedBar {
  /// Creates a placed bar for the bar at ([sectionId], [barIndex]).
  const PlacedBar({
    required this.sectionId,
    required this.barIndex,
    required this.bounds,
    required this.cells,
    required this.chords,
    this.staffText = const <PlacedStaffText>[],
    this.textCues = const <PlacedTextCue>[],
    this.melody = PlacedMelodyStaff.empty,
    this.beatMarkers = const <PlacedBeatMarker>[],
  });

  /// The section the bar belongs to.
  final String sectionId;

  /// The bar's index within its section, in written order.
  ///
  /// Together with [sectionId] this is the bar half of an annotation anchor, so a layout can be
  /// matched to an annotation without either side knowing the other's coordinate system.
  final int barIndex;

  /// Where the bar is drawn, in page coordinates.
  final LayoutRect bounds;

  /// The bar's cells, left to right, one per beat the bar has room for.
  ///
  /// The columns tile the bar's interior between its two paddings; a point inside the bar but in
  /// one of those paddings therefore lies over the bar and over no cell, which is a state a hit
  /// test reports rather than hides. There is always at least one cell: the meter declares at
  /// least one, and the engine widens the count to include a chord written past the meter.
  final List<PlacedCell> cells;

  /// The chords inside the bar, ordered by cell and then by step.
  final List<PlacedChord> chords;

  /// The staff-text lines the bar draws, stacked upward from its bottom edge in model order.
  ///
  /// The words are the display form, so a reader never meets the `*NN` prefix; an entry whose
  /// display form is empty is absent rather than placed empty. Empty for a bar whose model carries
  /// no staff text, which is the common case.
  final List<PlacedStaffText> staffText;

  /// The text cues anchored to this bar, in document order.
  ///
  /// They sit in the rows the layout reserved ABOVE this bar's stave — so above [bounds], not
  /// inside it — stacked upward from the stave so the first cue stays closest to the bar it
  /// remarks on. The bar's own [bounds], its [cells] and its [chords] are untouched by a cue: a
  /// remark reserves room from the page rather than moving the music. Empty for a bar no cue
  /// names, which is the common case, and for a cue whose text is empty — a cue with nothing to
  /// say gets no row.
  final List<PlacedTextCue> textCues;

  /// The melody staff drawn under this bar, from `Bar.melody`.
  ///
  /// ONE STAFF PER BAR rather than one per system, so that the five lines and everything on them
  /// are addressed exactly as a chord and a cell are: by the bar's own rectangle. The bounds of two
  /// neighbouring bars on a system tile, so the lines read as one continuous staff.
  ///
  /// [PlacedMelodyStaff.empty] for a song whose bars carry no melody at all — every imported chart
  /// — and in that state nothing is reserved, nothing is drawn, and this bar's [bounds], [cells]
  /// and [chords] are exactly what they were before a melody staff existed.
  ///
  /// THE STAFF LIES BELOW [bounds], NOT INSIDE IT. A bar's rectangle is its chord-line stave, and
  /// that is what the hit test measures a tap against, so extending it over the staff would change
  /// what a tap on the chord line means. The melody has its own rectangle instead; a point in the
  /// staff is over no bar until note entry gives it meaning.
  final PlacedMelodyStaff melody;

  /// The beat markers under this bar's staff, one per cell, left to right.
  ///
  /// They name the beat a musician is choosing, in the column that beat owns, and they exist only
  /// because the song declared a pitched staff: on a chords-only chart this is EMPTY and nothing
  /// is drawn, which is what keeps such a chart's page exactly what it was. A marker carries the
  /// beat's ordinal on the bar that OPENS a system — the beats of the bars after it are the same
  /// numbers on the same columns, so printing them again would say nothing — and an empty label
  /// elsewhere; the tick is drawn either way.
  final List<PlacedBeatMarker> beatMarkers;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedBar ||
        other.sectionId != sectionId ||
        other.barIndex != barIndex ||
        other.bounds != bounds ||
        other.cells.length != cells.length ||
        other.chords.length != chords.length ||
        other.staffText.length != staffText.length ||
        other.textCues.length != textCues.length ||
        other.melody != melody ||
        other.beatMarkers.length != beatMarkers.length) {
      return false;
    }
    for (int index = 0; index < cells.length; index++) {
      if (other.cells[index] != cells[index]) {
        return false;
      }
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
    for (int index = 0; index < textCues.length; index++) {
      if (other.textCues[index] != textCues[index]) {
        return false;
      }
    }
    for (int index = 0; index < beatMarkers.length; index++) {
      if (other.beatMarkers[index] != beatMarkers[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    sectionId,
    barIndex,
    bounds,
    Object.hashAll(cells),
    Object.hashAll(chords),
    Object.hashAll(staffText),
    Object.hashAll(textCues),
    melody,
    Object.hashAll(beatMarkers),
  );

  @override
  String toString() => 'PlacedBar($sectionId[$barIndex]) at $bounds';
}

/// One line of a page: the bars engraved side by side.
class PlacedSystem {
  /// Creates a system with the given [bounds], [bars] and optional section heading.
  const PlacedSystem({
    required this.bounds,
    required this.bars,
    this.sectionId,
    this.sectionLabel,
    this.labelBand,
  });

  /// Where the system is drawn, including any section label above the stave.
  final LayoutRect bounds;

  /// The bars of the system, left to right.
  final List<PlacedBar> bars;

  /// The section this system begins, or null when it continues a section.
  ///
  /// A system begins a section or it does not; the engine always starts a new system at a
  /// section boundary, so a section is never split across the heading that names it.
  final String? sectionId;

  /// The label drawn above this system, or null when the system continues a section.
  final String? sectionLabel;

  /// The band the section label is placed in, or null when there is no label.
  ///
  /// It is published rather than left to the painter to infer from the geometry because a system's
  /// band above the stave now holds TWO things: the heading, which owns the top
  /// `LayoutStyle.sectionLabelHeight` of it, and the cue rows, which own the rest. A painter that
  /// centred the label in the whole band would put it among the cue rows and let a plate drawn over
  /// them cover the letter that names the section. Publishing the band keeps the heading where it
  /// was on every page that carries no cue, and above the words on every page that does.
  final LayoutRect? labelBand;

  @override
  bool operator ==(Object other) {
    if (other is! PlacedSystem ||
        other.bounds != bounds ||
        other.sectionId != sectionId ||
        other.sectionLabel != sectionLabel ||
        other.labelBand != labelBand ||
        other.bars.length != bars.length) {
      return false;
    }
    for (int index = 0; index < bars.length; index++) {
      if (other.bars[index] != bars[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    bounds,
    sectionId,
    sectionLabel,
    labelBand,
    Object.hashAll(bars),
  );

  @override
  String toString() =>
      'PlacedSystem(${bars.length} bar(s)${sectionLabel == null ? '' : ', "$sectionLabel"'})';
}

/// One page of engraved music.
class PageLayout {
  /// Creates a page with the given [index], page [size] and [systems].
  const PageLayout({
    required this.index,
    required this.size,
    required this.systems,
    this.scale = 1,
  });

  /// Zero-based page number.
  final int index;

  /// The page's extent, in the coordinates the page was engraved in. This is the size the caller
  /// asked for, not the extent of its content.
  final LayoutSize size;

  /// The systems on this page, top to bottom.
  final List<PlacedSystem> systems;

  /// The factor that maps this page's coordinates onto the surface it is drawn on.
  ///
  /// Every rectangle above is in engraved page coordinates; a renderer must scale by this factor
  /// before drawing. It is 1 for an ordinary page, and below 1 for the single page the FIT mode
  /// produces: there the page was engraved at `size / scale` so that the systems could be packed
  /// wide, and shrinking the result by [scale] lands it inside the surface the caller measured.
  /// Keeping the geometry in one coordinate system and this factor as the only bridge is what
  /// lets a hit test, an annotation anchor and a golden image each apply one transform instead of
  /// each re-deriving the fit.
  final double scale;

  /// Every bar on this page, in reading order.
  List<PlacedBar> get bars => <PlacedBar>[
    for (final PlacedSystem system in systems) ...system.bars,
  ];

  // PURPOSE: Turn a point on the surface the page is drawn on into the point in this page's own
  //          coordinates that lies under it. This is the inverse of the single transform the
  //          renderer applies, and it exists here because a hit test given a surface point would
  //          otherwise have to know that [scale] exists — and a hit test that assumes scale 1 is
  //          wrong ONLY for a fitted page, which is the failure hardest to notice, because every
  //          ordinary page still answers correctly.
  // INPUTS: surfacePoint — a position measured from the top-left of the rectangle the page is
  //         drawn into, in logical pixels. This is the coordinate a pointer event arrives in when
  //         the page fills its widget.
  // OUTPUTS: The position in this page's engraved coordinates. Equal to [surfacePoint] when
  //          [scale] is 1, so an ordinary page pays nothing; divided by [scale] otherwise. A
  //          non-positive [scale] is not produced by the engine — [LayoutEngine] emits 1 or a
  //          value at or above its legibility floor — so no clamp is applied here: a page a
  //          caller built by hand with a meaningless scale yields a meaningless, visible result
  //          rather than a plausible-looking wrong one.
  // KEYWORDS: coordinate-transform, page-scale, fit, hit-testing, single-bridge, inverse
  /// Returns the point of this page under [surfacePoint].
  LayoutOffset pagePointOf(LayoutOffset surfacePoint) => scale == 1
      ? surfacePoint
      : LayoutOffset(surfacePoint.x / scale, surfacePoint.y / scale);

  @override
  bool operator ==(Object other) {
    if (other is! PageLayout ||
        other.index != index ||
        other.size != size ||
        other.scale != scale ||
        other.systems.length != systems.length) {
      return false;
    }
    for (int index = 0; index < systems.length; index++) {
      if (other.systems[index] != systems[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(index, size, scale, Object.hashAll(systems));

  @override
  String toString() =>
      'PageLayout($index, ${systems.length} system(s), ${bars.length} bar(s)'
      '${scale == 1 ? '' : ', scale $scale'})';
}
