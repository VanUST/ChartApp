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
}
