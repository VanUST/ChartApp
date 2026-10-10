// PURPOSE: Hold the colours every modal edit sheet draws on, so the sheets a musician opens while
//          working — the chord palette and the form sheet — are visibly the same surface rather
//          than two panels that happen to be dark. A colour literal copied between two files is a
//          surface that drifts the first time one of them is touched.
// INPUTS: None. Every constant is a compile-time colour.
// OUTPUTS: The six colours a sheet needs: the panel behind everything, the cell a musician can
//          press, the cell that is currently chosen, the accent that marks the current choice, the
//          text colour on the panel, and the muted colour of a secondary label. They are the values
//          the chord palette shipped with, moved here unchanged so the surface does not move.
// KEYWORDS: sheet-surface, colour-tokens, dark-panel, shared-style, chord-palette, song-form
//
// WHY THE PANEL IS DARK AND THE CHART IS NOT. The chart page is white because paper is what a chart
// looks like, and a sheet over it is chrome read at arm's length in a dark room, which is the same
// reason the scene bar carries its own colours instead of the application theme's.
import 'dart:ui' show Color;

/// The dark panel a modal edit sheet is drawn on.
const Color sheetPanelColor = Color(0xFF0F1B2A);

/// The colour of a cell in a sheet that a musician can press.
const Color sheetCellColor = Color(0xFF1C2E44);

/// The colour of the cell a sheet currently holds or is previewing.
const Color sheetSelectedCellColor = Color(0xFF2E5D8A);

/// The accent that marks the current choice and the pickable outlines.
const Color sheetAccentColor = Color(0xFFFFC857);

/// The colour of text on the dark panel.
const Color sheetOnPanelColor = Color(0xFFF5F8FB);

/// The colour of a secondary label, such as a degree number or a hint.
const Color sheetMutedColor = Color(0xFFB9C7D6);
