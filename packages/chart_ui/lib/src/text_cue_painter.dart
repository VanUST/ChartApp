// PURPOSE: Draw the words a musician has written on the chart — `To Coda`, `D.C. al Fine`, `Solo`,
//          `Vamp`, `4×` — in the rows the layout reserved for them, above the bars they remark on.
//          It is the visible half of the `textcue.*` family: `EditSession` decides which event a
//          gesture is, the document holds the cues, the layout reserves and places a row for each
//          one, and this painter is the only thing that puts them on the page. A SEPARATE PAINTER
//          FROM `ChartPainter` for the same reason `InkPainter` is one: the chart painter draws
//          engraved notation, which is identical for every reader of a tune, while a cue belongs to
//          one band and one rehearsal. Keeping them apart is also what makes this layer testable and
//          addable without touching a line of the engraver — while the rows the layout hands it are
//          what keep the remark off the chord beneath it.
// INPUTS: A list of [ResolvedTextCue] — each carrying a document cue, the origin of the row the
//         layout reserved for it, and the box it occupies there, all in the page's engraved
//         coordinates — the page's own [pageScale], and the style and plate colour the layer draws
//         with.
// OUTPUTS: [paint] writes into the canvas and returns nothing. A cue with no words draws nothing at
//          all, not even its plate; see [TextCuePainter] for why. Everything is drawn inside the
//          page's clip, so a cue that runs past the page edge cannot bleed into a neighbouring page
//          of a `PageView`.
// KEYWORDS: text-cue-renderer, custom-painter, placed-row, surface-legibility, page-scale,
//           draw-order, plate
//
// WHY THE LETTERS FOLLOW THE PAGE DOWN TO A FLOOR OF THEIR OWN.
//
// The anchor is resolved to a rectangle in the page's ENGRAVED coordinates and the row the layout
// reserved for the cue sits above it, so the position on the surface is
// `(row.origin + offset) * pageScale` — the same one-transform bridge `ChartPainter` and
// `InkPainter` apply, and the reason a cue survives a FITTED page, a transposition and a round
// trip. That multiplication is not optional: it is what puts the words on the bar. Only the X half
// of it is now the anchor's own column; the Y half is the reserved row, which is what keeps the
// plate off the chord beneath it.
//
// The LETTERS are scaled too, but only down to `textCueMinLegibleScale`, and the two floors are
// different numbers on purpose. Owner decision D13 lets FIT shrink a whole song onto one page and
// refuses to go below `LayoutEngine.minLegibleScale = 0.5` (A30) — that is a floor on the MUSIC,
// chosen so a chord stays readable. A cue is set from a smaller budget than a chord is: it is a
// sentence read once from a stand, often in a dark room, so its own floor is HIGHER, at 0.8. On the
// page: down to a page scale of 0.8 the words shrink exactly as the bar does, so a cue occupies the
// same part of its bar on a fitted page as on an ordinary one; below 0.8 the words stop shrinking
// while the bar keeps going, so the cue becomes proportionally larger — the direction a performance
// instruction may safely err in — and it can never reach the glass smaller than
// `16 * 0.8 = 12.8` surface logical pixels, which is still larger than the fitted chord it
// annotates.
//
// WHERE THE ROOM FOR IT COMES FROM, AND WHAT THAT COSTS. The letters' floor is a promise about the
// SIZE ON THE GLASS, so the row that holds them grows in the page's own coordinates as the page
// shrinks: the box the layout reserved is `(letters * letterScale + plate) / pageScale` pixels
// tall, and `LayoutEngine` engraves every trial of the FIT search at the scale it is testing so
// that this is the same number the reader will see. The cost is therefore paid in VERTICAL ROOM —
// a system carrying a cue gives up a band above its stave, and a page whose systems no longer fit
// paginates sooner or overflows its bottom edge visibly — and not, as it once was, in the chord
// symbol the remark was written about. A cue is never dropped and never drawn over its own chord;
// `PlacedTextCue` carries the row for exactly that reason.
//
// WHY THE SIZE IS 16 AND THE PLATE IS THERE.
//
// `FlutterTextMetrics.chordStyle` draws a chord at 15 logical pixels, semibold. A chord is read at
// a glance by someone who already knows the song; a cue is the only thing on the page that is a
// SENTENCE rather than a symbol — `D.C. al Fine` has to be read in full, once, from a stand, often
// in a dark room — so it is set one step LARGER than the music it annotates, at 16 pixels and
// semibold, in the same dark ink. The words are then laid on a nearly opaque plate for a reason
// that follows from the placement rule: a cue is allowed to run wider than its own bar (it does not
// reflow and it is not clipped to the bar), so it can cross a neighbouring chord symbol or a
// barline, and a plate is what keeps the sentence readable where it does. Neither the plate nor the
// words is drawn for an empty cue, because there is nothing to read and an empty cue must not look
// like a mark on the page.
import 'package:chart_core/chart_core.dart';
import 'package:flutter/rendering.dart';

import 'flutter_text_metrics.dart';

// PURPOSE: Carry one cue together with the box the layout placed it in, which is the pair this
//          renderer needs and the pair the caller has just read off the page. It exists so the
//          painter never searches a layout mid-frame for an anchor, and never measures a string
//          the layout already measured: the lookup happens once per rebuild, in the caller, exactly
//          as `ResolvedInkStroke` does for the ink layer.
// INPUTS: The document cue, the origin of the row the layout reserved for it, in the page's
//         engraved coordinates, and the size of the box it occupies there.
// OUTPUTS: An immutable value. The cue's own words and offset are NOT copied or transformed, so a
//          page that has no row for the cue is the only way a cue is absent here.
// KEYWORDS: resolved-cue, cue-row, page-coordinates, render-input, immutable, no-measurement
/// A document text cue placed in the row the layout reserved for it.
class ResolvedTextCue {
  /// Creates a resolved cue for [cue] at [origin] occupying [size].
  const ResolvedTextCue({
    required this.cue,
    required this.origin,
    required this.size,
  });

  /// The cue as the document holds it.
  final TextCue cue;

  /// The top-left of the row the layout reserved, in the page's engraved coordinates.
  ///
  /// The cue's own stored offset is measured from here, so this is what the anchor's corner used
  /// to be: its x is the bar's or the cell's own left edge, and its y is the bottom of the band the
  /// system gave up so that the plate would not lie on the chord.
  final LayoutOffset origin;

  /// The box the plate occupies, in the page's engraved coordinates, as the layout published it.
  final LayoutSize size;

  @override
  String toString() =>
      'ResolvedTextCue(${cue.id} at ${origin.x.toStringAsFixed(1)},'
      '${origin.y.toStringAsFixed(1)} '
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)})';
}

/// Draws the text cues of one laid-out page over the music.
class TextCuePainter extends CustomPainter {
  /// Creates a painter for the cues that belong on one page.
  ///
  /// [pageScale] must be the same `PageLayout.scale` the `ChartPainter` drawing this page was
  /// given, because the two layers are positioned by the same transform and a mismatch would slide
  /// every cue off the bar it names.
  const TextCuePainter({
    required this.cues,
    required this.pageScale,
    this.textStyle = defaultTextStyle,
    this.plateColor = defaultPlateColor,
  });

  /// The size a cue is drawn at on an ordinary page, in logical pixels.
  ///
  /// See the file header for why it is one step larger than the chord style and why the page scale
  /// is allowed to bring it down — but no further than [minLegibleScale]. It is the same constant
  /// the layout measures the words with, so the row reserved for a cue and the words drawn in it
  /// are one size by construction.
  static const double cueFontSize = chartTextCueFontSize;

  /// The smallest fraction of [cueFontSize] a cue may be drawn at, whatever the page does.
  ///
  /// A separate floor from `LayoutEngine.minLegibleScale`, and a HIGHER one on purpose: 0.8 of 16 is
  /// 12.8 surface logical pixels, which is still larger than the fitted chord it annotates at the
  /// page's own floor of 0.5. It is `textCueMinLegibleScale` rather than a second number because the
  /// layout divides a cue's box by the page scale using the SAME floor: a cue that stopped shrinking
  /// at 0.8 here while the layout reserved rows at 0.9 would be drawn taller than its own row.
  static const double minLegibleScale = textCueMinLegibleScale;

  /// The style a cue is drawn with when the caller names none, before the page scale is applied.
  ///
  /// The metrics' own cue style, so the page the engine measured and the page this painter draws are
  /// the same page. A caller that hands [FlutterTextMetrics] a different `textCueStyle` must hand
  /// this painter the same style, or the words will be drawn in a box measured for other ones.
  static const TextStyle defaultTextStyle = chartTextCueStyle;

  /// The colour of the plate behind a cue when the caller names none: the page's white, at 90 %
  /// opacity, so a cue crossing a chord symbol or a barline is still read as one sentence.
  static const Color defaultPlateColor = Color(0xE6FFFFFF);

  /// The space the plate keeps between its edge and the words, in surface logical pixels.
  ///
  /// The layout reserves the plate, insets included, so this is a layout constant the painter reads
  /// rather than a number of its own — see `textCuePlateInsetX`/`textCuePlateInsetY`. The words are
  /// drawn this far inside the box the layout published, and the box is that much bigger than the
  /// words, which is what makes the two agree at every page scale.
  static const EdgeInsets platePadding = EdgeInsets.symmetric(
    horizontal: textCuePlateInsetX,
    vertical: textCuePlateInsetY,
  );

  /// The cues to draw, in render order: later entries lie on top, as they do in the document.
  final List<ResolvedTextCue> cues;

  /// The page's own scale.
  ///
  /// Applied to each cue's POSITION in full, and to its LETTERS down to [minLegibleScale].
  final double pageScale;

  /// The style the words are drawn with, in logical pixels at a page scale of 1.
  final TextStyle textStyle;

  /// The colour of the plate laid under the words, or fully transparent for none.
  final Color plateColor;

  // PURPOSE: Report the factor the letters are actually drawn at, which is [pageScale] with its own
  //          floor under it, so the one place that decides how small a cue may get is here rather
  //          than spread over the two places that measure and paint it.
  // INPUTS: None; reads [pageScale].
  // OUTPUTS: [pageScale] when it is at or above [minLegibleScale], and [minLegibleScale] otherwise.
  //          Never zero and never negative: the engine emits 1 or a value at or above its own floor,
  //          and the fallback for a page a caller built by hand with a meaningless scale is the
  //          floor, which draws words that are readable rather than words that are absent.
  // KEYWORDS: letter-scale, legibility-floor, total-function, single-decision
  /// Returns the factor the letters are drawn at: [pageScale] with its own floor under it.
  double get letterScale =>
      pageScale < minLegibleScale ? minLegibleScale : pageScale;

  // PURPOSE: Draw every cue at its anchor, in the document's own order, so that the words on screen
  //          are the words in the file rather than a re-derivation of them.
  // INPUTS: canvas — the target. size — the extent the painter was given, used only as the clip.
  // OUTPUTS: Nothing. The canvas is saved and restored around the clip, so a caller stacking this
  //          painter over the chart painter gets its transform back unchanged. An empty cue list,
  //          and a cue with no words, both draw nothing.
  // KEYWORDS: paint, clip, render-order, empty-cue-draws-nothing, save-restore
  @override
  void paint(Canvas canvas, Size size) {
    if (cues.isEmpty) {
      return;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final ResolvedTextCue resolved in cues) {
      _paintCue(canvas, resolved);
    }
    canvas.restore();
  }

  // PURPOSE: Draw one cue: its plate, then its words, in the box the layout published and at the
  //          position its own stored offset gives, with the letters brought down by the page scale
  //          no further than [letterScale] allows.
  // INPUTS: canvas — the target. resolved — the cue, the row the layout reserved for it and the box
  //         it occupies there.
  // OUTPUTS: Nothing. A cue with no words returns before drawing anything, so an inserted-but-empty
  //          cue is invisible on the page rather than an unlabelled plate that looks like a mark.
  // KEYWORDS: cue-plate, published-box, surface-position, letter-floor, empty-cue
  void _paintCue(Canvas canvas, ResolvedTextCue resolved) {
    final TextCue cue = resolved.cue;
    if (cue.text.isEmpty) {
      return;
    }
    final LayoutOffset row = resolved.origin;
    final LayoutSize size = resolved.size;
    final AnchoredPlace place = cue.place;
    // The row is the cue's home on the page; the cue's own stored offset moves the words from it,
    // exactly as it used to move them from the anchor's corner. One multiplication by the page scale
    // takes both into engraved-to-surface coordinates.
    final double left = (row.x + place.offsetX) * pageScale;
    final double top = (row.y + place.offsetY) * pageScale;
    final double width = size.width * pageScale;
    final double height = size.height * pageScale;
    if (plateColor.a > 0) {
      canvas.drawRect(
        Rect.fromLTWH(left, top, width, height),
        Paint()..color = plateColor,
      );
    }
    // The plate's box already holds the padding, because the layout had to reserve it; the words go
    // inside it. The painter does not measure the string for geometry: the width it draws into is
    // the width the layout measured with the metrics both sides share.
    final TextPainter painter = _painterFor(cue.text);
    painter.paint(
      canvas,
      Offset(left + platePadding.left, top + platePadding.top),
    );
    painter.dispose();
  }

  // PURPOSE: Report whether a new painter changes anything on screen, so a cue committed to the
  //          document repaints the layer.
  // INPUTS: oldDelegate — the painter this one replaces.
  // OUTPUTS: True when the cue list, the page scale, the style or the plate colour differs. The list
  //          is compared element by element because `List` has no value equality, and comparing
  //          identity would miss a freshly built list holding the same cues — which is the ordinary
  //          case after a rebuild, as it is for `InkPainter`.
  // KEYWORDS: should-repaint, element-comparison, rebuild, value-comparison
  @override
  bool shouldRepaint(covariant TextCuePainter oldDelegate) =>
      oldDelegate.pageScale != pageScale ||
      oldDelegate.textStyle != textStyle ||
      oldDelegate.plateColor != plateColor ||
      !_sameCues(oldDelegate.cues, cues);

  // PURPOSE: Build the one painter configuration every cue is laid out with, so measurement and
  //          painting cannot disagree about direction, line count or size.
  // INPUTS: text — the words, never empty for a caller.
  // OUTPUTS: A laid-out [TextPainter]; the caller owns it and must dispose it. The style's size is
  //          multiplied by [letterScale], which is the ONLY place the page scale reaches a cue's
  //          letters, so the box the caller was given and the words drawn into it are the same box.
  //          A cue is ONE line: wrapping would change where its words sit relative to the bar, and
  //          the placement rule is that a long cue runs wide rather than down.
  // KEYWORDS: text-painter, factory, left-to-right, single-line, no-wrap, letter-floor
  TextPainter _painterFor(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: textStyle.copyWith(
        fontSize: (textStyle.fontSize ?? cueFontSize) * letterScale,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  /// Whether two resolved-cue lists hold equal elements in the same order.
  static bool _sameCues(
    List<ResolvedTextCue> left,
    List<ResolvedTextCue> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index++) {
      final ResolvedTextCue a = left[index];
      final ResolvedTextCue b = right[index];
      if (a.origin != b.origin || a.size != b.size || a.cue != b.cue) {
        return false;
      }
    }
    return true;
  }
}
