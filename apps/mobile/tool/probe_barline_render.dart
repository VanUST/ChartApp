// PURPOSE: See the ink the owner actually wrote, at a size a human can read, before any threshold
//          about "vertical" is fixed. A barline is a shape, and a list of bounding boxes cannot say
//          whether the tall thin mark in the corner of a bar is a division the musician drew or the
//          stem of a letter inside a chord symbol. This instrument draws the real `.chart` with the
//          application's own painters and writes one picture of the whole page and one magnified
//          tile per bar.
// INPUTS: The chart path (first argument, defaulting to the owner's sample), the page width the
//         layout is engraved at (second argument, default 1200), and `BARLINE_PROBE_OUT` for the
//         output directory. A real system font is loaded so the bar frames and labels are legible.
// OUTPUTS: PNG files outside the repository plus `probe.*` lines on stdout naming each file's path,
//          byte length and SHA-256, and the resolved rectangle of every bar. Exit code 2 when the
//          chart cannot be read or laid out.
// KEYWORDS: probe, barline, ink, handwriting, png, evidence, magnified-tile, not-part-of-the-library
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the pictures are written. Outside the repository, because a rendered PNG is evidence for
/// one inspection and not an artefact to commit.
const String defaultOutDirectory =
    r'C:\projects\ChartApp-acl-reports\render\barline';

/// The sample the owner wrote with his pen on the tablet.
const String defaultChartPath =
    r'C:\projects\ChartApp-acl-reports\omr-sample\untitled.chart';

/// Font files tried in order, so a readable PNG can be produced on each platform.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
];

/// The page the probe engraves on, matching the application's own page margins.
const double probePageHeight = 1318;

/// The magnification one bar's image is drawn at, chosen so a 20-pixel mark is 160 pixels on screen
/// and its shape can be judged rather than guessed.
const double _barTileScale = 8;

/// Page pixels of margin drawn around a bar's rectangle in its own image.
const double _barTileMargin = 6;

// PURPOSE: The layout constants the application itself uses, so the probe measures the geometry the
//          musician's ink was written against rather than a different page.
// INPUTS: The text metrics the bars are measured with.
// OUTPUTS: A [LayoutStyle] that is the same value `viewer_screen.dart` builds.
// KEYWORDS: layout-style, application-geometry, measurement-fidelity
LayoutStyle appStyle(TextMetrics metrics) => LayoutStyle(
  textMetrics: metrics,
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes shows no label and no chord symbol.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists.
// KEYWORDS: font, font-loader, readable-text
Future<String?> loadFont() async {
  for (final String path in _fontCandidates) {
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final File font = file;
    final String family = 'ChartBarlineProbeFont';
    final FontLoader loader = FontLoader(family)
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(font.readAsBytesSync())),
      );
    await loader.load();
    return family;
  }
  return null;
}

// PURPOSE: Write one recorded canvas to a PNG and report it, so a claim about a picture points at a
//          file whose bytes are named.
// INPUTS: The recorder, the image size in device pixels, the target file and the pixel ratio.
// OUTPUTS: Prints the path, byte length and SHA-256 of the file. Returns nothing.
// KEYWORDS: png, encode, evidence, sha256
Future<void> writePicture(
  ui.PictureRecorder recorder,
  ui.Size size,
  File out,
  double pixelRatio,
) async {
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (size.width * pixelRatio).round(),
    (size.height * pixelRatio).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  out.parent.createSync(recursive: true);
  final List<int> bytes = png.buffer.asUint8List();
  out.writeAsBytesSync(bytes);
  stdout.writeln('probe.png path=${out.path} bytes=${bytes.length}');
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String chartPath = File(defaultChartPath).existsSync()
      ? defaultChartPath
      : (Platform.environment['BARLINE_PROBE_CHART'] ?? defaultChartPath);
  final File chart = File(chartPath);
  if (!chart.existsSync()) {
    stderr.writeln('no such chart file: $chartPath');
    exit(2);
  }
  final double pageWidth =
      double.tryParse(Platform.environment['BARLINE_PROBE_WIDTH'] ?? '') ??
      1200;
  final Directory out = Directory(
    Platform.environment['BARLINE_PROBE_OUT'] ?? defaultOutDirectory,
  );
  final String? family = await loadFont();
  final FlutterTextMetrics metrics = FlutterTextMetrics(
    chordStyle: TextStyle(
      fontFamily: family,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
    smallChordStyle: TextStyle(
      fontFamily: family,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
    sectionLabelStyle: TextStyle(
      fontFamily: family,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
    staffTextStyle: TextStyle(fontFamily: family, fontSize: 10),
    textCueStyle: TextStyle(
      fontFamily: family,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );

  final ChartFileDecodeResult decoded = ChartFileCodec.decode(
    chart.readAsBytesSync(),
  );
  final DocumentState document = decoded.file.reducedDocument;
  final Song song = document.song;
  final LayoutEngine engine = LayoutEngine(style: appStyle(metrics));
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: pageWidth,
    pageHeight: probePageHeight,
  );
  if (pages.isEmpty) {
    stderr.writeln('the chart laid out to no pages');
    exit(2);
  }
  stdout.writeln(
    'probe.input chart=$chartPath pageWidth=$pageWidth strokes=${document.strokes.length} '
    'font=${family ?? 'none'} out=${out.path}',
  );
  final PageLayout page = pages.first;
  final InkPageIndex index = InkPageIndex.ofPage(page);
  final List<ResolvedInkStroke> resolved = <ResolvedInkStroke>[];
  for (final InkStroke stroke in document.strokes) {
    final InkPlacement? placement = index.placementFor(stroke.anchor);
    if (placement == null) {
      stdout.writeln('probe.unplaced id=${stroke.id}');
      continue;
    }
    resolved.add(ResolvedInkStroke(stroke: stroke, origin: placement.origin));
  }

  // THE WHOLE PAGE, drawn at 1:1 in the page's own engraved coordinates.
  const double pageScale = 1;
  {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    const double ratio = 2;
    canvas.scale(ratio);
    final ui.Size size = ui.Size(pageWidth, probePageHeight);
    ChartPainter(song: song, page: page, metrics: metrics).paint(canvas, size);
    InkPainter(strokes: resolved, pageScale: pageScale).paint(canvas, size);
    await writePicture(
      recorder,
      size,
      File('${out.path}${Platform.pathSeparator}overview.png'),
      ratio,
    );
  }

  // THE PAGE THE APPLICATION ITSELF WOULD DRAW, and the file whose SHA-256 is the before/after
  // baseline for "a chart with no recognised division is drawn exactly as it was". It is written
  // ONLY when the input chart carries no division — which is every chart until recognition runs —
  // because a chart that does carry one is a different picture by design.
  //
  // THE THREE PAINTERS ARE THE APPLICATION'S OWN and are composed in the application's own order:
  // the engraving, then the musician's words, then the ink. Nothing here re-implements a glyph, so
  // a change to any of them shows up as a changed hash rather than being argued away.
  if (document.divisions.isEmpty) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    const double ratio = 2;
    canvas.scale(ratio);
    final ui.Size size = ui.Size(pageWidth, probePageHeight);
    ChartPainter(song: song, page: page, metrics: metrics).paint(canvas, size);
    InkPainter(strokes: resolved, pageScale: pageScale).paint(canvas, size);
    await writePicture(
      recorder,
      size,
      File('${out.path}${Platform.pathSeparator}no-divisions.png'),
      ratio,
    );
  } else {
    stdout.writeln(
      'probe.baseline skipped divisions=${document.divisions.length} '
      '(the page IS the recognised chart, so there is no undivided page to compare)',
    );
  }

  // ONE MAGNIFIED IMAGE PER BAR, so the shape of every mark can be judged rather than inferred.
  // The window is the bar's own rectangle plus a margin, and the magnification is [_barTileScale]
  // so that a mark 20 page-pixels tall is 160 pixels on screen.
  final Paint frame = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0xFF2E5D8A);
  final TextPainter label = TextPainter(textDirection: TextDirection.ltr);
  for (final PlacedBar bar in page.bars) {
    final List<ResolvedInkStroke> mine = <ResolvedInkStroke>[
      for (final ResolvedInkStroke stroke in resolved)
        if (stroke.stroke.anchor.sectionId == bar.sectionId &&
            stroke.stroke.anchor.bar == bar.barIndex)
          stroke,
    ];
    final ui.Size windowSize = ui.Size(
      (bar.bounds.size.width + 2 * _barTileMargin) * _barTileScale,
      (bar.bounds.size.height + 2 * _barTileMargin) * _barTileScale + 26,
    );
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, windowSize.width, windowSize.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.save();
    canvas.translate(0, 26);
    canvas.scale(_barTileScale);
    canvas.translate(
      -bar.bounds.origin.x + _barTileMargin,
      -bar.bounds.origin.y + _barTileMargin,
    );
    // DRAWN FROM THE STORED POINTS DIRECTLY, not through [InkPainter], because this instrument's
    // question is what the hand wrote and not how the application renders it. The colours are the
    // stored ones, so a fingertip stroke stays distinguishable from the pen.
    final Paint segment = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final ResolvedInkStroke stroke in mine) {
      segment
        // THE STORED COLOUR IS `#rrggbb`, so the alpha byte is supplied here rather than read out
        // of the first two hex digits, which are red and would make every stroke near-invisible.
        ..color = Color(
          0xFF000000 |
              int.parse(stroke.stroke.color.replaceFirst('#', ''), radix: 16),
        )
        ..strokeWidth = inkStrokeNibWidth(stroke.stroke);
      final List<InkPoint> points = stroke.stroke.points;
      if (points.length == 1) {
        canvas.drawCircle(
          Offset(
            stroke.origin.x + points.first.x,
            stroke.origin.y + points.first.y,
          ),
          segment.strokeWidth / 2,
          Paint()..color = segment.color,
        );
        continue;
      }
      for (int index = 1; index < points.length; index++) {
        canvas.drawLine(
          Offset(
            stroke.origin.x + points[index - 1].x,
            stroke.origin.y + points[index - 1].y,
          ),
          Offset(
            stroke.origin.x + points[index].x,
            stroke.origin.y + points[index].y,
          ),
          segment,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(
        bar.bounds.origin.x,
        bar.bounds.origin.y,
        bar.bounds.size.width,
        bar.bounds.size.height,
      ),
      frame,
    );
    // The four cell columns the layout gives this bar, so a mark can be placed against the beats.
    final Paint cellFrame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4
      ..color = const Color(0xFFD9E2EC);
    for (final LayoutRect cell in <LayoutRect>[bar.bounds]) {
      canvas.drawRect(
        Rect.fromLTWH(
          cell.origin.x,
          cell.origin.y,
          cell.size.width,
          cell.size.height,
        ),
        cellFrame,
      );
    }
    canvas.restore();
    label
      ..text = TextSpan(
        text:
            'bar ${bar.barIndex}  origin=(${bar.bounds.origin.x.toStringAsFixed(0)},'
            '${bar.bounds.origin.y.toStringAsFixed(0)})  '
            'w=${bar.bounds.size.width.toStringAsFixed(0)} '
            'h=${bar.bounds.size.height.toStringAsFixed(0)}  '
            'strokes=${mine.length}  '
            'colour: pen=#102a43 finger=#2f80ed',
        style: TextStyle(
          fontFamily: family,
          fontSize: 13,
          color: const Color(0xFF102A43),
        ),
      )
      ..layout()
      ..paint(canvas, const Offset(6, 6));
    await writePicture(
      recorder,
      windowSize,
      File(
        '${out.path}${Platform.pathSeparator}bar-'
        '${bar.barIndex.toString().padLeft(2, '0')}.png',
      ),
      1,
    );
    stdout.writeln(
      'probe.tile bar=${bar.barIndex} x=${bar.bounds.origin.x.toStringAsFixed(1)} '
      'w=${bar.bounds.size.width.toStringAsFixed(1)} '
      'h=${bar.bounds.size.height.toStringAsFixed(1)} strokes=${mine.length}',
    );
    for (final ResolvedInkStroke stroke in mine) {
      double minX = double.infinity;
      double maxX = -double.infinity;
      double minY = double.infinity;
      double maxY = -double.infinity;
      for (final InkPoint point in stroke.stroke.points) {
        final double x = stroke.origin.x + point.x;
        final double y = stroke.origin.y + point.y;
        if (x < minX) {
          minX = x;
        }
        if (x > maxX) {
          maxX = x;
        }
        if (y < minY) {
          minY = y;
        }
        if (y > maxY) {
          maxY = y;
        }
      }
      stdout.writeln(
        'probe.ink bar=${bar.barIndex} id=${stroke.stroke.id} '
        'origin=(${stroke.origin.x.toStringAsFixed(1)},'
        '${stroke.origin.y.toStringAsFixed(1)}) '
        'barLocal=(${(minX - bar.bounds.origin.x).toStringAsFixed(1)}..'
        '${(maxX - bar.bounds.origin.x).toStringAsFixed(1)},'
        '${(minY - bar.bounds.origin.y).toStringAsFixed(1)}..'
        '${(maxY - bar.bounds.origin.y).toStringAsFixed(1)})',
      );
    }
  }
  await probeClamp(
    song: song,
    page: page,
    metrics: metrics,
    out: out,
    pageWidth: pageWidth,
    family: family,
  );
}

// -------------------------------------------------------------------------------------------------
// THE CLAMP, AS A PICTURE AND AS NUMBERS FROM ONE RUN
//
// The owner's answer to "the recognised line is taller than the chart's own separators" was
// «Да обрезать». This section draws the two states of the same division with the application's OWN
// painter, in one crop, so the reader can see that the line after the clamp is the same height as the
// separator beside it — and prints the three heights involved, because a picture whose numbers are
// taken somewhere else is a picture that can lie quietly.
//
// The crop covers the chord row AND the melody staff below it, so both of the chart's own separators
// are in frame: the chord stave's barline and the staff's. The division is a stroke drawn across the
// staff, which is the mark the owner reported as unrecognised, placed by the application's own anchor
// rule and weighed by the real detector.
// -------------------------------------------------------------------------------------------------

/// The magnification the clamp crops are drawn at: a 52-pixel separator becomes 312 pixels, so its
/// equality with the line beside it can be judged by eye and not only by reading a number.
const double _clampScale = 6;

/// Page pixels of margin around the bar in a clamp crop.
const double _clampMargin = 8;

/// Draws the before/after clamp pictures for [page] and prints the heights they were drawn from.
Future<void> probeClamp({
  required Song song,
  required PageLayout page,
  required FlutterTextMetrics metrics,
  required Directory out,
  required double pageWidth,
  required String? family,
}) async {
  if (page.bars.isEmpty) {
    stdout.writeln('probe.clamp skipped=no-bar');
    return;
  }
  // THE LAST BAR OF THE PAGE, whose chord row his hand did not write on: the crop then shows the
  // chart's own separators, the staff, and the division, without a chord symbol standing inside the
  // gap the company gate needs. Measuring the mark against his own handwriting would answer a
  // different question — and did, `gate=crowded`, the first time this section was run on bar 0.
  final PlacedBar bar = page.bars.last;
  if (bar.melody.isEmpty) {
    stdout.writeln('probe.clamp skipped=the-page-declares-no-staff');
    return;
  }
  final LayoutRect staff = bar.melody.bounds;
  final LayoutRect row = bar.bounds;
  final double x = bar.bounds.origin.x + bar.bounds.size.width * 0.55;
  // THE STROKE A HAND WOULD DRAW across the staff, overshooting it as his marks overshoot the row.
  final List<LayoutOffset> pagePoints = <LayoutOffset>[
    for (int index = 0; index < 14; index++)
      LayoutOffset(
        x + (index.isEven ? 0.4 : -0.4),
        staff.origin.y - 2 + (staff.size.height + 4) * index / 13,
      ),
  ];
  final InkAnchorChoice? choice = resolveInkAnchor(page, pagePoints.first);
  if (choice == null) {
    stdout.writeln('probe.clamp skipped=no-anchor');
    return;
  }
  final InkStroke stroke = InkStroke(
    id: 'clamp-staff-division',
    tool: StrokeTool.pen,
    color: '#102a43',
    size: 3,
    anchor: choice.anchor,
    points: <InkPoint>[
      for (final LayoutOffset point in pagePoints)
        InkPoint(
          x: point.x - choice.origin.x,
          y: point.y - choice.origin.y,
          w: 0.5,
          t: 0,
        ),
    ],
  );
  // THE STROKE IS PLACED ONCE AND THE SAME INSTANCE IS HANDED TO THE DETECTOR BOTH WAYS, because
  // `measureBarlineStroke` skips a neighbour by IDENTITY: two equal-but-distinct values of one stroke
  // make the stroke its own neighbour, and the company gate then measures a gap of zero and refuses
  // it. That is what this section did on its first run (`gate=crowded` on a page with no ink near it),
  // and it is worth keeping in the code as a warning rather than quietly fixing.
  final PlacedInkStroke placedStroke = PlacedInkStroke(
    stroke: stroke,
    origin: choice.origin,
  );
  final BarlineVerdict verdict = measureBarlineStroke(
    stroke: placedStroke,
    strokes: <PlacedInkStroke>[placedStroke],
    barFrames: barlineFramesOfPage(page),
  );
  final BarlineCandidate? candidate = verdict.candidate;
  if (candidate == null) {
    stdout.writeln(
      'probe.clamp skipped=the-stroke-was-not-accepted '
      'gate=${verdict.rejection?.token}',
    );
    return;
  }
  final double barLeft = bar.bounds.origin.x;
  final double barTop = bar.bounds.origin.y;
  final double cropTop = barTop - _clampMargin;
  final double cropBottom = staff.origin.y + staff.size.height + _clampMargin;
  final ui.Size window = ui.Size(
    (bar.bounds.size.width + 2 * _clampMargin) * _clampScale,
    (cropBottom - cropTop) * _clampScale + 26,
  );
  // THE TWO DIVISIONS. `before` is the one the application drew until this change: the stroke's own
  // extent. `after` is the one the structure holds now: the span the separator is drawn across.
  final BarDivision before = BarDivision(
    id: 'division-before',
    place: AnchoredPlace(
      anchor: candidate.anchor,
      offsetX: candidate.centreX,
      offsetY: verdict.measurement.minY,
    ),
    height: verdict.measurement.height,
    sourceStrokeId: stroke.id,
  );
  final BarDivision after = BarDivision(
    id: 'division-after',
    place: AnchoredPlace(
      anchor: candidate.anchor,
      offsetX: candidate.centreX,
      offsetY: candidate.top,
    ),
    height: candidate.height,
    sourceStrokeId: stroke.id,
  );
  final List<ResolvedInkStroke> ink = <ResolvedInkStroke>[
    ResolvedInkStroke(stroke: stroke, origin: choice.origin),
  ];
  for (final (String name, BarDivision division, bool withInk)
      in <(String, BarDivision, bool)>[
        ('before', before, false),
        ('after', after, false),
        ('ink', before, true),
      ]) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final Paint white = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Rect.fromLTWH(0, 0, window.width, window.height), white);
    canvas.save();
    canvas.translate(0, 26);
    canvas.scale(_clampScale);
    canvas.translate(-barLeft + _clampMargin, -cropTop);
    // THE SAME THREE PAINTERS, IN THE APPLICATION'S ORDER, and the ideal division between them the
    // way the application stacks it.
    ChartPainter(
      song: song,
      page: page,
      metrics: metrics,
    ).paint(canvas, ui.Size(pageWidth, probePageHeight));
    if (withInk) {
      InkPainter(
        strokes: ink,
        pageScale: 1,
      ).paint(canvas, ui.Size(pageWidth, probePageHeight));
    }
    BarlinePainter(
      divisions: <ResolvedDivision>[
        ResolvedDivision(division: division, origin: choice.origin),
      ],
      pageScale: 1,
    ).paint(canvas, ui.Size(pageWidth, probePageHeight));
    canvas.restore();
    TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text:
            'clamp-$name   chart separator: chord ${row.size.height.toStringAsFixed(0)} px, '
            'staff ${staff.size.height.toStringAsFixed(0)} px   '
            'ink: ${verdict.measurement.height.toStringAsFixed(1)} px   '
            'line drawn: ${division.height.toStringAsFixed(1)} px',
        style: TextStyle(
          fontFamily: family,
          fontSize: 13,
          color: const Color(0xFF102A43),
        ),
      )
      ..layout()
      ..paint(canvas, const Offset(6, 6));
    await writePicture(
      recorder,
      window,
      File('${out.path}${Platform.pathSeparator}clamp-$name.png'),
      1,
    );
  }
  stdout.writeln(
    'probe.clamp bar=${bar.barIndex} band=${verdict.measurement.band?.kind.token} '
    'chord_separator=${row.origin.y.toStringAsFixed(1)}..'
    '${(row.origin.y + row.size.height).toStringAsFixed(1)} '
    'staff_separator=${staff.origin.y.toStringAsFixed(1)}..'
    '${(staff.origin.y + staff.size.height).toStringAsFixed(1)} '
    'ink_y=${verdict.measurement.minY.toStringAsFixed(1)}..'
    '${verdict.measurement.maxY.toStringAsFixed(1)} '
    'ink_height=${verdict.measurement.height.toStringAsFixed(1)} '
    'line_height_before=${before.height.toStringAsFixed(1)} '
    'line_height_after=${after.height.toStringAsFixed(1)}',
  );
}
