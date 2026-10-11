// PURPOSE: Hold the handful of numbers that decide how the reader's screen is spaced and framed, so
//          that the bars above the document, the document's own frame and the controls inside them
//          are built from ONE scale instead of from a number typed into each call site. It exists
//          because the owner asked for a screen that "does not look like one whole", and a screen is
//          not unified by intent: it is unified when the same gap, the same corner and the same
//          field appear wherever the eye looks, which only happens when there is a single place the
//          numbers come from.
//
//          WHAT THIS IS NOT. It is not a theme: colours and type stay with `ThemeData` in
//          `main.dart`, which is what Material widgets already read, and duplicating them here would
//          make two sources for one fact. This file owns the SPACING, the corner, the hairline and
//          the two heights this application invents for itself.
//
//          WHAT IT DOES NOT YET COVER, SAID RATHER THAN IMPLIED. `scene_bar.dart` still carries its
//          own paddings inside its own widgets, and the sheets have their own. Consolidating those
//          is a larger edit than the one that added this file, and claiming they are already covered
//          would be the kind of tidy-sounding sentence this project has already been burned by three
//          times today. What is covered is every surface the shell itself draws: the document tool
//          bar, the path bar, the pane's own rows, the document frame and the status bar.
// INPUTS: None. These are compile-time constants, chosen once and read everywhere.
// OUTPUTS: `double`s and `EdgeInsets` values. Nothing here reads the theme, the window or the
//          locale, so a value can never depend on which surface is being built.
// KEYWORDS: design-tokens, spacing-scale, corner-radius, hairline, bar-height, one-whole,
//           document-frame, not-a-theme
import 'package:flutter/widgets.dart';

/// The one scale the shell's spacing is drawn from.
///
/// Four steps rather than a continuous range, because a scale with a step for every situation stops
/// being a scale: the same gap then appears at two different sizes in two bars and the surface reads
/// as assembled rather than as designed. The names are sizes and not roles on purpose — a `gapSmall`
/// would have to be re-argued for every new use, while [spaceS] is simply the small step.
class UiKit {
  const UiKit._();

  /// The smallest step: the gap between a field and its own label, and the inset of a status line.
  static const double spaceXs = 4;

  /// The small step: the gap between two controls in one row, and the vertical inset of a bar.
  static const double spaceS = 8;

  /// The medium step: the horizontal inset of every bar, and the gap between two groups in a row.
  static const double spaceM = 12;

  /// The large step: the inset of the document from the shell around it.
  static const double spaceL = 16;

  /// The corner every framed surface shares, in logical pixels.
  ///
  /// One number for the document frame, the rail and the bars, so that no two of them are rounded by
  /// different amounts — which is the single most visible way a screen fails to read as one piece.
  static const double radius = 10;

  /// The hairline a framed surface is outlined with.
  static const double hairline = 1;

  /// The height of the bar the document keeps while the rest of the chrome is hidden.
  ///
  /// Tall enough for a 40-pixel touch target with [spaceXs] above and below it, and no taller: every
  /// pixel here is a pixel the music does not get, and the whole point of hiding the chrome is the
  /// music. It is deliberately below Material's own 56-pixel app-bar height, which is a phone
  /// gesture-bar convention rather than a music-stand one.
  static const double toolBarHeight = 44;

  /// The width of the library rail when it is shown.
  ///
  /// It is a WIDTH and not a fraction of the window, because the row it holds — a title, a key and a
  /// bar count — is legible at this width on every surface this application runs on, and a rail that
  /// grew with a desktop window would take room from the document to show nothing more.
  static const double railWidth = 260;

  /// The inset of a bar that sits in the shell's column, above or below the document.
  static const EdgeInsets barPadding = EdgeInsets.symmetric(
    horizontal: spaceM,
    vertical: spaceS,
  );

  /// The inset of a row that belongs to the document pane rather than to the shell.
  ///
  /// No vertical space above the row: the pane's rows are stacked and the gap between them is the
  /// scene bar's own, so adding one here would be a second answer to the same question.
  static const EdgeInsets paneRowPadding = EdgeInsets.fromLTRB(
    spaceM,
    0,
    spaceM,
    spaceXs,
  );

  /// The inset of the status line under the document.
  ///
  /// The smallest step on both axes, because this line reports a count and nothing else: at the
  /// short landscape size this project has already measured, every pixel of shell here is a pixel
  /// the music does not get, and the line's own text is 12 logical pixels tall.
  static const EdgeInsets statusPadding = EdgeInsets.symmetric(
    horizontal: spaceM,
    vertical: spaceXs,
  );

  /// The inset of the pane's own header row, where the chart's title is read.
  static const EdgeInsets paneHeaderPadding = EdgeInsets.fromLTRB(
    spaceM,
    spaceS,
    spaceM,
    spaceXs,
  );
}
