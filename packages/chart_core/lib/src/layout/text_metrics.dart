// PURPOSE: Decouple the layout engine from any text stack. Measuring a chord symbol is the one
//          operation the engine cannot perform itself without a font, and that is exactly the
//          dependency that would drag Flutter into chart_core and make the whole pipeline
//          unrunnable on a desktop. Injecting the measurement instead keeps the engine pure, so
//          a page can be laid out inside `dart test` and timed by spike S4 on a PC.
// INPUTS: Text to measure and the role it plays in a chart. Implementations may be backed by a
//         real font engine or by a deterministic model.
// OUTPUTS: A LayoutSize per measurement. The engine never asks for anything else from text: it
//          does not need glyph shapes, baselines or kerning, only the box a string occupies.
// KEYWORDS: text-metrics, dependency-injection, testability, deterministic, font-abstraction
//
// In the application the implementation is backed by Flutter's TextPainter. In tests and in the
// S4 benchmark it is [FixedAdvanceTextMetrics], whose answer depends only on the string length,
// so a layout assertion is exact rather than font-dependent.

import 'geometry.dart';

/// The roles text plays in a chart.
///
/// A role exists because the same string is a different size as a chord symbol and as a section
/// label. Asking for the role rather than a font size keeps font sizes out of the engine.
enum ChartTextRole {
  /// A chord symbol such as `Dm7`.
  chord,

  /// A section label such as `A` or `Intro`.
  sectionLabel,

  /// Free text carried by a bar, such as a navigation phrase.
  staffText,

  /// A phrase a musician writes ON the chart as a remark: `To Coda`, `D.C. al Fine`, `Solo`.
  ///
  /// A SEPARATE ROLE FROM [staffText], and not only because a cue is set larger. A cue is drawn
  /// ABOVE its bar, in a row the layout reserves for it, so the height this role answers with is
  /// not a detail of the drawing — it is the vertical room the page gives up to hold the remark.
  /// Measuring it with [staffText] would reserve the room of a 10-pixel line for words drawn at
  /// 16 and let the plate fall back onto the chord beneath, which is the defect this role exists
  /// to close.
  textCue,
}

/// Measures rendered text.
abstract class TextMetrics {
  /// Returns the box [text] occupies when drawn in [role].
  ///
  /// An empty string must measure to a zero-width box rather than throwing: a bar can carry an
  /// empty staff-text entry, and the engine treats that as nothing to draw.
  LayoutSize measure(String text, ChartTextRole role);
}

/// A metrics model whose answer depends only on the string length.
///
/// It exists so that layout behaviour is testable without a font: two runs on two machines
/// produce identical geometry, which is what lets a layout assertion name an exact number. It is
/// also what spike S4 measures, so the number it reports is the engine's cost and not the
/// font engine's.
class FixedAdvanceTextMetrics implements TextMetrics {
  /// Creates metrics advancing [advancePerCharacter] per character, with a fixed line height per
  /// role.
  const FixedAdvanceTextMetrics({
    this.advancePerCharacter = 8,
    this.chordHeight = 18,
    this.sectionLabelHeight = 20,
    this.staffTextHeight = 16,
    this.textCueHeight = 19,
  });

  /// Horizontal advance contributed by each character.
  final double advancePerCharacter;

  /// Line height of a chord symbol.
  final double chordHeight;

  /// Line height of a section label.
  final double sectionLabelHeight;

  /// Line height of staff text.
  final double staffTextHeight;

  /// Line height of a text cue, one step above [staffTextHeight] as a cue is one step above the
  /// music it annotates.
  final double textCueHeight;

  @override
  LayoutSize measure(String text, ChartTextRole role) {
    final double height = switch (role) {
      ChartTextRole.chord => chordHeight,
      ChartTextRole.sectionLabel => sectionLabelHeight,
      ChartTextRole.staffText => staffTextHeight,
      ChartTextRole.textCue => textCueHeight,
    };
    if (text.isEmpty) {
      return LayoutSize(0, height);
    }
    return LayoutSize(text.length * advancePerCharacter, height);
  }
}
