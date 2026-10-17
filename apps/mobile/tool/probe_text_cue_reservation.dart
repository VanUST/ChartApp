// PURPOSE: Produce the numbers and the pictures that show what a text cue's reserved row costs,
//          and what the layout does when the room for it is not there. It reports, for a bar that
//          carries cues, the row the LAYOUT reserved and the box the PAINTER was handed — so "the
//          room reserved and the plate drawn are the same box" is a pair of numbers rather than a
//          claim — and it renders the three states a reader has to judge by eye: a stack of cues, a
//          cue longer than its bar, and a page too short to give the rows the room they need.
//
//          It is an instrument, not part of the suite: it lives in `tool/`, so `flutter test`'s
//          default run and the `melos run verify` gate do not pick it up. Its expectations pin only
//          what it already printed, so a reader can check the numbers by eye and the runner still
//          reports a clean exit. Run it from `apps/mobile` with:
//
//              flutter test tool/probe_text_cue_reservation.dart
//
//          It writes PNGs to [textCueReservationDirectory], outside the repository, and opens no
//          window: `flutter test` runs the engine headless.
// INPUTS: None. The charts are synthetic, so the probe runs on any machine. A real system font is
//         loaded when one is found, because the framework's default test font draws every glyph as
//         a filled box and a page of boxes cannot show a phrase.
// OUTPUTS: `probe.*` lines on stdout — the reserved row and the drawn box per cue, the page's
//          content box, whether the FitOutcome accepted the chart and at what scale, and whether a
//          system's bottom ran past the page — plus one PNG per case. A case that could not be
//          built at all is reported as a `probe.skip` line rather than an exception.
// KEYWORDS: probe, text-cue, reserved-row, does-not-fit, overflow, headless, png, evidence
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// Where the probe's PNGs are written. Outside the repository: a rendered image is evidence for one
/// inspection, not an artefact to commit.
const String textCueReservationDirectory =
    r'C:\projects\ChartApp-acl-reports\render\text-cue-reservation';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartCueReservationFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The section the cues are written on.
const String _section = 'A';

/// The viewer's own layout constants, so the probe measures the geometry the application produces.
LayoutEngine _engineFor(FlutterTextMetrics metrics) => LayoutEngine(
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

/// The metrics the probe lays the pages out and draws the cues with.
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
//          glyph as a filled box and a page of boxes cannot show which words are written.
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

// PURPOSE: Build the chart every case writes its cues on. One section of four bars, every bar
//          carrying two chords, so a cue drawn over one bar has a neighbour to be compared against.
// INPUTS: [bars] — how many bars the section has.
// OUTPUTS: A song in C major whose bars hold a chord on cell 1 and a chord on cell 3.
// KEYWORDS: fixture, synthetic-song, four-bars, two-chords-per-bar
Song _chart(int bars) => Song(
  id: 'chartapp-cue-reservation',
  title: 'Cue reservation',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: _section,
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < bars; index++)
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: placeAt(0),
                chord: Chord(
                  root: ChordRoot(index),
                  quality: ChordQuality.majorSeventh,
                ),
              ),
              ChordMark(
                place: placeAt(2),
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

// PURPOSE: Write [words] onto one bar through the operation log, so the probe's document is built
//          the way the application builds one and the cue's own offset is the default.
// INPUTS: song — the music. bar — the bar index. words — one phrase per cue, in the order written.
// OUTPUTS: The session holding the chart and its cues.
// KEYWORDS: cue-insert, operation-log, document-state, session
EditSession _sessionWith(Song song, int bar, List<String> words) {
  final EditSession session = EditSession(document: DocumentState(song: song));
  for (final String text in words) {
    final String? id = session.insertTextCue(
      sectionId: _section,
      barIndex: bar,
      offsetX: 2,
      text: text,
    );
    if (id == null) {
      throw StateError('cue insert refused for bar $bar');
    }
  }
  return session;
}

// PURPOSE: Resolve every cue against one page exactly as the viewer does — by reading the row the
//          layout placed it in — so the probe measures the product's own placement.
// INPUTS: page — the layout. document — the state holding the cues.
// OUTPUTS: The cues this page has a row for, in the document's order.
// KEYWORDS: cue-row-lookup, viewer-parity, render-order
List<ResolvedTextCue> _resolveCues(PageLayout page, DocumentState document) {
  final Map<String, PlacedTextCue> placedById = <String, PlacedTextCue>{};
  for (final PlacedBar bar in page.bars) {
    for (final PlacedTextCue placed in bar.textCues) {
      placedById[placed.id] = placed;
    }
  }
  final List<ResolvedTextCue> resolved = <ResolvedTextCue>[];
  for (final TextCue cue in document.textCues) {
    final PlacedTextCue? placed = placedById[cue.id];
    if (placed == null) {
      continue;
    }
    resolved.add(
      ResolvedTextCue(cue: cue, origin: placed.origin, size: placed.size),
    );
  }
  return resolved;
}

// PURPOSE: Paint one page into a PNG, stacked exactly as the viewer stacks it: the chart, then the
//          cue layer, with both given the page's own scale.
// INPUTS: page, song, metrics, document and out as in the other render instruments. logicalWidth
//         and logicalHeight — the surface the painter is handed, which for a fitted page is the
//         SHRUNKEN surface the page scale maps onto.
// OUTPUTS: Writes the PNG and returns nothing. The image and picture are disposed, because they
//          hold engine-side memory.
// KEYWORDS: paint, picture-recorder, to-image, png, cue-layer, dispose
Future<void> _renderToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  DocumentState document,
  File out, {
  required double logicalWidth,
  required double logicalHeight,
}) async {
  const double pixelRatio = 2;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  final ui.Size size = ui.Size(logicalWidth, logicalHeight);
  ChartPainter(song: song, page: page, metrics: metrics).paint(canvas, size);
  TextCuePainter(
    cues: _resolveCues(page, document),
    pageScale: page.scale,
    textStyle: metrics.textCueStyle,
  ).paint(canvas, size);
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
  stdout.writeln(
    'probe.wrote path=${out.path} bytes=${out.lengthSync()} '
    'pixels=${(logicalWidth * pixelRatio).round()}x'
    '${(logicalHeight * pixelRatio).round()}',
  );
}

// PURPOSE: Report one placed case — the cue's reserved row, the box drawn in it, the chord bounds of
//          the same bar and the clearance between them — so the reservation is a measurement and not
//          an impression.
// INPUTS: label — the case's name. page — the layout. document — the state. scale — the page's
//         scale. bandHeight — the room the system gave up above its stave, in engraved pixels.
// OUTPUTS: `probe.cue` and `probe.reserve` lines on stdout. Nothing is asserted.
// KEYWORDS: report, reservation, clearance, engraved-and-surface, band
void _report(
  String label,
  PageLayout page,
  DocumentState document,
  double scale,
  double bandHeight,
) {
  stdout.writeln(
    'probe.case name=$label page=${page.index} scale=${scale.toStringAsFixed(6)} '
    'page_size=${page.size.width.toStringAsFixed(1)}x'
    '${page.size.height.toStringAsFixed(1)} '
    'systems=${page.systems.length} bars=${page.bars.length} '
    'cues=${_resolveCues(page, document).length}',
  );
  for (final PlacedSystem system in page.systems) {
    stdout.writeln(
      'probe.system top=${system.bounds.top.toStringAsFixed(2)} '
      'bottom=${system.bounds.bottom.toStringAsFixed(2)} '
      'height=${system.bounds.size.height.toStringAsFixed(2)} '
      'bars=${system.bars.length}',
    );
  }
  final List<ResolvedTextCue> cues = _resolveCues(page, document);
  for (final ResolvedTextCue placed in cues) {
    final TextCue cue = placed.cue;
    final double left = (placed.origin.x + cue.place.offsetX) * scale;
    final double top = (placed.origin.y + cue.place.offsetY) * scale;
    final double bottom = top + placed.size.height * scale;
    final PlacedBar bar = page.bars.firstWhere(
      (PlacedBar candidate) =>
          candidate.sectionId == cue.place.anchor.sectionId &&
          candidate.barIndex == cue.place.anchor.bar,
    );
    double? chordTop;
    for (final PlacedChord chord in bar.chords) {
      final double candidate = chord.bounds.top * scale;
      if (chordTop == null || candidate < chordTop) {
        chordTop = candidate;
      }
    }
    stdout.writeln(
      'probe.cue id=${cue.id} text="${cue.text}" '
      'row_engraved=(${placed.origin.x.toStringAsFixed(2)},'
      '${placed.origin.y.toStringAsFixed(2)}) '
      'box_engraved=${placed.size.width.toStringAsFixed(2)}x'
      '${placed.size.height.toStringAsFixed(2)} '
      'plate_surface=(${left.toStringAsFixed(2)},${top.toStringAsFixed(2)})..'
      '(${(left + placed.size.width * scale).toStringAsFixed(2)},'
      '${bottom.toStringAsFixed(2)}) '
      'bar_top_surface=${(bar.bounds.top * scale).toStringAsFixed(2)} '
      'chord_top_surface=${chordTop?.toStringAsFixed(2) ?? 'none'} '
      'clearance_surface='
      '${chordTop == null ? 'none' : (chordTop - bottom).toStringAsFixed(2)}',
    );
  }
  stdout.writeln(
    'probe.band name=$label band_engraved=${bandHeight.toStringAsFixed(2)} '
    'bar_height=${page.bars.first.bounds.size.height.toStringAsFixed(2)}',
  );
}

// PURPOSE: Read the room a system gave up for cues, from the geometry the engine published rather
//          than from the style, so the number is what was laid out.
// INPUTS: system — the system. style — the style the page was laid out with, for the section
//         label's height, which shares the band above the stave with the cue rows.
// OUTPUTS: The gap between the cue rows' top and the stave's top, in engraved pixels, with any
//          section label above it removed.
// KEYWORDS: band, geometry-derived, label-excluded, no-second-source
double _bandOf(PlacedSystem system, LayoutStyle style) {
  if (system.bars.isEmpty) {
    return 0;
  }
  final double labelHeight = system.sectionLabel == null
      ? 0
      : style.sectionLabelHeight;
  return system.bars.first.bounds.top - system.bounds.top - labelHeight;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the rows a text cue reserves, and what happens when they do not fit', () async {
    final String? family = await _loadFont();
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show which words are written',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutEngine engine = _engineFor(metrics);
    final Directory outDir = Directory(textCueReservationDirectory);
    outDir.createSync(recursive: true);

    // --- CASE 1: A STACK OF CUES ON ONE BAR, ON A FITTED PAGE --------------------------------
    //
    // Four cues on one bar is what "several phrases on one bar" costs: four rows above that bar and
    // only that bar. The fitted surface is the one the render instrument uses, so the numbers here
    // can be read against `text_cue_render_test.dart`'s.
    final EditSession stacked = _sessionWith(_chart(4), 1, <String>[
      'To Coda',
      'D.C. al Fine',
      'Solo',
      'Vamp 4x',
    ]);
    final FitOutcome stackedFit = engine.fitToPage(
      stacked.song,
      pageWidth: 260,
      pageHeight: 180,
      cues: stacked.document.textCues,
    );
    final PageLayout? stackedPage = stackedFit.page;
    if (stackedPage == null) {
      stdout.writeln('probe.skip case=stacked reason=the fixture did not fit');
    } else {
      final double scale = stackedPage.scale;
      final PlacedSystem first = stackedPage.systems.first;
      _report(
        'stacked-fit',
        stackedPage,
        stacked.document,
        scale,
        _bandOf(first, engine.style),
      );
      // The bar that actually carries the cues, not the system's first bar: an unfilled bar beside
      // it would otherwise report a stack of zero rows.
      final PlacedBar stackedBar = first.bars.firstWhere(
        (PlacedBar bar) => bar.textCues.isNotEmpty,
        orElse: () => first.bars.first,
      );
      stdout.writeln(
        'probe.stack bar=${stackedBar.barIndex} rows=${stackedBar.textCues.length} '
        'band_surface=${(_bandOf(first, engine.style) * scale).toStringAsFixed(2)} '
        'bar_rows_surface='
        '${(stackedBar.textCues.fold<double>(0, (double total, PlacedTextCue cue) => total + cue.size.height) * scale).toStringAsFixed(2)}',
      );
      await _renderToPng(
        stackedPage,
        stacked.song,
        metrics,
        stacked.document,
        File('${outDir.path}${Platform.pathSeparator}stacked-fit@2x.png'),
        logicalWidth: 260,
        logicalHeight: 180,
      );
    }

    // --- CASE 2: A CUE LONGER THAN ITS BAR ---------------------------------------------------
    //
    // The horizontal answer is unchanged and is measured here rather than asserted: a long cue runs
    // WIDE past its bar and is clipped only by the page, because wrapping it would change where its
    // words sit relative to the bar. The row it reserves is still one line.
    const String longWords =
        'Play the head twice, then D.C. al Fine and wait for the coda';
    final EditSession longCue = _sessionWith(_chart(4), 0, <String>[longWords]);
    final List<PageLayout> longPages = engine.layout(
      longCue.song,
      pageWidth: 824,
      pageHeight: 600,
      cues: longCue.document.textCues,
    );
    final PageLayout longPage = longPages.first;
    final ResolvedTextCue longPlaced = _resolveCues(
      longPage,
      longCue.document,
    ).single;
    final PlacedBar longBar = longPage.bars.first;
    stdout.writeln(
      'probe.long words=${longWords.length} '
      'plate_width=${longPlaced.size.width.toStringAsFixed(2)} '
      'bar_width=${longBar.bounds.size.width.toStringAsFixed(2)} '
      'runs_wide=${longPlaced.size.width > longBar.bounds.size.width} '
      'rows_reserved=${longBar.textCues.length} '
      'box_height=${longPlaced.size.height.toStringAsFixed(2)}',
    );
    _report(
      'long-cue',
      longPage,
      longCue.document,
      longPage.scale,
      _bandOf(longPage.systems.first, engine.style),
    );
    await _renderToPng(
      longPage,
      longCue.song,
      metrics,
      longCue.document,
      File('${outDir.path}${Platform.pathSeparator}long-cue@2x.png'),
      logicalWidth: 824,
      logicalHeight: 600,
    );

    // --- CASE 3: FIT THAT IS REFUSED BECAUSE OF THE ROWS -------------------------------------
    //
    // The counterfactual is measured on the same chart and the same surface: the same music with no
    // cues, then with a stack of them. If the first fits and the second does not, the rows are what
    // cost the page, and that is a number rather than a story.
    final EditSession crowded = _sessionWith(_chart(9), 0, <String>[
      for (int index = 0; index < 10; index++) 'Cue ${index + 1}',
    ]);
    final FitOutcome without = engine.fitToPage(
      crowded.song,
      pageWidth: 300,
      pageHeight: 240,
    );
    final FitOutcome withCues = engine.fitToPage(
      crowded.song,
      pageWidth: 300,
      pageHeight: 240,
      cues: crowded.document.textCues,
    );
    stdout.writeln(
      'probe.does_not_fit surface=300x240 '
      'without_cues fits=${without.fits} scale=${without.scale.toStringAsFixed(6)} '
      'with_cues fits=${withCues.fits} scale=${withCues.scale.toStringAsFixed(6)} '
      'cues=${crowded.document.textCues.length} min_scale=${LayoutEngine.minLegibleScale}',
    );
    // What the viewer draws when FIT refuses: the ordinary pagination.
    final List<PageLayout> fallback = engine.layout(
      crowded.song,
      pageWidth: 300,
      pageHeight: 240,
      cues: crowded.document.textCues,
    );
    final PageLayout fallbackPage = fallback.first;
    _report(
      'fit-refused-first-page',
      fallbackPage,
      crowded.document,
      fallbackPage.scale,
      _bandOf(fallbackPage.systems.first, engine.style),
    );
    await _renderToPng(
      fallbackPage,
      crowded.song,
      metrics,
      crowded.document,
      File(
        '${outDir.path}${Platform.pathSeparator}fit-refused-first-page@2x.png',
      ),
      logicalWidth: 300,
      logicalHeight: 240,
    );

    // --- CASE 4: A PAGE TOO SHORT FOR THE ROWS, IN PAGINATED MODE ----------------------------
    //
    // A page whose content box cannot hold one system plus its cue rows. The engine flushes the
    // system onto a page of its own and then places it at the page's top edge, so the overflow comes
    // off the BOTTOM — the stave runs past the page's bottom margin, exactly as a bar too wide for
    // the page runs past its right edge. The numbers printed below are the measurement of that: the
    // system's bottom against the page's own bottom margin.
    final EditSession shortPage = _sessionWith(_chart(4), 0, <String>[
      for (int index = 0; index < 8; index++) 'Stacked ${index + 1}',
    ]);
    const double shortWidth = 300;
    const double shortHeight = 150;
    final List<PageLayout> shortPages = engine.layout(
      shortPage.song,
      pageWidth: shortWidth,
      pageHeight: shortHeight,
      cues: shortPage.document.textCues,
    );
    final PageLayout firstShort = shortPages.first;
    final PlacedSystem firstSystem = firstShort.systems.first;
    final double contentBottom = shortHeight - engine.style.pageMargin;
    // What a musician can actually see of the stack: a row is visible when any of its plate falls
    // inside the page, so the rows the page's top edge cut away are counted rather than assumed.
    int rowsClipped = 0;
    int rowsVisible = 0;
    for (final ResolvedTextCue placed in _resolveCues(
      firstShort,
      shortPage.document,
    )) {
      final double topSurface =
          (placed.origin.y + placed.cue.place.offsetY) * firstShort.scale;
      final double bottomSurface =
          topSurface + placed.size.height * firstShort.scale;
      if (bottomSurface <= 0) {
        rowsClipped++;
      } else {
        rowsVisible++;
      }
    }
    stdout.writeln(
      'probe.overflow page=300x150 margin=${engine.style.pageMargin} '
      'content_bottom=$contentBottom '
      'system_top=${firstSystem.bounds.top.toStringAsFixed(2)} '
      'system_height=${firstSystem.bounds.size.height.toStringAsFixed(2)} '
      'system_bottom=${firstSystem.bounds.bottom.toStringAsFixed(2)} '
      'overflows_top_by='
      '${(engine.style.pageMargin - firstSystem.bounds.top).toStringAsFixed(2)} '
      'stave_top=${firstSystem.bars.first.bounds.top.toStringAsFixed(2)} '
      'stave_bottom='
      '${firstSystem.bars.first.bounds.bottom.toStringAsFixed(2)} '
      'rows_visible=$rowsVisible rows_clipped=$rowsClipped '
      'rows=${firstSystem.bars.first.textCues.length}',
    );
    _report(
      'too-short-first-page',
      firstShort,
      shortPage.document,
      firstShort.scale,
      _bandOf(firstSystem, engine.style),
    );
    await _renderToPng(
      firstShort,
      shortPage.song,
      metrics,
      shortPage.document,
      File('${outDir.path}${Platform.pathSeparator}too-short@2x.png'),
      logicalWidth: shortWidth,
      logicalHeight: shortHeight,
    );
  });
}
