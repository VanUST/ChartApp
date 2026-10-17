// PURPOSE: Collect the numeric constants that decide how much room the engraving gives each
//          element, so that a change to the chart's proportions is one edit in one place and the
//          layout engine holds only the algorithm. Keeping them out of the engine is also what
//          lets a test construct a style that makes an exact expected geometry obvious.
// INPUTS: A text-measurement implementation plus spacing constants, all in logical pixels.
// OUTPUTS: An immutable style. Every constant has a documented default, so a caller that only
//          needs testable behaviour can pass a metrics model and nothing else.
// KEYWORDS: layout-style, spacing, engraving-constants, configuration, chart-proportions
import 'text_metrics.dart';

/// The smallest fraction of its own size a text cue's letters may be drawn at, whatever the page
/// does.
///
/// A SEPARATE, HIGHER FLOOR from `LayoutEngine.minLegibleScale` (0.5) on purpose: 0.8 of a 16-pixel
/// cue is 12.8 surface logical pixels, which is still larger than the fitted chord it annotates.
/// It lives here rather than in the painter because the reservation and the drawing are two halves
/// of one number: below a page scale of 0.8 the letters stop shrinking while the music keeps
/// going, so the row a cue occupies is `letterHeight / pageScale` pixels tall in the page's own
/// coordinates and GROWS as the page shrinks. `TextCuePainter` reads this constant, and that is
/// what stops the row the layout reserved and the box the painter draws from being two values.
const double textCueMinLegibleScale = 0.8;

/// Horizontal room the cue plate keeps between its edge and the words, in surface logical pixels.
///
/// Part of the room a cue takes: the layout reserves a plate, not a string.
const double textCuePlateInsetX = 3;

/// Vertical room the cue plate keeps between its edge and the words, in surface logical pixels.
///
/// Part of the room a cue takes: the layout reserves a PLATE, not a string, so one cue's row is the
/// whole line height of the cue style — a value the font stack answers, not a font size — plus twice
/// this. Reserving the words' own box instead would let the plate's edge, which the painter draws,
/// fall that much further onto the chord below.
const double textCuePlateInsetY = 1;

/// The spacing constants and the metrics model the layout engine uses.
class LayoutStyle {
  /// Creates a style. Only [textMetrics] has no sensible default in production; the fixed model
  /// is the default so that a style built with no arguments is still deterministic.
  const LayoutStyle({
    this.textMetrics = const FixedAdvanceTextMetrics(),
    this.pageMargin = 24,
    this.barMinWidth = 56,
    this.barPadding = 8,
    this.chordSpacing = 10,
    this.minCellWidth = 14,
    this.staffTextInset = 2,
    this.staffTextBottomInset = 2,
    this.barHeight = 44,
    this.systemSpacing = 12,
    this.sectionLabelHeight = 22,
    this.melodyStaffSpace = 13,
    this.melodyStaffGap = 8,
    this.melodyStaffHeight = 52,
    this.melodyBandHeight = 196,
    this.beatMarkHeight = 15,
    this.beatMarkGap = 3,
    this.beatMarkMinCellWidth = 18,
    this.showBeatCaptions = false,
  });

  /// How text is measured.
  final TextMetrics textMetrics;

  /// Blank space between the page edge and the engraved content.
  final double pageMargin;

  /// The narrowest a bar may be drawn, so that a bar holding one short chord is still tappable.
  final double barMinWidth;

  /// Horizontal padding inside a bar, on each side of its first and last cell.
  final double barPadding;

  /// Gap between two chords that share a cell, and the room reserved after the last chord in a
  /// cell so that neighbouring cells do not touch.
  final double chordSpacing;

  /// The narrowest a cell may be drawn.
  ///
  /// An empty cell still occupies this much room. It has to: a cell is where a sustained chord
  /// is drawn, and letting empty cells collapse would pack the chords of a bar into a width that
  /// no longer says anything about where in the bar they fall.
  final double minCellWidth;

  /// Horizontal inset of a staff-text line from the bar's left edge.
  ///
  /// It exists so the placement the engine publishes and the width it reserves for the words are
  /// the same arithmetic: the line's box starts here, so the room a bar needs for its widest line
  /// is this inset plus the measured width plus the right [barPadding].
  final double staffTextInset;

  /// Vertical inset of the bottom-most staff-text line from the bar's bottom edge.
  ///
  /// Lines are stacked upward from here, so several phrases on one bar stay inside it instead of
  /// running past the system below.
  final double staffTextBottomInset;

  /// Vertical extent of one stave, before any section label above it.
  final double barHeight;

  /// Vertical gap between two systems.
  final double systemSpacing;

  /// Vertical room reserved above a system that begins a section.
  final double sectionLabelHeight;

  /// The distance between two adjacent lines of the melody staff.
  ///
  /// THE UNIT OF THE WHOLE STAFF. Every vertical position on the melody staff — a notehead's own
  /// height, a stem's length, how far a note lies outside the five lines and therefore how many
  /// ledger lines it needs — is an exact multiple of this value, measured in it rather than in
  /// pixels. That is what lets the geometry be derived by hand and asserted exactly, and it is why
  /// a change to the staff's size is one number rather than a page of arithmetic.
  ///
  /// WHY IT IS 13 AND NOT THE 9 IT WAS. This number is chosen from the READING DISTANCE, which is
  /// the only distance this application is drawn for: a musician at a stand, an arm's length from a
  /// tablet lying on it. At the owner's own fitted scale — 0.70, measured on his tablet in A65 — a
  /// staff space of 9 page pixels is 6.3 logical pixels on the glass, so a notehead is 7.6 pixels
  /// wide and the five lines are less than two millimetres apart: the staff was being drawn at a
  /// size where a notehead is smaller than the chord character beside it, and the owner's report is
  /// that the staff looks bad and unclear. 13 page pixels is 9.1 logical pixels at that scale,
  /// which puts a notehead at 10.9 and a space at very nearly the 2.1 mm of printed music — the
  /// size a chart is engraved at, which is the size a reader is trained on. The cost is stated in
  /// [melodyBandHeight] and paid by the page rather than by the musician's eyes: the staff is 44 per
  /// cent taller than it was, and the band around it is not.
  final double melodyStaffSpace;

  /// The vertical gap between the chord line's bottom edge and the melody staff's own band.
  ///
  /// It is what keeps a chord symbol from touching the top of the melody staff, and it is a
  /// constant rather than a share of the leftover room so that the staff lands at the same
  /// distance below the chords in every system and on every page.
  final double melodyStaffGap;

  /// The distance from the staff's top line to its bottom line: four [melodyStaffSpace] steps.
  ///
  /// A field rather than a getter because a caller may want a deliberately different staff, and
  /// because the engine reports the staff's own top and bottom line to the painter instead of
  /// letting the painter re-derive them; see [PlacedMelodyStaff].
  final double melodyStaffHeight;

  /// The vertical room a system gives up when the song carries any melody at all.
  ///
  /// FIXED FOR THE WHOLE SONG, on purpose, and this is the property that makes an undulating
  /// tune readable: the staff must sit at the same height in every system, so the band cannot be
  /// sized to the notes a particular system happens to contain. Any note lies within its own
  /// five staff spaces above or below the five lines, which is five ledger lines, so
  /// `melodyStaffHeight + 2 * 5 * melodyStaffSpace` is the guarantee this value encodes: every
  /// step [melodyStepOf] can return has a glyph inside its own band. It also keeps the pagination
  /// arithmetic honest — the SF4 and A30 bounds are found by bisection over a page whose system
  /// height is a constant, not a function of the music.
  ///
  /// It is ZERO for a song with no melody, which is what makes a chords-only chart paginate and
  /// print exactly as it did before a melody staff existed.
  ///
  /// IT IS THE BAND FOR A STAFF THAT IS BEING WRITTEN ON. A declared staff that carries no note at
  /// all reserves [melodyEmptyBandHeight] instead, which is the same staff with none of the ledger
  /// room this value exists to guarantee; see that getter for the derivation and for why the reserve
  /// can depend on whether a note exists while the STAFF itself cannot (D29).
  ///
  /// WHY IT IS 196 AND NOT THE 270 IT WAS, AND WHY THAT IS NOT A PROMISE TAKEN BACK. The guarantee
  /// this value encodes is `melodyStaffHeight + 2 * 5 * melodyStaffSpace` — every step
  /// [melodyStepOf] can return has a glyph inside its own band — and the layout CENTRES the staff in
  /// the band, so each half only has to hold half a staff, the five ledger steps on that side, and
  /// half a notehead: 26 + 65 + 6 + 1 for the stroke = 98, doubled = 196. The old 270 was not
  /// derived from anything: it was 2.76 times the guarantee it was supposed to encode, so a chart
  /// with one note in it reserved 117 page pixels of empty air above the five lines and as much
  /// again below them, and the owner's report of that page is "too much empty space" and "the staff
  /// does not belong". The guarantee is untouched; the slack around it is gone.
  final double melodyBandHeight;

  /// The vertical room a system gives up for a DECLARED melody staff that carries no note at all.
  ///
  /// WHY AN EMPTY STAFF MAY BE SHALLOWER, AND WHY THIS IS NOT D29 BEING RE-OPENED. D29 settled that
  /// the staff EXISTS because the chart declared it, and it does: this is a shorter staff, not a
  /// missing one — the five lines, the clef and the beat captions are all still drawn. What D29 did
  /// not say, and what its own numbers make obvious on a chart nobody will ever put a note on, is
  /// that a staff with nothing to write on it must reserve room for notes that do not exist:
  /// [melodyBandHeight] is 196 pixels of which 130 is the five ledger lines either side of the
  /// staff, and the guarantee it encodes — "every step [melodyStepOf] can return has a glyph inside
  /// its own band" — is vacuously true when there is no glyph. The reserve follows the music; the
  /// staff follows the declaration.
  ///
  /// HOW IT IS DERIVED, RATHER THAN PICKED. The layout centres the staff in the band (`melodyTop +
  /// band / 2` is the staff's middle line, in both `LayoutEngine._placeMelody` and
  /// `LayoutEngine._placeSystem`), so each HALF of the band must hold the staff's own half-height
  /// plus everything that has to fit on that side of it. Above the middle line: half the staff, and
  /// at least [melodyStaffGap] of air between the chord line and the staff's top line. Below it:
  /// half the staff, and the beat caption's own row, [beatMarkGap] plus [beatMarkHeight]. The band
  /// is twice the larger of the two, so the centring rule is left exactly as it is and no second
  /// placement rule is introduced.
  ///
  /// WHEN THE FIRST NOTE ARRIVES THE BAND GROWS TO [melodyBandHeight], and that is a reflow the
  /// musician sees once: every system of the song grows together, so the staff stays at one height
  /// across the chart, which is the property this pair of values must not break.
  double get melodyEmptyBandHeight {
    final double aboveTheMiddle = melodyStaffHeight / 2 + melodyStaffGap;
    final double belowTheMiddle =
        melodyStaffHeight / 2 + beatMarkGap + beatMarkHeight;
    return 2 *
        (aboveTheMiddle > belowTheMiddle ? aboveTheMiddle : belowTheMiddle);
  }

  /// The distance from the staff's TOP LINE up to the top of [melodyBandHeight].
  ///
  /// It is the room a ledger line above the staff is drawn in: five [melodyStaffSpace] steps (as
  /// many lines as [melodyStepOf] can ask for) plus the style's [melodyStaffGap], with the
  /// remainder of the band left below the staff for the ledger lines and the ties that hang
  /// under it.
  double get melodyTopSpace => melodyStaffHeight / 2 + 5 * melodyStaffSpace;

  /// The vertical room a beat marker occupies below the melody staff's bottom line.
  ///
  /// IT IS NOT PART OF [melodyBandHeight] ON PURPOSE. The band was chosen so that every note
  /// [melodyStepOf] can produce has a glyph inside it — five ledger lines either side of the five
  /// lines — and taking room out of it for a caption would move the staff on every chart that
  /// already has one. The marker is drawn in the space the staff's own centring leaves below it.
  ///
  /// WHY IT IS 15. The ordinal under the staff is the answer to «ориентироваться внутри такта
  /// трудно» — the defect the owner named before anything else — so it has to be READ, not merely
  /// present: the painter draws it at 0.9 of a staff space (11.7 logical pixels at the default
  /// size), whose line box is about 15. A shorter box would clip the digits the row exists for.
  final double beatMarkHeight;

  /// The vertical gap between the melody staff's bottom line and the top of a beat marker's box.
  ///
  /// Large enough that the marker reads as a caption under the staff rather than as a sixth line
  /// of it, and small enough that it stays clear of the next system's heading.
  final double beatMarkGap;

  /// Whether the beat captions under the staff are drawn at all.
  ///
  /// FALSE, AND THE REASON IS THE OWNER LOOKING AT HIS OWN SCREEN. The captions — the digits on the
  /// bar that opens a system and the tick on every column — were added because he had named
  /// «ориентироваться внутри такта трудно» as a defect before anything else, so the aid was meant to
  /// help. His report of the result is «какие то непонятные черты и цифры под нотным станом ... если
  /// это просто убрать - уже будет лучше». The aid failed, and the honest response to a musician
  /// saying that about his own screen is to take it away rather than to defend why it should have
  /// worked.
  ///
  /// WHAT REMAINS FOR ORIENTATION, said rather than assumed: a touch on a column of the staff opens
  /// the note palette FOR THAT BEAT and its header names it («Такт 1 · доля 1»), the selected cell is
  /// highlighted on the page, and the selection line names the bar and beat. Whether that is enough
  /// is the owner's call and is put to him as a question in the decision record — it is not settled
  /// here.
  ///
  /// The flag rather than a deleted feature, and the reason is that a feature which is OFF can be
  /// redesigned by whoever shows him a version that reads; a feature deleted in a hurry leaves nothing
  /// to redesign. It is off by default so that no screen has to opt out of noise.
  final bool showBeatCaptions;

  /// The narrowest cell that can carry a beat's ORDINAL NUMBER instead of one tick.
  ///
  /// A beat is named by its number in a bar (1, 2, 3, 4 …), and that number needs horizontal room
  /// the tick does not. Below this width the engine publishes a tick per beat and no digits, so a
  /// crowded bar shows the beat GRID without printing numbers that would touch each other. The
  /// value is a product decision, not a measurement: a single digit is about 7 logical pixels at
  /// the caption's size and a two-digit ordinal about 13, so 18 leaves five pixels of air beside the
  /// widest one — and it is set at the same value as the application's `minCellWidth`, so a four-beat
  /// bar always has room to name its beats.
  final double beatMarkMinCellWidth;
}
