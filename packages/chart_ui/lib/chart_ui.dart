// PURPOSE: Mark the boundary of the Flutter UI layer and publish its surface, so that presentation
//          concerns stay out of chart_core and domain rules stay out of widgets.
// INPUTS: None.
// OUTPUTS: The chart renderer: [FlutterTextMetrics], the TextPainter-backed side of chart_core's
//          text-measurement seam, and [ChartPainter], which draws one laid-out page.
// KEYWORDS: chart-ui, boundary, chart-renderer, text-metrics, public-api
//
// What belongs here:
//   - the Flutter implementation of chart_core's TextMetrics seam;
//   - the renderer that turns a PageLayout into pixels;
//   - dock widgets, the focus ribbon, and the tool-state indicator;
//   - the gesture arbitration surface (pen to ink, one finger to pan, two to zoom);
//   - visual tokens and the theme;
//   - widget tests for the above.
//
// What does not belong here: chord spelling, transposition, layout computation or file codecs.
// Those live in chart_core and are reached through chart_ui's dependencies.

/// ChartApp design system and interaction layer.
library;

export 'src/chart_painter.dart';
export 'src/flutter_text_metrics.dart';
