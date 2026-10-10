// PURPOSE: Accumulate the live samples of one handwritten stroke and, when the pen lifts, produce
//          the canonical [InkStroke] the operation log stores. It exists so that the two easy
//          mistakes in this step happen in one place and are decided rather than left to a call
//          site: the anchor must be chosen ONCE, from where the stroke began, and every stored point
//          must be measured from that same anchor.
//
//          WHY THE ANCHOR IS CHOSEN AT THE BEGINNING AND NOT THE END. The stroke's own first sample
//          is the only evidence of where the musician meant to write. Choosing the anchor from the
//          stroke's bounding-box centre — which is what a native surface reports after the fact,
//          because it hands back a blob and a box — would move a stroke that overshot its cell into
//          the neighbouring one, and the error would only appear after a transposition.
//
//          WHY A ONE-POINT STROKE IS NOT DROPPED. A dot is a real mark: a musician taps the pen to
//          place a dot over a chord. It is stored as two identical points, because [InkStroke]
//          rejects an empty list and because a stroke needs a finite length for a renderer to draw
//          with a round cap. The alternative — refusing it — loses a mark the musician made.
// INPUTS: A page to resolve the anchor against, the stroke's samples in SURFACE logical pixels, the
//         pointer kind, the time base of the samples, and the identity and ink parameters to commit
//         with.
// OUTPUTS: An [InkStroke] in the canonical anchor-local form, or null when the stroke began outside
//          every bar so there is no anchor to attach it to. Null is reported to the caller rather
//          than stored as a fabricated anchor.
// KEYWORDS: ink, stroke-assembly, canonical-form, anchor-local, dot-handling, pressure-normalising,
//           pure-dart
import 'package:chart_core/src/ink/page_anchor.dart';
import 'package:chart_core/src/layout/geometry.dart';
import 'package:chart_core/src/layout/hit_test.dart';
import 'package:chart_core/src/layout/page_layout.dart';
import 'package:chart_core/src/oplog/oplog.dart';

/// One raw sample of a live stroke, in the coordinates the surface delivered it in.
///
/// Kept as a separate value from [InkPoint] on purpose: an [InkPoint] is storage and is anchor-local
/// and complete, while this is capture and is surface-local and may be incomplete. Converting at the
/// boundary is what keeps the two from being confused for one another.
class InkSample {
  /// Creates a surface-local sample at ([x], [y]) with pressure [pressure] at [t] milliseconds.
  const InkSample({
    required this.x,
    required this.y,
    required this.pressure,
    required this.t,
  });

  /// Horizontal position on the surface the page is drawn on, in logical pixels.
  final double x;

  /// Vertical position on the surface the page is drawn on, in logical pixels.
  final double y;

  /// Pressure as the capture layer normalised it, nominally in `[0, 1]`.
  final double pressure;

  /// Milliseconds since the stroke's first sample.
  final double t;

  @override
  String toString() =>
      'InkSample(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
      'p=${pressure.toStringAsFixed(2)}, t=$t)';
}

// PURPOSE: Assemble one stroke from its samples, which is the whole of "what the pen drew becomes
//          what the document stores". It is separable from the pointer handler because the handler
//          owns a widget's lifecycle and this owns a decision about geometry, and because this half
//          can be run against synthetic samples with no browser and no hand.
// INPUTS: See [begin]; the parameters of one stroke. The page is examined only once, at [begin].
// OUTPUTS: A stroke per call to [end], in canonical anchor-local form, or null when no anchor
//          resolved. [cancel] discards without producing anything, which is what a platform
//          pointer-cancel means and not an error.
// KEYWORDS: stroke-builder, single-use, anchor-once, surface-to-local, no-anchor-no-stroke
/// Builds one canonical stroke from the live samples of one contact.
class InkStrokeAssembler {
  /// Opens an assembler for a stroke about to be drawn with [tool] and [color] at [size].
  ///
  /// [size] is the nib width in anchor-local logical pixels, which is also the unit the stored
  /// points are in, so a nib recorded here draws the same width at every page scale.
  InkStrokeAssembler({
    required this.tool,
    required this.color,
    required this.size,
  });

  /// The tool the finished stroke is committed with.
  final StrokeTool tool;

  /// The stroke colour as a `#rrggbb` or `#rrggbbaa` string.
  final String color;

  /// The nib width in anchor-local logical pixels.
  final double size;

  final List<InkSample> _samples = <InkSample>[];
  EventAnchor? _anchor;
  LayoutOffset _anchorOrigin = LayoutOffset.zero;
  double _startTime = 0;
  bool _begun = false;

  /// Whether a stroke is currently open.
  bool get isOpen => _begun;

  /// How many samples the open stroke holds.
  int get sampleCount => _samples.length;

  /// The anchor the open stroke resolved to, or null while it has not resolved one.
  EventAnchor? get anchor => _anchor;

  /// The time the open stroke began, in the samples' own millisecond base.
  ///
  /// Part of the identity a caller builds for the committed stroke, and exposed for that reason: an
  /// id derived from the start of the stroke is unique across two runs of the application, while an
  /// id that counts from one would collide with a stroke the file already carried.
  double get startTime => _startTime;

  /// The open stroke's samples converted to the canonical anchor-local form, without closing it.
  ///
  /// Used to draw a stroke that is still under the pen: it goes through the same conversion [end]
  /// does, so the live line and the committed line cannot land in different places. The points are
  /// complete, so a caller must not store them — they are not yet a stroke.
  ///
  /// An assembler whose anchor has not resolved returns an empty list rather than throwing, because
  /// a live preview is asked for on every move and a stroke between being refused and being replaced
  /// is a normal state.
  List<InkPoint> pointsSnapshot(PageLayout page) {
    if (_anchor == null || _samples.isEmpty) {
      return const <InkPoint>[];
    }
    final bool anyPressure = _samples.any((InkSample s) => s.pressure > 0);
    return <InkPoint>[
      for (final InkSample sample in _samples)
        _localPoint(sample, page, anyPressure: anyPressure),
    ];
  }

  // PURPOSE: Open the stroke and resolve, once, the anchor every later sample is measured against.
  // INPUTS: page — the layout the stroke is being drawn on, in engraved coordinates, which is what
  //         the hit test speaks. surfacePoint — the stroke's first position on the surface the page
  //         is drawn on, from which the page point is derived through the page's own
  //         [PageLayout.pagePointOf]. pressure and time — the first sample's values, in `[0, 1]` and
  //         milliseconds from an arbitrary origin. The absolute origin does not matter: only
  //         differences between samples are stored, which is what keeps a clock reset from
  //         corrupting a stroke.
  // OUTPUTS: True when an anchor resolved and the stroke is open; false when the first point lies
  //          over no bar, in which case nothing was recorded and [end] would produce null. A
  //          pen stroke that starts in the margin between two systems is refused rather than
  //          attached to the nearest bar, because "the nearest bar" is a guess about intent.
  // KEYWORDS: begin, anchor-resolution, hit-test, page-point, refuse-in-margin
  /// Opens the stroke against the bar or cell under [surfacePoint], reporting whether it resolved.
  bool begin({
    required PageLayout page,
    required LayoutOffset surfacePoint,
    required double pressure,
    required double time,
  }) {
    final LayoutOffset pagePoint = page.pagePointOf(surfacePoint);
    final ChartHit? hit = hitTestPage(page, pagePoint);
    if (hit == null) {
      _begun = false;
      _anchor = null;
      _samples.clear();
      return false;
    }
    final InkPlacement? placement = resolveEventAnchor(
      page,
      EventAnchor(sectionId: hit.sectionId, bar: hit.barIndex, beat: hit.beat),
    );
    if (placement == null) {
      _begun = false;
      _anchor = null;
      return false;
    }
    _anchor = placement.anchor;
    _anchorOrigin = placement.origin;
    _startTime = time;
    _samples
      ..clear()
      ..add(
        InkSample(
          x: surfacePoint.x,
          y: surfacePoint.y,
          pressure: pressure,
          t: time,
        ),
      );
    _begun = true;
    return true;
  }

  // PURPOSE: Record one more sample of the open stroke.
  // INPUTS: surfacePoint — where the contact was. pressure — its pressure. time — its timestamp,
  //         in the same base as [begin]'s.
  // OUTPUTS: Nothing. A sample for a stroke that never opened is dropped, so a move that arrives
  //          after a refused begin cannot resurrect the stroke with a missing first point.
  // KEYWORDS: add-sample, no-op-when-closed, surface-local
  /// Adds one sample, doing nothing when no stroke is open.
  void add({
    required LayoutOffset surfacePoint,
    required double pressure,
    required double time,
  }) {
    if (!_begun) {
      return;
    }
    _samples.add(
      InkSample(
        x: surfacePoint.x,
        y: surfacePoint.y,
        pressure: pressure,
        t: time,
      ),
    );
  }

  // PURPOSE: Close the open stroke and produce its canonical form.
  // INPUTS: page — the layout the stroke was drawn on, needed for the scale that converts the
  //         samples back into page coordinates. id — the identity the caller assigned, which must be
  //         unique in the document because the eraser removes by it.
  // OUTPUTS: The [InkStroke], or null when no stroke is open or no anchor ever resolved. The points
  //          are anchor-local, ordered as drawn, with `t` relative to the first sample. A stroke of
  //          one point becomes two identical points so it renders as a dot instead of as nothing.
  //
  //          THE PRESSURE FALLBACK IS DECLARED, NOT SILENT: a platform that reports pressure as a
  //          constant zero for every sample — a mouse, or a digitizer that publishes no pressure
  //          axis — would otherwise produce a stroke of zero-width nibs that draws nothing. When
  //          every sample is zero the stroke's pressures become one half, which is the neutral nib;
  //          a real pen whose reading happened to be zero for one sample keeps that sample, because
  //          a single low point in a stroke is a real measurement and not a missing axis.
  // KEYWORDS: end, canonical-form, anchor-local, pressure-fallback, dot, single-use
  /// Closes the stroke, returning it in canonical form or null when there is none.
  InkStroke? end({required PageLayout page, required String id}) {
    if (!_begun || _anchor == null) {
      _reset();
      return null;
    }
    final bool anyPressure = _samples.any((InkSample s) => s.pressure > 0);
    final List<InkPoint> points = <InkPoint>[
      for (final InkSample sample in _samples)
        _localPoint(sample, page, anyPressure: anyPressure),
    ];
    if (points.length == 1) {
      points.add(points.first);
    }
    final EventAnchor anchor = _anchor!;
    _reset();
    return InkStroke(
      id: id,
      tool: tool,
      color: color,
      size: size,
      anchor: anchor,
      points: points,
    );
  }

  // PURPOSE: Abandon the open stroke without producing anything, which is what a pointer cancel
  //          means: the contact was taken away rather than finished. Committing a cancelled stroke
  //          would put a line on the chart that the musician never drew.
  // INPUTS: None.
  // OUTPUTS: Nothing. The assembler is ready for a new stroke.
  // KEYWORDS: cancel, discard, pointer-cancel, reusable
  /// Discards the open stroke.
  void cancel() => _reset();

  /// Clears the working state so the assembler can be reused for the next stroke.
  void _reset() {
    _samples.clear();
    _anchor = null;
    _anchorOrigin = LayoutOffset.zero;
    _begun = false;
  }

  // PURPOSE: Convert one surface sample into the stored form: a position measured from the anchor's
  //          own origin, in the page's engraved units, with the stroke-relative time.
  // INPUTS: sample — the captured sample. page — the layout being drawn on, which carries the single
  //         surface-to-page transform as [PageLayout.pagePointOf]; the page is passed rather than its
  //         `scale` because a caller holding only the factor would have to re-derive the division
  //         here, and a second rule for one transform is exactly how a stroke and its renderer drift
  //         apart by a factor of the scale. anyPressure — whether any sample of this stroke reported
  //         pressure, which is passed in rather than recomputed per point because the answer is a
  //         property of the whole stroke and recomputing it here would give a per-point answer.
  // OUTPUTS: An [InkPoint]. The sample's surface position goes through the page's own
  //          [PageLayout.pagePointOf] and only then subtracts [inkPointToPage]'s inverse, so capture
  //          and the hit test that admitted the stroke are literally the same arithmetic. On a fitted
  //          page that transform DIVIDES by the scale — it does not multiply — because the painter
  //          reaches the surface by multiplying the engraved geometry up (`canvas.scale`).
  // KEYWORDS: point-conversion, anchor-local, pagePointOf, single-route, no-second-transform
  InkPoint _localPoint(
    InkSample sample,
    PageLayout page, {
    required bool anyPressure,
  }) {
    final LayoutOffset pagePoint = page.pagePointOf(
      LayoutOffset(sample.x, sample.y),
    );
    final LayoutOffset local = pagePointToAnchorLocal(pagePoint, _anchorOrigin);
    return InkPoint(
      x: local.x,
      y: local.y,
      w: _normalisePressure(sample.pressure, anyPressure: anyPressure),
      t: sample.t - _startTime,
    );
  }

  /// Clamps one sample's pressure into `[0, 1]`, substituting the neutral half when the whole stroke
  /// reported none.
  static double _normalisePressure(
    double pressure, {
    required bool anyPressure,
  }) {
    if (!anyPressure || !pressure.isFinite) {
      return 0.5;
    }
    if (pressure < 0) {
      return 0;
    }
    if (pressure > 1) {
      return 1;
    }
    return pressure;
  }
}
