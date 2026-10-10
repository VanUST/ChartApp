// PURPOSE: Verify the SCENE meaning of owner decision D14 through the application rather than beside
//          it, and produce PNGs of the result so the difference can be looked at instead of only
//          asserted. It has two halves: a widget test that drives the real viewer — opens the
//          programme sheet, edits an entry's transposition, plays the entry — and reads the app's own
//          verification handoff to show the CHART DOCUMENT's key beside the key the page is SHOWN in;
//          and a headless render that writes the written chart, the same chart through a +2 entry,
//          and a FITTED page, because a fitted page is where geometry goes quietly wrong.
// INPUTS: None. The chart is a synthetic iReal payload written in this file, in D major with
//         `D^ | E7 | D^ | E7`, so the run never reads the owner's export and never opens a window.
//         SETLIST_RENDER_OUT overrides the PNG directory.
// OUTPUTS: PNGs in the render output directory outside the repository, and printed measurements —
//          the written and shown keys, every bar's chord in both, and the fit scale — so the images
//          and the printed values can be checked against each other.
// KEYWORDS: test, widget, setlist, scene-transposition, D14, headless-render, png, fit, written-key
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ink_pointer_probe_contract.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/setlist_import.dart';
import 'package:chartapp/viewer_screen.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this file names
// the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The key the synthetic chart is written in, as the scene interval is measured from it.
const Key _dMajor = Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major);

/// The logical page width a fitted render is measured at, the same surface `render_test.dart` uses.
const double _pageWidth = 824;

/// The logical page height of the same surface.
const double _pageHeight = 1318;

/// Where the PNGs are written. Outside the repository on purpose: an image is evidence for one
/// inspection, not an artefact to commit.
const String _defaultOutputDirectory =
    r'C:\projects\ChartApp-acl-reports\render';

/// The family name a loaded system font is registered under.
const String _fontFamily = 'SetlistRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

// PURPOSE: Build a one-song payload in D major with the chord pair the scene proof checks, so the
//          chart goes through the real import path.
// INPUTS: None. The notation is written here and obfuscated with the library's own encoder, so the
//         payload cannot drift from the codec.
// OUTPUTS: A decoded payload string whose one song is `D^ | E7 | D^ | E7`.
// KEYWORDS: fixture, synthetic-payload, d-major, obfuscation, ten-field-layout
String _syntheticPayload() {
  const String notation = '*AT44D^ |E7 |D^ |E7 Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  return 'Test Tune=Test Composer==Medium Swing=D=0=$music=Medium Swing=120=1';
}

// PURPOSE: Build a two-song playlist payload, so the programme sheet has two charts to order and the
//          insert/move/delete operations act on a running order rather than on one row.
// INPUTS: None.
// OUTPUTS: A decoded payload whose two songs are both `D^ | E7 | D^ | E7` under the playlist name
//          `Test Playlist`, with distinct titles.
// KEYWORDS: fixture, playlist, two-songs, running-order, sheet-operations
String _twoSongPlaylist() {
  const String notation = '*AT44D^ |E7 |D^ |E7 Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  final String first = 'First Tune=Composer==Twist=D=0=$music=Twist=120=1';
  final String second = 'Second Tune=Composer==Swing=D=0=$music=Swing=120=1';
  return '$first===$second===Test Playlist';
}

// PURPOSE: Build a long one-song payload, so the FITTED render exercises the scaled geometry rather
//          than a page that fits at scale 1. A four-bar chart fits a page untouched, and a page that
//          never scales cannot show whether scaling is right — which is exactly the failure mode the
//          fitted render exists to catch.
// INPUTS: bars — how many bars of alternating `D^` and `E7` to write.
// OUTPUTS: A decoded payload string whose one song is [bars] bars long, in D major.
// KEYWORDS: fixture, long-chart, fit-geometry, scaled-page, d-major
String _longSyntheticPayload({int bars = 300}) {
  final List<String> chords = <String>[
    for (int index = 0; index < bars; index++) index.isEven ? 'D^ ' : 'E7 ',
  ];
  final String notation = '*AT44${chords.join('|')} Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  return 'Long Tune=Test Composer==Medium Swing=D=0=$music=Medium Swing=120=1';
}

/// The painter the viewer is currently showing.
ChartPainter _shownPainter(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  return tester.widget<CustomPaint>(finder).painter! as ChartPainter;
}

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes cannot be read back.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists — the render still happens
//          and the caller says on stdout that the image is layout-only.
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
    stdout.writeln('setlist.render.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Build the metrics the page is measured and drawn with, in one family, so the layout and
//          the pixels agree.
// INPUTS: family — the loaded font family, or null to use the framework default.
// OUTPUTS: A [FlutterTextMetrics] whose four styles share that family.
// KEYWORDS: metrics, styles, font-family, measure-and-draw-agreement
FlutterTextMetrics _metricsFor(String? family) => FlutterTextMetrics(
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

// PURPOSE: Build the engine every render in this file lays out with, so the written page and the
//          scene page are measured by the same rules and their difference is the transposition
//          rather than the layout.
// INPUTS: metrics — the metrics the engine must measure with.
// OUTPUTS: A [LayoutEngine] with the viewer's own style values.
// KEYWORDS: layout-engine, shared-style, viewer-parity
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

// PURPOSE: Paint one page into a PNG at a device pixel ratio, which is what makes a logical layout
//          inspectable.
// INPUTS: page — the layout to paint. song — the model the page came from. metrics — the metrics the
//         layout was measured with. surface — the drawable size, `page.size * page.scale`, which is
//         the space the painter scales its own geometry into. pixelRatio — 1.0 or 2.0. out — the
//         file to write.
// OUTPUTS: Writes the PNG and returns nothing. The image and picture are disposed.
// KEYWORDS: paint, picture-recorder, to-image, png, pixel-ratio, dispose
Future<void> _renderPageToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  Size surface,
  double pixelRatio,
  File out,
) async {
  final int pixelWidth = (surface.width * pixelRatio).round();
  final int pixelHeight = (surface.height * pixelRatio).round();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  ChartPainter(song: song, page: page, metrics: metrics).paint(canvas, surface);
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

// PURPOSE: Read every bar's first chord of [song] in [key], so two charts can be compared by what a
//          musician reads rather than by the key label alone.
// INPUTS: song — the chart. key — the key to spell the chords in.
// OUTPUTS: One string per bar, `-` for a bar with no chord.
// KEYWORDS: chord-list, render, comparison, reading-order
List<String> _chordsOf(Song song, Key key) {
  const SpellingTable table = SpellingTable();
  return <String>[
    for (final Bar bar in song.barsInReadingOrder)
      bar.chords.isEmpty ? '-' : bar.chords.first.chord.render(key, table),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Directory outputDirectory = Directory(
    Platform.environment['SETLIST_RENDER_OUT'] ?? _defaultOutputDirectory,
  );

  // The behavioural half: the real viewer, driven through its own programme sheet.
  testWidgets(
    'a +2 programme entry shows the chart two semitones up while its document keeps the written key',
    (WidgetTester tester) async {
      // A viewport wide enough for the app bar, so the new programme action cannot be pushed out of
      // the bar by the actions beside it and the test measures the feature rather than the layout.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final IRealLibrary library = parseIRealLibrary(_syntheticPayload());
      await tester.pumpWidget(
        MaterialApp(
          home: IRealViewerScreen(
            loader: (String path) async => library,
            initialPath: 'synthetic',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The chart opens in its written key, with no programme entry in force.
      final ChartPainter written = _shownPainter(tester);
      expect(written.song.key, _dMajor);
      expect(_chordsOf(written.song, written.song.key), <String>[
        'D^',
        'E7',
        'D^',
        'E7',
      ]);
      final Map<String, Object?> seeded =
          inkStateReader()['programme'] as Map<String, Object?>? ??
          const <String, Object?>{};
      expect(
        seeded['depth_undo'],
        0,
        reason: 'the import alone is not an edit',
      );
      expect(seeded['items']! as List<Object?>, hasLength(1));
      stdout.writeln(
        'setlist.seeded programme=${seeded['id']} items=${seeded['items']}',
      );

      // Open the programme and give its one entry a +2 transposition through the sheet.
      await tester.tap(find.byKey(const ValueKey<String>('viewer-setlist')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('setlist-items')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('setlist-edit-0')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('setlist-transpose-up')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('setlist-transpose-up')),
      );
      await tester.pump();
      expect(find.text('+2 st'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('setlist-edit-ok')));
      await tester.pumpAndSettle();

      // The entry carries the interval, and the setlist log explains it as an update.
      Map<String, Object?> programme =
          (inkStateReader()['programme'] as Map<String, Object?>?) ??
          const <String, Object?>{};
      expect(programme['scene'], isNull, reason: 'editing is not playing');
      expect((programme['items']! as List<Object?>).first, <String, Object?>{
        'documentId': 'ireal-0',
        'transposeSem': 2,
        'notes': '',
      });
      stdout.writeln(
        'setlist.edited scene=${programme['scene']} items=${programme['items']} '
        'log=${programme['log']} depth_undo=${programme['depth_undo']}',
      );

      // Play the entry. This is what "reached from the setlist" means in the application.
      await tester.tap(find.byKey(const ValueKey<String>('setlist-play-0')));
      await tester.pumpAndSettle();

      final ChartPainter shown = _shownPainter(tester);
      expect(shown.song.key.toString(), 'E major');
      expect(_chordsOf(shown.song, shown.song.key), <String>[
        'E^',
        'F#7',
        'E^',
        'F#7',
      ]);
      programme =
          (inkStateReader()['programme'] as Map<String, Object?>?) ??
          const <String, Object?>{};
      expect(programme['scene'], 0, reason: 'entry 0 is the one playing');
      // THE PAIR THAT SETTLES THE CLAIM: the document still says D major and the page is shown in
      // E major, both read from the application's own handoff after the tap.
      expect(programme['writtenKey'], 'D major');
      expect(programme['shownKey'], 'E major');
      expect(programme['shownSemitones'], 2);
      stdout.writeln(
        'setlist.playing scene=${programme['scene']} '
        'writtenKey=${programme['writtenKey']} shownKey=${programme['shownKey']} '
        'shownSemitones=${programme['shownSemitones']} '
        'shown_chords=${_chordsOf(shown.song, shown.song.key)}',
      );

      // The PNGs from the application's own painters: the chart as written and the same chart as the
      // programme entry shows it. The scene bar's POS field must read 1/1, the programme's position.
      expect(find.text('1/1'), findsOneWidget);
      // RUN ASYNC, because `toImage`/`toByteData` need the engine's real event loop and a widget
      // test's fake-async zone does not pump it: the first encode completes and the next waits
      // forever, which is a hang rather than a failure.
      await tester.runAsync(() async {
        for (final (String name, ChartPainter painter)
            in <(String, ChartPainter)>[
              ('setlist-written', written),
              ('setlist-scene-plus2', shown),
            ]) {
          final Size surface = Size(
            painter.page.size.width * painter.page.scale,
            painter.page.size.height * painter.page.scale,
          );
          final File out = File(
            '${outputDirectory.path}${Platform.pathSeparator}$name.png',
          );
          await _renderPageToPng(
            painter.page,
            painter.song,
            painter.metrics,
            surface,
            2,
            out,
          );
          stdout.writeln(
            'setlist.render.wrote path=${out.path} bytes=${out.lengthSync()} '
            'key=${painter.song.key} surface='
            '${surface.width.toStringAsFixed(1)}x'
            '${surface.height.toStringAsFixed(1)} scale=${painter.page.scale}',
          );
        }
      });
    },
  );

  // The sheet half: every operation the programme list offers is driven through the real sheet, and
  // the log it leaves is what makes each one an undoable edit rather than a list mutation.
  testWidgets(
    'the programme sheet renames, inserts, moves and deletes through the setlist log',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final IRealLibrary library = parseIRealLibrary(_twoSongPlaylist());
      await tester.pumpWidget(
        MaterialApp(
          home: IRealViewerScreen(
            loader: (String path) async => library,
            initialPath: 'synthetic',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('viewer-setlist')));
      await tester.pumpAndSettle();

      List<String> log() =>
          ((inkStateReader()['programme'] as Map<String, Object?>? ??
                      const <String, Object?>{})['log']!
                  as List<Object?>)
              .cast<String>();
      List<Object?> items() =>
          (inkStateReader()['programme'] as Map<String, Object?>? ??
                  const <String, Object?>{})['items']!
              as List<Object?>;
      // The import seeded one entry per song, in payload order.
      expect(items(), hasLength(2));
      expect((items().first! as Map<String, Object?>)['documentId'], 'ireal-0');

      // Rename, committed through the field's own submit action.
      await tester.enterText(
        find.byKey(const ValueKey<String>('setlist-title')),
        'Friday night',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        (inkStateReader()['programme']! as Map<String, Object?>)['title'],
        'Friday night',
      );

      // Insert a chart: the picker lists the loaded library, and a duplicate is legal.
      await tester.tap(find.byKey(const ValueKey<String>('setlist-insert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('setlist-add-0')));
      await tester.pumpAndSettle();
      expect(items(), hasLength(3));

      // Move the second entry to the front, then remove the first entry.
      await tester.tap(find.byKey(const ValueKey<String>('setlist-up-1')));
      await tester.pumpAndSettle();
      // Delete is only allowed on a row the list still has, so read the count back first.
      await tester.tap(find.byKey(const ValueKey<String>('setlist-delete-0')));
      await tester.pumpAndSettle();
      expect(items(), hasLength(2));
      expect(log(), <String>[
        'setlist.rename',
        'setlist.item.insert',
        'setlist.item.move',
        'setlist.item.delete',
      ]);
      // The deleted ENTRY is what undo must restore, not a blank row: compare the whole first item.
      final Map<String, Object?> beforeDelete = <String, Object?>{
        'documentId': 'ireal-1',
        'transposeSem': 0,
        'notes': '',
      };
      await tester.tap(find.byKey(const ValueKey<String>('setlist-undo')));
      await tester.pumpAndSettle();
      expect(items(), hasLength(3));
      expect(items().first, beforeDelete);
      stdout.writeln(
        'setlist.sheet log=${log()} items_after_undo=${items().length} '
        'first=${items().first}',
      );
    },
  );

  // The geometry half: the same scene chart fitted to one page, where a wrong scale shows up as a
  // page that does not fit rather than as a wrong chord.
  test('renders the written, the +2 scene and a FITTED scene page to PNG', () async {
    final IRealLibrary library = parseIRealLibrary(_syntheticPayload());
    final IRealSong entry = library.songs.single;
    final Song written = entry.song;

    // The app's own path: import the playlist to a setlist, edit the one entry through the setlist
    // session, and resolve what the stage draws through `setlistSceneFor`.
    final SetlistSession session = SetlistSession(
      setlist: importedSetlist(library),
    );
    final bool edited = session.updateItem(
      0,
      transposeSem: 2,
      notes: 'chorus twice',
    );
    final SetlistScene scene = setlistSceneFor(
      entry: session.items.single,
      written: written,
    );
    stdout.writeln(
      'setlist.probe edited=$edited written=${written.key} shown=${scene.shownKey} '
      'semitones=${scene.semitones} scene=$scene',
    );
    expect(edited, isTrue);
    expect(scene.shownKey.toString(), 'E major');
    expect(written.key, _dMajor);
    expect(_chordsOf(written, written.key), <String>['D^', 'E7', 'D^', 'E7']);
    expect(_chordsOf(scene.shown, scene.shownKey), <String>[
      'E^',
      'F#7',
      'E^',
      'F#7',
    ]);

    final String? family = await _loadChartFont();
    if (family == null) {
      stdout.writeln(
        'setlist.render.font none reason=no-candidate-found '
        '(glyphs will be boxes; the image proves layout only)',
      );
    }
    final FlutterTextMetrics metrics = _metricsFor(family);
    final LayoutEngine engine = _engineFor(metrics);

    Future<void> write(
      String name,
      PageLayout page,
      Song song,
      double ratio,
    ) async {
      final Size surface = Size(
        page.size.width * page.scale,
        page.size.height * page.scale,
      );
      final File out = File(
        '${outputDirectory.path}${Platform.pathSeparator}$name.png',
      );
      await _renderPageToPng(page, song, metrics, surface, ratio, out);
      stdout.writeln(
        'setlist.render.wrote path=${out.path} bytes=${out.lengthSync()} '
        'key=${song.key} mode=${page.scale == 1 ? 'pages' : 'fit'} '
        'scale=${page.scale} surface='
        '${surface.width.toStringAsFixed(1)}x'
        '${surface.height.toStringAsFixed(1)}',
      );
    }

    final List<PageLayout> writtenPages = engine.layout(
      written,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    final List<PageLayout> scenePages = engine.layout(
      scene.shown,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    expect(writtenPages, isNotEmpty);
    expect(scenePages, isNotEmpty);
    // The same bars, in the same places: a transposition moves the labels, not the form.
    expect(
      writtenPages.first.bars.length,
      scenePages.first.bars.length,
      reason: 'the scene chart must have the same bars in the same systems',
    );
    stdout.writeln(
      'setlist.render.pages written_bars=${writtenPages.first.bars.length} '
      'scene_bars=${scenePages.first.bars.length} '
      'written_chords=${_chordsOf(written, written.key)} '
      'scene_chords=${_chordsOf(scene.shown, scene.shownKey)}',
    );
    await write('setlist-standalone-written', writtenPages.first, written, 2);
    await write(
      'setlist-standalone-scene-plus2',
      scenePages.first,
      scene.shown,
      2,
    );

    // THE FITTED PAGE, on a chart long enough that the scale is genuinely below 1: this is where a
    // wrong scale shows as a page that does not fit or a chord drawn outside its cell. The same
    // app path is used — import to a setlist, edit the entry, resolve the scene — so the fitted page
    // is the SCENE chart, not a chart that merely happens to be transposed.
    final IRealLibrary longLibrary = parseIRealLibrary(_longSyntheticPayload());
    final Song longWritten = longLibrary.songs.single.song;
    final SetlistSession longSession = SetlistSession(
      setlist: importedSetlist(longLibrary),
    );
    final bool longEdited = longSession.updateItem(0, transposeSem: 2);
    final SetlistScene longScene = setlistSceneFor(
      entry: longSession.items.single,
      written: longWritten,
    );
    expect(longEdited, isTrue);
    expect(longWritten.key, _dMajor);
    expect(longScene.shownKey.toString(), 'E major');
    final FitOutcome fit = engine.fitToPage(
      longScene.shown,
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
    );
    final PageLayout? fitted = fit.page;
    expect(
      fitted,
      isNotNull,
      reason:
          'a ${longWritten.writtenBarCount}-bar chart must fit one page at or above '
          '${LayoutEngine.minLegibleScale}, but the engine reported ${fit.scale}',
    );
    expect(
      fit.scale,
      lessThan(1.0),
      reason: 'the fitted page must actually be scaled, or it proves nothing about FIT',
    );
    stdout.writeln(
      'setlist.render.fit written=${longWritten.key} shown=${longScene.shownKey} '
      'written_bars=${longWritten.writtenBarCount} '
      'shown_bars=${longScene.shown.writtenBarCount} scale=${fit.scale} '
      'bars=${fitted!.bars.length} systems=${fitted.systems.length} '
      'page_logical=${_pageWidth}x$_pageHeight',
    );
    await write(
      'setlist-standalone-scene-plus2-fit',
      fitted,
      longScene.shown,
      2,
    );
  });
}
