// PURPOSE: Produce a PNG of a page with a selection highlight, and the same page without one, so a
//          human can SEE that the highlight lands on the bar and cell the hit test named instead of
//          trusting a boolean. It is headless on purpose: `flutter test` runs the real engine with no
//          window, and a window on this machine would take focus from whoever is working at it. The
//          two images differ by exactly one thing, which is what makes the comparison evidence.
// INPUTS: None. The chart is synthetic, so this instrument runs on any machine; a system font is
//         loaded when one is found so the chord symbols are readable rather than filled boxes.
// OUTPUTS: Two PNGs under [selectionRenderDirectory], outside the repository, named for the case,
//          plus a `render.select ...` line on stdout carrying the page rectangle the highlight was
//          drawn from. The test is skipped when no font is available, because a page of boxes cannot
//          show WHERE a highlight is.
// KEYWORDS: headless-render, png, selection-highlight, before-and-after, no-window, evidence
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The logical page width and height: the tablet viewport the other render instrument uses.
const double selectionPageWidth = 824;
const double selectionPageHeight = 600;

/// Where the PNGs are written. Outside the repository: a rendered image is evidence for one
/// inspection, not an artefact to commit.
const String selectionRenderDirectory =
    r'C:\projects\ChartApp-acl-reports\render\selection';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartSelectionRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

// PURPOSE: Build a chart with a section break and enough chords that a highlight has something
//          visible to sit on, and so a bar's ordinal can be checked by eye against the section.
// INPUTS: None.
// OUTPUTS: A 16-bar song: section A of eight bars and section B of eight, each bar carrying a chord
//          on beat 0 and every second bar a second chord on beat 2.
// KEYWORDS: fixture, synthetic-song, two-sections, visible-chords
Song selectionChart() => Song(
  title: 'Selection render',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    for (final String label in <String>['A', 'B'])
      Section(
        id: label,
        label: SectionLabel.letter(label),
        bars: <Bar>[
          for (int index = 0; index < 8; index++)
            Bar(
              chords: <ChordMark>[
                ChordMark(
                  place: placeAt(0),
                  chord: Chord(
                    root: ChordRoot(index),
                    quality: ChordQuality.majorSeventh,
                  ),
                ),
                if (index.isEven)
                  ChordMark(
                    place: placeAt(2),
                    chord: Chord(
                      root: ChordRoot(index),
                      quality: ChordQuality.minorSeventh,
                    ),
                  ),
              ],
            ),
        ],
      ),
  ],
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes cannot show which bar was selected.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists.
// KEYWORDS: font, font-loader, readable-text
Future<String?> _loadChartFont() async {
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
    stdout.writeln('render.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

/// The metrics the page is measured and drawn with, in the loaded family.
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
);

// PURPOSE: Paint one page into a PNG, optionally with a selection highlighted.
// INPUTS: page, song, metrics and out as in the other render instrument. selection — the hit to
//         highlight, or null for a clean page. logicalWidth and logicalHeight — the surface the
//         painter is handed, which for a fitted page is the SHRUNKEN surface the page scale maps
//         onto, not the larger size it was engraved at.
// OUTPUTS: Writes the PNG and returns nothing.
// KEYWORDS: paint, picture-recorder, to-image, png, selection, fitted-surface, dispose
Future<void> _renderToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  ChartHit? selection,
  File out, {
  double logicalWidth = selectionPageWidth,
  double logicalHeight = selectionPageHeight,
}) async {
  const double pixelRatio = 2;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
    selection: selection,
  ).paint(canvas, ui.Size(logicalWidth, logicalHeight));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (logicalWidth * pixelRatio).round(),
    (logicalHeight * pixelRatio).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  image.dispose();
  picture.dispose();
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(png.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a selected page and a clean page to PNGs without opening a window', () async {
    final String? family = await _loadChartFont();
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show where a highlight is',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutEngine engine = LayoutEngine(
      style: LayoutStyle(
        textMetrics: metrics,
        pageMargin: 20,
        barMinWidth: 64,
        barPadding: 8,
        chordSpacing: 12,
        minCellWidth: 18,
        barHeight: 52,
        systemSpacing: 18,
        sectionLabelHeight: 26,
      ),
    );
    final Song song = selectionChart();
    final List<PageLayout> pages = engine.layout(
      song,
      pageWidth: selectionPageWidth,
      pageHeight: selectionPageHeight,
    );
    expect(pages, hasLength(1), reason: 'the fixture is meant to be one page');
    final PageLayout page = pages.single;

    // The bar to select, named the way the viewer labels it: the ninth written bar, third cell.
    // Section A holds eight bars, so the ninth bar is bar index 0 of section B, and its third cell
    // carries a chord — so the highlight has to wrap a symbol the eye can check it against.
    final PlacedBar bar = page.bars[8];
    expect(bar.sectionId, 'B');
    expect(bar.barIndex, 0);
    final LayoutRect cell = bar.bounds;
    final LayoutOffset point = LayoutOffset(
      cell.left + cell.size.width / 2,
      cell.top + cell.size.height / 2,
    );
    final ChartHit? hit = hitTestPage(page, point);
    expect(hit, isNotNull);
    expect(hit!.sectionId, 'B');
    expect(hit.barIndex, 0);
    expect(hit.local.x, 2);

    stdout.writeln(
      'render.select bar=9 cell=3 section=${bar.sectionId} '
      'bar_index=${bar.barIndex} beat=${cell.left} '
      'cell_rect=(${cell.left},${cell.top},'
      '${cell.size.width},${cell.size.height}) '
      'bar_rect=(${bar.bounds.left},${bar.bounds.top},'
      '${bar.bounds.size.width},${bar.bounds.size.height}) '
      'page_scale=${page.scale} page_bars=${page.bars.length} '
      'page_systems=${page.systems.length}',
    );

    final Directory outDir = Directory(selectionRenderDirectory);
    outDir.createSync(recursive: true);
    final File clean = File(
      '${outDir.path}${Platform.pathSeparator}before-no-selection@2x.png',
    );
    final File marked = File(
      '${outDir.path}${Platform.pathSeparator}after-selection-bar9-cell3@2x.png',
    );
    await _renderToPng(page, song, metrics, null, clean);
    await _renderToPng(page, song, metrics, hit, marked);
    stdout.writeln(
      'render.wrote clean=${clean.path} bytes=${clean.lengthSync()}',
    );
    stdout.writeln(
      'render.wrote marked=${marked.path} bytes=${marked.lengthSync()}',
    );

    // The fitted case, which is the one a hit test can get wrong while every ordinary page still
    // answers correctly. The page is re-engraved on a surface it does not fit, the painter shrinks
    // it, and the highlight must land on the cell where the shrink PUT it — so the rectangle below
    // is the engraved cell multiplied by the scale, and the PNG is the surface in those units.
    const double fitWidth = 400;
    const double fitHeight = 300;
    final FitOutcome fit = engine.fitToPage(
      song,
      pageWidth: fitWidth,
      pageHeight: fitHeight,
    );
    final PageLayout fitted = fit.page!;
    expect(fitted.scale, lessThan(1));
    final PlacedBar fitBar = fitted.bars[fitted.bars.length ~/ 2];
    final LayoutRect fitCell = fitBar.bounds;
    final ChartHit? fitHit = hitTestPage(
      fitted,
      LayoutOffset(
        fitCell.left + fitCell.size.width / 2,
        fitCell.top + fitCell.size.height / 2,
      ),
    );
    expect(fitHit, isNotNull);
    expect(fitHit!.barIndex, fitBar.barIndex);
    expect(fitHit.local.x, 2);
    stdout.writeln(
      'render.select.fit scale=${fitted.scale} '
      'engraved_cell=(${fitCell.left},${fitCell.top},'
      '${fitCell.size.width},${fitCell.size.height}) '
      'surface_cell=(${fitCell.left * fitted.scale},'
      '${fitCell.top * fitted.scale},'
      '${fitCell.size.width * fitted.scale},'
      '${fitCell.size.height * fitted.scale}) '
      'bar_index=${fitBar.barIndex} left=${fitCell.left} '
      'fitted_bars=${fitted.bars.length}',
    );
    final File fittedPng = File(
      '${outDir.path}${Platform.pathSeparator}'
      'after-selection-bar${fitBar.barIndex + 1}-cell3-fit@2x.png',
    );
    await _renderToPng(
      fitted,
      song,
      metrics,
      fitHit,
      fittedPng,
      logicalWidth: fitWidth,
      logicalHeight: fitHeight,
    );
    stdout.writeln(
      'render.wrote fitted=${fittedPng.path} bytes=${fittedPng.lengthSync()}',
    );
  });
}
