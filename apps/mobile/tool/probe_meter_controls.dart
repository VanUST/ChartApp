// PURPOSE: Drive the REAL zonal meter control in the REAL form sheet — the two bar-number boxes and
//          the two M/N boxes a musician types — and prove what a model-level check cannot: that a
//          RUN OF BARS is set in one gesture ("15/8 from bar 2 to bar 3"), that each bar of the run
//          really changes, and that every input that is not a run or not a meter (0/0, a negative
//          figure, a fraction, a blank box, an absurd figure, a reversed run, a bar outside the
//          section) is REFUSED WITH THE BOX STILL OPEN and nothing applied. The refusals are the
//          interesting half: a control that silently corrected `0/0` to `4/4`, or a backwards range
//          to a forwards one, would look like it worked and would have written a meter nobody asked
//          for on bars nobody named.
//
//          It is an instrument, not part of the suite: it lives in `tool/`, so `flutter test`'s
//          default run and the `melos run verify` gate do not pick it up. Run it from `apps/mobile`
//          with:
//
//              flutter test tool/probe_meter_controls.dart
//
//          It opens no window: `flutter test` runs the engine headless.
// INPUTS: METER_CONTROLS_OUT names the directory the PNGs are written to, defaulting to a path
//         outside the repository. METER_CONTROLS_LOCALE selects the catalogue language for the run
//         (`ru` or anything else for English), so the refusal text is quoted from the musician's own
//         language as well as the default one.
// OUTPUTS: `meter.control.*` lines on stdout — what the box opened on, the section's meters after
//          every attempt, the EVENT TYPES the log recorded, whether the sheet stayed open, whether
//          the page rebuilt, and the exact refusal text shown for each bad input — plus one PNG of
//          the page after the zonal set, so the sign on every bar of the run is shown rather than
//          asserted.
// KEYWORDS: probe, meter, zone, bar-range, m-over-n, form-sheet, typed-refusal, 0-over-0, undo,
//           png, headless, d22
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

/// Where the PNGs are written. Outside the repository: an image is evidence for one inspection, not
/// an artefact to commit.
const String meterControlsDirectory =
    r'C:\projects\ChartApp-acl-reports\render\meter-sign-controls';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartMeterControlsFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The logical page the instrument engraves at.
const double _pageWidth = 640;

/// The page height.
const double _pageHeight = 320;

/// The document id the instrument's session writes under.
const String _docId = 'chartapp-meter-controls';

/// The section the control acts on.
const String _sectionId = 'A';

/// The bar the sheet's cursor is opened on: the SECOND bar, so the run the box opens on is not the
/// first bar and a sign at the start of the system cannot be confused with a change.
const int _cursorBar = 1;

/// How many bars the synthetic section has.
const int _barCount = 4;

// PURPOSE: Build the music the run is set on: one section of four 4/4 bars, each carrying a
//          different root, so a run that landed on the wrong bars is visible rather than plausible.
// INPUTS: None.
// OUTPUTS: A four-bar song in C major, every bar in 4/4.
// KEYWORDS: fixture, synthetic-song, four-bars, 4/4, visible-chords
Song _meterChart() => Song(
  id: _docId,
  title: 'Meter controls',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: _sectionId,
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < _barCount; index++)
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

/// The engine the page is produced with: the viewer's own spacing constants.
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
// glyph as a filled box and a page of boxes cannot show a meter.
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
    stdout.writeln('meter.controls.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Paint the page into a PNG, so the sign a zonal meter produced can be LOOKED AT on every
//          bar of the run rather than counted.
// INPUTS: page and song — what to draw. metrics — how it was measured. out — the file.
// OUTPUTS: Nothing; writes the file.
// KEYWORDS: paint, picture-recorder, to-image, png, evidence
Future<void> _renderPage(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  File out,
) async {
  const double pixelRatio = 2;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
  ).paint(canvas, const ui.Size(_pageWidth, _pageHeight));
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
  out.writeAsBytesSync(png.buffer.asUint8List());
}

/// The harness: the real form sheet over one session, rebuilt on every edit the way the viewer
/// rebuilds it.
class _MeterHarness extends StatefulWidget {
  const _MeterHarness({required this.session});

  /// The document being edited.
  final EditSession session;

  @override
  State<_MeterHarness> createState() => _MeterHarnessState();
}

/// The harness state: how many times an edit asked the page to rebuild.
class _MeterHarnessState extends State<_MeterHarness> {
  int _rebuilds = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        Text(
          'rebuilds=$_rebuilds',
          key: const ValueKey<String>('meter-harness-rebuilds'),
        ),
        TextButton(
          key: const ValueKey<String>('meter-harness-open'),
          onPressed: () => showSongForm(
            context,
            session: widget.session,
            sectionId: _sectionId,
            barIndex: _cursorBar,
            onChanged: () => setState(() => _rebuilds++),
          ),
          child: const Text('open the form sheet'),
        ),
      ],
    ),
  );
}

/// Whether the form sheet is still on screen.
bool _sheetOpen(WidgetTester tester) =>
    find.byKey(const ValueKey<String>('song-form-done')).evaluate().isNotEmpty;

/// Whether the zone box is on screen.
bool _boxOpen(WidgetTester tester) =>
    find.byKey(const ValueKey<String>('form-zone-apply')).evaluate().isNotEmpty;

/// The number of page rebuilds the sheet has asked the harness for.
int _rebuilds(WidgetTester tester) => int.parse(
  tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('meter-harness-rebuilds')),
          )
          .data
          ?.split('=')
          .last ??
      '0',
);

/// Every bar's meter in the section, in written order, as `4/4 15/8 …`.
String _meters(Song song) => song.sections
    .expand((Section section) => section.bars)
    .map((Bar bar) => bar.timeSignature.toString())
    .join(' ');

/// The refusal currently shown in the box, or an empty string.
String _refusal(WidgetTester tester) {
  final Finder finder = find.byKey(const ValueKey<String>('form-zone-error'));
  if (finder.evaluate().isEmpty) {
    return '';
  }
  return tester.widget<Text>(finder).data ?? '';
}

// PURPOSE: Type a full zoning gesture — the run and the meter — into the four boxes of the open box.
// INPUTS: tester — the running test. first, last, numerator and denominator — the four typed values.
//         A null value is left as the box opened on it, so a case that tests only the meter does not
//         have to restate the run.
// OUTPUTS: Nothing; the boxes hold the typed text.
// KEYWORDS: type, four-boxes, gesture, partial-input
Future<void> _type(
  WidgetTester tester, {
  String? first,
  String? last,
  String? numerator,
  String? denominator,
}) async {
  Future<void> into(String key, String? value) async {
    if (value == null) {
      return;
    }
    await tester.enterText(find.byKey(ValueKey<String>(key)), value);
  }

  await into('form-zone-first', first);
  await into('form-zone-last', last);
  await into('form-zone-numerator', numerator);
  await into('form-zone-denominator', denominator);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the zonal meter box sets a run of bars and refuses every bad input',
    (WidgetTester tester) async {
      final String? family = await tester.runAsync<String?>(_loadFont);
      expect(
        family,
        isNotNull,
        reason: 'a page of filled boxes cannot show a meter',
      );
      final FlutterTextMetrics metrics = _metricsFor(family!);
      final LayoutEngine engine = _layoutEngine(metrics);
      final String outDir =
          Platform.environment['METER_CONTROLS_OUT'] ?? meterControlsDirectory;
      Directory(outDir).createSync(recursive: true);

      final EditSession session = EditSession(
        document: DocumentState(song: _meterChart()),
        docId: _docId,
      );
      await tester.pumpWidget(
        MaterialApp(
          // The musician reads Russian, so the refusals are shown in Russian in that run and the text
          // is quoted from both catalogues. The locale is an INPUT so one instrument checks both.
          locale: Platform.environment['METER_CONTROLS_LOCALE'] == 'ru'
              ? const Locale('ru')
              : const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _MeterHarness(session: session),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('meter-harness-open')),
      );
      await tester.pumpAndSettle();
      expect(_sheetOpen(tester), isTrue, reason: 'the sheet must be open');

      // --- WHAT THE BOX OPENS ON -----------------------------------------------------------------
      await tester.tap(find.byKey(const ValueKey<String>('song-form-meter')));
      await tester.pumpAndSettle();
      expect(_boxOpen(tester), isTrue, reason: 'the zone box must open');
      String text(String key) =>
          tester
              .widget<TextField>(find.byKey(ValueKey<String>(key)))
              .controller
              ?.text ??
          '';
      stdout.writeln(
        'meter.control.opened first="${text('form-zone-first')}" '
        'last="${text('form-zone-last')}" '
        'meter="${text('form-zone-numerator')}/${text('form-zone-denominator')}"',
      );
      await tester.tap(find.byKey(const ValueKey<String>('form-zone-cancel')));
      await tester.pumpAndSettle();
      expect(_boxOpen(tester), isFalse, reason: 'cancel must close the box');

      // --- A BAD METER IS REFUSED, AND THE BOX STAYS OPEN ----------------------------------------
      //
      // The run stays the one the box opened on (the cursor's bar), so each refusal is about the METER
      // alone. NONE of these may be corrected into a meter: the section must be untouched after each.
      const List<(String, String, String)> badMeters =
          <(String, String, String)>[
            ('0', '0', 'numerator'),
            ('-3', '4', 'numerator'),
            ('3.5', '4', 'numerator'),
            ('4', '0', 'denominator'),
            ('999', '4', 'numerator'),
          ];
      for (final (String numerator, String denominator, String field)
          in badMeters) {
        final String before = _meters(session.song);
        final int eventsBefore = session.log.length;
        await tester.tap(find.byKey(const ValueKey<String>('song-form-meter')));
        await tester.pumpAndSettle();
        await _type(tester, numerator: numerator, denominator: denominator);
        await tester.tap(find.byKey(const ValueKey<String>('form-zone-apply')));
        await tester.pumpAndSettle();
        stdout.writeln(
          'meter.control.refused.meter typed="$numerator/$denominator" '
          'field=$field box_open=${_boxOpen(tester)} '
          'meters=${_meters(session.song)} '
          'events_appended=${session.log.length - eventsBefore} '
          'text="${_refusal(tester)}"',
        );
        expect(_boxOpen(tester), isTrue, reason: 'the box must stay open');
        expect(_meters(session.song), before, reason: 'nothing may change');
        expect(_refusal(tester), isNotEmpty, reason: 'the box must say why');
        await tester.tap(
          find.byKey(const ValueKey<String>('form-zone-cancel')),
        );
        await tester.pumpAndSettle();
      }

      // --- A BAD RUN IS REFUSED, AND THE BOX STAYS OPEN ------------------------------------------
      //
      // The meter stays 3/4, which is a perfectly good meter, so each refusal here is about the RUN.
      const List<(String, String, String)> badRuns = <(String, String, String)>[
        ('3', '2', 'reversed'),
        ('1', '9', 'out-of-range'),
        ('', '2', 'empty-first'),
        ('x', '2', 'not-a-number'),
      ];
      for (final (String first, String last, String label) in badRuns) {
        final String before = _meters(session.song);
        final int eventsBefore = session.log.length;
        await tester.tap(find.byKey(const ValueKey<String>('song-form-meter')));
        await tester.pumpAndSettle();
        await _type(
          tester,
          first: first,
          last: last,
          numerator: '3',
          denominator: '4',
        );
        await tester.tap(find.byKey(const ValueKey<String>('form-zone-apply')));
        await tester.pumpAndSettle();
        stdout.writeln(
          'meter.control.refused.run case=$label typed="$first..$last" '
          'box_open=${_boxOpen(tester)} meters=${_meters(session.song)} '
          'events_appended=${session.log.length - eventsBefore} '
          'text="${_refusal(tester)}"',
        );
        expect(_boxOpen(tester), isTrue, reason: 'the box must stay open');
        expect(_meters(session.song), before, reason: 'nothing may change');
        expect(_refusal(tester), isNotEmpty, reason: 'the box must say why');
        await tester.tap(
          find.byKey(const ValueKey<String>('form-zone-cancel')),
        );
        await tester.pumpAndSettle();
      }

      // --- A RUN IS SET IN ONE GESTURE -----------------------------------------------------------
      //
      // Bars 2 and 3 (the musician's counting) taken into 15/8 in ONE dialog: this is the zone the
      // owner asked for, and the section afterwards shows exactly those two bars changed.
      final String before = _meters(session.song);
      final int rebuildsBefore = _rebuilds(tester);
      final int eventsBefore = session.log.length;
      await tester.tap(find.byKey(const ValueKey<String>('song-form-meter')));
      await tester.pumpAndSettle();
      await _type(
        tester,
        first: '2',
        last: '3',
        numerator: '15',
        denominator: '8',
      );
      await tester.tap(find.byKey(const ValueKey<String>('form-zone-apply')));
      await tester.pumpAndSettle();
      final List<String> appliedTypes = session.log
          .skip(eventsBefore)
          .map((DocumentEvent event) => event.type)
          .toList();
      stdout.writeln(
        'meter.control.zone typed="bars 2-3 -> 15/8" box_open=${_boxOpen(tester)} '
        'sheet_open=${_sheetOpen(tester)} meters=${_meters(session.song)} '
        'before="$before" events_appended=${session.log.length - eventsBefore} '
        'event_types=${appliedTypes.join(',')} '
        'page_rebuilt=${_rebuilds(tester) > rebuildsBefore}',
      );
      expect(_boxOpen(tester), isFalse, reason: 'a valid zone closes the box');
      expect(
        _meters(session.song),
        '4/4 15/8 15/8 4/4',
        reason: 'exactly the named run must change',
      );
      expect(
        appliedTypes,
        <String>['meter.set', 'meter.set'],
        reason: 'one per-bar event per bar of the run, and no composite event',
      );

      // UNDO AND REDO. The zone is two per-bar events, so it takes two undo steps — the cost is stated
      // in the report and measured here rather than described.
      final bool firstUndo = session.undo();
      final String afterOneUndo = _meters(session.song);
      final bool secondUndo = session.undo();
      stdout.writeln(
        'meter.control.undo first=$firstUndo after_one="$afterOneUndo" '
        'second=$secondUndo restored="$before" all="${_meters(session.song)}" '
        'restored_equal_before=${_meters(session.song) == before}',
      );
      expect(session.undoDepth, 0, reason: 'the zone took one undo per bar');
      expect(
        _meters(session.song),
        before,
        reason: 'two undos restore the run',
      );
      expect(session.redo(), isTrue);
      expect(session.redo(), isTrue);
      stdout.writeln(
        'meter.control.redo meters=${_meters(session.song)} '
        'reapplied=${_meters(session.song) == '4/4 15/8 15/8 4/4'}',
      );
      expect(_meters(session.song), '4/4 15/8 15/8 4/4');

      // --- THE PAGE ------------------------------------------------------------------------------
      final File png = File(
        '$outDir${Platform.pathSeparator}meter-controls-zone-15-8@2x.png',
      );
      await tester.runAsync(() async {
        final List<PageLayout> pages = engine.layout(
          session.song,
          pageWidth: _pageWidth,
          pageHeight: _pageHeight,
        );
        await _renderPage(pages.first, session.song, metrics, png);
      });
      final PageLayout page = engine
          .layout(session.song, pageWidth: _pageWidth, pageHeight: _pageHeight)
          .first;
      stdout.writeln(
        'meter.control.page signs=${meterSignsOnPage(session.song, page)} '
        'png=${png.path} bytes=${png.lengthSync()}',
      );

      await tester.tap(find.byKey(const ValueKey<String>('song-form-done')));
      await tester.pumpAndSettle();
      stdout.writeln(
        'meter.control.done sheet_open=${_sheetOpen(tester)} '
        'events=${session.log.length} undo_depth=${session.undoDepth}',
      );
      expect(_sheetOpen(tester), isFalse, reason: 'Done must close the sheet');
    },
  );
}
