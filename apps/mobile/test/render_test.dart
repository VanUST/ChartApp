// PURPOSE: Render the ground-truth song "В Парке Чаир 1" from the owner's real export to PNG files,
//          headlessly, so the layout can be inspected without starting a window. `flutter test`
//          runs the real Flutter engine with no window, so the painting here is the same painting
//          the application does; only the target differs (an image instead of a screen). It exists
//          because a window on this machine takes focus away from whoever is working at it, and an
//          agent that pops one to look at its own output interferes with its user. The same test
//          renders the song in a requested key, so a transposition can be checked by eye against
//          the PNG and against the chord list printed beside it.
// INPUTS: The owner's export, named by the IREAL_RENDER_EXPORT environment variable — NOT by the
//         value the application ships, which a test must not depend on and which silently silenced
//         this test when it was emptied. A real system font is loaded when one is found,
//         because the framework's default test font draws every glyph as a filled box and a page
//         of boxes proves the layout but nothing about the text. IREAL_RENDER_TRANSPOSE selects a
//         key by the interval the twelve-key grid uses.
// OUTPUTS: PNGs in the render output directory outside the repository, named for the song and the
//          key, with their paths, page count, bar count and the chord of every bar printed to
//          stdout. The test is SKIPPED when the owner's file is absent, so the suite stays green on
//          a machine that does not have the export.
// KEYWORDS: headless-render, png, ground-truth, chair, page-layout, offscreen, no-window, font,
//           transposition, two-keys
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/ireal_source.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logical page width: a Galaxy Tab S8+ viewport once 1752 physical pixels are divided by the
/// device pixel ratio 2.125.
const double renderPageWidth = 824;

/// The logical page height, from the same 2800 physical pixels.
const double renderPageHeight = 1318;

/// The title of the song verified bar for bar against the owner's iReal Pro screenshots.
const String renderSongTitle = 'В Парке Чаир 1';

/// Where the PNGs are written. Outside the repository on purpose: a rendered image is evidence for
/// one inspection, not an artefact to commit, and a chart of someone's song does not belong in a
/// public repository.
const String renderOutputDirectory = r'C:\projects\ChartApp-acl-reports\render';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

// PURPOSE: Read the owner's export and parse every song it holds, through the same loader the
//          viewer uses, so the render exercises the real import path end to end.
// INPUTS: None.
// OUTPUTS: The parsed library, or null when the file or its `irealb://` link is absent.
// KEYWORDS: owner-file, export, parse, load, shared-path
IRealLibrary? _loadOwnerLibrary(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final RegExpMatch? link = RegExp('irealb://([^"]*)')
      .firstMatch(file.readAsStringSync());
  if (link == null) {
    return null;
  }
  return parseIRealLibrary(Uri.decodeFull(link.group(1)!));
}

// PURPOSE: Find a song by its exact title, so the render names the tune it expects instead of
//          depending on an index a re-export could change.
// INPUTS: library — the parsed library. title — the exact title to match.
// OUTPUTS: The matching entry, or null when no song has that title.
// KEYWORDS: lookup, title, ground-truth, null-safe
/// The first song whose title CONTAINS [title], compared case-insensitively.
///
/// A substring rather than an exact match, because this is driven from the environment as a filter
/// and typing a full Cyrillic title there is both unnecessary and easy to get subtly wrong. The
/// first match wins, and the caller prints the title it actually rendered, so a filter that
/// matched something unintended is visible in the output rather than silent.
IRealSong? _songTitled(IRealLibrary library, String title) {
  final String needle = title.toLowerCase();
  for (final IRealSong entry in library.songs) {
    if (entry.title.toLowerCase().contains(needle)) {
      return entry;
    }
  }
  return null;
}

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes cannot be compared against iReal Pro.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists — in which case the render
//          still happens and the caller says on stdout that the image is layout-only.
// KEYWORDS: font, font-loader, readable-text, graceful-degradation
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

// PURPOSE: Build the metrics the page is measured and drawn with, in one family, so the layout and
//          the pixels agree.
// INPUTS: family — the loaded font family, or null to use the framework default.
// OUTPUTS: A [FlutterTextMetrics] whose four styles share that family.
// KEYWORDS: metrics, styles, font-family, measure-and-draw-agreement
FlutterTextMetrics _metricsFor(String? family) {
  return FlutterTextMetrics(
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
}

// PURPOSE: Paint one page into a PNG at a device pixel ratio, which is what makes the same logical
//          layout inspectable on a high-density screen.
// INPUTS: page — the layout to paint. song — the model the page came from. metrics — the metrics
//         the layout was measured with. pixelRatio — 1.0 for logical pixels, 2.0 for double.
//         out — the file to write.
// OUTPUTS: Writes the PNG and returns nothing. The image and picture are disposed, because they
//          hold engine-side memory.
// KEYWORDS: paint, picture-recorder, to-image, png, pixel-ratio, dispose
Future<void> _renderPageToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  double pixelRatio,
  File out,
) async {
  final int pixelWidth = (renderPageWidth * pixelRatio).round();
  final int pixelHeight = (renderPageHeight * pixelRatio).round();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  // The canvas is scaled BEFORE the painter runs, so text is laid out at the logical size it was
  // measured at and then rasterised at a higher density. Scaling the output instead would blur it,
  // and scaling the logical size would move every chord, because the page is a fixed logical size.
  canvas.scale(pixelRatio);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
  ).paint(canvas, const ui.Size(renderPageWidth, renderPageHeight));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(pixelWidth, pixelHeight);
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

  // NAMED BY THE RUNNER, NOT BY THE PRODUCT. This used to be `File(defaultIRealPath)` — the value the
  // application ships as the path it opens on launch. That is a coupling between a test and a
  // production default, and it broke silently the moment the default was emptied for a good reason
  // (an absolute path from one developer's home directory was compiled into the Android build and
  // opened the app on a red error on the tablet). Emptying it turned this test from PASSING into
  // SKIPPED, so the suite stayed green while a real render against the owner's own export stopped
  // being exercised. A test that stops running because a product default changed is a test whose
  // green means less than it looks.
  //
  // IREAL_RENDER_EXPORT names the file explicitly. Unset, the test skips and SAYS SO, which is the
  // honest outcome on a machine that does not hold the owner's export — CI included.
  final File fixture = File(Platform.environment['IREAL_RENDER_EXPORT'] ?? '');

  // Overridable, because a verification instrument that can only render one song stops being one
  // the moment a different song needs checking. IREAL_RENDER_SONG takes a title substring and
  // IREAL_RENDER_OUT an output directory; the file names follow the song so two renders do not
  // overwrite each other.
  final String song =
      Platform.environment['IREAL_RENDER_SONG'] ?? renderSongTitle;
  final String outputDirectory =
      Platform.environment['IREAL_RENDER_OUT'] ?? renderOutputDirectory;
  final String slug = song.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  // The interval the twelve-key grid uses: -5..+6, 0 for the written key. Anything else is
  // rejected rather than silently clamped, because a render that quietly shows a different key
  // than the one asked for is worse than no render.
  final int transpose =
      int.tryParse(Platform.environment['IREAL_RENDER_TRANSPOSE'] ?? '0') ?? 0;

  test(
    'renders $song to PNG files without opening a window',
    () async {
      // THE SAME PATH the skip above checked. Reading it from the production default instead is what
      // turned this from a skipped test into a CRASHING one — `_loadOwnerLibrary('')` answers null and
      // the `!` throws, so a machine without the export would fail rather than skip.
      final IRealLibrary library = _loadOwnerLibrary(fixture.path)!;
      final IRealSong? entry = _songTitled(library, song);
      expect(entry, isNotNull, reason: 'the owner export must contain "$song"');
      final Song written = entry!.song;
      final TranspositionTarget target = const TranspositionGrid()
          .targets(written.key)
          .firstWhere(
            (TranspositionTarget candidate) => candidate.semitones == transpose,
            orElse: () => throw StateError(
              'IREAL_RENDER_TRANSPOSE=$transpose is outside the twelve-key '
              'grid interval range -5..+6',
            ),
          );
      final Song shown = transpose == 0
          ? written
          : transposeSong(written, transpose, toKey: target.key);
      const SpellingTable renderTable = SpellingTable();
      final String keySlug = shown.key.toString().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        '-',
      );

      final String? family = await _loadChartFont();
      if (family == null) {
        stdout.writeln(
          'render.font none reason=no-candidate-found '
          '(glyphs will be boxes; the image proves layout only)',
        );
      }
      final FlutterTextMetrics metrics = _metricsFor(family);
      // The engine MUST take the same metrics instance the painter does, or a chord is drawn into a
      // box that was measured with a different font.
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
      // IREAL_RENDER_FIT=1 renders the FIT page instead of the first paginated one, so the scaled
      // page can be looked at rather than only asserted about.
      final bool fitMode = Platform.environment['IREAL_RENDER_FIT'] == '1';
      final List<PageLayout> pages;
      double fitScale = 1;
      if (fitMode) {
        final FitOutcome fit = engine.fitToPage(
          shown,
          pageWidth: renderPageWidth,
          pageHeight: renderPageHeight,
        );
        final PageLayout? fitted = fit.page;
        expect(
          fitted,
          isNotNull,
          reason:
              'FIT must put the song on one page at a scale of at least '
              '${LayoutEngine.minLegibleScale}, but it reported '
              '${fit.scale}',
        );
        fitScale = fit.scale;
        pages = <PageLayout>[fitted!];
      } else {
        pages = engine.layout(
          shown,
          pageWidth: renderPageWidth,
          pageHeight: renderPageHeight,
        );
      }
      expect(
        pages,
        isNotEmpty,
        reason: 'a song with bars must lay out to a page',
      );

      final String labels = pages.first.systems
          .where((PlacedSystem system) => system.sectionLabel != null)
          .map((PlacedSystem system) => system.sectionLabel)
          .join(',');
      stdout.writeln(
        'render.song title="${entry.title}" written=${written.key} '
        'shown=${shown.key} transpose=$transpose mode=${fitMode ? 'fit' : 'pages'} '
        'bars=${shown.writtenBarCount} sections=${shown.sections.length} '
        'issues=${entry.issues.length} pages=${pages.length} '
        'fit_scale=$fitScale '
        'page_logical=${renderPageWidth}x$renderPageHeight',
      );
      for (final IRealParseIssue issue in entry.issues) {
        stdout.writeln('render.issue @${issue.offset}: ${issue.message}');
      }
      // Every bar's chords in the shown key, printed with the beat they sit on, so the
      // transposition and the cells the chords occupy can be checked against the PNG.
      stdout.writeln('render.chords key=${shown.key}');
      for (final Section section in shown.sections) {
        for (int index = 0; index < section.bars.length; index++) {
          final Bar bar = section.bars[index];
          final String chords = bar.chords
              .map(
                (BeatChord placed) =>
                    '${placed.beat}.${placed.step}'
                    '=${placed.chord.render(shown.key, renderTable)}',
              )
              .join(' ');
          stdout.writeln(
            'render.chord ${section.label}[$index] '
            '${chords.isEmpty ? '(none)' : chords}',
          );
        }
      }
      stdout.writeln(
        'render.page1 bars=${pages.first.bars.length} '
        'systems=${pages.first.systems.length} labels=$labels',
      );

      final Directory outDir = Directory(outputDirectory);
      outDir.createSync(recursive: true);
      for (final double ratio in <double>[1.0, 2.0]) {
        final String name = ratio == 1.0
            ? '$slug-$keySlug-page-1${fitMode ? '-fit' : ''}.png'
            : '$slug-$keySlug-page-1${fitMode ? '-fit' : ''}@2x.png';
        final File out = File('${outDir.path}${Platform.pathSeparator}$name');
        await _renderPageToPng(pages.first, shown, metrics, ratio, out);
        stdout.writeln(
          'render.wrote path=${out.path} bytes=${out.lengthSync()} '
          'pixels=${(renderPageWidth * ratio).round()}x'
          '${(renderPageHeight * ratio).round()}',
        );
      }
    },
    skip: fixture.existsSync()
        ? null
        : 'set IREAL_RENDER_EXPORT to the owner\'s iReal export to run this render; '
            'nothing exists at "${fixture.path}" on this machine',
  );
}
