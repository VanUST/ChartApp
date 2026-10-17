// PURPOSE: Read the NOTES a musician wrote on the melody staff out of the vector ink he wrote them
//          with, and give each one a pitch, a beat and a position inside that beat. A notehead's
//          vertical position on the staff IS its pitch — on a treble staff the second space from the
//          bottom is A4 by definition — so reading a melody needs no model, no weights and no
//          dependency: it needs the staff's own geometry, which this application HAS as numbers, and
//          one subtraction. That is why this file exists and why it is here rather than in the app:
//          it runs on Android, iOS, the desktop and the browser with nothing to install.
//
//          WHAT IT IS PORTED FROM, AND HOW MUCH OF THAT SURVIVES. The method was proved outside the
//          application on a RASTER of this repository's own engraving (`geometry_notes.py`, measured
//          at 16/16 pitch and 16/16 stem direction on four notes per bar at the app's own spacing,
//          clean and pen-degraded, with zero false positives). The measurement is the argument for
//          building this, so the port keeps the parts that were measured and drops the parts that
//          were only ever a way of getting pixels:
//
//            * SURVIVES EXACTLY — the notehead SHAPE RULES and their constants, all expressed in
//              staff spaces: a row of ink counts when its extent is between 0.5 and 1.7 notehead
//              widths; a band of such rows must be at least 0.55 head-heights tall; the band must
//              TAPER (an ellipse does, a beam does not); a row wider than the gate is skipped
//              rather than ending the band, and consecutive counted rows are BRIDGED across a gap
//              of a quarter of a space, which is what keeps a notehead whole when it sits ON a
//              ledger line. And the pitch arithmetic survives verbatim: `step = 4 − (y − middle) /
//              (space / 2)`, rounded, with the clef GIVEN by the document rather than recognised.
//            * DOES NOT SURVIVE, because there is nothing to recover — finding the five staff lines,
//              clustering them, removing them "only where thin", and removing ledger lines by the
//              same rule. All of that existed to discover from pixels a geometry this application
//              already stores as numbers: the staff's middle line, its space, its clef and its cell
//              columns all arrive in a [MelodyStaffFrame]. The three steps that dominated the
//              prototype's 10–16 ms per bar are gone rather than optimised.
//            * CHANGES — the input. The musician's ink is not a photograph: it is [InkStroke]
//              polylines with a known nib width, already in the page's own coordinates. This file
//              therefore does not threshold, denoise or dilate anything; it STAMPS each stroke at
//              its own nib width onto a grid whose cell is a FRACTION OF A STAFF SPACE, which is
//              the one grid in the pipeline and is arithmetic on the musician's own stroke rather
//              than an imported image.
//            * CHANGES, and this is the part the raster could not do at all — the DISPATCH. The
//              prototype had no cells, so it matched its noteheads to the truth by nearest x. Here
//              the bar publishes the columns its beats were engraved at, so which beat a notehead
//              belongs to is read, and the order of heads inside one beat gives the sub-beat ordinal
//              that [BeatNote.step] stores (A75: `step` is TIME, and the engraver draws step k at
//              the k-th position across the cell).
//
//          WHAT IT DELIBERATELY DOES NOT DO, AND EACH IS A BOUND THE MEASUREMENT HAS TOO:
//            * DURATIONS. Beams, flags and dots are not read, so a recognised note has no rhythm.
//              `recognisedNoteValue` in `melody_note_writer.dart` says what value it is given
//              instead and why, and it is not a guess dressed as a reading.
//            * ACCIDENTALS. A sharp or flat is a separate glyph left of the head, and it is not
//              read; every recognised pitch is a NATURAL. The sign is rejected as ink too narrow to
//              be a head, so it is not misreported either.
//            * STEMS. Stem direction was measured on the raster (16/16) and is NOT read here: the
//              engraver already derives it from the pitch (A70, A74), so reading it from ink would
//              be a second answer to a question the model already answers.
//            * A NOTEHEAD IS NOT A LETTER. A chord symbol drawn on the same bar is ink too, and a
//              blob that passes the shape gates would be a false note. Two things stop it: the
//              place gate — a head whose centre is not inside the melody band the page reserved
//              cannot be on the staff — and the shape gates themselves. Both are measured against
//              the owner's real chord ink in `tool/probe_note_reader.dart`; the numbers are in the
//              decision record and the judgement about them is not made here.
// INPUTS: The ink of ONE BAR as [PageInkStroke] values — points already translated onto the page,
//         each with the nib width it was drawn at — and the [MelodyStaffFrame] of that bar, which
//         the page publishes through [melodyFramesOfPage]. The frame carries the middle line, the
//         staff space, the clef, the band a notehead's centre may lie in, and the columns the bar's
//         beats were engraved at. Nothing in this file reads a file, a device or a clock.
// OUTPUTS: A [MelodyNoteReading]: the heads it accepted in reading order, each with its page
//          position, its staff step, the pitch that step names, its beat and its sub-beat ordinal;
//          and, for every blob it refused, the gate that refused it. Detection is TOTAL — a shape
//          this reader cannot name is a [MelodyNoteRejection], never an exception — and a bar with
//          no ink yields an empty reading rather than a failure. Nothing is written anywhere: the
//          caller decides what to do with the reading, and `melody_note_writer.dart` is the one
//          place that turns it into operations.
// KEYWORDS: note-reading, geometry, notehead, staff-step, pitch, beat-dispatch, ink, pure-dart,
//          no-model, no-dependency, d37, ported-from-measurement
import 'dart:math' as math;

import 'package:chart_core/src/ink/page_anchor.dart';
import 'package:chart_core/src/layout/geometry.dart';
import 'package:chart_core/src/layout/melody_staff.dart';
import 'package:chart_core/src/layout/page_layout.dart';
import 'package:chart_core/src/oplog/oplog.dart';
import 'package:chart_core/src/song/note.dart';

/// The numeric gates a blob of ink must pass to count as a notehead.
///
/// ONE OBJECT RATHER THAN SCATTERED LITERALS, so that the thresholds this feature lives or dies by
/// can be read, argued with and changed in one place, and so that the probe which reports them on
/// the owner's own ink reports the same numbers the reader uses.
///
/// EVERY VALUE IS IN STAFF SPACES OR AS A RATIO, NEVER IN PIXELS, which is what makes the gates
/// survive a change of staff size: the staff space is the unit the engraving is built from
/// (`LayoutStyle.melodyStaffSpace`), so a page engraved at 13 and a page engraved at 26 are read by
/// the same rules. The four defaults below are not invented here — they are the four the raster
/// prototype was measured with, carried over unchanged so that its numbers and this port's numbers
/// mean the same thing.
class MelodyNoteThresholds {
  /// Creates a threshold set; the defaults are the ones the measurement used.
  const MelodyNoteThresholds({
    this.minHeadWidthFraction = 0.5,
    this.maxHeadWidthFraction = 1.7,
    this.minBandHeightFraction = 0.55,
    this.minTaper = 0.15,
    this.bandBridgeSpaces = 0.25,
    this.minInkAreaFraction = 0.12,
    this.cellsPerSpace = 12,
    this.lineRunHeadWidths = 1.8,
    this.lineThicknessSpaces = 0.45,
  });

  /// The measured set: the defaults, named so a caller can say which rules it used.
  static const MelodyNoteThresholds standard = MelodyNoteThresholds();

  /// The narrowest a row of counted ink may be, as a fraction of a notehead's width.
  ///
  /// A notehead is `MelodyMetrics.noteheadWidth` wide, so half of it is the floor. The gate is what
  /// rejects a STEM (a hairline, about a tenth of a head), an accidental and a stroke's own
  /// wobble; it is deliberately generous, because the upper gate is what separates the shapes that
  /// matter and a floor that cut into a real notehead would lose a note rather than refuse a mark.
  final double minHeadWidthFraction;

  /// The widest a row of counted ink may be, as a fraction of a notehead's width.
  ///
  /// 1.7 is the measured ceiling: a notehead drawn by a hand overshoots its engraved box
  /// (`MelodyMetrics.noteheadWidth`), and the raster prototype read heads up to 1.026 of a head's
  /// width, so the gate sits well above a drawing hand and below the next wide thing on the staff.
  /// What it rejects is everything that is LONGER than a notehead and would otherwise be read as
  /// one: a ledger line is 2.6 spaces (2.17 head widths), a staff line and a beam are longer still.
  ///
  /// AND IT IS THE GATE THAT A PAIR OF OVERLAPPING NOTEHEADS FAILS, which is why the cell width is
  /// a musical decision and not a cosmetic one: two heads on adjacent beats whose columns are
  /// narrower than a head MERGE into one blob whose rows are two heads wide, every row fails this
  /// gate, and the bar reports no notes at all. See `LayoutStyle.minCellWidth`.
  final double maxHeadWidthFraction;

  /// The least height of a band of counted rows, as a fraction of a notehead's height.
  ///
  /// A dot, a ledger line, a beamlet and a stroke's tapered end are all thinner than this, and the
  /// minimum band is what stops each of them being reported as a note. 0.55 is the measured value:
  /// a drawn notehead's counted band came to about 0.9 of a head's height, and its hollow form a
  /// little less, because the ring's own stroke is what carries the widest rows.
  final double minBandHeightFraction;

  /// The least relative change of width across a band that counts as a TAPER.
  ///
  /// `(widest row − narrowest row) / widest row`. This is the gate that separates a notehead from
  /// a beam or a beamlet, which are rectangles about a space long and half a space thick: a
  /// rectangle does not taper, an ellipse does. Without it a thick horizontal stroke of the right
  /// length is indistinguishable from a notehead by length alone.
  final double minTaper;

  /// The largest gap, in staff spaces, that counted rows may leave and still be ONE band.
  ///
  /// A notehead that SITS ON a ledger line has that line's row inside its own vertical extent, and
  /// the row is skipped as too wide rather than counted. Without a bridge the head would be cut
  /// into two bands, each too short to pass the height gate, and the note would vanish — which is
  /// exactly the regression the raster prototype hit and fixed when it added ledger-line removal
  /// (`MelodyMetrics.strokeWidth` is 0.12 of a space, so a quarter of a space is the drawn
  /// thickness of such a line with room to spare).
  final double bandBridgeSpaces;

  /// The least ink area of a component, as a fraction of a notehead's area.
  ///
  /// A guard against a few stray cells that happen to form a wide short run; the shape gates
  /// normally refuse them first, and this one makes sure a single sample's worth of ink can never
  /// be reported as a note.
  final double minInkAreaFraction;

  /// How many grid cells one staff space is divided into.
  ///
  /// THE RESOLUTION OF THE ONLY GRID IN THIS PIPELINE, and it is a fraction of the staff's own
  /// unit rather than a number of pixels, so the same value serves a page engraved at 13 or at 26.
  ///
  /// WHY TWELVE, DERIVED RATHER THAN PICKED. The narrowest thing this reader has to keep apart is
  /// the clear space between two noteheads on ADJACENT beats, which is
  /// `LayoutStyle.minCellWidth − MelodyMetrics.noteheadWidth × melodyStaffSpace` = 18 − 15.6 = 2.4
  /// pixels = 0.185 of a staff space at the default engraving. A row's extent is counted in whole
  /// cells, so the grid must be at least twice as fine as that gap or one cell of quantisation
  /// closes it and two notes become one blob — the very failure the cell width was widened to
  /// prevent. Half of 0.185 is 0.092, and 1 / 0.092 = 10.8, so twelve is the smallest round number
  /// above the floor. A coarser grid still reads the notes; it loses the SEPARATION between two of
  /// them.
  final int cellsPerSpace;

  /// How long a horizontal run of ink must be before it is INK THAT IS NOT A NOTEHEAD, in
  /// notehead widths.
  ///
  /// A notehead is one head wide; a ledger line is `MelodyMetrics.ledgerWidth` = 2.6 staff spaces =
  /// 2.17 head widths, a beam is longer, and the five staff lines are longer still. 1.8 is the
  /// prototype's measured value: above any drawn head, below a ledger line.
  ///
  /// SUCH INK IS REMOVED RATHER THAN MERELY NOT COUNTED, and the distinction cost this port a
  /// measurement. "Too long to be a head" is enough to stop a row being COUNTED, and that is all the
  /// first version did — after which a bar of four quarter notes reported two, because a ledger line
  /// runs from one note's column into its NEIGHBOUR'S head, welding the two notes into ONE component
  /// whose stem rows then measured twenty pixels wide. Removing the line's own cells is what the
  /// prototype did and why; see [lineThicknessSpaces] for the half of the rule that keeps a head
  /// whole.
  final double lineRunHeadWidths;

  /// How thick ink may be, in staff spaces, and still be treated as a line rather than as part of a
  /// notehead.
  ///
  /// THE OTHER HALF OF THE RULE, and the half that makes it safe: a ledger line drawn THROUGH a
  /// notehead is only erased where it is a line. The head's own columns are `noteheadHeight` = 0.9
  /// of a space thick and are kept, so the head survives intact and the note sitting on the line is
  /// still found. The prototype erased the whole run and lost three of ten notes, which is why this
  /// half exists at all.
  ///
  /// WHY HALF A NOTEHEAD AND NOT THE PROTOTYPE'S 0.3. A line's drawn thickness is the PEN's, not a
  /// constant: the prototype's 0.3 of a space assumed a fine nib, and the pen-degraded pass here —
  /// a 4.4-pixel nib on a 13-pixel staff — draws a ledger line 4.4 pixels thick, which is 0.34 of a
  /// space and slipped past 0.3. The gate then failed to remove the line, two notes welded together
  /// exactly as they do in the clean case, and five of sixteen notes were lost. Half a head's height
  /// is the largest a line can be and still leave a notehead readable around it, so it is the bound
  /// that does not depend on how hard the musician presses.
  final double lineThicknessSpaces;

  @override
  String toString() =>
      'MelodyNoteThresholds(head=$minHeadWidthFraction..$maxHeadWidthFraction, '
      'band>=$minBandHeightFraction, taper>=$minTaper, bridge=$bandBridgeSpaces, '
      'area>=$minInkAreaFraction, cells/space=$cellsPerSpace)';
}

/// The gate a blob of ink failed, so a refusal can be printed instead of guessed at.
enum MelodyNoteRejection {
  /// The ink is narrower than half a notehead, so it is a stem, an accidental or a wobble.
  tooNarrow('too-narrow'),

  /// No row of the ink was narrow enough to be a notehead: it is a line or a beam.
  noCountedRow('no-counted-row'),

  /// There is too little ink to be a notehead at all.
  tooLittleInk('too-little-ink'),

  /// The band of counted rows is shorter than a notehead.
  tooThin('too-thin'),

  /// The band does not taper, so it is a rectangle: a beam or a beamlet.
  notTapered('not-tapered'),

  /// The head lies outside the band the page reserved for the melody staff, so it is not a note of
  /// this staff — a chord symbol in the chord row above it is the case this gate exists for.
  outsideTheStaff('outside-the-staff'),

  /// The head's position decodes to a staff step this staff cannot write, five ledger lines past
  /// the five lines (`melodyLowestStep` … `melodyHighestStep`).
  notOnTheStaff('not-on-the-staff'),

  /// The head lies to the left of the bar's first column or to the right of its last, so it is ink
  /// beside the music rather than at a beat of it.
  beyondTheBar('beyond-the-bar');

  const MelodyNoteRejection(this.token);

  /// Stable spelling used in a log line and in a probe's output.
  final String token;
}

/// One column of a bar: a beat, and the x range its column was engraved in.
///
/// The range rather than just a left edge, because a notehead has width and a head drawn near a
/// column's edge belongs to the column it mostly stands in; the column is also what turns a
/// measured x into the beat address the model stores.
class MelodyBeatColumn {
  /// Creates the column of [beat] spanning [left] to [right], in the frame's coordinates.
  const MelodyBeatColumn({
    required this.beat,
    required this.left,
    required this.right,
  });

  /// Zero-based cell index inside the bar, the address a chord uses too.
  final int beat;

  /// The column's left edge.
  final double left;

  /// The column's right edge.
  final double right;

  /// The column's width.
  double get width => right - left;

  @override
  String toString() =>
      'MelodyBeatColumn($beat ${left.toStringAsFixed(1)}..'
      '${right.toStringAsFixed(1)})';
}

/// The melody staff of one bar as NUMBERS: where its middle line is, how far apart its lines are,
/// which clef names it, which band a notehead may lie in, and where its beats were engraved.
///
/// This is the whole of what the raster prototype had to recover from pixels and could not: it
/// found the five lines by looking for long horizontal runs, checked they were equally spaced, and
/// removed them. Here they arrive as numbers, so the reader never has to decide which line is which
/// or whether a run of ink is a staff line or a beam. The clef is part of the frame because the
/// DOCUMENT knows it (D37, `Song.staffSet`), which is the structural advantage this application has
/// over any paper-photo reader: no clef identification is needed or attempted.
class MelodyStaffFrame {
  /// Creates a frame for a staff whose middle line is at [middleLineY].
  const MelodyStaffFrame({
    required this.middleLineY,
    required this.staffSpace,
    required this.headTop,
    required this.headBottom,
    required this.beatColumns,
    this.clef = 'treble',
    this.metrics = const MelodyMetrics(),
  });

  /// The y of the staff's MIDDLE line, in the coordinate space of the ink being read.
  ///
  /// The middle line and not the top one, because the pitch arithmetic counts from it: the middle
  /// line is staff step 4 on both clefs (`melodyStepCenterY`), so a frame built from any other line
  /// would need a second offset and the two could disagree.
  final double middleLineY;

  /// The distance between two adjacent staff lines, in the same units as [middleLineY].
  ///
  /// THE UNIT OF THE WHOLE READING: a staff step is half of it, a notehead's width is 1.2 of it, and
  /// every threshold in [MelodyNoteThresholds] is a ratio of it. It is the staff's own value and not
  /// a constant of this file, so a page engraved at a different density is read by the same rules.
  final double staffSpace;

  /// The topmost y a notehead's CENTRE may lie at, inclusive.
  ///
  /// It is the melody band's top, clamped to the chord row's bottom, and it is the PLACE gate: a
  /// chord symbol is drawn in the chord row above the staff, so a blob of ink whose centre is above
  /// this line is not on the melody staff however notehead-like its shape. A note at the top of the
  /// band has its centre a little BELOW this value, so the gate does not cut into the music.
  final double headTop;

  /// The bottommost y a notehead's centre may lie at, inclusive; the mirror of [headTop].
  final double headBottom;

  /// The bar's beat columns, in ascending order, as the layout engraved them.
  ///
  /// A head is dispatched to the column it stands in, and the columns are also why this reader
  /// needs no truth to score against: the beat a note belongs to is read from the page's own
  /// geometry rather than matched to an answer.
  final List<MelodyBeatColumn> beatColumns;

  /// The clef this staff is written in, `treble` or `bass`, GIVEN rather than recognised.
  final String clef;

  /// The proportions of the engraving, so that a notehead's width and height are the rendered
  /// ones and a caller with a different density needs no second set of numbers.
  final MelodyMetrics metrics;

  /// How wide a notehead is in this frame's units.
  double get headWidth => metrics.noteheadWidth * staffSpace;

  /// How tall a notehead is in this frame's units.
  double get headHeight => metrics.noteheadHeight * staffSpace;

  /// The staff step a y decodes to, before any clamping or range check.
  ///
  /// THE ONE LINE OF ARITHMETIC THE WHOLE FEATURE RESTS ON, written as the inverse of
  /// [melodyStepCenterY]: on a staff whose middle line is step 4 and whose step is half a space,
  /// the step at a y is `4 − (y − middle) / (space / 2)`, rounded. No clamp happens here — a
  /// position past what the staff can write must be REFUSED by the caller rather than silently
  /// moved to the last writable line, or a chord symbol high above the staff would be reported as a
  /// note at the top of it.
  int stepAtY(double y) => (4 - (y - middleLineY) / (staffSpace / 2)).round();

  /// The column a head centred at [x] stands in, or null when it stands in none of them.
  ///
  /// The column CONTAINING x is taken, boundary inclusive on the left and exclusive on the right so
  /// that two adjacent columns cannot both claim a head exactly on their shared edge. A head drawn
  /// half in one column and half in the next belongs to the one its centre is in.
  ///
  /// NULL IS A REAL ANSWER AND NOT A NEAREST GUESS. A head in the bar's padding, on the barline or
  /// outside the bar was not written at a beat, and claiming the nearest one would put a note on the
  /// page that the musician did not write — the same reasoning that makes a stroke the page cannot
  /// place a refusal rather than a fabricated rectangle. The caller reports it as
  /// [MelodyNoteRejection.beyondTheBar].
  MelodyBeatColumn? columnAt(double x) {
    for (final MelodyBeatColumn column in beatColumns) {
      if (x >= column.left && x < column.right) {
        return column;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'MelodyStaffFrame(middle=${middleLineY.toStringAsFixed(1)}, '
      'space=${staffSpace.toStringAsFixed(1)}, $clef, '
      'heads ${headTop.toStringAsFixed(1)}..${headBottom.toStringAsFixed(1)}, '
      '${beatColumns.length} column(s))';
}

/// One committed stroke placed on the PAGE: its points translated by its anchor's origin, together
/// with the nib width it was drawn at.
///
/// It mirrors `PlacedInkStroke` for the barline detector, and it exists for the same reason: the
/// ink of one bar is captured against several anchors — a cell when the stroke began over the chord
/// row, the bar itself when it began on the staff, which lies below every cell — so the only space
/// in which two of them can be compared is the page's.
class PageInkStroke {
  /// Places [points], drawn with a nib [nib] wide, under [id].
  const PageInkStroke({
    required this.id,
    required this.points,
    required this.nib,
  });

  /// The stroke's identity, carried so a refusal can name the ink it refused.
  final String id;

  /// The stroke's samples, in the page's own coordinates.
  final List<LayoutOffset> points;

  /// The nib width the stroke was drawn at, in the same units as [points].
  ///
  /// It is the reason this reader needs no threshold: a stroke has a KNOWN width, so the ink it
  /// covers is arithmetic on the musician's own stroke rather than a guess about a scan's darkness.
  final double nib;

  @override
  String toString() =>
      'PageInkStroke($id, ${points.length} point(s), nib ${nib.toStringAsFixed(1)})';
}

/// A notehead this reader accepted, with everything the model and a probe need to know about it.
class MelodyNoteHead {
  /// Creates a head centred at ([x], [y]) standing at staff [step] of [beat], [orderInBeat]-th.
  const MelodyNoteHead({
    required this.x,
    required this.y,
    required this.step,
    required this.beat,
    required this.orderInBeat,
    required this.pitch,
    required this.widthFraction,
    required this.bandFraction,
  });

  /// The head's horizontal centre, in the frame's coordinates.
  final double x;

  /// The head's vertical centre, in the frame's coordinates — the number the pitch comes from.
  final double y;

  /// The staff step the head's centre decodes to: 0 is the staff's bottom line, 4 its middle line.
  final int step;

  /// The beat (cell) of the bar the head stands in, as the page's columns name it.
  final int beat;

  /// The head's position INSIDE its beat, counting from the left: 0 is the first note of the cell,
  /// which is the ordinal [BeatNote.step] stores and the engraver draws at the k-th x (A75).
  final int orderInBeat;

  /// The pitch that staff step names, with a NATURAL alteration.
  ///
  /// THE ALTERATION IS ALWAYS 0 AND THIS IS NOT A DEFAULT. A staff step carries a letter and an
  /// octave; a sharp or a flat is a separate sign drawn beside the head, and this reader does not
  /// read it. A caller that needs the written accidental must say that this reading does not
  /// supply one, which is why it is stated on the field itself rather than in a comment a reader of
  /// the class might not reach.
  final PitchedNote pitch;

  /// The counted ink's width divided by a notehead's width.
  ///
  /// The prototype reported this as its `score` column, and it is kept and reported for the same
  /// reason: a head read at 1.02 of a head's width is a clean one and a head read at 1.63 is nearly
  /// a beam, and a probe that printed only the count would hide the difference.
  final double widthFraction;

  /// The counted band's height divided by a notehead's height; 1.0 is an ordinary drawn head.
  final double bandFraction;

  @override
  String toString() =>
      'MelodyNoteHead($pitch at step $step, beat $beat.$orderInBeat, '
      'x=${x.toStringAsFixed(1)} y=${y.toStringAsFixed(1)}, '
      'w=${widthFraction.toStringAsFixed(2)})';
}

/// One blob of ink the reader refused, with the gate that refused it.
///
/// A refusal is a RESULT and not an error: the raster prototype's honest abstention was that "a head
/// that fails the gates is simply not reported", and the count of what was refused is the other half
/// of the argument — a reader that reported no notes on a bar full of ink would otherwise look the
/// same whether it had refused ten blobs or found none.
class MelodyNoteRefusal {
  /// Creates a refusal of a blob centred at ([x], [y]) for [reason].
  const MelodyNoteRefusal({
    required this.x,
    required this.y,
    required this.nib,
    required this.reason,
    this.widthFraction = 0,
    this.bandFraction = 0,
  });

  /// The refused blob's horizontal centre, in the frame's coordinates.
  final double x;

  /// The refused blob's vertical centre, in the frame's coordinates.
  final double y;

  /// The widest nib among the strokes that make up the blob, so a reader can tell a hairline from a
  /// heavy stroke in a probe's output.
  final double nib;

  /// The gate it failed.
  final MelodyNoteRejection reason;

  /// The blob's widest counted row, as a fraction of a notehead's width; zero when none counted.
  final double widthFraction;

  /// The blob's counted band height, as a fraction of a notehead's height; zero when none counted.
  final double bandFraction;

  @override
  String toString() =>
      'MelodyNoteRefusal(${reason.token} at '
      '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)} '
      'w=${widthFraction.toStringAsFixed(2)} h=${bandFraction.toStringAsFixed(2)})';
}

/// What reading one bar produced: the heads, in reading order, and every blob that was refused.
class MelodyNoteReading {
  /// Creates the reading of ([sectionId], [barIndex]).
  const MelodyNoteReading({
    required this.sectionId,
    required this.barIndex,
    required this.heads,
    required this.refusals,
  });

  /// A reading that found nothing, which is what a bar with no ink yields.
  MelodyNoteReading.empty(this.sectionId, this.barIndex)
    : heads = const <MelodyNoteHead>[],
      refusals = const <MelodyNoteRefusal>[];

  /// The section the bar belongs to.
  final String sectionId;

  /// Zero-based index of the bar inside that section.
  final int barIndex;

  /// The accepted heads, ordered by beat and then by their position inside the beat.
  final List<MelodyNoteHead> heads;

  /// The blobs that were refused, in the order they were found.
  final List<MelodyNoteRefusal> refusals;

  /// Whether the bar's ink yielded no notes at all.
  bool get isEmpty => heads.isEmpty;

  /// How many blobs of ink were weighed, accepted or refused.
  int get blobsConsidered => heads.length + refusals.length;

  @override
  String toString() =>
      'MelodyNoteReading($sectionId bar $barIndex: ${heads.length} head(s), '
      '${refusals.length} refusal(s))';
}

/// Reads notes out of the ink of one bar.
///
/// It is a class rather than a function only so that a caller can hold a threshold set; the reader
/// itself is stateless and const.
class MelodyNoteReader {
  /// Creates a reader using [thresholds].
  const MelodyNoteReader({this.thresholds = MelodyNoteThresholds.standard});

  /// The gates this reader applies.
  final MelodyNoteThresholds thresholds;

  /// Reads the heads of ONE BAR from [ink], against [frame].
  ///
  /// The ink must be the whole of that bar's ink in ONE coordinate space and nothing else: a stroke
  /// of a neighbouring bar has its own origin, and comparing the two would be comparing two
  /// translations. [melodyInkOfBar] builds exactly that input from a page and a bar's address.
  MelodyNoteReading read({
    required String sectionId,
    required int barIndex,
    required List<PageInkStroke> ink,
    required MelodyStaffFrame frame,
  }) {
    if (ink.isEmpty || frame.staffSpace <= 0) {
      return MelodyNoteReading.empty(sectionId, barIndex);
    }
    final _InkGrid? grid = _InkGrid.of(
      ink: ink,
      frame: frame,
      thresholds: thresholds,
    );
    if (grid == null) {
      return MelodyNoteReading.empty(sectionId, barIndex);
    }
    final List<_InkBlob> blobs = grid.blobs(frame);
    final List<MelodyNoteHead> heads = <MelodyNoteHead>[];
    final List<MelodyNoteRefusal> refusals = <MelodyNoteRefusal>[];
    for (final _InkBlob blob in blobs) {
      final _BlobVerdict verdict = blob.weigh(frame, thresholds);
      if (verdict.headX == null || verdict.headY == null) {
        refusals.add(
          MelodyNoteRefusal(
            x: blob.centreX,
            y: blob.centreY,
            nib: blob.widestNib,
            reason: verdict.rejection ?? MelodyNoteRejection.noCountedRow,
            widthFraction: verdict.widthFraction,
            bandFraction: verdict.bandFraction,
          ),
        );
        continue;
      }
      final double x = verdict.headX!;
      final double y = verdict.headY!;
      final int step = frame.stepAtY(y);
      final MelodyBeatColumn? column = frame.columnAt(x);
      MelodyNoteRejection? place;
      if (y < frame.headTop || y > frame.headBottom) {
        place = MelodyNoteRejection.outsideTheStaff;
      } else if (step < melodyLowestStep || step > melodyHighestStep) {
        place = MelodyNoteRejection.notOnTheStaff;
      } else if (column == null) {
        place = MelodyNoteRejection.beyondTheBar;
      }
      if (place != null || column == null) {
        refusals.add(
          MelodyNoteRefusal(
            x: x,
            y: y,
            nib: blob.widestNib,
            reason: place ?? MelodyNoteRejection.beyondTheBar,
            widthFraction: verdict.widthFraction,
            bandFraction: verdict.bandFraction,
          ),
        );
        continue;
      }
      heads.add(
        MelodyNoteHead(
          x: x,
          y: y,
          step: step,
          beat: column.beat,
          // Filled in below, once every head of this cell is known: the ordinal is a RANK among
          // the heads of one beat, and a single head's own position cannot say what that rank is.
          orderInBeat: 0,
          pitch: melodyPitchOfStep(step, clef: frame.clef),
          widthFraction: verdict.widthFraction,
          bandFraction: verdict.bandFraction,
        ),
      );
    }
    return MelodyNoteReading(
      sectionId: sectionId,
      barIndex: barIndex,
      heads: _orderedByBeat(heads),
      refusals: refusals,
    );
  }

  // PURPOSE: Give every head of a beat its ordinal inside that beat, and hand the heads back in
  //          reading order, which is the order the model addresses them in.
  // INPUTS: heads — the accepted heads, in the order the blobs were found.
  // OUTPUTS: The same heads, one per beat sorted left to right, and beats ascending. The ordinal is
  //          the head's RANK by x within its own beat: the leftmost head of a cell is 0 and the
  //          engraver draws step 0 leftmost (A75), so the ordinal is `BeatNote.step` and reading it
  //          from the drawing is the same statement the engraver makes.
  //
  //          An empty list yields an empty list; a bar whose heads all fall in one beat yields that
  //          beat's heads in x order.
  // KEYWORDS: sub-beat-order, step-ordinal, reading-order, left-to-right, a75
  List<MelodyNoteHead> _orderedByBeat(List<MelodyNoteHead> heads) {
    final List<MelodyNoteHead> sorted = <MelodyNoteHead>[...heads]
      ..sort((MelodyNoteHead a, MelodyNoteHead b) {
        if (a.beat != b.beat) {
          return a.beat.compareTo(b.beat);
        }
        return a.x.compareTo(b.x);
      });
    final List<MelodyNoteHead> ordered = <MelodyNoteHead>[];
    int beat = -1;
    int order = 0;
    for (final MelodyNoteHead head in sorted) {
      if (head.beat != beat) {
        beat = head.beat;
        order = 0;
      }
      ordered.add(
        MelodyNoteHead(
          x: head.x,
          y: head.y,
          step: head.step,
          beat: head.beat,
          orderInBeat: order,
          pitch: head.pitch,
          widthFraction: head.widthFraction,
          bandFraction: head.bandFraction,
        ),
      );
      order++;
    }
    return ordered;
  }
}

/// Reads the notes of one bar of [page] out of [strokes], the whole document's ink.
///
/// The convenience the application calls: it places the ink, filters it to the bar and builds the
/// frame, so a caller holding a page and a stroke list needs no geometry of its own.
MelodyNoteReading readMelodyNotesOfBar({
  required PageLayout page,
  required List<InkStroke> strokes,
  required String sectionId,
  required int barIndex,
  MelodyNoteReader reader = const MelodyNoteReader(),
}) {
  final MelodyStaffFrame? frame = melodyFramesOfPage(
    page,
  )[_barKey(sectionId, barIndex)];
  if (frame == null) {
    return MelodyNoteReading.empty(sectionId, barIndex);
  }
  return reader.read(
    sectionId: sectionId,
    barIndex: barIndex,
    ink: melodyInkOfBar(
      page: page,
      strokes: strokes,
      sectionId: sectionId,
      barIndex: barIndex,
    ),
    frame: frame,
  );
}

/// The frame of every bar of [page] that draws a melody staff, keyed by section and bar.
///
/// WHY THE FRAME IS BUILT FROM THE PAGE AND NOT FROM THE SONG: the numbers a reader needs — the
/// middle line's y and the beats' columns — are the LAYOUT's answers, not the model's, and the
/// layout is the only thing that knows where a staff was actually drawn. A frame built from the
/// song would have to re-derive the placement and would then be a second answer to "where is this
/// staff", which is the defect this project keeps finding.
///
/// THE HEAD WINDOW IS CLAMPED TO THE CHORD ROW'S BOTTOM, and that clamp is the place gate's whole
/// rule. The melody staff is placed BELOW the bar's own rectangle (`LayoutEngine._placeMelody`), so
/// the chord row and the staff occupy different bands of the page; a head whose centre is above the
/// bar's bottom edge is in the chord row, which is where a chord symbol is written and where a note
/// is not. The window's other end is the lowest step the engraver can write, so a mark far below the
/// staff is refused as well.
///
/// WHAT IT COSTS, STATED RATHER THAN HIDDEN: on a chart that declares a staff and holds no note yet,
/// the layout reserves the shorter empty band (`LayoutStyle.melodyEmptyBandHeight`), and that band's
/// top is the chord row's bottom — so a musician writing his FIRST melody draws inside a band whose
/// upper half does not exist, and a note he writes above the staff's top line lands in the chord row
/// and is refused. The band grows to the full height the moment the song holds one note, so this
/// window is only ever wrong on a bar before its first note is structured.
Map<String, MelodyStaffFrame> melodyFramesOfPage(PageLayout page) {
  final Map<String, MelodyStaffFrame> frames = <String, MelodyStaffFrame>{};
  for (final PlacedBar bar in page.bars) {
    final PlacedMelodyStaff staff = bar.melody;
    if (staff.isEmpty) {
      continue;
    }
    // The staff's own box is its five lines: its top is the top LINE and its bottom the bottom
    // line, so the middle line is halfway between them and a space is a quarter of the height —
    // the same two relations `melodyStepCenterY` uses in the other direction.
    final double middle = staff.bounds.top + staff.bounds.size.height / 2;
    final double space = staff.bounds.size.height / 4;
    final double writtenTop = middle + (4 - melodyHighestStep) * (space / 2);
    final double writtenBottom = middle + (4 - melodyLowestStep) * (space / 2);
    frames[_barKey(bar.sectionId, bar.barIndex)] = MelodyStaffFrame(
      middleLineY: middle,
      staffSpace: space,
      headTop: writtenTop > bar.bounds.bottom ? writtenTop : bar.bounds.bottom,
      headBottom: writtenBottom,
      beatColumns: <MelodyBeatColumn>[
        for (final PlacedCell cell in bar.cells)
          MelodyBeatColumn(
            beat: cell.beat,
            left: cell.bounds.left,
            right: cell.bounds.right,
          ),
      ],
      clef: staff.clef ?? 'treble',
    );
  }
  return frames;
}

/// The ink of one bar, in page coordinates: every stroke anchored to that bar or to one of its
/// beats, translated by the page origin its anchor resolved to.
///
/// The strokes of a bar are captured against SEVERAL anchors — a cell when the stroke began over the
/// chord row, the bar when it began on the staff, which lies below every cell — so translating each
/// by its own origin is the only way the ink of one bar becomes comparable with itself. A stroke
/// whose anchor this page cannot resolve is left out, exactly as the renderer leaves it out: ink
/// that is not on this page cannot be weighed against ink that is.
List<PageInkStroke> melodyInkOfBar({
  required PageLayout page,
  required List<InkStroke> strokes,
  required String sectionId,
  required int barIndex,
}) {
  final InkPageIndex index = InkPageIndex.ofPage(page);
  final List<PageInkStroke> ink = <PageInkStroke>[];
  for (final InkStroke stroke in strokes) {
    final EventAnchor anchor = stroke.anchor;
    if (anchor.sectionId != sectionId || anchor.bar != barIndex) {
      continue;
    }
    final InkPlacement? placement = index.placementFor(anchor);
    if (placement == null) {
      continue;
    }
    ink.add(
      PageInkStroke(
        id: stroke.id,
        points: <LayoutOffset>[
          for (final InkPoint point in stroke.points)
            inkPointToPage(point, placement.origin),
        ],
        nib: stroke.size,
      ),
    );
  }
  return ink;
}

/// The key a bar's frame is indexed by, matching the key [melodyFramesOfPage] builds.
String _barKey(String sectionId, int barIndex) => '$sectionId\u0000$barIndex';

/// Whether one component of ink, measured by its rows, is a notehead.
class _BlobVerdict {
  const _BlobVerdict({
    this.headX,
    this.headY,
    this.rejection,
    this.widthFraction = 0,
    this.bandFraction = 0,
  });

  /// The accepted head's centre, or null when the blob was refused.
  final double? headX;

  /// The accepted head's centre, or null when the blob was refused.
  final double? headY;

  /// The gate the blob failed, or null when it was accepted.
  final MelodyNoteRejection? rejection;

  /// The widest counted row, as a fraction of a notehead's width.
  final double widthFraction;

  /// The counted band's height, as a fraction of a notehead's height.
  final double bandFraction;
}

/// What one component of ink looks like when it is measured the way the prototype measured:
/// by the horizontal EXTENT of each of its rows.
class _InkBlob {
  _InkBlob({
    required this.rows,
    required this.cell,
    required this.centreX,
    required this.centreY,
    required this.width,
    required this.areaPixels,
    required this.widestNib,
  });

  /// One entry per occupied row of the component's own box, ascending: the row's y in the frame's
  /// coordinates, the extent of its ink and the centre of that extent.
  final List<_InkRow> rows;

  /// The grid's cell size, which converts an extent counted in cells into pixels.
  final double cell;

  /// The component's centre, from the ink's own bounding box.
  final double centreX;

  /// The component's centre, from the ink's own bounding box.
  final double centreY;

  /// The width of the component's own bounding box, in pixels.
  ///
  /// The gate that rejects a STEM on its own: a stem is a hairline and a notehead is not, and a
  /// component narrower than half a head is a stroke rather than a mark.
  final double width;

  /// The component's own ink area, in SQUARE PIXELS — cells counted through [cell], so that the
  /// floor it is compared with (a fraction of a notehead's area) is in the same units.
  final double areaPixels;

  /// The widest nib among the strokes that made this component.
  final double widestNib;

  // PURPOSE: Weigh this blob against the shape gates and, when it passes, report the notehead's
  //          centre — which is the single number the pitch is read from.
  // INPUTS: frame — the staff the blob was drawn on, for the head's own proportions; thresholds —
  //         the gates.
  // OUTPUTS: A verdict carrying either the head's centre or the gate that refused it. The centre is
  //          the ink-weighted mean of the COUNTED rows only, so a stem hanging off the head, whose
  //          rows are far too narrow to count, cannot pull the head down and change its pitch.
  //
  //          The gates run smallest-first, so that a refusal names the most specific thing wrong
  //          with the ink: too little ink, then the wrong width, then no row narrow enough, then a
  //          band too short, then a band that does not taper. An empty row list yields
  //          [MelodyNoteRejection.noCountedRow] rather than a division by zero.
  // KEYWORDS: notehead-shape, row-extent, band, taper, centre-of-ink, pitch-source
  _BlobVerdict weigh(MelodyStaffFrame frame, MelodyNoteThresholds thresholds) {
    final double headWidth = frame.headWidth;
    final double headHeight = frame.headHeight;
    if (areaPixels < thresholds.minInkAreaFraction * headWidth * headHeight) {
      return const _BlobVerdict(rejection: MelodyNoteRejection.tooLittleInk);
    }
    if (width < thresholds.minHeadWidthFraction * headWidth) {
      return const _BlobVerdict(rejection: MelodyNoteRejection.tooNarrow);
    }
    final double low = thresholds.minHeadWidthFraction * headWidth;
    final double high = thresholds.maxHeadWidthFraction * headWidth;
    final List<_InkRow> counted = <_InkRow>[
      for (final _InkRow row in rows)
        if (row.extent >= low && row.extent <= high) row,
    ];
    if (counted.isEmpty) {
      return const _BlobVerdict(rejection: MelodyNoteRejection.noCountedRow);
    }
    // A ledger line drawn THROUGH a notehead is wider than the gate, so its row is not counted and
    // would cut one head into two bands, each too short to accept. The bridge is a quarter of a
    // space — the drawn thickness of such a line with room to spare — and it is why the prototype's
    // ledger-line REMOVAL is not needed here at all: a line too long to be a head is not counted,
    // and the band it interrupts is rejoined across it.
    final double bridge = thresholds.bandBridgeSpaces * frame.staffSpace;
    final List<List<_InkRow>> bands = <List<_InkRow>>[];
    List<_InkRow> band = <_InkRow>[counted.first];
    for (final _InkRow row in counted.skip(1)) {
      if (row.y - band.last.y <= bridge) {
        band.add(row);
      } else {
        bands.add(band);
        band = <_InkRow>[row];
      }
    }
    bands.add(band);
    // The TALLEST band wins: a head is one band, and a disc whose top and bottom rings are counted
    // with a hollow middle — a very shallow drawn ring — would otherwise be reported twice.
    List<_InkRow> best = bands.first;
    for (final List<_InkRow> candidate in bands) {
      if (candidate.last.y - candidate.first.y > best.last.y - best.first.y) {
        best = candidate;
      }
    }
    final double bandHeight = best.last.y - best.first.y + cell;
    final double bandFraction = bandHeight / headHeight;
    final double widest = best.fold<double>(
      0,
      (double most, _InkRow row) => row.extent > most ? row.extent : most,
    );
    final double narrowest = best.fold<double>(
      double.infinity,
      (double least, _InkRow row) => row.extent < least ? row.extent : least,
    );
    final double taper = widest <= 0 ? 0 : (widest - narrowest) / widest;
    final double widthFraction = widest / headWidth;
    if (bandFraction < thresholds.minBandHeightFraction) {
      return _BlobVerdict(
        rejection: MelodyNoteRejection.tooThin,
        widthFraction: widthFraction,
        bandFraction: bandFraction,
      );
    }
    if (taper < thresholds.minTaper) {
      return _BlobVerdict(
        rejection: MelodyNoteRejection.notTapered,
        widthFraction: widthFraction,
        bandFraction: bandFraction,
      );
    }
    double weight = 0;
    double weightedY = 0;
    double weightedX = 0;
    for (final _InkRow row in best) {
      weight += row.extent;
      weightedY += (row.y + cell / 2) * row.extent;
      weightedX += row.centre * row.extent;
    }
    return _BlobVerdict(
      headX: weightedX / weight,
      headY: weightedY / weight,
      widthFraction: widthFraction,
      bandFraction: bandFraction,
    );
  }
}

/// One occupied row of a component: where it is, how wide its ink is and where that ink is centred.
class _InkRow {
  const _InkRow({required this.y, required this.extent, required this.centre});

  /// The row's y in the frame's coordinates, at the row's top edge.
  final double y;

  /// The horizontal EXTENT of the row's ink, from its leftmost cell to its rightmost, in pixels.
  ///
  /// The EXTENT and not the longest unbroken run, and the distinction is the one that makes a
  /// hollow notehead visible: a ring's widest row is two short runs with a hole between them, so a
  /// longest-run test reads it as two thin rows and every half note disappears. The extent covers
  /// the hole, which is what the notehead covers.
  final double extent;

  /// The centre of the row's ink, in the frame's coordinates.
  final double centre;
}

/// The ink of one bar stamped onto a coarse grid, so that the ROW STRUCTURE the shape gates are
/// made of can be counted.
///
/// WHY A GRID AT ALL, WHEN THE INPUT IS VECTOR. The gates that were measured are statements about
/// how wide a horizontal slice of the ink is — of a notehead against a stem, of a head against a
/// beam — and a slice is a grid concept. Doing it on a grid whose cell is a fraction of a STAFF
/// SPACE, with the ink stamped at the stroke's own nib width, is arithmetic on the musician's own
/// stroke; it is not an imported image and nothing is thresholded, denoised or dilated. The
/// alternative — measuring vector strokes only — cannot express "how wide is this row", which is
/// the question the four gates answer.
class _InkGrid {
  _InkGrid._({
    required this.cell,
    required this.left,
    required this.top,
    required this.columns,
    required this.rows,
  }) : _cells = List<int>.filled(columns * rows, 0),
       _nibs = List<double>.filled(columns * rows, 0);

  // PURPOSE: Stamp every stroke of [ink] onto a grid that covers the ink with a cell of its own, so
  //          that one pass over cells answers the row questions the gates ask.
  // INPUTS: ink — one bar's strokes in page coordinates; frame — the staff, for the cell size;
  //         thresholds — for how many cells make a staff space.
  // OUTPUTS: The grid, or null when the ink has no extent at all (a stroke of one point, or an
  //          empty list) — the caller then reports an empty reading rather than a division by zero.
  //          The grid is sized from the INK's own bounding box plus a cell of margin, so a bar of
  //          no ink costs no memory and a bar of ink is never clipped by a frame that guessed wrong.
  // KEYWORDS: rasterise, stroke-width, grid, row-extent, arithmetic-not-image
  static _InkGrid? of({
    required List<PageInkStroke> ink,
    required MelodyStaffFrame frame,
    required MelodyNoteThresholds thresholds,
  }) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    for (final PageInkStroke stroke in ink) {
      for (final LayoutOffset point in stroke.points) {
        final double r = stroke.nib / 2;
        if (point.x - r < minX) {
          minX = point.x - r;
        }
        if (point.y - r < minY) {
          minY = point.y - r;
        }
        if (point.x + r > maxX) {
          maxX = point.x + r;
        }
        if (point.y + r > maxY) {
          maxY = point.y + r;
        }
      }
    }
    if (!minX.isFinite || !minY.isFinite) {
      return null;
    }
    final double cell = frame.staffSpace / thresholds.cellsPerSpace;
    final int columns = ((maxX - minX) / cell).ceil() + 2;
    final int rows = ((maxY - minY) / cell).ceil() + 2;
    if (columns <= 0 || rows <= 0) {
      return null;
    }
    final _InkGrid grid = _InkGrid._(
      cell: cell,
      left: minX - cell,
      top: minY - cell,
      columns: columns,
      rows: rows,
    );
    for (final PageInkStroke stroke in ink) {
      grid._stampStroke(stroke);
    }
    grid._clearLongThinRuns(frame, thresholds);
    return grid;
  }

  // PURPOSE: Take the LONG THIN horizontal ink out of the grid before anything is grouped, so that
  //          a ledger line cannot weld its own note to the note beside it.
  // INPUTS: frame — the staff, whose unit every length below is measured in; thresholds — the two
  //         numbers this rule is made of.
  // OUTPUTS: Nothing; the grid is edited. A horizontal run longer than
  //          [MelodyNoteThresholds.lineRunHeadWidths] notehead widths is a line, a beam or a staff
  //          line rather than a notehead, and each of its COLUMNS is cleared only where the vertical
  //          run through that column is thinner than [MelodyNoteThresholds.lineThicknessSpaces] — so
  //          the line goes and a notehead it crosses stays whole. A page whose ink holds no such run
  //          is unchanged, and an empty grid does nothing.
  //
  //          WHY THE VERTICAL RUN AND NOT THE HORIZONTAL ONE. A notehead that sits ON a ledger line
  //          is thick exactly where the line crosses it, so the thick columns are the head's and the
  //          thin ones are the line's. Erasing the whole horizontal run instead would cut the head
  //          into two halves, each too short to pass the band gate — measured as three lost notes in
  //          ten by the prototype, and the reason this half of the rule exists at all.
  // KEYWORDS: line-removal, ledger-line, thin-only, vertical-run, weld, separation
  void _clearLongThinRuns(
    MelodyStaffFrame frame,
    MelodyNoteThresholds thresholds,
  ) {
    final int runLimit = (thresholds.lineRunHeadWidths * frame.headWidth / cell)
        .round();
    final int thinLimit =
        (thresholds.lineThicknessSpaces * frame.staffSpace / cell).round();
    for (int row = 0; row < rows; row++) {
      int column = 0;
      while (column < columns) {
        if (_cells[row * columns + column] == 0) {
          column++;
          continue;
        }
        int end = column;
        while (end < columns && _cells[row * columns + end] != 0) {
          end++;
        }
        if (end - column > runLimit) {
          for (int x = column; x < end; x++) {
            int first = row;
            while (first > 0 && _cells[(first - 1) * columns + x] != 0) {
              first--;
            }
            int last = row;
            while (last < rows - 1 && _cells[(last + 1) * columns + x] != 0) {
              last++;
            }
            if (last - first + 1 <= thinLimit) {
              for (int y = first; y <= last; y++) {
                _cells[y * columns + x] = 0;
              }
            }
          }
        }
        column = end;
      }
    }
  }

  /// The grid's cell size in pixels: one staff space divided by
  /// [MelodyNoteThresholds.cellsPerSpace].
  final double cell;

  /// The frame-space x of the grid's first column.
  final double left;

  /// The frame-space y of the grid's first row.
  final double top;

  /// How many columns the grid has.
  final int columns;

  /// How many rows the grid has.
  final int rows;

  final List<int> _cells;

  /// The widest nib stamped into each cell, so that a refusal can name the weight of the ink it
  /// refused: a hairline and a heavy stroke fail the same gate for different reasons.
  final List<double> _nibs;

  /// The x of a column's centre, in the frame's coordinates.
  double xOf(int column) => left + (column + 0.5) * cell;

  /// The y of a row's centre, in the frame's coordinates.
  double yOf(int row) => top + (row + 0.5) * cell;

  /// The column a frame-space x falls in, clamped to the grid.
  int columnOf(double x) {
    final int column = ((x - left) / cell).floor();
    return column < 0 ? 0 : (column >= columns ? columns - 1 : column);
  }

  /// The row a frame-space y falls in, clamped to the grid.
  int rowOf(double y) {
    final int row = ((y - top) / cell).floor();
    return row < 0 ? 0 : (row >= rows ? rows - 1 : row);
  }

  /// Marks every cell within [radius] of ([x], [y]) as ink drawn with [nib].
  ///
  /// A disc rather than a square, because a nib is round and a square stamp would make a diagonal
  /// stroke thicker than a vertical one by the ratio of a diagonal to a side. A radius below half a
  /// cell is raised to half a cell, so that a stroke thinner than the grid still marks the cell it
  /// passes through instead of falling between two of them.
  void _stamp(double x, double y, double radius, double nib) {
    final double r = radius < cell / 2 ? cell / 2 : radius;
    final int firstColumn = columnOf(x - r);
    final int lastColumn = columnOf(x + r);
    final int firstRow = rowOf(y - r);
    final int lastRow = rowOf(y + r);
    for (int row = firstRow; row <= lastRow; row++) {
      for (int column = firstColumn; column <= lastColumn; column++) {
        final double dx = xOf(column) - x;
        final double dy = yOf(row) - y;
        if (dx * dx + dy * dy <= r * r) {
          final int index = row * columns + column;
          _cells[index] = 1;
          if (nib > _nibs[index]) {
            _nibs[index] = nib;
          }
        }
      }
    }
  }

  /// Stamps one stroke: a disc of its nib at every sample along every segment.
  void _stampStroke(PageInkStroke stroke) {
    final double radius = stroke.nib / 2;
    final List<LayoutOffset> points = stroke.points;
    if (points.length == 1) {
      _stamp(points.first.x, points.first.y, radius, stroke.nib);
      return;
    }
    for (int index = 1; index < points.length; index++) {
      final LayoutOffset from = points[index - 1];
      final LayoutOffset to = points[index];
      final double dx = to.x - from.x;
      final double dy = to.y - from.y;
      final double length = math.sqrt(dx * dx + dy * dy);
      final int steps = math.max(1, (length / (cell / 2)).ceil());
      for (int step = 0; step <= steps; step++) {
        final double t = step / steps;
        _stamp(from.x + dx * t, from.y + dy * t, radius, stroke.nib);
      }
    }
  }

  // PURPOSE: Group the stamped ink into CONNECTED COMPONENTS and measure each one by its rows, so
  //          that the shape gates have something to weigh.
  // INPUTS: frame — the staff, for the row measurements; thresholds — the gates, carried so that a
  //         caller can see the blob count is produced under the same rules [weigh] applies.
  // OUTPUTS: One blob per component of ink, in the order the components were found. Each blob's rows
  //          are the horizontal EXTENT of its own cells, which is the measurement the gates are
  //          written against.
  //
  //          Connectivity is eight-way, which is what a drawn stroke needs: two cells that touch at
  //          a corner are the same mark, and a four-way search would cut a diagonal stroke into
  //          pieces.
  //
  //          NO COMPONENT IS DROPPED HERE, however little ink it holds. A single sample's worth of
  //          ink is still ink the musician made, and the refusal it deserves
  //          ([MelodyNoteRejection.tooLittleInk]) is produced by [weigh] — so the count of blobs a
  //          bar offered, and the reasons each was refused, add up to the whole of its ink.
  // KEYWORDS: connected-components, eight-connectivity, row-extent, ink-area, blob
  List<_InkBlob> blobs(MelodyStaffFrame frame) {
    final List<int> labels = List<int>.of(_cells);
    final List<_InkBlob> blobs = <_InkBlob>[];
    final List<int> stack = <int>[];
    int nextLabel = 2;
    for (int start = 0; start < labels.length; start++) {
      if (labels[start] != 1) {
        continue;
      }
      final int label = nextLabel++;
      int minColumn = columns;
      int maxColumn = -1;
      int minRow = rows;
      int maxRow = -1;
      int area = 0;
      stack
        ..clear()
        ..add(start);
      labels[start] = label;
      while (stack.isNotEmpty) {
        final int index = stack.removeLast();
        final int row = index ~/ columns;
        final int column = index - row * columns;
        area++;
        if (column < minColumn) {
          minColumn = column;
        }
        if (column > maxColumn) {
          maxColumn = column;
        }
        if (row < minRow) {
          minRow = row;
        }
        if (row > maxRow) {
          maxRow = row;
        }
        for (int dRow = -1; dRow <= 1; dRow++) {
          final int neighbourRow = row + dRow;
          if (neighbourRow < 0 || neighbourRow >= rows) {
            continue;
          }
          for (int dColumn = -1; dColumn <= 1; dColumn++) {
            final int neighbourColumn = column + dColumn;
            if (neighbourColumn < 0 || neighbourColumn >= columns) {
              continue;
            }
            final int neighbour = neighbourRow * columns + neighbourColumn;
            if (labels[neighbour] == 1) {
              labels[neighbour] = label;
              stack.add(neighbour);
            }
          }
        }
      }
      final List<_InkRow> rowList = <_InkRow>[];
      double widestNib = 0;
      for (int row = minRow; row <= maxRow; row++) {
        int first = columns;
        int last = -1;
        for (int column = minColumn; column <= maxColumn; column++) {
          if (labels[row * columns + column] == label) {
            if (column < first) {
              first = column;
            }
            last = column;
          }
        }
        if (last < 0) {
          continue;
        }
        for (int column = first; column <= last; column++) {
          final double nib = _nibs[row * columns + column];
          if (nib > widestNib) {
            widestNib = nib;
          }
        }
        rowList.add(
          _InkRow(
            y: top + row * cell,
            extent: (last - first + 1) * cell,
            centre: left + (first + last + 1) * cell / 2,
          ),
        );
      }
      blobs.add(
        _InkBlob(
          rows: rowList,
          cell: cell,
          centreX: left + (minColumn + maxColumn + 1) * cell / 2,
          centreY: top + (minRow + maxRow + 1) * cell / 2,
          width: (maxColumn - minColumn + 1) * cell,
          areaPixels: area * cell * cell,
          widestNib: widestNib,
        ),
      );
    }
    return blobs;
  }
}
