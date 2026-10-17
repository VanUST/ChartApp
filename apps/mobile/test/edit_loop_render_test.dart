// PURPOSE: LOOK at the edit loop: render one bar of a chart to a PNG before a chord is changed and
//          to another PNG after, through the same session, the same operation log and the same
//          reducer the application uses, so that "the right cell now says the right chord" can be
//          checked by eye instead of trusted from a boolean. A comparison of two images that differ
//          by exactly one chord is the only evidence that says WHICH cell changed, and a boolean
//          assertion cannot.
// INPUTS: None. The chart is synthetic, so this instrument runs on any machine. A real system font
//         is loaded when one is found, because the framework's default test font draws every glyph
//         as a filled box and a page of boxes cannot show a chord symbol.
// OUTPUTS: PNGs under [editLoopRenderDirectory], outside the repository, named for the case, plus
//          `edit.*` lines on stdout carrying the chord list of the edited bar before and after, the
//          document id, and the operation types the session logged. The instrument is SKIPPED when
//          no font is available, because a page of boxes proves the layout and nothing about the
//          text. Rendering happens under `flutter test`, which runs the real engine with no window:
//          a window on this machine would take focus from whoever is working at it.
// KEYWORDS: headless-render, png, edit-loop, before-and-after, fitted-page, chord-palette, evidence,
//           no-window, font, cell-by-cell
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logical page width and height: the tablet viewport the other render instruments use.
const double editPageWidth = 824;
const double editPageHeight = 600;

/// Where the PNGs are written. Outside the repository: a rendered image is evidence for one
/// inspection, not an artefact to commit.
const String editLoopRenderDirectory =
    r'C:\projects\ChartApp-acl-reports\render\edit-loop';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartEditRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The section the edited bar lives in.
const String _editedSection = 'A';

/// The edited bar's index inside its section. Bar 1 of the chart, the first bar on the page.
const int _editedBar = 0;

/// The edited cell. Cell 3 of the bar, which is the cell the fixture writes a minor seventh into.
const int _editedBeat = 2;

// PURPOSE: Build the chart this instrument edits. One section of four bars, every bar carrying a
//          chord on its first cell and a second chord on its third, so that changing one cell has a
//          neighbour on each side to be compared against — a change that shifted everything after
//          it would be visible rather than plausible.
// INPUTS: None.
// OUTPUTS: A song in C major whose bar 1 holds `C^7` on cell 1 and `D-7` on cell 3.
// KEYWORDS: fixture, synthetic-song, one-section, four-bars, two-chords-per-bar
Song editLoopChart() => Song(
  id: 'chartapp-edit-loop',
  title: 'Edit loop',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: _editedSection,
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < 4; index++)
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: cellPlace(_editedSection, index, 0),
                chord: Chord(
                  root: ChordRoot(index),
                  quality: ChordQuality.majorSeventh,
                ),
              ),
              ChordMark(
                place: cellPlace(_editedSection, index, 2),
                chord: Chord(
                  root: ChordRoot(index + 2),
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
//          glyph as a filled box and a page of boxes cannot show a chord symbol.
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
// INPUTS: page, song, metrics and out as in the other render instruments. selection — the hit to
//         highlight, or null. logicalWidth and logicalHeight — the surface the painter is handed,
//         which for a fitted page is the SHRUNKEN surface the page scale maps onto.
// OUTPUTS: Writes the PNG and returns nothing.
// KEYWORDS: paint, picture-recorder, to-image, png, fitted-surface, dispose
Future<void> _renderToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  ChartHit? selection,
  File out, {
  double logicalWidth = editPageWidth,
  double logicalHeight = editPageHeight,
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

// PURPOSE: Print one bar's chords in the order the model holds them, so the PNG and the log can be
//          checked against each other rather than one being trusted.
// INPUTS: chart — the song. sectionId and barIndex — the bar to describe.
// OUTPUTS: A line such as `cell 1 (beat 0): C^7 | cell 3 (beat 2): Eb^7`. An empty bar prints
//          `(no chords)`, which is a state this instrument needs to be able to show rather than
//          mistake for a missing line.
// KEYWORDS: bar-dump, cell-list, chord-render, before-and-after
void _printBar(String label, Song chart, String sectionId, int barIndex) {
  final Bar? bar = chart.barAt(sectionId, barIndex);
  if (bar == null) {
    stdout.writeln('edit.$label bar=$sectionId[$barIndex] (no such bar)');
    return;
  }
  if (bar.chords.isEmpty) {
    stdout.writeln('edit.$label bar=$sectionId[$barIndex] (no chords)');
    return;
  }
  final String cells = bar.chords
      .map(
        (ChordMark placed) =>
            'cell ${placed.pseudoBeat + 1} (beat ${placed.pseudoBeat}) -> '
            '${placed.chord.render(chart.key, const SpellingTable())}',
      )
      .join(' | ');
  stdout.writeln('edit.$label bar=$sectionId[$barIndex]: $cells');
}

// PURPOSE: Report where the layout put every bar and which chord it drew there, which is the second
//          half of the before/after evidence: the model dump above says what the document holds and
//          this says what the page actually engraved, so a discrepancy between the two — a chord
//          lost, a cell shifted, a bar reordered — is visible in the output rather than only in an
//          image a reader would have to know how to interpret.
// INPUTS: label — the column the line is tagged with. page — the layout to describe.
// OUTPUTS: One line per bar carrying its x-range, the x of each cell, and the chord drawn on each.
// KEYWORDS: layout-dump, placed-chords, cell-geometry, evidence
void _dumpPlacedBar(String label, PageLayout page) {
  for (final PlacedBar bar in page.bars) {
    final String chords = bar.chords
        .map(
          (PlacedChord placed) =>
              'cell ${placed.beat + 1} '
              '${placed.chord.render(Key.cMajor, const SpellingTable())} '
              '@${placed.bounds.left.toStringAsFixed(1)}',
        )
        .join(' | ');
    stdout.writeln(
      'edit.$label ${bar.sectionId}[${bar.barIndex}] '
      'x=${bar.bounds.left.toStringAsFixed(1)}..'
      '${bar.bounds.right.toStringAsFixed(1)} chords=$chords',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('renders the edited bar before and after a chord change, fitted and not', () async {
    final String? family = await _loadChartFont();
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show which cell changed',
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

    final EditSession session = EditSession(
      document: DocumentState(song: editLoopChart()),
    );
    final Song before = session.song;
    _printBar('before', before, _editedSection, _editedBar);

    final Directory outDir = Directory(editLoopRenderDirectory);
    outDir.createSync(recursive: true);

    // --- BEFORE --------------------------------------------------------------------------------
    final List<PageLayout> pagesBefore = engine.layout(
      before,
      pageWidth: editPageWidth,
      pageHeight: editPageHeight,
    );
    expect(
      pagesBefore,
      hasLength(1),
      reason: 'the fixture is meant to be one page',
    );
    final File beforePng = File(
      '${outDir.path}${Platform.pathSeparator}before@2x.png',
    );
    await _renderToPng(
      pagesBefore.single,
      before,
      metrics,
      _selectionFor(pagesBefore.single),
      beforePng,
    );
    stdout.writeln(
      'render.wrote before=${beforePng.path} bytes=${beforePng.lengthSync()}',
    );
    _dumpPlacedBar('layout.before', pagesBefore.single);

    // --- THE EDIT, through the operation log and nothing else -----------------------------------
    final ChordMark? held = session.existingChordAt(
      sectionId: _editedSection,
      barIndex: _editedBar,
      beat: _editedBeat,
    );
    expect(
      held,
      isNotNull,
      reason: 'the fixture writes a chord into the edited cell',
    );
    final List<ChordRootChoice> roots = chordRootChoicesFor(before.key);
    final ChordRootChoice chosen = roots.firstWhere(
      (ChordRootChoice root) => root.pitchClass == 3,
    );
    final bool applied = session.applyChordToCell(
      sectionId: _editedSection,
      barIndex: _editedBar,
      beat: _editedBeat,
      chord: chordOf(chosen, ChordQuality.majorSeventh),
      size: held!.size,
    );
    expect(applied, isTrue);
    final Song after = session.song;
    _printBar('after', after, _editedSection, _editedBar);
    stdout.writeln(
      'edit.ops types=${session.log.map((ChartEvent event) => event.type).toList()} '
      'seq=${session.seq} '
      'event_seqs=${session.log.map((ChartEvent event) => event.seq).toList()}',
    );

    // --- AFTER ---------------------------------------------------------------------------------
    final List<PageLayout> pagesAfter = engine.layout(
      after,
      pageWidth: editPageWidth,
      pageHeight: editPageHeight,
    );
    expect(pagesAfter, hasLength(1));
    final ChartHit selection = _selectionFor(pagesAfter.single);
    final File afterPng = File(
      '${outDir.path}${Platform.pathSeparator}after@2x.png',
    );
    await _renderToPng(pagesAfter.single, after, metrics, selection, afterPng);
    stdout.writeln(
      'render.wrote after=${afterPng.path} bytes=${afterPng.lengthSync()} '
      'selected_section=${selection.sectionId} '
      'selected_bar=${selection.barIndex} selected_beat=${selection.beat} '
      'selected_cell_rect=(${selection.cell!.bounds.left},'
      '${selection.cell!.bounds.top},${selection.cell!.bounds.size.width},'
      '${selection.cell!.bounds.size.height})',
    );
    _dumpPlacedBar('layout.after', pagesAfter.single);

    // --- THE FITTED CASE, where geometry silently goes wrong ------------------------------------
    // The surface is deliberately narrower than one system of this chart, so the fitter must shrink
    // the engravings onto it and `page.scale` comes out below 1. A surface that happened to fit
    // would give scale 1, which is exactly the case this instrument must avoid: a rectangle
    // computed without the scale is right for every ordinary page and wrong only for a fitted one.
    const double fitWidth = 260;
    const double fitHeight = 180;
    final FitOutcome fitBefore = engine.fitToPage(
      before,
      pageWidth: fitWidth,
      pageHeight: fitHeight,
    );
    final FitOutcome fitAfter = engine.fitToPage(
      after,
      pageWidth: fitWidth,
      pageHeight: fitHeight,
    );
    expect(fitBefore.page, isNotNull, reason: 'a four-bar chart must fit');
    expect(fitAfter.page, isNotNull);
    final PageLayout fittedBefore = fitBefore.page!;
    final PageLayout fittedAfter = fitAfter.page!;
    final File fitBeforePng = File(
      '${outDir.path}${Platform.pathSeparator}before-fit@2x.png',
    );
    final File fitAfterPng = File(
      '${outDir.path}${Platform.pathSeparator}after-fit@2x.png',
    );
    await _renderToPng(
      fittedBefore,
      before,
      metrics,
      null,
      fitBeforePng,
      logicalWidth: fitWidth,
      logicalHeight: fitHeight,
    );
    await _renderToPng(
      fittedAfter,
      after,
      metrics,
      null,
      fitAfterPng,
      logicalWidth: fitWidth,
      logicalHeight: fitHeight,
    );
    final PlacedCell fittedCell = fittedAfter.bars
        .firstWhere(
          (PlacedBar bar) =>
              bar.sectionId == _editedSection && bar.barIndex == _editedBar,
        )
        .cells[_editedBeat];
    stdout.writeln(
      'render.wrote fitted_before=${fitBeforePng.path} '
      'fitted_after=${fitAfterPng.path} '
      'fit_scale_before=${fittedBefore.scale} '
      'fit_scale_after=${fittedAfter.scale} '
      'fitted_bars=${fittedAfter.bars.length} '
      'fitted_cell_engraved=(${fittedCell.bounds.left},'
      '${fittedCell.bounds.top},${fittedCell.bounds.size.width},'
      '${fittedCell.bounds.size.height}) '
      'fitted_cell_surface=(${fittedCell.bounds.left * fittedAfter.scale},'
      '${fittedCell.bounds.top * fittedAfter.scale},'
      '${fittedCell.bounds.size.width * fittedAfter.scale},'
      '${fittedCell.bounds.size.height * fittedAfter.scale})',
    );
  });
}

/// The cell this instrument edits, as the hit test names it on [page].
///
/// Aimed from the page's own rectangle for the cell rather than from a hard-coded pixel, so the
/// highlight in the PNG is the cell the model was edited at and not a neighbouring one.
ChartHit _selectionFor(PageLayout page) {
  final PlacedBar bar = page.bars.firstWhere(
    (PlacedBar placed) =>
        placed.sectionId == _editedSection && placed.barIndex == _editedBar,
  );
  final PlacedCell cell = bar.cells[_editedBeat];
  final ChartHit? hit = hitTestPage(
    page,
    LayoutOffset(
      cell.bounds.left + cell.bounds.size.width / 2,
      cell.bounds.top + cell.bounds.size.height / 2,
    ),
  );
  if (hit == null) {
    throw StateError('the edited cell did not hit-test');
  }
  return hit;
}
