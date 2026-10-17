// PURPOSE: Drive the REAL chord palette's typed-symbol field and the REAL form sheet's staff switch,
//          and show what each produced — a picture of the surface and the number of operations it
//          appended. It is the instrument behind two claims that would otherwise be sentences:
//          D28's "a chord is one action, because the symbol is typed", and D29's "the musician holds
//          the choice of whether the chart carries a staff".
//
//          It is an instrument, not part of the suite: it lives in `tool/`, so `flutter test`'s
//          default run and the `melos run verify` gate do not pick it up. Run it from `apps/mobile`
//          with:
//
//              flutter test tool/probe_input_surface.dart
//
//          It opens no window: `flutter test` runs the engine headless.
// INPUTS: INPUT_SURFACE_OUT names the directory the PNGs are written to, defaulting to a path outside
//         the repository. INPUT_SURFACE_LOCALE selects the catalogue language (`ru` or anything else
//         for English), so both the field's caption and a refusal are quoted in the musician's own
//         language as well as the default one. A real system font is loaded when one is found,
//         because the framework's default test font draws every glyph as a filled box.
// OUTPUTS: `input.surface.*` lines on stdout — what the chord field wrote for a typed symbol, the
//          event types the log recorded, the refusal text for a symbol that is not a chord, the staff
//          switch's effect on `Song.staffSet`, whether the notes already written survived the switch
//          being turned off and on, and the undo depth each action cost — plus PNGs of the palette
//          and of the form sheet.
// KEYWORDS: probe, chord-palette, typed-chord, staff, declared-staff, toggle, action-count, refusal,
//           png, headless, d28, d29
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chord_palette_sheet.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/song_form_sheet.dart';
// Flutter's own `Key` (widget identity) collides with the domain's musical Key, and this instrument
// names the musical one; its widget keys are ValueKey, so nothing here needs Flutter's.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter/rendering.dart' hide Key;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the PNGs are written. Outside the repository: an image is evidence for one inspection, not
/// an artefact to commit.
const String inputSurfaceDirectory =
    r'C:\projects\ChartApp-acl-reports\render\input-surface-d28';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartInputSurfaceFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The document id the instrument's session writes under.
const String _docId = 'chartapp-input-surface';

/// The section the two sheets act on.
const String _sectionId = 'A';

/// The logical window the palette and the form sheet are pumped at, which is the tablet's portrait
/// pane rather than a phone's, because that is the surface the owner tested on.
const Size _window = Size(824, 1318);

// PURPOSE: Build the chart both surfaces act on: two bars, the first empty so the palette has a
//          genuinely blank cell to write into, the second carrying a note so the staff switch has
//          something to keep.
// INPUTS: None.
// OUTPUTS: A two-bar song in C major that DECLARES a pitched staff and holds exactly one note.
// KEYWORDS: fixture, blank-cell, declared-staff, existing-note, visible-effect
Song _surfaceChart() => Song(
  id: _docId,
  title: 'Input surface',
  key: Key.cMajor,
  staffSet: const StaffSet(pitched: StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: _sectionId,
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(),
        Bar(
          melody: <NoteMark>[
            NoteMark(
              place: cellAt(0),
              pitch: const PitchedNote(
                note: WrittenNote(NoteLetter.g, 0),
                octave: 4,
              ),
              value: const NoteValue.plain(NoteBase.quarter),
            ),
          ],
        ),
      ],
    ),
  ],
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes shows no caption.
// INPUTS: None. The first existing candidate is used.
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
    stdout.writeln('input.surface.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Write the widget tree the tester is currently showing into a PNG, so a reader can see the
//          surface rather than take its description on trust.
// INPUTS: tester — the running test. out — the file to write.
// OUTPUTS: Writes the PNG and returns its bytes. The capture runs inside `runAsync` because
//          `toImage` needs the engine's real event loop, and a render tree that cannot produce an
//          image is reported rather than silently producing no file.
// KEYWORDS: widget-png, repaint-boundary, to-image, evidence, run-async
Future<List<int>> _captureWidget(WidgetTester tester, File out) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(surfaceBoundaryKey));
  final ByteData? png = await tester.runAsync<ByteData?>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    return data;
  });
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  final List<int> bytes = png.buffer.asUint8List();
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  return bytes;
}

// PURPOSE: Report every chord of a bar the way a musician reads it, so a symbol that was typed and
//          a chord that landed are the same string in the log.
// INPUTS: song — the chart. barIndex — the bar to read.
// OUTPUTS: One string per chord, `beat.step:rendered`.
// KEYWORDS: chord-rendering, readable-report
List<String> _chords(Song song, int barIndex) => <String>[
  for (final ChordMark placed in song.barsInReadingOrder[barIndex].chords)
    _readableChord(song, placed),
];

/// One chord as `beat.step:rendered`, in a function because the lint forbids two adjacent string
/// literals inside a list and this line is longer than one.
String _readableChord(Song song, ChordMark placed) {
  final String text = placed.chord.render(song.key, const SpellingTable());
  return '${placed.pseudoBeat}.${placed.pseudoStep}:$text';
}

/// The key of the [RepaintBoundary] the harness wraps itself in, which is what a capture reads:
/// a modal sheet is painted inside the app's overlay, so a boundary around the harness would miss it.
const ValueKey<String> surfaceBoundaryKey = ValueKey<String>(
  'surface-boundary',
);

/// The harness that opens either surface, rebuilt on every edit the way the viewer rebuilds it.
class _SurfaceHarness extends StatefulWidget {
  const _SurfaceHarness({required this.session, required this.which});

  /// The document being edited.
  final EditSession session;

  /// Which surface the harness's one button opens.
  final String which;

  @override
  State<_SurfaceHarness> createState() => _SurfaceHarnessState();
}

/// The harness state: how many times an edit asked the page to rebuild.
class _SurfaceHarnessState extends State<_SurfaceHarness> {
  int _rebuilds = 0;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: surfaceBoundaryKey,
    child: Scaffold(
      // THE SHEET IS PUMPED INLINE RATHER THAN MODALLY, and that is what makes the picture show the
      // surface. A modal sheet is painted in the app's own overlay, which is a sibling of this
      // boundary's layer, so a capture of the boundary shows the page BEHIND the sheet and not the
      // sheet. The WIDGET is the same object the modal path builds — it is public — so what is
      // drawn here is the real surface; only the route that shows it differs.
      body: widget.which == 'chord'
          ? ChordPaletteSheet(
              session: widget.session,
              sectionId: _sectionId,
              barIndex: 0,
              beat: 0,
              shownKey: Key.cMajor,
              onChanged: () => setState(() => _rebuilds++),
            )
          : SongFormSheet(
              session: widget.session,
              sectionId: _sectionId,
              barIndex: 0,
              onChanged: () => setState(() => _rebuilds++),
            ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the typed chord field and the staff switch', (
    WidgetTester tester,
  ) async {
    final String? family = await tester.runAsync<String?>(_loadFont);
    expect(
      family,
      isNotNull,
      reason: 'a page of filled boxes shows no caption',
    );
    final String outDir =
        Platform.environment['INPUT_SURFACE_OUT'] ?? inputSurfaceDirectory;
    Directory(outDir).createSync(recursive: true);
    final Locale locale = Platform.environment['INPUT_SURFACE_LOCALE'] == 'ru'
        ? const Locale('ru')
        : const Locale('en');

    final EditSession session = EditSession(
      document: DocumentState(song: _surfaceChart()),
      docId: _docId,
    );

    await tester.binding.setSurfaceSize(_window);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // ---------------------------------------------------------------- THE TYPED CHORD FIELD -----
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        // THE LOADED FAMILY IS THE APP'S, or the picture shows a page of filled boxes: the widgets
        // under test are the application's own, and their text styles name no family of their own.
        theme: ThemeData(fontFamily: family),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _SurfaceHarness(session: session, which: 'chord'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('chord-palette-symbol')),
      findsOneWidget,
      reason: 'the typed field must be on the palette',
    );
    stdout.writeln(
      'input.surface.palette field=${find.byKey(const ValueKey<String>('chord-palette-symbol')).evaluate().isNotEmpty} '
      'apply=${find.byKey(const ValueKey<String>('chord-palette-symbol-apply')).evaluate().isNotEmpty} '
      'grid=${find.byKey(const ValueKey<String>('chord-palette-roots')).evaluate().isNotEmpty} '
      'quality_chips=${find.byKey(const ValueKey<String>('chord-palette-quality-maj')).evaluate().isNotEmpty}',
    );
    final List<int> paletteBytes = await _captureWidget(
      tester,
      File('$outDir${Platform.pathSeparator}palette-empty-cell@2x.png'),
    );
    stdout.writeln('input.surface.palette.png bytes=${paletteBytes.length}');

    // A SYMBOL THE MUSICIAN TYPES: one field, one press. The event count is the action count on the
    // document's side, and it is the number this claim rests on.
    for (final String symbol in <String>['Dm7', 'F#7#11', 'Bb7(b9)/F']) {
      final int before = session.log.length;
      await tester.enterText(
        find.byKey(const ValueKey<String>('chord-palette-symbol')),
        symbol,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('chord-palette-symbol-apply')),
      );
      await tester.pumpAndSettle();
      stdout.writeln(
        'input.surface.typed "$symbol" => chords=${_chords(session.song, 0)} '
        'events=${session.log.length - before} '
        'types=${session.log.map((ChartEvent e) => e.type).toList()} '
        'field_now="${tester.widget<TextField>(find.byKey(const ValueKey<String>('chord-palette-symbol'))).controller?.text}"',
      );
    }

    // A SYMBOL THAT IS NOT A CHORD: nothing may be written, and the field must say why.
    final int beforeRefusal = session.log.length;
    await tester.enterText(
      find.byKey(const ValueKey<String>('chord-palette-symbol')),
      'H7',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('chord-palette-symbol-apply')),
    );
    await tester.pumpAndSettle();
    final Finder error = find.byKey(
      const ValueKey<String>('chord-palette-symbol-error'),
    );
    stdout.writeln(
      'input.surface.refused "H7" events_appended=${session.log.length - beforeRefusal} '
      'chords=${_chords(session.song, 0)} '
      'message="${error.evaluate().isEmpty ? '' : tester.widget<Text>(error).data}"',
    );
    final List<int> refusedBytes = await _captureWidget(
      tester,
      File('$outDir${Platform.pathSeparator}palette-refused@2x.png'),
    );
    stdout.writeln('input.surface.refused.png bytes=${refusedBytes.length}');

    // ----------------------------------------------------------------- THE STAFF SWITCH ---------
    final int noteCountBefore =
        session.song.barsInReadingOrder[1].melody.length;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        // THE LOADED FAMILY IS THE APP'S, or the picture shows a page of filled boxes: the widgets
        // under test are the application's own, and their text styles name no family of their own.
        theme: ThemeData(fontFamily: family),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _SurfaceHarness(session: session, which: 'form'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('song-form-staff-melody')),
      findsOneWidget,
      reason: 'the staff switch must be on the form sheet',
    );
    final List<int> formOnBytes = await _captureWidget(
      tester,
      File('$outDir${Platform.pathSeparator}form-staff-on@2x.png'),
    );
    stdout.writeln('input.surface.form.png bytes=${formOnBytes.length}');

    final int beforeOff = session.log.length;
    await tester.tap(
      find.byKey(const ValueKey<String>('song-form-staff-melody')),
    );
    await tester.pumpAndSettle();
    stdout.writeln(
      'input.surface.staff off staffSet=${session.song.staffSet} '
      'events=${session.log.length - beforeOff} '
      'last_type=${session.log.last.type} '
      'notes_kept=${session.song.barsInReadingOrder[1].melody.length} '
      'undo_depth=${session.undoDepth}',
    );
    final List<int> formOffBytes = await _captureWidget(
      tester,
      File('$outDir${Platform.pathSeparator}form-staff-off@2x.png'),
    );
    stdout.writeln('input.surface.form.off.png bytes=${formOffBytes.length}');

    final int beforeOn = session.log.length;
    await tester.tap(
      find.byKey(const ValueKey<String>('song-form-staff-melody')),
    );
    await tester.pumpAndSettle();
    stdout.writeln(
      'input.surface.staff on_again staffSet=${session.song.staffSet} '
      'events=${session.log.length - beforeOn} '
      'last_type=${session.log.last.type} '
      'notes_kept=${session.song.barsInReadingOrder[1].melody.length}',
    );

    // The switch is one undo step, and undoing it returns the staves that were there.
    final bool undone = session.undo();
    stdout.writeln(
      'input.surface.staff undo done=$undone staffSet=${session.song.staffSet} '
      'notes=${session.song.barsInReadingOrder[1].melody.length} '
      'note_before_switch=$noteCountBefore',
    );
    stdout.writeln('input.surface.out dir=$outDir');
  });
}
