// PURPOSE: LOOK at the repeat and ending controls, and prove they and `derivePlayOrder` agree. The
//          instrument drives the REAL form sheet — the buttons a musician presses, including the
//          ending dialog — against a real `EditSession`, renders the same music to a PNG before and
//          after the signs are set, renders a FITTED page as well because that is where page
//          geometry goes silently wrong, and prints the play order the derivation reads back from
//          the chart the controls produced. A boolean "the barline changed" cannot show WHICH sign
//          landed on WHICH bar, and a derivation checked only against hand-built fixtures cannot
//          show that the controls write a shape it understands; both halves are printed together.
//
//          It also proves the scene bar's REPEATS field follows the edit on the same press: the
//          harness holds the real [SceneBar] and the real sheet, and rebuilds the way the viewer
//          rebuilds — the sheet's `onChanged` calls `setState` — so the summary read while the sheet
//          is still open is the summary the musician sees behind it, not one recomputed by hand.
// INPUTS: None. The chart is synthetic and the taps are the product's own buttons, so this runs on
//         any machine. A real system font is loaded when one is found, because the framework's
//         default test font draws every glyph as a filled box and a page of boxes cannot show a
//         repeat barline or an ending bracket.
// OUTPUTS: PNGs under [repeatRenderDirectory], outside the repository, named `before`/`after` and
//          `before-fit`/`after-fit`; `repeat.*` lines on stdout carrying the scene-bar summary at
//          every step, the written signs of every bar on both sides of every edit, what undo was
//          compared against, the fitted page's scale with one cell's engraved and surface
//          rectangles, and the whole derivation trace. Rendering happens under `flutter test`, which
//          runs the real engine with no window: a window on this machine would take focus from
//          whoever is working at it.
// KEYWORDS: headless-render, png, repeat, volta, ending, song-form, op-log, undo, exact-restore,
//           play-order, agreement, fitted-page, scene-bar, evidence, no-window
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/scene_bar.dart';
import 'package:chartapp/song_form_sheet.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this instrument
// names the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The logical page the instrument engraves at.
const double repeatPageWidth = 640;
const double repeatPageHeight = 420;

/// The surface a FITTED page is asked for. Deliberately too narrow for the four bars to form one
/// system and too short to hold the systems they wrap into, so `fitToPage` must re-engrave the page
/// wider and shrink the result: a surface that already fitted at full size would come back with
/// scale 1, which is exactly the case where a rectangle computed without the scale looks right.
///
/// IT WAS 500 × 150, AND THE NUMBER STOPPED FORCING ANYTHING. THE OLD VALUES, QUOTED:
/// `repeatFitWidth = 500` and `repeatFitHeight = 150`. They were too narrow for four bars while a bar
/// was four cells wide — 500 points of surface holds 4 × 88 of music — and a bar is as wide as its
/// content now (one chord is 56), so the four bars fitted one system of a 452-point content width and
/// the page came back at scale 1, which is the case this surface exists to avoid. 200 × 100 is narrow
/// enough that one bar fills a system's content width and short enough that the four systems do not
/// fit at scale 1, so the fit still has to shrink — which is the only thing the case is about.
const double repeatFitWidth = 200;
const double repeatFitHeight = 100;

/// Where the PNGs are written. Outside the repository: an image is evidence for one inspection, not
/// an artefact to commit.
const String repeatRenderDirectory =
    r'C:\projects\ChartApp-acl-reports\render\repeat-controls';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartRepeatRenderFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The document id the instrument's session writes under.
const String _docId = 'chartapp-repeat-controls';

/// The section every control in this instrument acts on.
const String _sectionId = 'A';

/// The four bars of the fixture, as one-based ordinals a musician would use.
const int _repeatStartBar = 0;
const int _repeatEndBar = 1;
const int _secondEndingBar = 2;

// PURPOSE: Build the music every case in this instrument edits: one section of four bars, each
//          carrying a different root on its first cell and a second chord on its third, so a bar's
//          identity is readable on the page and a sign that landed on the wrong bar is visible
//          rather than plausible.
// INPUTS: None.
// OUTPUTS: A four-bar song in C major with no repeat sign and no bracket anywhere.
// KEYWORDS: fixture, synthetic-song, four-bars, no-signs, visible-chords, bar-identity
Song repeatChart() => Song(
  id: _docId,
  title: 'Repeat controls',
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
            chords: <ChordMark>[
              ChordMark(
                place: placeIn(_sectionId, index, 0),
                chord: Chord(
                  root: ChordRoot(index),
                  quality: ChordQuality.majorSeventh,
                ),
              ),
              ChordMark(
                place: placeIn(_sectionId, index, 2),
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

/// The engine the pages are produced with: the viewer's own spacing constants.
LayoutEngine _layoutEngine(FlutterTextMetrics metrics) => LayoutEngine(
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

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes cannot show a repeat barline or an ending
//          bracket.
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
    stdout.writeln('repeat.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Paint one page — ordinary or fitted — into a PNG.
// INPUTS: page — the layout to draw. song — the model it came from. metrics — how it is engraved.
//         out — where the bytes go. logicalWidth and logicalHeight — the surface the painter is
//         handed, which for a fitted page is the SHRUNKEN surface the scale maps onto.
// OUTPUTS: Writes the file. Throws when the engine produced no PNG bytes, because a missing image is
//          not a rendering of "nothing".
// KEYWORDS: paint, picture-recorder, to-image, png, fitted-surface, dispose
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

/// One bar's written signs and chords, so the PNG and this text can be read against each other.
String _barSigns(Song song, String sectionId, int barIndex) {
  final Bar? bar = song.barAt(sectionId, barIndex);
  if (bar == null) {
    return '$sectionId[$barIndex] (no such bar)';
  }
  final String chords = bar.chords.isEmpty
      ? '(blank)'
      : bar.chords
            .map(
              (ChordMark placed) =>
                  '${placed.chord.render(song.key, const SpellingTable())}'
                  '@${placed.offsetX.toStringAsFixed(1)}',
            )
            .join(',');
  return '$sectionId[$barIndex] open=${bar.openingBarline.name} '
      'close=${bar.closingBarline.name} '
      'previous=${bar.repeatPrevious.name} '
      'volta=${bar.volta == null ? 'none' : '${bar.volta}'} '
      'chords=$chords';
}

// PURPOSE: Print every bar of [song] with its signs, so what the controls WROTE is quoted beside
//          what the derivation READ.
// INPUTS: label — the column this dump is tagged with. song — the chart to describe.
// OUTPUTS: One `repeat.$label` line per bar, in reading order.
// KEYWORDS: document-dump, signs, barlines, volta, before-and-after
void _dumpSigns(String label, Song song) {
  for (final Section section in song.sections) {
    for (int index = 0; index < section.bars.length; index++) {
      stdout.writeln('repeat.$label ${_barSigns(song, section.id, index)}');
    }
  }
}

/// The one-based ordinal of a written bar in the whole chart, used to name bars in the trace.
int _flatIndex(Song song, WrittenBarAddress address) {
  int ordinal = 0;
  for (final Section section in song.sections) {
    if (section.id == address.sectionId) {
      return ordinal + address.barIndex + 1;
    }
    ordinal += section.bars.length;
  }
  return ordinal + address.barIndex + 1;
}

// PURPOSE: Print the whole play order `derivePlayOrder` produces for [song], one line per played
//          position, with the passages and the issues, so the reading can be checked against the
//          signs above rather than inferred from a pass/fail.
// INPUTS: label — the column this trace is tagged with. song — the chart the controls produced.
// OUTPUTS: The trace lines plus a summary line carrying the multiset of SOUNDING written bars, which
//          is the property a wrong derivation would change. The multiset is returned so the caller
//          can assert it.
// KEYWORDS: play-order, trace, agreement, sounding-multiset, evidence
Map<int, int> _dumpPlayOrder(String label, Song song) {
  final PlayOrder order = derivePlayOrder(song);
  stdout.writeln(
    'repeat.$label played=${order.length} passages=${order.passages.length} '
    'issues=${order.issues.length}',
  );
  for (final PlayedBar bar in order.played) {
    final String chain = bar.passes
        .map(
          (PlayedPass pass) =>
              '${pass.repeatStart}=${pass.pass}/${pass.passCount}',
        )
        .join(' in ');
    stdout.writeln(
      'repeat.$label   pos=${bar.position} '
      'written=${_flatIndex(song, bar.written)} '
      'source=${_flatIndex(song, bar.source)} '
      'pass=${bar.pass}/${bar.passCount}'
      '${chain.isEmpty ? '' : ' passages=$chain'}',
    );
  }
  final Map<int, int> sounding = <int, int>{};
  for (final WrittenBarAddress address in order.sources) {
    final int index = _flatIndex(song, address);
    sounding[index] = (sounding[index] ?? 0) + 1;
  }
  stdout.writeln('repeat.$label sounding=$sounding');
  for (final RepeatPassage passage in order.passages) {
    stdout.writeln(
      'repeat.$label passage start=${_flatIndex(song, passage.start)} '
      'end=${_flatIndex(song, passage.end)} passes=${passage.passCount} '
      'basis=${passage.passCountBasis.name} crosses=${passage.crossesSection}',
    );
  }
  for (final PlayOrderIssue issue in order.issues) {
    stdout.writeln('repeat.$label issue ${issue.kind.name}: ${issue.message}');
  }
  return sounding;
}

/// The text the scene bar's REPEATS field currently shows, read from the live widget tree.
String _sceneRepeatSummary(WidgetTester tester) {
  final Finder field = find.byKey(const ValueKey<String>('scene-bar-repeat'));
  final Finder texts = find.descendant(of: field, matching: find.byType(Text));
  final List<Text> widgets = tester.widgetList<Text>(texts).toList();
  return widgets.last.data ?? '';
}

// PURPOSE: Do one control press, then undo it and redo it, printing what the comparison was. This is
//          the shape the form instrument uses: an undo is only evidence when the whole
//          [DocumentState] afterwards is compared to the whole state before, because a boolean
//          assertion on one field passes for an undo that restored that field and lost another.
// INPUTS: tester — the running widget test. session — the session the controls write through.
//         label — what the press is called in the report. act — the presses themselves, which may be
//         one tap or a tap and a dialog choice.
// OUTPUTS: Nothing. Prints one `repeat.undo` line and fails when the press changed nothing, when
//          undo was unavailable, when the restored state differs from the state before the press in
//          any part, or when the redo did not put the edit back.
// KEYWORDS: undo, whole-state-comparison, redo, exact-restore, single-press-evidence
Future<void> _pressThenUndoRedo(
  WidgetTester tester,
  EditSession session,
  String label,
  Future<void> Function() act,
) async {
  final DocumentState before = session.document;
  final int depthBefore = session.undoDepth;
  await act();
  final DocumentState applied = session.document;
  final List<String> types = session.log
      .map((ChartEvent event) => event.type)
      .toList();
  final bool changed = applied != before;
  final bool undone = session.undo();
  final DocumentState restored = session.document;
  final bool redone = session.redo();
  final DocumentState reapplied = session.document;
  stdout.writeln(
    'repeat.undo label="$label" changed=$changed types=$types '
    'undo_depth_before=$depthBefore undone=$undone '
    'restored_equal_before=${restored == before} '
    'song_equal=${restored.song == before.song} '
    'redone=$redone reapplied_equal_applied=${reapplied == applied} '
    'seq=${session.seq} undo_depth=${session.undoDepth}',
  );
  expect(changed, isTrue, reason: '$label must change the document');
  expect(undone, isTrue, reason: 'undo must be available after $label');
  expect(
    restored,
    before,
    reason: 'undo of $label must restore the whole DocumentState',
  );
  expect(redone, isTrue, reason: 'redo must be available after undoing $label');
  expect(
    reapplied,
    applied,
    reason: 'redo of $label must put the edit back exactly',
  );
}

/// The harness: the real [SceneBar] and the real form sheet over one session, rebuilt the way the
/// viewer rebuilds — the sheet's `onChanged` calls `setState` — so a summary read while the sheet is
/// open is the summary the musician sees behind it.
class _FormHarness extends StatefulWidget {
  const _FormHarness({required this.session});

  /// The document being edited.
  final EditSession session;

  @override
  State<_FormHarness> createState() => _FormHarnessState();
}

/// The harness state: which bar the next opened sheet lands on.
class _FormHarnessState extends State<_FormHarness> {
  int _cursor = 0;

  // PURPOSE: Open the product's form sheet on the chosen bar, with the same rebuild callback the
  //          viewer passes, so the scene bar in this harness follows the edit exactly as it does in
  //          the application.
  // INPUTS: barIndex — the bar the sheet's own cursor starts on.
  // OUTPUTS: A future that completes when the sheet is dismissed.
  // KEYWORDS: harness, form-sheet, on-changed, rebuild, viewer-parity
  Future<void> _open(int barIndex) async {
    setState(() => _cursor = barIndex);
    await showSongForm(
      context,
      session: widget.session,
      sectionId: _sectionId,
      barIndex: barIndex,
      onChanged: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        Text('cursor=$_cursor', key: const ValueKey<String>('harness-cursor')),
        SceneBar(
          position: 1,
          songCount: 1,
          song: widget.session.song,
          semitones: 0,
          pageMode: PageMode.pages,
          onOpenKeyGrid: () {},
          onPageModeChanged: (PageMode _) {},
          onEditTempo: () {},
          onEditStyle: () {},
        ),
        for (int bar = 0; bar < 4; bar++)
          TextButton(
            key: ValueKey<String>('harness-open-$bar'),
            onPressed: () => _open(bar),
            child: Text('open bar $bar'),
          ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the repeat and ending controls write signs the derivation reads', (
    WidgetTester tester,
  ) async {
    final String? family = await tester.runAsync<String?>(_loadChartFont);
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes cannot show a repeat barline',
    );
    final FlutterTextMetrics metrics = _metricsFor(family!);
    final LayoutEngine engine = _layoutEngine(metrics);
    final Directory outDir = Directory(repeatRenderDirectory);
    outDir.createSync(recursive: true);

    final EditSession session = EditSession(
      document: DocumentState(song: repeatChart()),
      docId: _docId,
    );

    // --- BEFORE --------------------------------------------------------------------------------
    _dumpSigns('before', session.song);
    await tester.runAsync(() async {
      final List<PageLayout> pages = engine.layout(
        session.song,
        pageWidth: repeatPageWidth,
        pageHeight: repeatPageHeight,
      );
      expect(
        pages,
        hasLength(1),
        reason: 'the fixture is meant to be one page',
      );
      final File beforePng = File(
        '${outDir.path}${Platform.pathSeparator}before@2x.png',
      );
      await _renderToPng(
        pages.single,
        session.song,
        metrics,
        beforePng,
        logicalWidth: repeatPageWidth,
        logicalHeight: repeatPageHeight,
      );
      stdout.writeln(
        'repeat.wrote before=${beforePng.path} bytes=${beforePng.lengthSync()} '
        'page_size=(${pages.single.size.width},${pages.single.size.height}) '
        'page_scale=${pages.single.scale} page_bars=${pages.single.bars.length} '
        'systems=${pages.single.systems.length}',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        // The application's own delegates, so anything the harness renders comes from the same
        // catalogue the application uses.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _FormHarness(session: session),
      ),
    );
    final String summaryBefore = _sceneRepeatSummary(tester);
    stdout.writeln('repeat.summary stage=before text="$summaryBefore"');

    // --- THE PRESSES, all of them through the product's own buttons ------------------------------
    await tester.tap(find.byKey(const ValueKey<String>('harness-open-0')));
    await tester.pumpAndSettle();
    await _pressThenUndoRedo(
      tester,
      session,
      'repeat start on bar $_repeatStartBar',
      () async {
        await tester.tap(
          find.byKey(const ValueKey<String>('song-form-repeat-start')),
        );
        await tester.pumpAndSettle();
      },
    );
    final String summaryAfterStart = _sceneRepeatSummary(tester);
    stdout.writeln(
      'repeat.summary stage=after-repeat-start text="$summaryAfterStart"',
    );
    await tester.tap(find.byKey(const ValueKey<String>('song-form-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('harness-open-1')));
    await tester.pumpAndSettle();
    await _pressThenUndoRedo(
      tester,
      session,
      'repeat end on bar $_repeatEndBar',
      () async {
        await tester.tap(
          find.byKey(const ValueKey<String>('song-form-repeat-end')),
        );
        await tester.pumpAndSettle();
      },
    );
    final String summaryAfterEnd = _sceneRepeatSummary(tester);
    stdout.writeln(
      'repeat.summary stage=after-repeat-end text="$summaryAfterEnd"',
    );

    // The ending is chosen in a dialog the sheet opens, so this press is two taps; both are the
    // product's controls and the dialog is the only path to a bracket.
    await _pressThenUndoRedo(
      tester,
      session,
      'ending 1 on bar $_repeatEndBar',
      () async {
        await tester.tap(find.byKey(const ValueKey<String>('song-form-volta')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('song-form-volta-n1')),
        );
        await tester.pumpAndSettle();
      },
    );
    final String summaryAfterEnding1 = _sceneRepeatSummary(tester);
    stdout.writeln(
      'repeat.summary stage=after-ending-1 text="$summaryAfterEnding1"',
    );
    await tester.tap(find.byKey(const ValueKey<String>('song-form-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('harness-open-2')));
    await tester.pumpAndSettle();
    await _pressThenUndoRedo(
      tester,
      session,
      'ending 2 on bar $_secondEndingBar',
      () async {
        await tester.tap(find.byKey(const ValueKey<String>('song-form-volta')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('song-form-volta-n2')),
        );
        await tester.pumpAndSettle();
      },
    );
    final String summaryAfterEnding2 = _sceneRepeatSummary(tester);
    stdout.writeln(
      'repeat.summary stage=after-ending-2 text="$summaryAfterEnding2"',
    );
    await tester.tap(find.byKey(const ValueKey<String>('song-form-done')));
    await tester.pumpAndSettle();

    stdout.writeln(
      'repeat.summary before="$summaryBefore" after_repeat_start="$summaryAfterStart" '
      'after_repeat_end="$summaryAfterEnd" after_ending_1="$summaryAfterEnding1" '
      'after_ending_2="$summaryAfterEnding2"',
    );
    expect(summaryBefore, 'none', reason: 'the fixture carries no sign at all');
    expect(
      summaryAfterStart,
      '1×',
      reason: 'one repeat pass is what the musician just set',
    );
    expect(summaryAfterEnd, '1×', reason: 'an end adds no passage count');
    expect(
      summaryAfterEnding1,
      '1× · 1 volta',
      reason: 'the REPEATS field must follow the bracket on the same edit',
    );
    expect(
      summaryAfterEnding2,
      '1× · 2 volta',
      reason: 'a second bracket must reach the field without a reload',
    );

    // --- AFTER ---------------------------------------------------------------------------------
    _dumpSigns('after', session.song);
    await tester.runAsync(() async {
      final List<PageLayout> pages = engine.layout(
        session.song,
        pageWidth: repeatPageWidth,
        pageHeight: repeatPageHeight,
      );
      expect(pages, hasLength(1));
      final File afterPng = File(
        '${outDir.path}${Platform.pathSeparator}after@2x.png',
      );
      await _renderToPng(
        pages.single,
        session.song,
        metrics,
        afterPng,
        logicalWidth: repeatPageWidth,
        logicalHeight: repeatPageHeight,
      );
      stdout.writeln(
        'repeat.wrote after=${afterPng.path} bytes=${afterPng.lengthSync()}',
      );
    });

    // --- THE FITTED PAGE, where geometry goes silently wrong ------------------------------------
    await tester.runAsync(() async {
      final FitOutcome fit = engine.fitToPage(
        session.song,
        pageWidth: repeatFitWidth,
        pageHeight: repeatFitHeight,
      );
      expect(
        fit.page,
        isNotNull,
        reason: 'a four-bar chart must fit the fitted surface',
      );
      final PageLayout fitted = fit.page!;
      expect(
        fitted.scale < 1,
        isTrue,
        reason: 'the fitted surface must actually force a shrink',
      );
      final File fitPng = File(
        '${outDir.path}${Platform.pathSeparator}after-fit@2x.png',
      );
      await _renderToPng(
        fitted,
        session.song,
        metrics,
        fitPng,
        logicalWidth: repeatFitWidth,
        logicalHeight: repeatFitHeight,
      );
      final PlacedBar placed = fitted.bars.firstWhere(
        (PlacedBar bar) =>
            bar.sectionId == _sectionId && bar.barIndex == _repeatEndBar,
      );
      final LayoutRect cell = placed.bounds;
      stdout.writeln(
        'repeat.wrote fitted_after=${fitPng.path} '
        'fit_scale=${fitted.scale} fitted_bars=${fitted.bars.length} '
        'engraved_cell=(${cell.left},${cell.top},'
        '${cell.size.width},${cell.size.height}) '
        'surface_cell=(${cell.left * fitted.scale},'
        '${cell.top * fitted.scale},'
        '${cell.size.width * fitted.scale},'
        '${cell.size.height * fitted.scale})',
      );
    });

    // --- THE AGREEMENT --------------------------------------------------------------------------
    // The signs the CONTROLS wrote are printed by `_dumpSigns('after', ...)` above and the order the
    // DERIVATION reads is printed here, in the same run, from the same session. The property is the
    // multiset of SOUNDING written bars. Read as a musician would: bar 1 opens the passage, bar 2
    // closes it under `[1.`, and bar 3 sits after the closing barline under `[2.`. So bar 1 sounds
    // on both passes, bar 2 only on pass 1, bar 3 only on pass 2, and bar 4 once — which is
    // `{1: 2, 2: 1, 3: 1, 4: 1}` over the one-based ordinals this instrument prints.
    final Map<int, int> sounding = _dumpPlayOrder('after', session.song);
    final List<RepeatPassage> passages = derivePlayOrder(session.song).passages;
    stdout.writeln(
      'repeat.agreement signs="${_barSigns(session.song, _sectionId, _repeatStartBar)} | '
      '${_barSigns(session.song, _sectionId, _repeatEndBar)} | '
      '${_barSigns(session.song, _sectionId, _secondEndingBar)}" '
      'sounding=$sounding passages=${passages.length} '
      'pass_count=${passages.single.passCount} '
      'basis=${passages.single.passCountBasis.name}',
    );
    expect(
      passages,
      hasLength(1),
      reason: 'the repeat the controls wrote must be one passage',
    );
    expect(
      passages.single.passCount,
      2,
      reason: 'a bracket numbered 2 requires two passes',
    );
    expect(
      passages.single.passCountBasis,
      PassCountBasis.voltaRequired,
      reason: 'the second ending is what decided the count, not an assumption',
    );
    expect(
      sounding,
      <int, int>{1: 2, 2: 1, 3: 1, 4: 1},
      reason:
          'the first ending sounds on pass 1 only and the second on pass 2 only, '
          'which is what the written `[1.` and `[2.` say',
    );
    expect(
      derivePlayOrder(session.song).issues,
      isEmpty,
      reason:
          'the shape the controls wrote must not force a derivation decision',
    );
  });
}
