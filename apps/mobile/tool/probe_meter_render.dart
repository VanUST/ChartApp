// PURPOSE: Produce the numbers and the pictures that answer owner decision D22's rendering half:
//          what a meter sign costs, whether a chart that never changes meter still draws exactly
//          what it drew before a sign existed, and how many chord cells a 3/4 bar and a 15/8 bar
//          really offer. It is the instrument behind four claims that would otherwise be
//          impressions: the meter sign is VISIBLE where a musician needs it, an unchanged chart is
//          BYTE-IDENTICAL, the cell count follows the meter, and the hit test still addresses those
//          cells by `{bar, cell}`.
//
//          It is an instrument, not part of the suite: it lives in `tool/`, so `flutter test`'s
//          default run and the `melos run verify` gate do not pick it up. Run it from
//          `apps/mobile` with:
//
//              flutter test tool/probe_meter_render.dart
//
//          and set METER_PROBE_OUT to send the PNGs somewhere named for the run — which is how the
//          pre-change reference is captured for the byte-identity comparison.
// INPUTS: METER_PROBE_OUT names the directory the PNGs are written to, defaulting to a path outside
//         the repository. Nothing else; the charts are synthetic, so the probe runs on any machine.
//         A real system font is loaded when one is found, because the framework's default test font
//         draws every glyph as a filled box and a page of boxes shows no sign.
// OUTPUTS: `probe.*` lines on stdout — the signs the rule puts on each page, the cell count and the
//          per-cell hit test of a 3/4 bar and a 15/8 bar, and what the typed-figures reader does
//          with 0/0, a negative numerator and the valid 15/8 — plus one PNG per case. A page that
//          could not be built at all is reported as a `probe.skip` line rather than an exception.
// KEYWORDS: probe, meter, time-signature, meter-sign, pixel-identity, cell-count, hit-test,
//           headless, png, evidence, d22
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the probe's PNGs are written. Outside the repository: a rendered image is evidence for one
/// inspection, not an artefact to commit. Overridden by `METER_PROBE_OUT`.
const String meterProbeDirectory =
    r'C:\projects\ChartApp-acl-reports\render\meter-sign';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartMeterProbeFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The surface every case is engraved on, matching the other render instruments' page.
const double _pageWidth = 824;

/// The page height, matching the other render instruments' surface.
const double _pageHeight = 1318;

/// The layout constants the application uses, so the probe measures the geometry it produces.
LayoutStyle _styleFor(FlutterTextMetrics metrics) => LayoutStyle(
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

/// The metrics the probe lays the pages out and draws the signs with.
FlutterTextMetrics _metricsFor(String family) => FlutterTextMetrics(
  chordStyle: TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
  smallChordStyle: TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
  sectionLabelStyle: TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: const Color(0xFF2E5D8A),
  ),
  staffTextStyle: TextStyle(
    fontFamily: family,
    fontSize: 10,
    color: const Color(0xFF486581),
  ),
  textCueStyle: TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
// glyph as a filled box and a page of boxes cannot show which meter is written.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists.
// KEYWORDS: font, font-loader, readable-text
Future<String?> _loadFont() async {
  for (final String path in _fontCandidates) {
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final FontLoader loader = FontLoader(_fontFamily)
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    await loader.load();
    stdout.writeln('probe.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Build the chart every case is drawn from, with the meter of each bar given explicitly.
// INPUTS: meters — one meter per bar, in written order. Each bar gets a chord on every cell its
//         meter offers, so a 3/4 bar carries three chords and a 15/8 bar the five its compound
//         reading offers: the picture then SHOWS the cell count rather than leaving it to a log
//         line. One sign of each kind is placed so the meter sign is judged against the other
//         things drawn in the same band: a volta on bar 6, a segno on bar 7 and a repeat end on bar
//         6, exactly as the other render instruments do.
// OUTPUTS: A one-section song in C major whose bar count is `meters.length`.
// KEYWORDS: fixture, per-bar-meter, chords-per-cell, signs, comparable
Song _chart(List<TimeSignature> meters) => Song(
  id: 'chartapp-meter-probe',
  title: 'Meter probe',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < meters.length; index++)
          Bar(
            timeSignature: meters[index],
            chords: <ChordMark>[
              for (int cell = 0; cell < meters[index].cellsPerBar; cell++)
                ChordMark(
                  place: cellAt(cell),
                  chord: Chord(
                    root: ChordRoot((index + cell) % 12),
                    quality: cell.isEven
                        ? ChordQuality.majorSeventh
                        : ChordQuality.minorSeventh,
                  ),
                ),
            ],
            volta: index == 6 ? const Volta(1) : null,
            closingBarline: index == 6 ? Barline.repeatEnd : Barline.single,
            marks: index == 7
                ? const <BarMark>{BarMark.segno}
                : const <BarMark>{},
          ),
      ],
    ),
  ],
);

// PURPOSE: Paint one page into a PNG with one scale, so two runs of the same page can be compared by
//          the bytes of the file rather than by two images side by side.
// INPUTS: page and song — what to draw. metrics — the metrics the page was measured with. out — the
//         file. pixelRatio — the device pixel ratio, fixed so a comparison is between like and like.
// OUTPUTS: Writes the PNG and returns the bytes written. The image and picture are disposed, because
//          they hold engine-side memory.
// KEYWORDS: paint, picture-recorder, to-image, png, deterministic
Future<List<int>> _renderToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  File out, {
  double pixelRatio = 2,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  final ui.Size size = ui.Size(_pageWidth, _pageHeight);
  ChartPainter(song: song, page: page, metrics: metrics).paint(canvas, size);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (_pageWidth * pixelRatio).round(),
    (_pageHeight * pixelRatio).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  image.dispose();
  picture.dispose();
  out.parent.createSync(recursive: true);
  final List<int> bytes = png.buffer.asUint8List();
  out.writeAsBytesSync(bytes);
  return bytes;
}

// PURPOSE: Report the signs the RULE puts on a page, so the drawn PNG can be checked against a
//          printed expectation rather than against a memory of what it should look like.
// INPUTS: label — the case's name. song and page — the pair the rule reads.
// OUTPUTS: `probe.signs` on stdout listing every signed bar in page order. Nothing is asserted: the
//          reader compares this line with the picture.
// KEYWORDS: signs-report, rule-vs-page, reading-order
void _reportSigns(String label, Song song, PageLayout page) {
  final Map<String, String> signs = meterSignsOnPage(song, page);
  final List<String> inOrder = <String>[];
  for (final PlacedSystem system in page.systems) {
    for (final PlacedBar bar in system.bars) {
      final String key = '${bar.sectionId}#${bar.barIndex}';
      if (signs.containsKey(key)) {
        inOrder.add('$key=${signs[key]}');
      }
    }
  }
  stdout.writeln(
    'probe.signs name=$label page=${page.index} count=${inOrder.length} '
    'bars=${page.bars.length} signs=${inOrder.join(',')}',
  );
}

// PURPOSE: Report the cell count and the hit test of one bar, cell by cell, in NUMBERS — the
//          requirement is that the meter decides how many cells a bar offers and that a touch still
//          names the cell it landed on, and both are counts rather than adjectives.
// INPUTS: song and page — the laid-out chart. sectionId and barIndex — the bar to measure.
// OUTPUTS: `probe.cells` with the bar's meter, the number of cells the layout placed, and the hit
//          test result at the centre of each cell, plus the two negative controls: a point in the
//          bar's LEFT padding (bar, no cell) and a point below the bar (no hit at all).
// KEYWORDS: cell-count, hit-test, beat-address, padding, negative-control
void _reportCells(Song song, PageLayout page, String sectionId, int barIndex) {
  PlacedBar? bar;
  for (final PlacedBar candidate in page.bars) {
    if (candidate.sectionId == sectionId && candidate.barIndex == barIndex) {
      bar = candidate;
      break;
    }
  }
  final Bar? model = song.barAt(sectionId, barIndex);
  if (bar == null || model == null) {
    stdout.writeln(
      'probe.skip cells bar=$sectionId#$barIndex reason=not on this page',
    );
    return;
  }
  final List<String> hits = <String>[];
  for (final PlacedCell cell in bar.cells) {
    final double x = cell.bounds.left + cell.bounds.size.width / 2;
    final double y = cell.bounds.top + cell.bounds.size.height / 2;
    final ChartHit? hit = hitTestPage(page, LayoutOffset(x, y));
    hits.add(
      'cell${cell.beat}:${hit == null ? 'null' : '${hit.barIndex}'
                '/${hit.beat ?? 'none'}'}',
    );
  }
  final double padX = bar.bounds.left + 1;
  final double midY = bar.bounds.top + bar.bounds.size.height / 2;
  final ChartHit? padding = hitTestPage(page, LayoutOffset(padX, midY));
  final ChartHit? below = hitTestPage(
    page,
    LayoutOffset(
      bar.bounds.left + bar.bounds.size.width / 2,
      bar.bounds.bottom + 4,
    ),
  );
  stdout.writeln(
    'probe.cells bar=$sectionId#$barIndex meter=${model.timeSignature} '
    'cellsPerBar=${model.timeSignature.cellsPerBar} '
    'placed_cells=${bar.cells.length} '
    'bar_width=${bar.bounds.size.width.toStringAsFixed(2)} hits=${hits.join(' ')} '
    'padding_hit=${padding == null ? 'null' : 'bar${padding.barIndex}'
              '/${padding.beat ?? 'none'}'} '
    'below_hit=${below == null ? 'null' : 'bar${below.barIndex}'}',
  );
}

// PURPOSE: Report what the typed-figures reader does with the inputs a musician might really type,
//          so the refusal of a nonsense meter is a logged answer rather than a promise.
// INPUTS: None.
// OUTPUTS: One `probe.input` line per pair, carrying the meter produced or the field and the kind
//          of problem. Nothing is asserted.
// KEYWORDS: typed-input, refusal, 0-over-0, negative, 15-over-8, evidence
void _reportTypedInput() {
  const List<(String, String)> cases = <(String, String)>[
    ('4', '4'),
    ('15', '8'),
    ('0', '0'),
    ('-3', '4'),
    ('4', '0'),
    ('3.5', '4'),
    ('', '4'),
    ('999', '4'),
  ];
  for (final (String numerator, String denominator) in cases) {
    try {
      final TimeSignature meter = parseMeterFigures(
        numerator: numerator,
        denominator: denominator,
      );
      stdout.writeln('probe.input "$numerator"/"$denominator" => meter $meter');
    } on MeterInputException catch (error) {
      stdout.writeln(
        'probe.input "$numerator"/"$denominator" => refused '
        'field=${error.field.name} problem=${error.problem.name}',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the meter sign, the cell count it decides, and the identity of a steady chart', () async {
    final String? family = await _loadFont();
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show which meter is written',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutEngine engine = LayoutEngine(style: _styleFor(metrics));
    final String outDir =
        Platform.environment['METER_PROBE_OUT'] ?? meterProbeDirectory;
    Directory(outDir).createSync(recursive: true);

    // --- CASE A: A CHART THAT NEVER CHANGES METER ----------------------------------------------
    //
    // Every bar 4/4. This is the case whose page must be BYTE-IDENTICAL to the page the same chart
    // produced before a meter sign existed, and the reference for that comparison is a run of THIS
    // probe against the tree before the painter changed, written to another directory.
    final Song steady = _chart(<TimeSignature>[
      for (int index = 0; index < 16; index++) TimeSignature.fourFour,
    ]);
    final List<PageLayout> steadyPages = engine.layout(
      steady,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportSigns('steady-4-4', steady, steadyPages.first);
    final List<int> steadyBytes = await _renderToPng(
      steadyPages.first,
      steady,
      metrics,
      File('$outDir${Platform.pathSeparator}meter-steady-4-4@2x.png'),
    );
    stdout.writeln(
      'probe.identity name=steady-4-4 png_bytes=${steadyBytes.length} '
      'digest=${_digestOf(steadyBytes)}',
    );

    // --- CASE B: 4/4 INTO 3/4 MID-TUNE ---------------------------------------------------------
    //
    // Half the chart in 4/4 and half in 3/4, long enough to wrap onto several systems, so the
    // picture shows BOTH rules at once: the sign at the bar where the meter changes, and the sign
    // again at the start of every system that is in 3/4.
    final Song waltz = _chart(<TimeSignature>[
      for (int index = 0; index < 16; index++)
        index < 8 ? TimeSignature.fourFour : TimeSignature.threeFour,
    ]);
    final List<PageLayout> waltzPages = engine.layout(
      waltz,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportSigns('4-4-into-3-4', waltz, waltzPages.first);
    _reportCells(waltz, waltzPages.first, 'A', 4);
    _reportCells(waltz, waltzPages.first, 'A', 8);
    await _renderToPng(
      waltzPages.first,
      waltz,
      metrics,
      File('$outDir${Platform.pathSeparator}meter-4-4-into-3-4@2x.png'),
    );

    // --- CASE C: A BAR IN 15/8 ----------------------------------------------------------------
    //
    // The meter D22 names by name. 15/8 is read as a COMPOUND meter by the model's own rule — a
    // denominator of 8 with a numerator divisible by three is counted in dotted quarters — so the
    // bar offers FIVE cells rather than fifteen, and that number is the model's existing behaviour
    // rather than this change's. It is printed here precisely so the number is visible.
    final Song fifteenEight = _chart(<TimeSignature>[
      for (int index = 0; index < 16; index++)
        index < 8
            ? TimeSignature.fourFour
            : const TimeSignature(numerator: 15, denominator: 8),
    ]);
    final List<PageLayout> fifteenPages = engine.layout(
      fifteenEight,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportSigns('into-15-8', fifteenEight, fifteenPages.first);
    _reportCells(fifteenEight, fifteenPages.first, 'A', 8);
    await _renderToPng(
      fifteenPages.first,
      fifteenEight,
      metrics,
      File('$outDir${Platform.pathSeparator}meter-into-15-8@2x.png'),
    );

    // --- CASE D: AN UNUSUAL METER FROM THE FIRST BAR -------------------------------------------
    //
    // A chart that never changes meter but is not in 4/4. The page changes even though the meter
    // does not, because every system start is signed — which is the one deliberate exception to
    // "an unchanged chart renders identically", and it is shown here rather than left implicit.
    final Song waltzOnly = _chart(<TimeSignature>[
      for (int index = 0; index < 16; index++) TimeSignature.threeFour,
    ]);
    final List<PageLayout> waltzOnlyPages = engine.layout(
      waltzOnly,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    _reportSigns('3-4-throughout', waltzOnly, waltzOnlyPages.first);
    await _renderToPng(
      waltzOnlyPages.first,
      waltzOnly,
      metrics,
      File('$outDir${Platform.pathSeparator}meter-3-4-throughout@2x.png'),
    );

    _reportTypedInput();
    stdout.writeln('probe.out dir=$outDir');
  });
}

// PURPOSE: Report a stable digest of the bytes this run wrote, so a reader can see at a glance
//          whether two runs produced the same file.
// INPUTS: bytes — the PNG.
// OUTPUTS: A 64-bit FNV-1a digest as 16 hexadecimal characters. It is NOT a cryptographic hash
//          and is not used as one: the SHA-256 that settles byte identity is computed on the file
//          by the shell that compares the two runs, and this digest exists so the log shows the
//          answer without anybody opening the file.
// KEYWORDS: digest, fnv1a, comparison, logging, non-cryptographic
String _digestOf(List<int> bytes) {
  int hash = 0xcbf29ce484222325;
  for (final int byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
