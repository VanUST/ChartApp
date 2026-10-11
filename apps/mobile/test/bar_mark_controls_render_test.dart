// PURPOSE: LOOK at the four signs a bar can carry — the segno, the coda, the fermata and the
//          player's stop — and prove the controls that set them write the model, clear it again and
//          undo exactly. The instrument drives the REAL form sheet (the buttons a musician presses)
//          against a real [EditSession], and renders the same page before every edit and after it,
//          so what the painter actually drew can be read rather than inferred from a count. A
//          boolean "the mark set changed" cannot show WHICH glyph landed on WHICH bar, and a wrong
//          glyph table is exactly the defect a count would pass.
//
//          The four signs are exercised ONE AT A TIME over the same empty bar, so each PNG shows the
//          one sign its step set — a page carrying all four at once could not tell which glyph came
//          from which button. After the four, two signs are set on one bar at once, because that is
//          the case the model stores as a set and the painter joins into one line of glyphs.
//
//          It also proves the SHEET STAYS OPEN and the PAGE REBUILDS after every press: the sheet's
//          `onChanged` is the harness's `setState`, exactly as the viewer passes it, and the harness
//          reads the page back from `session.song` after each rebuild.
// INPUTS: None. The chart is synthetic and the taps are the product's own buttons, so this runs on
//         any machine. A real system font is loaded when one is found, because the framework's
//         default test font draws every glyph as a filled box and a page of boxes cannot show an
//         `S`, a `C` or a `^`.
// OUTPUTS: PNGs under [markRenderDirectory], outside the repository, named `before`, `after-<mark>`
//          for each of the four signs, and `two-marks`; `mark.*` lines on stdout carrying the marks
//          of the target bar at every step, what undo was compared against, whether the sheet was
//          still open, and where the target bar was placed on the page. Rendering happens under
//          `flutter test`, which runs the real engine with no window: a window on this machine would
//          take focus from whoever is working at it.
// KEYWORDS: headless-render, png, bar-mark, segno, coda, fermata, player-ending, song-form, op-log,
//           undo, exact-restore, sheet-stays-open, rebuild-on-apply, no-window
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/song_form_sheet.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this instrument
// names the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logical page the instrument engraves at.
const double markPageWidth = 640;
const double markPageHeight = 420;

/// Where the PNGs are written. Outside the repository: an image is evidence for one inspection, not
/// an artefact to commit.
const String markRenderDirectory =
    r'C:\projects\ChartApp-acl-reports\render\bar-marks';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartMarkRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The document id the instrument's session writes under.
const String _docId = 'chartapp-bar-marks';

/// The section every control in this instrument acts on.
const String _sectionId = 'A';

/// The bar the four signs are set on and taken off, as a zero-based index: the SECOND bar, so it is
/// not the first bar of the system and a sign drawn at its right edge is inside the page.
const int _targetBar = 1;

// PURPOSE: Build the music this instrument signs: one section of four bars, each carrying a
//          different root on its first cell, so a sign that landed on the wrong bar is visible
//          rather than plausible.
// INPUTS: None.
// OUTPUTS: A four-bar song in C major with no mark anywhere.
// KEYWORDS: fixture, synthetic-song, four-bars, no-marks, visible-chords, bar-identity
Song barMarkChart() => Song(
  id: _docId,
  title: 'Bar marks',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: _sectionId,
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < 4; index++)
          Bar(
            chords: <BeatChord>[
              BeatChord(
                chord: Chord(
                  root: ChordRoot(index * 2),
                  quality: ChordQuality.majorSeventh,
                ),
                beat: 0,
              ),
            ],
          ),
      ],
    ),
  ],
);

/// The metrics the page is measured and drawn with, in the loaded family.
///
/// The staff-text style is deliberately larger than the viewer's: the signs this instrument is
/// looking at are drawn in that style, and a 10-pixel glyph in a scaled-down inspection image is a
/// smudge rather than an `S`.
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
    fontSize: 16,
    color: const Color(0xFF486581),
  ),
);

/// The engine the pages are produced with: the viewer's own spacing constants, with a taller bar so
/// the larger sign style does not lie on the chord under it.
LayoutEngine _layoutEngine(FlutterTextMetrics metrics) => LayoutEngine(
  style: LayoutStyle(
    textMetrics: metrics,
    pageMargin: 20,
    barMinWidth: 64,
    barPadding: 8,
    chordSpacing: 12,
    minCellWidth: 18,
    barHeight: 58,
    systemSpacing: 18,
    sectionLabelHeight: 26,
  ),
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes cannot show an `S`, a `C` or a `^`.
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
    stdout.writeln('mark.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Paint one page into a PNG.
// INPUTS: page — the layout to draw. song — the model it came from. metrics — how it is engraved.
//         out — where the bytes go. logicalWidth and logicalHeight — the surface the painter is
//         handed.
// OUTPUTS: Writes the file. Throws when the engine produced no PNG bytes, because a missing image
//          is not a rendering of "nothing".
// KEYWORDS: paint, picture-recorder, to-image, png, dispose
Future<void> _renderToPng(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  File out, {
  required double logicalWidth,
  required double logicalHeight,
}) async {
  const double pixelRatio = 2;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
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

/// The names of the target bar's marks, in the order the painter would join them.
String _marks(Song song) {
  final Bar? bar = song.barAt(_sectionId, _targetBar);
  if (bar == null) {
    return '[no such bar]';
  }
  return '[${bar.marks.map((BarMark mark) => mark.name).join(', ')}]';
}

/// The harness: the real form sheet over one session, rebuilt the way the viewer rebuilds — the
/// sheet's `onChanged` calls `setState` — so a page read while the sheet is open is the page the
/// musician sees behind it.
class _MarkHarness extends StatefulWidget {
  const _MarkHarness({required this.session});

  /// The document being edited.
  final EditSession session;

  @override
  State<_MarkHarness> createState() => _MarkHarnessState();
}

/// The harness state: how many times a press asked the page to rebuild.
class _MarkHarnessState extends State<_MarkHarness> {
  int _rebuilds = 0;

  /// Opens the product's form sheet on [barIndex], with the same rebuild callback the viewer passes.
  Future<void> _open(int barIndex) => showSongForm(
    context,
    session: widget.session,
    sectionId: _sectionId,
    barIndex: barIndex,
    onChanged: () => setState(() => _rebuilds++),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        Text(
          'rebuilds=$_rebuilds',
          key: const ValueKey<String>('harness-rebuilds'),
        ),
        TextButton(
          key: const ValueKey<String>('harness-open-target'),
          onPressed: () => _open(_targetBar),
          child: const Text('open the target bar'),
        ),
      ],
    ),
  );
}

/// Whether the form sheet is still on screen, which is the "the sheet survives the edit" claim.
bool _sheetOpen(WidgetTester tester) =>
    find.byKey(const ValueKey<String>('song-form-done')).evaluate().isNotEmpty;

/// The number of page rebuilds the sheet has asked the harness for.
int _rebuilds(WidgetTester tester) => int.parse(
  tester
          .widget<Text>(find.byKey(const ValueKey<String>('harness-rebuilds')))
          .data
          ?.split('=')
          .last ??
      '0',
);

// PURPOSE: Lay out and render the current page, printing where the target bar landed so the PNG can
//          be read against the model.
// INPUTS: tester — the running widget test. session — the session holding the page's song. metrics
//         and engine — how it is engraved. out — the PNG to write.
// OUTPUTS: Nothing. Prints one `mark.wrote` line with the file, its size, the page's own size and
//          the target bar's rectangle.
// KEYWORDS: render, page-layout, target-bar-rect, evidence
Future<void> _renderPage(
  WidgetTester tester,
  EditSession session,
  FlutterTextMetrics metrics,
  LayoutEngine engine,
  File out,
) async {
  await tester.runAsync(() async {
    final List<PageLayout> pages = engine.layout(
      session.song,
      pageWidth: markPageWidth,
      pageHeight: markPageHeight,
    );
    expect(pages, hasLength(1), reason: 'the fixture is meant to be one page');
    await _renderToPng(
      pages.single,
      session.song,
      metrics,
      out,
      logicalWidth: markPageWidth,
      logicalHeight: markPageHeight,
    );
    final PlacedBar placed = pages.single.bars.firstWhere(
      (PlacedBar bar) =>
          bar.sectionId == _sectionId && bar.barIndex == _targetBar,
    );
    stdout.writeln(
      'mark.wrote file=${out.path} bytes=${out.lengthSync()} '
      'marks=${_marks(session.song)} '
      'page=(${pages.single.size.width},${pages.single.size.height}) '
      'bar_rect=(${placed.bounds.left},${placed.bounds.top},'
      '${placed.bounds.size.width},${placed.bounds.size.height})',
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the four bar-mark controls set, clear and undo each sign', (
    WidgetTester tester,
  ) async {
    final String? family = await tester.runAsync<String?>(_loadChartFont);
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show an `S`, a `C` or a `^`',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutEngine engine = _layoutEngine(metrics);
    final Directory outDir = Directory(markRenderDirectory);
    outDir.createSync(recursive: true);
    String path(String name) => '${outDir.path}${Platform.pathSeparator}$name';

    final EditSession session = EditSession(
      document: DocumentState(song: barMarkChart()),
      docId: _docId,
    );

    // --- BEFORE --------------------------------------------------------------------------------
    stdout.writeln('mark.before marks=${_marks(session.song)}');
    await _renderPage(
      tester,
      session,
      metrics,
      engine,
      File(path('before@2x.png')),
    );

    await tester.pumpWidget(
      MaterialApp(
        // The application's own delegates, so anything the harness renders comes from the same
        // catalogue the application uses.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _MarkHarness(session: session),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('harness-open-target')));
    await tester.pumpAndSettle();
    expect(
      _sheetOpen(tester),
      isTrue,
      reason: 'the sheet must be open to press',
    );
    stdout.writeln(
      'mark.sheet stage=opened open=${_sheetOpen(tester)} '
      'rebuilds=${_rebuilds(tester)} bar=$_targetBar',
    );

    // --- EACH SIGN, ONE AT A TIME, ON THE SAME BAR ----------------------------------------------
    for (final BarMark mark in BarMark.values) {
      final DocumentState before = session.document;
      final int rebuildsBefore = _rebuilds(tester);
      final Finder button = find.byKey(
        ValueKey<String>('song-form-mark-${mark.name}'),
      );
      expect(
        button,
        findsOneWidget,
        reason: 'one button per sign: ${mark.name}',
      );

      // SET. The tap is the product's own button; nothing here calls the session directly.
      await tester.tap(button);
      await tester.pumpAndSettle();
      final DocumentState applied = session.document;
      final bool changed = applied != before;
      final bool rebuilt = _rebuilds(tester) > rebuildsBefore;
      await _renderPage(
        tester,
        session,
        metrics,
        engine,
        File(path('after-${mark.name}@2x.png')),
      );
      stdout.writeln(
        'mark.set sign=${mark.name} changed=$changed marks=${_marks(session.song)} '
        'type=${session.log.last.type} sheet_open=${_sheetOpen(tester)} '
        'page_rebuilt=$rebuilt',
      );
      expect(changed, isTrue, reason: '${mark.name} must change the document');
      expect(
        _sheetOpen(tester),
        isTrue,
        reason: 'the sheet must survive setting ${mark.name}',
      );
      expect(
        rebuilt,
        isTrue,
        reason: 'the page must follow the edit on the same press',
      );

      // UNDO, compared against the WHOLE state rather than the one field that changed.
      final bool undone = session.undo();
      final DocumentState restored = session.document;
      final bool redone = session.redo();
      final DocumentState reapplied = session.document;
      stdout.writeln(
        'mark.undo sign=${mark.name} undone=$undone '
        'restored_equal_before=${restored == before} '
        'song_equal=${restored.song == before.song} '
        'redone=$redone reapplied_equal_applied=${reapplied == applied} '
        'marks=${_marks(session.song)}',
      );
      expect(
        undone,
        isTrue,
        reason: 'undo must be available after ${mark.name}',
      );
      expect(
        restored,
        before,
        reason: 'undo of ${mark.name} must restore the whole DocumentState',
      );
      expect(
        redone,
        isTrue,
        reason: 'redo must be available after ${mark.name}',
      );
      expect(
        reapplied,
        applied,
        reason: 'redo of ${mark.name} must put the edit back exactly',
      );

      // CLEAR, through the same button, so the bar is empty again for the next sign.
      await tester.tap(button);
      await tester.pumpAndSettle();
      final bool cleared = session.document == before;
      stdout.writeln(
        'mark.clear sign=${mark.name} cleared_back_to_before=$cleared '
        'marks=${_marks(session.song)} type=${session.log.last.type} '
        'sheet_open=${_sheetOpen(tester)}',
      );
      expect(
        cleared,
        isTrue,
        reason: 'clearing ${mark.name} must restore the whole DocumentState',
      );
      expect(
        _sheetOpen(tester),
        isTrue,
        reason: 'the sheet must survive clearing ${mark.name}',
      );
    }

    // --- TWO SIGNS ON ONE BAR, which is what the model's set stores and the painter joins --------
    final DocumentState beforeTwo = session.document;
    await tester.tap(
      find.byKey(const ValueKey<String>('song-form-mark-segno')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('song-form-mark-coda')));
    await tester.pumpAndSettle();
    await _renderPage(
      tester,
      session,
      metrics,
      engine,
      File(path('two-marks@2x.png')),
    );
    final Set<BarMark> two = session.song.barAt(_sectionId, _targetBar)!.marks;
    stdout.writeln(
      'mark.two marks=${_marks(session.song)} count=${two.length} '
      'has_segno=${two.contains(BarMark.segno)} has_coda=${two.contains(BarMark.coda)} '
      'sheet_open=${_sheetOpen(tester)}',
    );
    expect(
      two,
      containsAll(<BarMark>[BarMark.segno, BarMark.coda]),
      reason: 'a bar must be able to carry two signs at once',
    );
    expect(
      two.length,
      2,
      reason: 'a bar with two signs must carry exactly two',
    );
    // Undoing the second sign leaves the first, and undoing that leaves nothing: the two presses
    // are two edits, not one.
    expect(session.undo(), isTrue);
    stdout.writeln(
      'mark.two.undo stage=one marks=${_marks(session.song)} '
      'has_segno=${session.song.barAt(_sectionId, _targetBar)!.marks.contains(BarMark.segno)}',
    );
    expect(session.undo(), isTrue);
    stdout.writeln(
      'mark.two.undo stage=none marks=${_marks(session.song)} '
      'equal_before_two=${session.document == beforeTwo}',
    );
    expect(
      session.document,
      beforeTwo,
      reason: 'undoing both presses must restore the whole DocumentState',
    );
    await tester.tap(find.byKey(const ValueKey<String>('song-form-done')));
    await tester.pumpAndSettle();
    stdout.writeln(
      'mark.done sheet_open=${_sheetOpen(tester)} events=${session.log.length} '
      'seq=${session.seq} undo_depth=${session.undoDepth}',
    );
    expect(_sheetOpen(tester), isFalse, reason: 'Done must close the sheet');
  });
}
