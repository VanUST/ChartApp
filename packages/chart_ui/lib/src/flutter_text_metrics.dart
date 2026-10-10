// PURPOSE: Measure chart text with the real font stack, so that the layout engine — which is
//          deliberately Flutter-free — can place a chord in the box it will actually occupy.
//          chart_core defines the TextMetrics seam; this file is the production side of it.
// INPUTS: A string and the role it plays in a chart. The four styles are constructor parameters,
//         so a different visual density is a different instance and never a process-wide global.
// OUTPUTS: A LayoutSize per measurement, in logical pixels. An empty string measures to a
//          zero-width box, which is the contract chart_core documents for TextMetrics.
// KEYWORDS: text-metrics, text-painter, font, layout-bridge, chart-ui, production-metrics
//
// WHY THIS LIVES IN chart_ui AND NOT IN chart_core. chart_core's dependency list is empty on
// purpose: that is what lets its whole layout pipeline — and every assertion about it — run under
// `dart test` on a machine with no device and no Flutter. TextPainter needs the Flutter engine, so
// the implementation belongs on this side of the seam.
//
// The measurement and the drawing must come from ONE instance. ChartPainter takes the same
// FlutterTextMetrics the engine was given, so the chord it paints lands in the rectangle the
// engine reserved for it. A second instance with different styles would draw wider text than was
// measured, and neighbouring chords would overlap.

import 'package:chart_core/chart_core.dart';
import 'package:flutter/painting.dart';

/// The size a text cue's words are set at on an ordinary page, in logical pixels.
///
/// ONE STEP ABOVE THE CHORD. `chordStyle` draws a chord at 15; a cue is the only thing on the page
/// that is a SENTENCE rather than a symbol — `D.C. al Fine` has to be read in full, from a stand,
/// often in a dark room — so it is set one step larger, in the same dark ink.
///
/// It lives here, beside the style built from it, because the LAYOUT measures with this number and
/// the painter draws with it: a cue's row is reserved at its measured height, so a second copy of
/// 16 in the painter would let the row and the words it holds disagree.
const double chartTextCueFontSize = 16;

/// The style a text cue is measured and drawn with, before the page scale is applied.
///
/// `ChartTextRole.textCue` answers with this style in [FlutterTextMetrics]'s default construction,
/// and `TextCuePainter` draws with it, so the height the engine reserved and the words the reader
/// sees come from one declaration.
const TextStyle chartTextCueStyle = TextStyle(
  fontSize: chartTextCueFontSize,
  fontWeight: FontWeight.w600,
  color: Color(0xFF102A43),
);

/// Measures chart text with Flutter's [TextPainter].
class FlutterTextMetrics implements TextMetrics {
  /// Creates metrics whose measurement and drawing share one set of styles.
  ///
  /// Every parameter has a default that a desktop window can read at arm's length, so a caller
  /// that only needs working metrics can pass nothing.
  const FlutterTextMetrics({
    this.chordStyle = const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Color(0xFF102A43),
    ),
    this.smallChordStyle = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Color(0xFF102A43),
    ),
    this.sectionLabelStyle = const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: Color(0xFF2E5D8A),
    ),
    this.staffTextStyle = const TextStyle(
      fontSize: 10,
      color: Color(0xFF486581),
    ),
    this.textCueStyle = chartTextCueStyle,
  });

  /// The style of a chord symbol at normal size.
  final TextStyle chordStyle;

  /// The style of a chord the model marks [ChordSize.small].
  ///
  /// Separate from [chordStyle] because a small chord is a property of one beat, not of the chord
  /// role: the engine asks `measure(text, ChartTextRole.chord)` for every chord and has no way to
  /// ask for the small size, so [ChartPainter] chooses this style per placed chord instead.
  final TextStyle smallChordStyle;

  /// The style of a section label such as `A` or `Intro`.
  final TextStyle sectionLabelStyle;

  /// The style of staff text and of the bar signs drawn as glyphs.
  final TextStyle staffTextStyle;

  /// The style of a text cue — the words a musician writes on the chart as a remark.
  ///
  /// A SEPARATE STYLE FROM [staffTextStyle] and not a bigger one of it: the engine measures a cue
  /// with this style to reserve the row above its bar, and `TextCuePainter` draws the words at
  /// this style's size brought down by the page scale no further than `textCueMinLegibleScale`.
  /// A caller that changes this style must hand the same one to the painter, exactly as a caller
  /// that changes [chordStyle] must keep drawing chords with it.
  final TextStyle textCueStyle;

  // PURPOSE: Give the one style a role is both measured and drawn with, so the two cannot drift
  //          apart through a second lookup elsewhere.
  // INPUTS: role — which kind of chart text the caller is asking about.
  // OUTPUTS: The style for that role. Never null. [ChartTextRole.chord] returns [chordStyle];
  //          the small size is not reachable from a role and is chosen by ChartPainter per chord.
  // KEYWORDS: style-lookup, role, measure-and-draw-agreement
  /// Returns the style [role] is measured and drawn with.
  TextStyle styleFor(ChartTextRole role) => switch (role) {
    ChartTextRole.chord => chordStyle,
    ChartTextRole.sectionLabel => sectionLabelStyle,
    ChartTextRole.staffText => staffTextStyle,
    ChartTextRole.textCue => textCueStyle,
  };

  // PURPOSE: Answer the one question the layout engine asks of the font stack — how big is this
  //          string — without handing the engine a paragraph, a baseline or a glyph run it has no
  //          use for.
  // INPUTS: text — the string to measure; may be empty. role — the style to measure it with.
  // OUTPUTS: A LayoutSize in logical pixels. An empty string returns zero width, which is the
  //          documented contract, and a line height taken from the painter or, when the font
  //          stack reports none, from the style's font size.
  // KEYWORDS: measure, layout-size, empty-string, total-function
  @override
  LayoutSize measure(String text, ChartTextRole role) {
    final TextStyle style = styleFor(role);
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double width = text.isEmpty ? 0 : painter.width;
    final double height = painter.height;
    painter.dispose();
    return LayoutSize(width, height > 0 ? height : _fallbackLineHeight(style));
  }

  // PURPOSE: Keep [measure] total when the font stack reports no line height, which an unresolvable
  //          fallback font can do, instead of returning a zero-height box that would stack every
  //          chord of a bar onto one line.
  // INPUTS: style — the style whose line height could not be measured.
  // OUTPUTS: A positive height derived from the style's font size, or 17.5 when the style names no
  //          size either. Never zero.
  // KEYWORDS: fallback, line-height, total-function, missing-font
  double _fallbackLineHeight(TextStyle style) => (style.fontSize ?? 14) * 1.25;

  // PURPOSE: Let a painter decide whether it has to repaint, which requires the metrics to compare
  //          by value rather than by identity: a rebuild creates a new metrics instance from the
  //          same styles, and an identity comparison would repaint the page on every frame.
  // INPUTS: other — any object.
  // OUTPUTS: True for a FlutterTextMetrics built from the same five styles.
  // KEYWORDS: equality, value-semantics, repaint, styles
  @override
  bool operator ==(Object other) =>
      other is FlutterTextMetrics &&
      other.chordStyle == chordStyle &&
      other.smallChordStyle == smallChordStyle &&
      other.sectionLabelStyle == sectionLabelStyle &&
      other.staffTextStyle == staffTextStyle &&
      other.textCueStyle == textCueStyle;

  @override
  int get hashCode => Object.hash(
    chordStyle,
    smallChordStyle,
    sectionLabelStyle,
    staffTextStyle,
    textCueStyle,
  );

  @override
  String toString() =>
      'FlutterTextMetrics(chord ${chordStyle.fontSize}, '
      'small ${smallChordStyle.fontSize}, label ${sectionLabelStyle.fontSize}, '
      'cue ${textCueStyle.fontSize})';
}
