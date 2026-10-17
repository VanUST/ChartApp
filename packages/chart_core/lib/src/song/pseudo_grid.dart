// PURPOSE: LET A CALLER THAT STILL SPEAKS IN BEATS ASK A PLACE FOR ITS CELL. This file is a
//          TEMPORARY ADAPTER and it is not part of the model's design: it exists so that the
//          removal of the grid can be landed in stages instead of all at once, and it is deleted by
//          the stage that finishes the job. The model stores a coordinate ([AnchoredPlace.offsetX])
//          and nothing else; every consumer that has not been rewritten yet — the layout engine,
//          the melody staff, the hit test, the chord and note palettes, the painter and the tests —
//          recovers the beat and step it used to read from a field by inverting the one arithmetic
//          that WROTE the value.
// INPUTS: A beat and a step (write direction, [PseudoGrid.place] and [PseudoGrid.xOf]), or a place
//         (read direction, [PseudoGrid.beatOf] and [PseudoGrid.stepOf]).
// OUTPUTS: An [AnchoredPlace] whose offsetX encodes the pair, and the pair back. The two directions
//          are exact inverses for every value any caller in this tree produces, which is what makes
//          the shim transparent: a mark written at beat 2 is engraved in the cell 2 column exactly
//          as it was before the model changed.
// KEYWORDS: shim, temporary, pseudo-grid, adapter, beat-index, migration, delete-in-stage-two,
//           dequantisation, staged-change
//
// WHY A PSEUDO-GRID HAS TO EXIST AT ALL, AND WHY IT IS NOT THE GRID COMING BACK. The owner's
// decision is that a mark's place is a COORDINATE — «Запись сама по себе структурированная
// единица. Относительное ее положение — нет. Сетка НЕ квантизована.» — and the model now stores
// one. But three quarters of this tree still think in cells: the engraver divides a bar into
// columns, the hit test names a cell, the palette edits "the chord on beat 2", and 486 tests assert
// beat indices. Rewriting all of that in the same change as the model is what produced 956 analyzer
// errors in the previous attempt and forced the whole thing to be reverted. So this file answers
// the old question for the old callers, in ONE place, with an expiry date.
//
// WHY IT IS EXACT AND NOT LOSSY. A "which of N columns does this x fall in" projection would be
// lossy — two x values in one column are one answer — and every existing geometry assertion would
// then be asserting a rounding. The inversion here is exact instead because the value it inverts was
// WRITTEN by the forward direction: in this stage nothing in the model holds an x that a pen chose,
// so every offsetX is [xOf] of an integer pair, and the pair comes back unchanged. The moment a
// stage gives the model a real pen position (which is the point of the change), this exactness is
// gone and so is the shim.
//
// WHAT THE CONSTANTS ARE, AND WHY THEY ARE ALLOWED TO BE CONSTANTS. 8 and 18 are
// `LayoutStyle.barPadding` and `LayoutStyle.minCellWidth` — the same pair the iReal importer already
// uses to turn its own real grid into coordinates (`irealChordX`). They are written here as literals
// rather than read from a style because a style is a LAYOUT decision and a stored position must not
// change when the engraving's proportions change: a chart opened with a different style would
// otherwise decode every mark into a different cell. A caller whose bar is engraved with a
// non-default style still gets the right cell, because the round trip never consults the style: the
// layout divides its own bar into its own columns and asks only WHICH column the mark was written
// in.
library;

import '../anchored_place.dart';
import 'bar.dart';
import 'note.dart';

/// The temporary beat/step adapter for a place. DELETE WHEN THE LAYOUT READS THE OFFSET.
abstract final class PseudoGrid {
  /// The x a bar's first column begins at, in bar-local logical pixels.
  ///
  /// Equal to the default `LayoutStyle.barPadding`. See the library comment for why it is a literal.
  static const double cellOrigin = 8;

  /// The distance between two adjacent columns, in bar-local logical pixels.
  ///
  /// Equal to the default `LayoutStyle.minCellWidth`. See the library comment for why it is a
  /// literal, and [subCellPitch] for how a second mark in the same column is kept apart.
  static const double cellPitch = 18;

  /// How many distinct steps a single column can address.
  ///
  /// A step is the order of a mark among several written in one column — a packed chord pair
  /// `E7b5 A7`, or a sixteenth run inside one beat. Sixteen is more than any caller in this tree
  /// produces (the largest step written anywhere is 8) and it leaves room for the crowded cases the
  /// melody staff already draws. A step beyond this range would collide with the next column, which
  /// is stated rather than defended against because the alternative is a second, larger pitch that
  /// no caller asked for.
  static const int subCellsPerCell = 16;

  /// The distance between two adjacent steps of one column, in bar-local logical pixels.
  ///
  /// An exact binary fraction, so the encoding is exact: `1.125` is `9/8`, and every value
  /// [xOf] produces from integer inputs is exactly representable, which is what makes
  /// [beatOf] and [stepOf] its exact inverses with no tolerance anywhere.
  static const double subCellPitch = cellPitch / subCellsPerCell;

  /// The x a mark written on [beat], at [step], is stored at.
  ///
  /// This is the ONLY forward definition of the pseudo-grid: a caller that needs a place from a
  /// cell asks for one here rather than doing the arithmetic itself.
  static double xOf(int beat, int step) =>
      cellOrigin + beat * cellPitch + step * subCellPitch;

  /// A place at [beat], at [step], of the bar [anchor] names.
  ///
  /// The vertical offset is left at zero: a chord's own place on the chord line and a note's height
  /// are not part of a cell address, and a caller that has one adds it to the result.
  static AnchoredPlace place(
    EventAnchor anchor, {
    required int beat,
    int step = 0,
    double offsetY = 0,
  }) =>
      AnchoredPlace(anchor: anchor, offsetX: xOf(beat, step), offsetY: offsetY);

  /// The column the mark at [offsetX] was written in.
  ///
  /// Rounds down, which is what keeps a mark written at any step of a column inside that column,
  /// including the negative beats the layout engine already tolerates (a cell left of the bar's
  /// own first column).
  static int beatOf(double offsetX) =>
      ((offsetX - cellOrigin) / cellPitch).floor();

  /// The order within its column of the mark at [offsetX].
  ///
  /// A negative offset can leave a remainder that rounds to a value one past the column either way;
  /// the result is therefore clamped into `0 .. subCellsPerCell - 1` rather than allowed to name a
  /// slot that does not exist.
  static int stepOf(double offsetX) {
    final double columns = (offsetX - cellOrigin) / cellPitch;
    final double fraction = columns - columns.floorToDouble();
    final int step = (fraction * subCellsPerCell).round();
    if (step < 0) {
      return 0;
    }
    return step >= subCellsPerCell ? subCellsPerCell - 1 : step;
  }

  /// The x of the first column of a bar, which is where a bar's content begins.
  ///
  /// Offered because several callers start a search here rather than at zero, and a caller that
  /// wrote `barPadding` itself would be restating the shim's own origin.
  static double get contentOrigin => cellOrigin;
}

// PURPOSE: Build the place of a cell for a caller that knows which bar it is writing into. SHIM:
//          this is the write half of [PseudoGrid], and it exists for the two writers that have not
//          been migrated yet — the edit session, which is still asked for a beat, and the iReal
//          importer's callers.
// INPUTS: sectionId and bar — the bar's address, the same pair an annotation anchor takes. beat —
//         the cell. step — the order within the cell, which most callers leave at zero.
// OUTPUTS: An [AnchoredPlace] in that bar at that cell, with no vertical offset. The result is
//          exactly the place the mark would have had if the caller had written the offset itself,
//          which is what makes the migration of a caller invisible on the page.
// KEYWORDS: shim, temporary, write-direction, cell-address, anchored-place, delete-in-stage-two
/// Returns the place of cell [beat].[step] of ([sectionId], [bar]). SHIM.
AnchoredPlace cellPlace(String sectionId, int bar, int beat, [int step = 0]) =>
    PseudoGrid.place(
      EventAnchor(sectionId: sectionId, bar: bar),
      beat: beat,
      step: step,
    );

// PURPOSE: Build the place of a cell for a caller that does NOT know the bar's address. SHIM: the
//          write half of [PseudoGrid] for a bar built on its own — a test's expected value, a
//          fixture, a bar that is about to be inserted into a section.
// INPUTS: beat — the cell. step — the order within the cell.
// OUTPUTS: An [AnchoredPlace] carrying an address no section and no bar can have — see
//          [unaddressedAnchor] — at that cell. A bar that reaches the document through an event is
//          re-anchored by `DocumentReducer._anchoredBars`, so the placeholder never survives into a
//          stored document; what it does is let a caller build a bar before knowing where it goes.
//
//          A CALLER THAT KNOWS THE ADDRESS MUST USE [cellPlace] INSTEAD. The placeholder is a
//          placeholder: two bars that differ only in it compare unequal, which is what keeps a
//          mark's address inside its value rather than outside it.
// KEYWORDS: shim, temporary, write-direction, unaddressed-bar, fixture, delete-in-stage-two
/// Returns the place of cell [beat].[step] in a bar whose address the caller does not know. SHIM.
AnchoredPlace cellAt(int beat, [int step = 0]) =>
    PseudoGrid.place(unaddressedAnchor, beat: beat, step: step);

// PURPOSE: Name the placeholder address [cellAt] writes on a bar that is not in a document yet.
// INPUTS: None.
// OUTPUTS: An [EventAnchor] with an EMPTY section id, which no section can carry: a section id is
//          either given by the importer or minted by the edit session, and both are never empty.
//          The empty id is therefore the one address that is recognisably not an address, which is
//          what lets a reader of a document spot a bar that was never placed rather than silently
//          reading it as the first bar of a section called nothing.
// KEYWORDS: shim, temporary, placeholder-address, empty-section-id, delete-in-stage-two
/// The placeholder anchor [cellAt] uses. SHIM.
const EventAnchor unaddressedAnchor = EventAnchor(sectionId: '', bar: 0);

/// Reads a place as the column and step it was written at. SHIM: see [PseudoGrid].
extension PseudoGridPlace on AnchoredPlace {
  /// The column this place was written in. SHIM.
  int get pseudoBeat => PseudoGrid.beatOf(offsetX);

  /// The order within its column. SHIM.
  int get pseudoStep => PseudoGrid.stepOf(offsetX);

  /// This place moved to the same bar at [beat] and [step], keeping its vertical offset. SHIM.
  AnchoredPlace atPseudoCell({required int beat, int step = 0}) =>
      AnchoredPlace(
        anchor: anchor,
        offsetX: PseudoGrid.xOf(beat, step),
        offsetY: offsetY,
      );
}

/// Reads a chord mark as the column and step it was written at. SHIM: see [PseudoGrid].
extension ChordMarkPseudoGrid on ChordMark {
  /// The column this chord was written in. SHIM.
  int get pseudoBeat => place.pseudoBeat;

  /// The order of this chord within its column. SHIM.
  int get pseudoStep => place.pseudoStep;
}

/// Reads a note mark as the column and step it was written at. SHIM: see [PseudoGrid].
extension NoteMarkPseudoGrid on NoteMark {
  /// The column this note was written in. SHIM.
  int get pseudoBeat => place.pseudoBeat;

  /// The order of this note within its column. SHIM.
  int get pseudoStep => place.pseudoStep;
}

/// Reads a percussion mark as the column and step it was written at. SHIM: see [PseudoGrid].
extension PercussionMarkPseudoGrid on PercussionMark {
  /// The column this hit was written in. SHIM.
  int get pseudoBeat => place.pseudoBeat;

  /// The order of this hit within its column. SHIM.
  int get pseudoStep => place.pseudoStep;
}
