// PURPOSE: Put NUMBERS on the barline detector against the ink the owner actually wrote, so that
//          "it works" is a measurement and not an adjective. It decodes a real `.chart` with the
//          repository's own codec, lays the page out with the application's own style, weighs every
//          stroke against the detector's gates, and prints one line per stroke plus the totals that
//          matter: how many marks were accepted, how many were refused, and — the number that
//          decides whether the feature is worth having — HOW MANY OF HIS CHORD-SYMBOL LETTERS IT
//          WOULD HAVE CALLED A BARLINE.
//
//          It prints the MEASUREMENT of every stroke, not only the verdict, because a threshold that
//          refuses real ink has to be visible doing it: `height=22.8 aspect=4.5 verticality=0.93`
//          beside `gate=too-short` is the argument, and a bare count of zero is not.
// INPUTS: The chart path (first argument, defaulting to the owner's sample), and optionally
//         `--page <index>` for a document of more than one page.
// OUTPUTS: `probe.*` lines on stdout and exit code 0. Exit code 2 when the file cannot be read or
//          laid out, so a missing input never prints a misleading zero.
// KEYWORDS: probe, barline, detector, false-positive, threshold, handwriting, evidence, d37,
//           not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// The sample the owner wrote, unless a path is given on the command line.
const String defaultChartPath =
    r'C:\projects\ChartApp-acl-reports\omr-sample\untitled.chart';

/// The page the probe engraves on, matching the application's own proportions.
const double probePageWidth = 824;

/// The page height the probe engraves on.
const double probePageHeight = 1318;

// PURPOSE: The layout constants the application uses, so the row heights the detector divides by
//          are the row heights the musician's ink was written against.
// INPUTS: None.
// OUTPUTS: The same [LayoutStyle] `viewer_screen.dart` builds.
// KEYWORDS: layout-style, application-geometry, measurement-fidelity
LayoutStyle appStyle() => const LayoutStyle(
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

/// One decimal place, so a printed column stays readable and a difference of a pixel still shows.
String f(double value) => value.isFinite ? value.toStringAsFixed(1) : 'inf';

void main(List<String> arguments) {
  final String path = arguments.isEmpty || arguments.first.startsWith('--')
      ? defaultChartPath
      : arguments.first;
  final File file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('no such chart file: $path');
    exit(2);
  }
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(
    file.readAsBytesSync(),
  );
  final DocumentState document = decoded.file.reducedDocument;
  final List<PageLayout> pages = LayoutEngine(style: appStyle()).layout(
    document.song,
    pageWidth: probePageWidth,
    pageHeight: probePageHeight,
  );
  if (pages.isEmpty) {
    stderr.writeln('the chart laid out to no pages');
    exit(2);
  }
  final PageLayout page = pages.first;
  final List<PlacedInkStroke> placed = placeInkStrokes(page, document.strokes);
  final Map<String, LayoutRect> rows = barRowsOfPage(page);
  const BarlineDetector detector = BarlineDetector();
  stdout.writeln(
    'probe.input chart=$path strokes=${document.strokes.length} '
    'placed=${placed.length} divisions_in_file=${document.divisions.length} '
    'bars=${page.bars.length} ${detector.thresholds}',
  );
  for (final MapEntry<String, LayoutRect> row in rows.entries) {
    stdout.writeln(
      'probe.row key=${row.key.replaceAll('\u0000', '#')} '
      'x=${f(row.value.origin.x)} y=${f(row.value.origin.y)} '
      'w=${f(row.value.size.width)} h=${f(row.value.size.height)} '
      'minimum_height=${f(detector.thresholds.minimumHeightFor(row.value.size.height))} '
      'minimum_gap=${f(detector.thresholds.minimumIsolationFor(row.value.size.height))}',
    );
  }
  final List<BarlineVerdict> verdicts = measureBarlineDivisions(
    strokes: placed,
    barRows: rows,
    detector: detector,
  );
  int accepted = 0;
  final Map<String, int> byGate = <String, int>{};
  double tallestVerticalMark = 0;
  for (final BarlineVerdict verdict in verdicts) {
    final BarlineMeasurement m = verdict.measurement;
    if (m.verticality >= detector.thresholds.minVerticality &&
        m.aspect >= detector.thresholds.minAspect) {
      tallestVerticalMark = m.height > tallestVerticalMark
          ? m.height
          : tallestVerticalMark;
    }
    final String verdictToken = verdict.accepted
        ? 'ACCEPT'
        : verdict.rejection!.token;
    if (verdict.accepted) {
      accepted++;
    } else {
      byGate[verdict.rejection!.token] =
          (byGate[verdict.rejection!.token] ?? 0) + 1;
    }
    stdout.writeln(
      'probe.stroke id=${m.strokeId} '
      'bar=${m.anchor.sectionId}#${m.anchor.bar} '
      'x=${f(m.minX)}..${f(m.maxX)} y=${f(m.minY)}..${f(m.maxY)} '
      'height=${f(m.height)} width=${f(m.width)} '
      'aspect=${f(m.aspect)} verticality=${m.verticality.toStringAsFixed(2)} '
      'row=${f(m.rowHeight)} overlap=${m.rowOverlap.toStringAsFixed(2)} '
      'isolation=${f(m.isolation)} gate=$verdictToken',
    );
  }
  // THE SHAPE GATES ON THEIR OWN, with the company gate switched off by passing no neighbours. The
  // difference between this count and the count above is exactly what the isolation rule contributes
  // on this page, and it is printed because a rule whose effect cannot be measured is a rule nobody
  // can defend.
  int shapeOnly = 0;
  for (final PlacedInkStroke one in placed) {
    final LayoutRect? row = _rowFor(one, rows);
    if (row == null) {
      continue;
    }
    final BarlineVerdict verdict = detector.measure(
      stroke: one.stroke,
      row: row,
    );
    if (verdict.accepted) {
      shapeOnly++;
    }
  }
  final double shortestAllowed = rows.isEmpty
      ? 0
      : detector.thresholds.minimumHeightFor(rows.values.first.size.height);
  stdout.writeln(
    'probe.totals strokes=${verdicts.length} accepted=$accepted '
    'refused=${verdicts.length - accepted} '
    'accepted_by_shape_alone=$shapeOnly '
    'tallest_vertical_mark=${f(tallestVerticalMark)} '
    'shortest_allowed_line=${f(shortestAllowed)} '
    'margin=${f(shortestAllowed - tallestVerticalMark)} '
    'gates=${byGate.entries.map((MapEntry<String, int> e) => '${e.key}:${e.value}').join(',')}',
  );
  for (final PlacedBarlineCandidate candidate in detectBarlineDivisions(
    strokes: placed,
    barRows: rows,
    detector: detector,
  )) {
    stdout.writeln(
      'probe.division from=${candidate.candidate.strokeId} '
      'x=${f(candidate.candidate.centreX)} '
      'top=${f(candidate.candidate.top)} '
      'height=${f(candidate.candidate.height)} '
      'page_x=${f(candidate.pageX)}',
    );
  }
}

/// The row the stroke must divide, in that stroke's own anchor-local space.
///
/// Duplicated from the detector's own private helper ONLY to drive the shape-only pass above; the
/// pass that decides what the application does goes through the library and never through this.
LayoutRect? _rowFor(PlacedInkStroke stroke, Map<String, LayoutRect> rows) {
  final LayoutRect? row =
      rows['${stroke.stroke.anchor.sectionId}\u0000${stroke.stroke.anchor.bar}'];
  if (row == null) {
    return null;
  }
  return LayoutRect(
    origin: LayoutOffset(
      row.origin.x - stroke.origin.x,
      row.origin.y - stroke.origin.y,
    ),
    size: row.size,
  );
}
