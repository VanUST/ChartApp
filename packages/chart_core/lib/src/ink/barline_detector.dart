// PURPOSE: Decide, from the handwriting a musician actually put on the page, which marks are the
//          VERTICAL DIVISIONS of the chart — the strokes that cut one bar's music off from the next
//          — and which are only letters that happen to be tall and narrow. It exists because the
//          owner asked for a chart with no imposed grid: he draws the divisions himself and the
//          application finds them, so the finding must be geometry that can be measured and argued
//          about rather than a model that cannot be inspected.
//
//          A VERTICAL STROKE IS ALSO HOW A MUSICIAN WRITES `1`, `l`, `I`, the stem of a `t`, the
//          bar of a `7`, the paren of a `(b9)` and the slash of a `6/9`. The owner's own page holds
//          exactly those, and a detector that fires on them is worse than none, because he would
//          have to repair every one. So a candidate must satisfy THREE INDEPENDENT GATES, each of
//          which alone rejects every tall narrow letter in his sample, and a fourth that is about
//          the chart rather than the mark:
//
//            1. SHAPE  — it travels downward and does not come back: net fall over path length, and
//                        height over width. This is what a line is and a curve is not.
//            2. SIZE   — it is tall relative to the ROW it divides. Derived from his hand: the
//                        tallest vertical mark he wrote is 22.8 px in a 52 px row, 44% of it, so
//                        the floor is set above that and below the row's own height.
//            3. PLACE  — it crosses the row it claims to divide rather than sitting above or below
//                        it. A note stem or a mark in the margin is not a division of this bar.
//            4. COMPANY — no other ink within a gap at its side. THIS IS THE GATE THAT SEPARATES
//                        "inside a chord symbol" from "between two symbols", and it is the one the
//                        page's own letters cannot pass: the owner's `(` stands 1.1 px from the `b`
//                        it belongs to.
//
//          WHAT IT DELIBERATELY DOES NOT DO. It does not read notes or chord symbols, and it does
//          not guess a musician's intention from a mark that is merely close: a candidate must be
//          a line by measurement. It also does not act on the chart — it returns candidates, and
//          the caller records them as divisions through the operation log.
// INPUTS: A committed [InkStroke] whose points are in ANCHOR-LOCAL logical pixels, the
//         [LayoutRect] of the anchor it was captured against, and — for the company gate — the
//         other strokes on the same page with the anchor origins that place them.
// OUTPUTS: [BarlineCandidate] values naming the stroke, the anchor-local centre of the line it
//         implies, and its vertical extent. Detection is TOTAL: a stroke that fails any gate is
//         reported with the gate it failed as a [BarlineRejection], never with an exception, and a
//         page with no ink yields no candidates. Every threshold lives in [BarlineThresholds] as a
//         named constant with the measurement that chose it beside it, so a change is one edit
//         rather than a hunt.
// KEYWORDS: barline, detection, handwriting, geometry, verticality, aspect, isolation, false-
//           positive, thresholds-from-ink, d37, no-ml, pure-dart
import 'dart:math' as math;

import 'package:chart_core/src/ink/page_anchor.dart';
import 'package:chart_core/src/layout/geometry.dart';
import 'package:chart_core/src/layout/page_layout.dart';
import 'package:chart_core/src/oplog/oplog.dart';

/// The numeric gates a mark must pass to count as a division of a bar.
///
/// ONE OBJECT RATHER THAN SCATTERED LITERALS, so that the thresholds this feature lives or dies by
/// can be read, argued with and changed in one place — and so that the probe which reports them on
/// the owner's real ink reports the same numbers the detector uses.
class BarlineThresholds {
  /// Creates a threshold set; the defaults are the ones derived from the owner's handwriting.
  const BarlineThresholds({
    this.minVerticality = 0.80,
    this.minAspect = 4.0,
    this.minHeightFraction = 0.75,
    this.minRowOverlapFraction = 0.50,
    this.minIsolationFraction = 0.15,
  });

  /// The least share of a stroke's length that must be downward travel, in `[0, 1]`.
  ///
  /// Measured on the owner's page: the `(` of `(b9)` scores 0.93, the `7` 0.85 and the slash of
  /// `6/9` 0.82, so this gate alone does NOT separate his letters and is deliberately kept low
  /// (0.80) for that reason — it is here to reject a CIRCLE or a hook, which cannot be a barline
  /// however tall, and to carry no weight it cannot bear. The separators are [minHeightFraction]
  /// and [minIsolationFraction].
  final double minVerticality;

  /// The least height-to-width ratio of the stroke's bounding box.
  ///
  /// The owner's `(` is 4.5 and his `7` is 5.7; the slash of `6/9` is 2.1. A division is drawn
  /// long and narrow and its own wobble is small beside its length, so the floor sits above a
  /// letter's: 4.0 rejects the slash and is deliberately NOT raised to 6 to reject the paren,
  /// because a hand-drawn line with a lean can genuinely reach that value and rejecting it would
  /// be the missed-barline error, which this feature chooses to prefer — but only where the
  /// preference is stated, not by accident.
  final double minAspect;

  /// The least height of the stroke as a fraction of the row it divides.
  ///
  /// THE MEASUREMENT THAT CHOSE 0.75. On the owner's page the tallest vertical mark he wrote — the
  /// `(` of `(b9)` — is 22.8 anchor-local pixels tall inside a 52-pixel chord row, which is 0.44 of
  /// the row. A mark that divides a row must be most of the row's height, and the owner draws
  /// through the chord line and past it rather than inside it. 0.75 therefore sits 1.7 times above
  /// every letter he has written and a quarter of the row below the row's own top and bottom.
  ///
  /// THE HONEST GAP: the sample above contains NO true barline, so this number is anchored to the
  /// CEILING of his letters and not to the floor of his divisions. It is the one threshold that a
  /// page of his real divisions can still move, and the arithmetic for moving it is: take the
  /// shortest division he would draw and set this below it while keeping it above 0.44.
  final double minHeightFraction;

  /// The least share of the anchor row's height that the stroke's vertical span must cover.
  ///
  /// This is the PLACE gate: a tall vertical stroke written well above or below the row is a mark
  /// about something else — a margin note, a note stem in the melody staff under the chords — and
  /// a division must cross the row it divides. Half the row is the floor because the owner's marks
  /// overshoot the row symmetrically and a division drawn to one side only would not be one.
  final double minRowOverlapFraction;

  /// The least empty gap, as a fraction of the row height, that must stand between the candidate
  /// and any other ink at its side.
  ///
  /// THE COMPANY GATE, AND THE ONE THAT ANSWERS "AND WHAT ABOUT `1`, `l`, `I` AND THE STEM OF A
  /// `t`". Those letters live inside a word: something is always beside them. On the owner's page
  /// the `(` of `(b9)` stands 1.1 px from the `b` it belongs to and the `7` 1.2 px from the `(`,
  /// while 7.8 px (0.15 of 52) is the floor here. A division written between two chord symbols is
  /// separated by the space a musician leaves to make the division visible, which is what makes
  /// this gate legitimate rather than a heuristic: if the mark were touching the symbol, the
  /// musician himself would not read it as a division.
  final double minIsolationFraction;

  /// The threshold set the detector uses unless a caller says otherwise.
  static const BarlineThresholds standard = BarlineThresholds();

  /// The least height, in anchor-local pixels, a stroke must have to divide a row [rowHeight] tall.
  double minimumHeightFor(double rowHeight) => rowHeight * minHeightFraction;

  /// The least empty gap, in anchor-local pixels, a candidate needs on each side in a row
  /// [rowHeight] tall.
  double minimumIsolationFor(double rowHeight) =>
      rowHeight * minIsolationFraction;

  @override
  String toString() =>
      'BarlineThresholds(verticality>=$minVerticality, aspect>=$minAspect, '
      'height>=$minHeightFraction x row, overlap>=$minRowOverlapFraction x row, '
      'isolation>=$minIsolationFraction x row)';
}

/// Why a stroke was not accepted as a division.
///
/// A REJECTION IS A VALUE, not a silence: the probe prints these so that a threshold which rejects
/// real ink can be seen doing it, and so that "the detector found nothing" can be told apart from
/// "the detector refused everything".
enum BarlineRejection {
  /// The stroke has too few samples to measure, or no points at all.
  tooFewPoints('too-few-points'),

  /// The stroke doubles back, curves, or runs sideways: it is not a line.
  notVerticalEnough('not-vertical-enough'),

  /// The stroke is wide for its height: a slash, a letter, a hook.
  notNarrowEnough('not-narrow-enough'),

  /// The stroke is shorter than the row it would divide allows.
  tooShort('too-short'),

  /// The stroke does not cross the row: it sits above, below, or beside it.
  missesTheRow('misses-the-row'),

  /// Another mark stands within the gap the division needs at one of its sides.
  crowded('crowded');

  const BarlineRejection(this.token);

  /// The stable token the probe and any future diagnostics print.
  final String token;
}

/// One stroke measured against the geometry a candidate division needs.
///
/// It exists so that the probe can print every number the decision was made from — including for
/// the strokes that were REJECTED — rather than only the verdict. A detector whose numbers cannot
/// be read is one that cannot be argued with.
class BarlineMeasurement {
  /// Creates the measurement of [strokeId] anchored at [anchor].
  const BarlineMeasurement({
    required this.strokeId,
    required this.anchor,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.pathLength,
    required this.netDy,
    required this.verticality,
    required this.aspect,
    required this.rowHeight,
    required this.rowOverlap,
    required this.isolation,
  });

  /// Identifier of the stroke measured.
  final String strokeId;

  /// The anchor the stroke was captured against.
  final EventAnchor anchor;

  /// Leftmost sample, in anchor-local pixels.
  final double minX;

  /// Rightmost sample, in anchor-local pixels.
  final double maxX;

  /// Topmost sample, in anchor-local pixels.
  final double minY;

  /// Bottommost sample, in anchor-local pixels.
  final double maxY;

  /// Length of the polyline through the samples.
  final double pathLength;

  /// Vertical displacement from the first sample to the last; positive means downward.
  final double netDy;

  /// Share of the path that is downward travel, in `[0, 1]`.
  final double verticality;

  /// Bounding-box height over width, with a width of zero reported as [unboundedAspect].
  final double aspect;

  /// Height of the row the stroke was captured against, in anchor-local pixels.
  final double rowHeight;

  /// Share of the row's height the stroke's vertical span covers, in `[0, 1]`.
  final double rowOverlap;

  /// The narrowest empty gap, in anchor-local pixels, between this stroke and another mark whose
  /// vertical span overlaps it, or [double.infinity] when nothing is near.
  final double isolation;

  /// Width of the bounding box in anchor-local pixels.
  double get width => maxX - minX;

  /// Height of the bounding box in anchor-local pixels.
  double get height => maxY - minY;

  /// The horizontal centre of the line the stroke implies.
  double get centreX => (minX + maxX) / 2;

  /// The aspect reported for a stroke with no horizontal extent, so printing stays finite.
  static const double unboundedAspect = 999;

  @override
  String toString() =>
      'BarlineMeasurement($strokeId, '
      'x=${minX.toStringAsFixed(1)}..${maxX.toStringAsFixed(1)}, '
      'y=${minY.toStringAsFixed(1)}..${maxY.toStringAsFixed(1)}, '
      'height=${height.toStringAsFixed(1)}, aspect=${aspect.toStringAsFixed(1)}, '
      'verticality=${verticality.toStringAsFixed(2)}, '
      'row=${rowHeight.toStringAsFixed(1)}, '
      'overlap=${rowOverlap.toStringAsFixed(2)}, '
      'isolation=${isolation.isFinite ? isolation.toStringAsFixed(1) : 'unbounded'})';
}

/// A stroke accepted as the division of a bar, with the ideal line it stands for.
class BarlineCandidate {
  /// Creates a candidate for [measurement] whose line is [lineHeight] pixels tall, centred on
  /// [centreX] and spanning [top] to [bottom] in anchor-local pixels.
  const BarlineCandidate({
    required this.measurement,
    required this.centreX,
    required this.top,
    required this.bottom,
  });

  /// The measurement the candidate was accepted from.
  final BarlineMeasurement measurement;

  /// The horizontal centre of the ideal line, in anchor-local pixels.
  final double centreX;

  /// The top of the ideal line, in anchor-local pixels.
  final double top;

  /// The bottom of the ideal line, in anchor-local pixels.
  final double bottom;

  /// Identifier of the stroke this candidate was recognised from.
  String get strokeId => measurement.strokeId;

  /// The anchor the ideal line is measured against.
  EventAnchor get anchor => measurement.anchor;

  /// Height of the ideal line in anchor-local pixels.
  double get height => bottom - top;

  @override
  String toString() =>
      'BarlineCandidate($strokeId at x=${centreX.toStringAsFixed(1)}, '
      'y=${top.toStringAsFixed(1)}..${bottom.toStringAsFixed(1)})';
}

/// What one stroke's detection decided: a candidate, or the gate that stopped it.
class BarlineVerdict {
  /// Creates a verdict carrying [measurement] and either [candidate] or [rejection].
  const BarlineVerdict({
    required this.measurement,
    this.candidate,
    this.rejection,
  });

  /// The numbers the verdict was reached from.
  final BarlineMeasurement measurement;

  /// The division this stroke implies, when it was accepted.
  final BarlineCandidate? candidate;

  /// The gate that rejected the stroke, when it was rejected.
  final BarlineRejection? rejection;

  /// Whether the stroke was accepted.
  bool get accepted => candidate != null;

  @override
  String toString() => accepted
      ? 'accepted: $candidate'
      : 'rejected(${rejection?.token}): $measurement';
}

/// Detects bar divisions in handwriting by measurement alone.
///
/// See the library header for what each gate is for and which number chose it. The detector holds
/// no state: every call is a function of the ink and the layout handed to it.
class BarlineDetector {
  /// Creates a detector using [thresholds], the standard set by default.
  const BarlineDetector({this.thresholds = BarlineThresholds.standard});

  /// The numeric gates this detector applies.
  final BarlineThresholds thresholds;

  /// Measures [stroke] inside the anchor rectangle [row] and decides whether it divides the row.
  ///
  /// [neighbours] are the other strokes on the same page, ALREADY RESOLVED to the same anchor-local
  /// space as [stroke] — see [detectBarlineDivisions] for the function that does the resolving
  /// across a whole page. Passing an empty list disables the company gate, so a caller that has no
  /// page can still see what the three shape gates alone would say, and the probe reports both.
  ///
  /// A stroke that is part of a chord symbol cannot pass: it is either short, or crowded, or both.
  BarlineVerdict measure({
    required InkStroke stroke,
    required LayoutRect row,
    List<InkStroke> neighbours = const <InkStroke>[],
  }) {
    final List<InkPoint> points = stroke.points;
    if (points.length < 2) {
      return BarlineVerdict(
        measurement: _emptyMeasurement(stroke, row),
        rejection: BarlineRejection.tooFewPoints,
      );
    }
    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    double path = 0;
    for (int index = 0; index < points.length; index++) {
      final InkPoint point = points[index];
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
      if (index > 0) {
        final InkPoint previous = points[index - 1];
        path += math.sqrt(
          math.pow(point.x - previous.x, 2) + math.pow(point.y - previous.y, 2),
        );
      }
    }
    final double height = maxY - minY;
    final double width = maxX - minX;
    final double netDy = points.last.y - points.first.y;
    final double rowHeight = row.size.height;
    final double verticality = path <= 0 ? 0 : netDy.abs() / path;
    final double aspect = width <= 0.0001
        ? BarlineMeasurement.unboundedAspect
        : height / width;
    final double rowTop = row.origin.y;
    final double rowBottom = row.origin.y + rowHeight;
    final double overlap = (math.min(maxY, rowBottom) - math.max(minY, rowTop))
        .clamp(0, height);
    final double overlapFraction = height <= 0
        ? 0
        : (overlap / rowHeight).clamp(0, 1);
    final double isolation = _isolationOf(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      rowHeight: rowHeight,
      neighbours: neighbours,
    );
    final BarlineMeasurement measurement = BarlineMeasurement(
      strokeId: stroke.id,
      anchor: stroke.anchor,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      pathLength: path,
      netDy: netDy,
      verticality: verticality,
      aspect: aspect,
      rowHeight: rowHeight,
      rowOverlap: overlapFraction,
      isolation: isolation,
    );
    final BarlineRejection? rejection = _firstFailedGate(measurement);
    if (rejection != null) {
      return BarlineVerdict(measurement: measurement, rejection: rejection);
    }
    return BarlineVerdict(
      measurement: measurement,
      candidate: BarlineCandidate(
        measurement: measurement,
        centreX: measurement.centreX,
        top: minY,
        bottom: maxY,
      ),
    );
  }

  /// The gate [measurement] fails first, in the order the gates are documented, or null.
  ///
  /// THE ORDER IS PART OF THE RESULT: a stroke is reported against the first rule it breaks, so a
  /// reader asking "why was my `7` refused" is answered with the reason a musician would recognise
  /// rather than an arbitrary one of three.
  BarlineRejection? _firstFailedGate(BarlineMeasurement measurement) {
    if (measurement.verticality < thresholds.minVerticality) {
      return BarlineRejection.notVerticalEnough;
    }
    if (measurement.aspect < thresholds.minAspect) {
      return BarlineRejection.notNarrowEnough;
    }
    if (measurement.height <
        thresholds.minimumHeightFor(measurement.rowHeight)) {
      return BarlineRejection.tooShort;
    }
    if (measurement.rowOverlap < thresholds.minRowOverlapFraction) {
      return BarlineRejection.missesTheRow;
    }
    if (measurement.isolation <
        thresholds.minimumIsolationFor(measurement.rowHeight)) {
      return BarlineRejection.crowded;
    }
    return null;
  }

  /// The narrowest horizontal gap between the box `[minX]..[maxX]` and another mark on the same
  /// side, considering only marks whose vertical span `[minY]..[maxY]` overlaps this one.
  ///
  /// Marks that do not overlap vertically are not in the candidate's way and are ignored, which is
  /// what lets the chord row's ink be compared with a division that starts above it: a chord below
  /// the row is not beside the line. The result is [double.infinity] when nothing is near.
  double _isolationOf({
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required double rowHeight,
    required List<InkStroke> neighbours,
  }) {
    double nearest = double.infinity;
    for (final InkStroke other in neighbours) {
      if (other.points.isEmpty) {
        continue;
      }
      double otherMinX = double.infinity;
      double otherMaxX = -double.infinity;
      double otherMinY = double.infinity;
      double otherMaxY = -double.infinity;
      for (final InkPoint point in other.points) {
        otherMinX = math.min(otherMinX, point.x);
        otherMaxX = math.max(otherMaxX, point.x);
        otherMinY = math.min(otherMinY, point.y);
        otherMaxY = math.max(otherMaxY, point.y);
      }
      if (otherMaxY < minY || otherMinY > maxY) {
        continue;
      }
      final double gap = otherMaxX < minX
          ? minX - otherMaxX
          : otherMinX > maxX
          ? otherMinX - maxX
          : 0;
      nearest = math.min(nearest, gap);
    }
    return nearest;
  }

  /// The measurement reported for a stroke too short to have one.
  BarlineMeasurement _emptyMeasurement(InkStroke stroke, LayoutRect row) =>
      BarlineMeasurement(
        strokeId: stroke.id,
        anchor: stroke.anchor,
        minX: 0,
        maxX: 0,
        minY: 0,
        maxY: 0,
        pathLength: 0,
        netDy: 0,
        verticality: 0,
        aspect: 0,
        rowHeight: row.size.height,
        rowOverlap: 0,
        isolation: double.infinity,
      );
}

/// A stroke together with the page position of its anchor, which is the pair the company gate needs
/// to compare ink that was captured against different anchors.
///
/// It mirrors `ResolvedInkStroke` in `chart_ui` on purpose instead of importing it: that type lives
/// in the Flutter package and this detector must stay runnable under `dart test`.
class PlacedInkStroke {
  /// Places [stroke] at [origin], the anchor's top-left corner in page coordinates.
  const PlacedInkStroke({required this.stroke, required this.origin});

  /// The anchored stroke.
  final InkStroke stroke;

  /// The anchor's top-left corner, in the page's engraved coordinates.
  final LayoutOffset origin;

  @override
  String toString() =>
      'PlacedInkStroke(${stroke.id} at '
      '${origin.x.toStringAsFixed(1)},${origin.y.toStringAsFixed(1)})';
}

/// A candidate division together with the row it was measured against, in page coordinates.
class PlacedBarlineCandidate {
  /// Creates a placed candidate for [candidate] whose row is [row] on the page.
  const PlacedBarlineCandidate({required this.candidate, required this.row});

  /// The candidate, in anchor-local pixels.
  final BarlineCandidate candidate;

  /// The anchor's rectangle in the page's engraved coordinates.
  final LayoutRect row;

  /// The ideal line's horizontal centre in page coordinates.
  double get pageX => row.origin.x + candidate.centreX;

  /// The ideal line's top in page coordinates.
  double get pageTop => row.origin.y + candidate.top;

  /// The ideal line's bottom in page coordinates.
  double get pageBottom => row.origin.y + candidate.bottom;

  @override
  String toString() =>
      'PlacedBarlineCandidate(${candidate.strokeId} x=${pageX.toStringAsFixed(1)}, '
      'y=${pageTop.toStringAsFixed(1)}..${pageBottom.toStringAsFixed(1)})';
}

/// Detects divisions across every stroke of one page, comparing ink that was captured against
/// different anchors by placing it in page coordinates first.
///
/// WHY THIS LIVES BESIDE THE PER-STROKE DETECTOR AND NOT INSIDE THE APP. The company gate is what
/// rejects a letter inside a word, and a letter and the division beside it are very often anchored
/// to DIFFERENT cells — the owner's `(` belongs to the cell of the chord it is part of, and a
/// division drawn between two beats belongs to no cell's column. Comparing only strokes that share
/// an anchor would therefore compare the wrong pairs, and the gate would pass marks it should
/// reject. Placing both in page coordinates is the only comparison that means what the rule says.
///
/// INPUTS: Every stroke of the page, each with its anchor's page origin, and the anchor rectangle
/// the division must divide — the BAR, because a division divides a bar and not one cell of it.
/// OUTPUTS: One [PlacedBarlineCandidate] per accepted stroke, in the order the strokes were given.
List<PlacedBarlineCandidate> detectBarlineDivisions({
  required List<PlacedInkStroke> strokes,
  required Map<String, LayoutRect> barRows,
  BarlineDetector detector = const BarlineDetector(),
}) {
  final List<PlacedBarlineCandidate> accepted = <PlacedBarlineCandidate>[];
  for (final PlacedInkStroke placed in strokes) {
    final BarlineVerdict verdict = measureBarlineStroke(
      stroke: placed,
      strokes: strokes,
      barRows: barRows,
      detector: detector,
    );
    final BarlineCandidate? candidate = verdict.candidate;
    if (candidate != null) {
      accepted.add(
        PlacedBarlineCandidate(
          candidate: candidate,
          row: _rowFor(placed.stroke, placed.origin, barRows)!,
        ),
      );
    }
  }
  return accepted;
}

/// Every verdict on a page, accepted or rejected, so a probe can print the reasons.
List<BarlineVerdict> measureBarlineDivisions({
  required List<PlacedInkStroke> strokes,
  required Map<String, LayoutRect> barRows,
  BarlineDetector detector = const BarlineDetector(),
}) => <BarlineVerdict>[
  for (final PlacedInkStroke placed in strokes)
    measureBarlineStroke(
      stroke: placed,
      strokes: strokes,
      barRows: barRows,
      detector: detector,
    ),
];

/// Weighs ONE stroke against the whole page and returns what the detector decided.
///
/// WHY A SINGLE-STROKE ENTRY POINT EXISTS AND IS THE ONE THE APPLICATION CALLS. Recognition runs
/// when a stroke is committed, and the only stroke whose verdict can have changed is the one just
/// written: every other stroke was measured when it was committed, and a decision that moved would
/// move a division the musician may already have rejected. Re-weighing the whole page on every
/// commit would both cost the pen time proportional to the chart and resurrect divisions the
/// musician deleted — so the application asks about the new stroke and about nothing else, while the
/// page's other ink is still what the company gate compares it with.
///
/// A stroke the page cannot place — one whose anchor names a bar this page does not hold — gets a
/// verdict with [BarlineRejection.missesTheRow] and a zero-height row, rather than throwing: this
/// function is called from the write path, and a detector that could fail there could lose ink.
BarlineVerdict measureBarlineStroke({
  required PlacedInkStroke stroke,
  required List<PlacedInkStroke> strokes,
  required Map<String, LayoutRect> barRows,
  BarlineDetector detector = const BarlineDetector(),
}) {
  final LayoutRect? row = _rowFor(stroke.stroke, stroke.origin, barRows);
  if (row == null) {
    return detector.measure(
      stroke: stroke.stroke,
      row: const LayoutRect(origin: LayoutOffset(0, 0), size: LayoutSize(0, 0)),
    );
  }
  final List<InkStroke> neighbours = <InkStroke>[
    for (final PlacedInkStroke other in strokes)
      if (!identical(other, stroke))
        if (_isNear(stroke, other)) _shifted(other, to: stroke.origin),
  ];
  return detector.measure(
    stroke: stroke.stroke,
    row: row,
    neighbours: neighbours,
  );
}

/// The row a stroke must divide, expressed in THAT STROKE'S OWN anchor-local space.
///
/// The BAR and never the cell, because a division divides a bar. A stroke captured inside one cell
/// of a four-beat bar is stored against that cell, and reading its row from the cell's own height
/// would be the same number but reading its ORIGIN from the cell would shift the row by the cell's
/// column — which is the difference between "this line crosses the row" and "this line is beside
/// it". A cell rect does span the bar's full stave height, so only the origin has to be converted.
LayoutRect? _rowFor(
  InkStroke stroke,
  LayoutOffset origin,
  Map<String, LayoutRect> barRows,
) {
  final LayoutRect? row = barRows[_rowKey(stroke.anchor)];
  if (row == null) {
    return null;
  }
  return LayoutRect(
    origin: LayoutOffset(row.origin.x - origin.x, row.origin.y - origin.y),
    size: row.size,
  );
}

/// The key a bar's row is indexed by, matching the key [barRowsOfPage] builds.
String _rowKey(EventAnchor anchor) => '${anchor.sectionId}\u0000${anchor.bar}';

/// The row every bar of [page] occupies, indexed by the section-and-bar key the detector uses.
///
/// THE KEY IS A STRING AND NOT THE ANCHOR ITSELF because a bar has no beat and an anchor that named
/// one would be a different address; encoding the two fields that identify a bar is the smallest
/// thing that cannot be confused with a cell.
Map<String, LayoutRect> barRowsOfPage(PageLayout page) => <String, LayoutRect>{
  for (final PlacedBar bar in page.bars)
    '${bar.sectionId}\u0000${bar.barIndex}': bar.bounds,
};

/// Every stroke of [strokes] that [page] can place, with the page position of its anchor.
///
/// A stroke whose anchor this page does not resolve is left out, exactly as the renderer leaves it
/// out: a stroke the page cannot place cannot be weighed against the ink beside it on that page.
/// The order is the document's order, so a caller that reports per stroke reports in a stable one.
List<PlacedInkStroke> placeInkStrokes(
  PageLayout page,
  List<InkStroke> strokes,
) {
  final InkPageIndex index = InkPageIndex.ofPage(page);
  final List<PlacedInkStroke> placed = <PlacedInkStroke>[];
  for (final InkStroke stroke in strokes) {
    final InkPlacement? placement = index.placementFor(stroke.anchor);
    if (placement == null) {
      continue;
    }
    placed.add(PlacedInkStroke(stroke: stroke, origin: placement.origin));
  }
  return placed;
}

/// Whether [other] is close enough on the page to be worth comparing with [placed].
///
/// A cheap bound rather than an exact one: two strokes on different pages or a system apart cannot
/// be in each other's way, and the company gate only ever asks about ink within a row's height
/// vertically and a bar's width horizontally. The bounds are deliberately GENEROUS — a mark drawn
/// in a margin beside a row is exactly the case the gate exists for, and a bound that was too tight
/// would silently drop the neighbour that should have blocked the candidate.
bool _isNear(PlacedInkStroke placed, PlacedInkStroke other) {
  if (placed.stroke.anchor.sectionId != other.stroke.anchor.sectionId) {
    return false;
  }
  final double dy = (other.origin.y - placed.origin.y).abs();
  if (dy > _nearRowHeight) {
    return false;
  }
  final double dx = (other.origin.x - placed.origin.x).abs();
  return dx <= _nearBarWidth;
}

/// The vertical reach of the cheap proximity bound, in page pixels — larger than any system this
/// application engraves.
const double _nearRowHeight = 120;

/// The horizontal reach of the cheap proximity bound, in page pixels — a few bars wide.
const double _nearBarWidth = 600;

/// [stroke]'s points re-expressed in the anchor-local space of [to], the anchor whose origin they
/// must be compared against.
///
/// The points are not copied into a new stroke where the shift is zero, which is the common case:
/// every stroke of one bar shares an anchor.
InkStroke _shifted(PlacedInkStroke from, {required LayoutOffset to}) {
  final LayoutOffset origin = from.origin;
  final double dx = origin.x - to.x;
  final double dy = origin.y - to.y;
  if (dx == 0 && dy == 0) {
    return from.stroke;
  }
  return InkStroke(
    id: from.stroke.id,
    tool: from.stroke.tool,
    color: from.stroke.color,
    size: from.stroke.size,
    anchor: from.stroke.anchor,
    points: <InkPoint>[
      for (final InkPoint point in from.stroke.points)
        InkPoint(x: point.x + dx, y: point.y + dy, w: point.w, t: point.t),
    ],
  );
}
