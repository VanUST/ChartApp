// PURPOSE: Mark the boundary of the Flutter UI layer and state what belongs in it, so that
//          presentation concerns stay out of chart_core and domain rules stay out of widgets.
// INPUTS: None.
// OUTPUTS: A library with no public API in Phase 0; the dock, ribbon and gesture widgets are
//          Phase 2 work and are built against the real domain types from the Phase 1 spikes.
// KEYWORDS: chart-ui, boundary, phase-0, no-api-yet, presentation-layer
//
// The vertical slice that fills this package — Library, Editor with chord input and docks,
// and the Scene pager — is Phase 2. Building widgets now would mean building them against a
// song model that the S1/S3/S4 spikes have not yet settled, and every widget would have to be
// rewritten when the model lands.
//
// What belongs here:
//   - dock widgets, the focus ribbon, and the tool-state indicator;
//   - the gesture arbitration surface (pen to ink, one finger to pan, two to zoom);
//   - visual tokens and the theme;
//   - widget tests for the above.
//
// What does not belong here: chord spelling, transposition, layout computation or file
// codecs. Those live in chart_core and are reached through chart_ui's dependencies.

/// ChartApp design system and interaction layer.
library;
