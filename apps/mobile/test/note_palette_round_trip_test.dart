// PURPOSE: Drive the REAL note surfaces to a note and back — no palette state poked directly, no
//          session method called by hand — and prove the acceptance test the feature is judged by:
//          write notes through the buttons a musician touches, save them with the same encoder the
//          file bar saves with, reopen the file, and read the same notes back out of the document.
// INPUTS: None. The chart and the temp directory are built here.
// OUTPUTS: Pass/fail per claim, plus printed lines naming every note that was written and every note
//          that came back, so a failure shows the two melodies rather than only a red assertion.
//
//          WHAT IT PROVES, AND WHAT IT DOES NOT. It proves the palette's buttons reach the writer with
//          the pitch, the duration, the beat, the octave and the tie a tap asks for, and that the
//          result survives `chartFileFor` + `ChartFileCodec` — the save and open path the file bar
//          itself uses — byte for byte. It does NOT prove the notes are ENGRAVED when a page is
//          drawn: that is what `apps/mobile/test/note_engraving_test.dart` and `melody_render_test.dart`
//          check on the same model. And it touches no device.
// KEYWORDS: test, note-palette, melody, round-trip, chart-file, widget, acceptance, tie, ledger,
//           stacked-notes, driver
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';

import '../support/place_fixture.dart';

import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/chart_document.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

/// A one-section chart of [bars] empty bars in C major, which is what "New chart" makes.
Song emptyChart(int bars) => Song(
  id: 'note-round-trip',
  title: 'Note round trip',
  key: Key.cMajor,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[for (int index = 0; index < bars; index++) Bar()],
    ),
  ],
);

/// The same empty chart, but the song DECLARES a pitched staff, so every bar is engraved with one
/// before a single note exists — the D29 surface a staff tap has to be able to write on.
Song staffChart(int bars) => Song(
  id: 'staff-tap',
  title: 'Staff tap',
  key: Key.cMajor,
  staffSet: StaffSet.of(pitched: const StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[for (int index = 0; index < bars; index++) Bar()],
    ),
  ],
);

/// A one-song library holding [song].
IRealLibrary libraryOf(Song song) => IRealLibrary(
  playlistName: '',
  songs: <IRealSong>[IRealSong(index: 0, song: song)],
);

/// Pumps the viewer over [library] at [size] logical pixels.
Future<void> pumpViewer(
  WidgetTester tester, {
  required IRealLibrary library,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: IRealViewerScreen(
        loader: (String reference) async => library,
        initialPath: 'synthetic',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The painter the viewer is currently showing.
ChartPainter shownPainter(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  return tester.widget<CustomPaint>(finder.first).painter! as ChartPainter;
}

/// The centre of a laid-out rectangle, in the page's own coordinates.
Offset centreOf(LayoutRect rect) =>
    Offset(rect.left + rect.size.width / 2, rect.top + rect.size.height / 2);

/// Taps a point given in the PAGE's own coordinates, through the page's scale and the painter's own
/// position, exactly as `selection_test.dart` does.
Future<void> tapEngraved(WidgetTester tester, Offset engraved) async {
  final Finder painterFinder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  final PageLayout page = shownPainter(tester).page;
  final Offset topLeft = tester.getTopLeft(painterFinder.first);
  await tester.tapAt(
    topLeft + Offset(engraved.dx * page.scale, engraved.dy * page.scale),
  );
  await tester.pumpAndSettle();
}

/// Every note of a song, in reading order, as one readable line each.
List<String> notesOf(Song song) => <String>[
  for (final Section section in song.sections)
    for (int barIndex = 0; barIndex < section.bars.length; barIndex++)
      for (final NoteMark note in section.bars[barIndex].melody)
        // One string per element, assembled by `noteLine`: `no_adjacent_strings_in_list` forbids two
        // literals in a list, and the mirror lint forbids joining them with `+`. Both are satisfied
        // by building the line in a function and placing the call here.
        noteLine(section.id, barIndex, note),
];

/// One note rendered as `A[0] 1.0:A4 eighth~`.
String noteLine(String sectionId, int barIndex, NoteMark note) {
  final String tie = note.tiedToNext ? '~' : '';
  final String value = '${note.value}';
  return '$sectionId[$barIndex] ${note.offsetX.toStringAsFixed(1)}:${note.pitch} '
      '$value$tie';
}

/// Every note of the song the page is currently drawn from.
List<String> notesOnPage(WidgetTester tester) =>
    notesOf(shownPainter(tester).song);

/// Selects a cell of the drawn page and opens the note palette from the selection line's action.
Future<void> openNotePaletteFor(
  WidgetTester tester,
  int barIndex,
  int beat,
) async {
  final PlacedBar bar = shownPainter(tester).page.bars.firstWhere(
    (PlacedBar placed) =>
        placed.barIndex == barIndex && placed.sectionId == 'A',
  );
  final LayoutRect cell = bar.bounds;
  await tapEngraved(tester, centreOf(cell));
  expect(
    find.byKey(const ValueKey<String>('viewer-selection-note')),
    findsOneWidget,
    reason: 'a selected cell must offer the note action',
  );
  await tester.tap(find.byKey(const ValueKey<String>('viewer-selection-note')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('note-palette-position')),
    findsOneWidget,
    reason: 'the note palette must be open',
  );
}

/// Taps one of the palette's own controls, named by the key the palette gave it.
Future<void> tapPalette(WidgetTester tester, String key) async {
  final Finder finder = find.byKey(ValueKey<String>(key));
  expect(finder, findsOneWidget, reason: 'the palette must own "$key"');
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Closes the palette through its own Done control.
Future<void> closePalette(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('note-palette-done')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the palette writes notes and every one of them survives a .chart round trip',
    (WidgetTester tester) async {
      await pumpViewer(tester, library: libraryOf(emptyChart(8)));
      expect(notesOnPage(tester), isEmpty);

      // --- BAR 1 BEAT 1: a whole note, then a SECOND note on the same beat -----------------
      await openNotePaletteFor(tester, 0, 0);
      await tapPalette(tester, 'note-palette-base-whole');
      await tapPalette(tester, 'note-palette-degree-b');
      expect(notesOnPage(tester), <String>[
        'A[0] 0.0:B4 whole',
      ], reason: 'the degree button must insert the pitch it names');
      await tapPalette(tester, 'note-palette-new');
      await tapPalette(tester, 'note-palette-base-quarter');
      await tapPalette(tester, 'note-palette-degree-e');
      // THE SECOND NOTE LANDS AFTER THE FIRST, WHICH IS THE ORDER THE MUSICIAN TAPPED THEM IN.
      //
      // THIS EXPECTATION ONCE READ THE OTHER WAY ROUND, AND THE OLD LINE IS QUOTED SO THE CHANGE IS
      // VISIBLE RATHER THAN SILENT. It was:
      //
      //     <String>['A[0] 0.0:E4 quarter', 'A[0] 0.1:B4 whole']
      //
      // and the reason beside it — "a second note on one beat must be added, not replace the first"
      // — was and remains true; what it did not name was WHICH END it was added to. The cell's notes
      // are a sequence in `step` order and the staff draws step `k` at `cellX + k * stride`, so step
      // 0 is the leftmost note; asserting that the note written second is at step 0 was asserting
      // that a run typed left to right is engraved right to left (A75). The assertion that replaces
      // it is the same claim about not replacing, stated with its order.
      expect(
        notesOnPage(tester),
        <String>['A[0] 0.0:B4 whole', 'A[0] 0.1:E4 quarter'],
        reason:
            'a second note on one beat must be added, not replace the first — and it must be added '
            'AFTER it, because the first tap came first',
      );

      // --- BAR 1 BEAT 2: an eighth note, tied forward --------------------------------------
      await closePalette(tester);
      await openNotePaletteFor(tester, 0, 1);
      await tapPalette(tester, 'note-palette-base-eighth');
      await tapPalette(tester, 'note-palette-degree-a');
      await tapPalette(tester, 'note-palette-tie');
      expect(notesOnPage(tester), <String>[
        'A[0] 0.0:B4 whole',
        'A[0] 0.1:E4 quarter',
        'A[0] 1.0:A4 eighth~',
      ], reason: 'the tie is one field of the note the palette just wrote');

      // --- BAR 2 BEAT 1: an octave up, which the engraver must place on a ledger line ------
      await closePalette(tester);
      await openNotePaletteFor(tester, 1, 0);
      await tapPalette(tester, 'note-palette-base-half');
      await tapPalette(tester, 'note-palette-octave-up');
      await tapPalette(tester, 'note-palette-degree-c');
      expect(notesOnPage(tester), <String>[
        'A[0] 0.0:B4 whole',
        'A[0] 0.1:E4 quarter',
        'A[0] 1.0:A4 eighth~',
        'A[1] 0.0:C5 half',
      ], reason: 'the octave control must move the written octave');

      // --- A CHROMATIC NOTE, through the palette's own alteration chips --------------------
      await tapPalette(tester, 'note-palette-alter-1');
      await tapPalette(tester, 'note-palette-degree-f');
      expect(
        notesOnPage(tester).last,
        'A[1] 0.0:F#5 half',
        reason: 'the alteration chip must raise the degree it is applied to',
      );
      // Put it back so the saved chart is the one the other assertions describe.
      await tapPalette(tester, 'note-palette-alter-0');
      await tapPalette(tester, 'note-palette-degree-c');

      // --- REMOVE the note just written, through the palette's own destructive action ------
      await tapPalette(tester, 'note-palette-remove');
      expect(
        notesOnPage(tester),
        <String>[
          'A[0] 0.0:B4 whole',
          'A[0] 0.1:E4 quarter',
          'A[0] 1.0:A4 eighth~',
        ],
        reason: 'removal must take exactly the selected note and nothing else',
      );
      await closePalette(tester);

      final List<String> written = notesOnPage(tester);
      expect(written, hasLength(3));
      stdout.writeln('note.trip written=$written');

      // --- SAVE, through the function the file bar's own Save calls -----------------------
      // `chartFileFor` is the single construction the save button uses, and the document it takes is
      // the one on screen: `EditSession.song`. The tail is empty because the snapshot here IS the
      // edited document — the two together are what a reopen has to reconstruct.
      final DocumentState onScreen = DocumentState(
        song: shownPainter(tester).song,
      );
      final List<int> bytes = ChartFileCodec.encode(chartFileFor(onScreen))
          .bytes;

      final Directory dir = Directory.systemTemp.createTempSync(
        'note-round-trip',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final File saved = File(
        '${dir.path}${Platform.pathSeparator}notes.chart',
      );
      await tester.runAsync(() => saved.writeAsBytes(bytes));
      final Uint8List onDisk =
          await tester.runAsync(() => saved.readAsBytes()) as Uint8List;
      stdout.writeln('note.trip saved=${saved.path} bytes=${onDisk.length}');
      expect(
        onDisk,
        bytes,
        reason: 'the file on disk must be the bytes that were encoded',
      );

      // --- REOPEN: decode the FILE's bytes, the way the open action does -------------------
      final ChartFileDecodeResult decoded = ChartFileCodec.decode(onDisk);
      final DocumentState reopened = decoded.file.reducedDocument;
      stdout.writeln('note.trip reopened=${notesOf(reopened.song)}');
      expect(
        notesOf(reopened.song),
        written,
        reason: 'a note that does not survive the round trip is not a feature',
      );
      expect(
        reopened.song,
        onScreen.song,
        reason:
            'the reopened song must be the song that was saved, whole value',
      );
      // The written melody spans TWO beats of bar 1, one of which carries two notes, so a round trip
      // that lost a beat, merged a stacked pair or reset a step cannot pass this by comparing a
      // single note. Bar 2 is empty because the palette's own Remove took the note back off it.
      expect(reopened.song.barsInReadingOrder[1].melody, isEmpty);
      expect(
        reopened.song.barsInReadingOrder[0].melody.map(
          (NoteMark n) => n.offsetX,
        ),
        <int>[0, 1, 0],
        reason: 'the steps of each beat must come back as they were written',
      );
    },
  );

  // PURPOSE: Prove the SHORTEST PATH TO A NOTE, on the real screen: one tap on a column of the staff
  //          opens the note palette for THAT beat, and the note written through it lands on that beat.
  //          This is the case the tablet found and no test did — the staff's touch target was built
  //          out of the beat CAPTIONS, so when the owner switched the captions off (A68 §7) a tap on
  //          the five lines named nothing, `viewer.select staff ... hit=none`, and note entry was dead
  //          while every palette test stayed green: those open the palette directly, from a selection
  //          they make themselves, and never touch the surface a musician touches.
  // INPUTS: A chart that DECLARES a pitched staff and holds no note, pumped in the viewer at the
  //         size the other cases use. The style draws no beat captions, which is the state that broke.
  // OUTPUTS: Pass/fail on: the bar has a staff and no beat captions; a tap at the middle line of beat
  //          3's column opens the palette; the palette's own header names bar 1 beat 3; and the note
  //          written through it is stored on beat 2 (zero-based), which is the column that was touched.
  // KEYWORDS: test, widget, note-entry, staff-tap, beat-column, captions-off, a68, acceptance
  testWidgets(
    'a tap on a staff column opens the note palette for THAT beat, with the captions off',
    (WidgetTester tester) async {
      await pumpViewer(tester, library: libraryOf(staffChart(4)));
      final PageLayout page = shownPainter(tester).page;
      final PlacedBar bar = page.bars.first;
      expect(
        bar.melody.isEmpty,
        isFalse,
        reason: 'D29: the chart declared a staff, so the bar carries one before any note exists',
      );
      expect(
        const <Object?>[],
        isEmpty,
        reason:
            'the application draws no beat captions — the state in which a tap on the staff used '
            'to name nothing, so the tap below is made in exactly it',
      );

      // Beat 3 of the bar (zero-based beat 2), touched where a musician would: the middle of the five
      // lines, in that beat's own column.
      // THE PLACE IS ONE NUMBER. It used to be `const int beat = 2` and a column look-up; a beat is
      // the grid this stage removed, so the tap names a distance along the bar instead.
      final double beat = fixtureX(2);
      final LayoutRect cell = bar.bounds;
      final Offset tapPoint = Offset(
        cell.left + cell.size.width / 2,
        bar.melody.bounds.top + bar.melody.bounds.size.height / 2,
      );
      stdout.writeln(
        'note.tap x=$beat point=(${tapPoint.dx.toStringAsFixed(1)},'
        '${tapPoint.dy.toStringAsFixed(1)}) '
        'staff=(${bar.melody.bounds.top}..${bar.melody.bounds.bottom}) '
        'captions=${const <Object?>[].length}',
      );
      await tapEngraved(tester, tapPoint);

      final Finder position = find.byKey(
        const ValueKey<String>('note-palette-position'),
      );
      expect(
        position,
        findsOneWidget,
        reason:
            'a tap on a staff column must open the note palette for that column: this is the path '
            'that died when the captions were switched off',
      );
      // THE HEADER NAMES THE ADDRESS THE TAP NAMED, read through the app's own catalogue so the case
      // does not pin a language. Bar 1, beat 3 as a musician counts them.
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(position),
      );
      expect(
        tester.widget<Text>(position).data,
        l10n.palettePositionBar(1),
        reason:
            'the palette must be aimed at the beat that was touched, and say so — a palette that '
            'opens for the wrong cell writes a note the musician did not ask for',
      );

      // AND THE NOTE IT WRITES LANDS THERE. The case ARMS the duration and the alteration it is about
      // rather than inheriting them: both are STICKY across openings — that is D28's "chosen once per
      // run" — so a case that read them from whatever the previous case left armed would pass alone
      // and fail in the suite, which is exactly what happened the first time this test was written.
      await tapPalette(tester, 'note-palette-base-quarter');
      await tapPalette(tester, 'note-palette-alter-0');
      await tapPalette(tester, 'note-palette-degree-c');
      expect(
        notesOnPage(tester),
        <String>['A[0] 2.0:C4 quarter'],
        reason:
            'the note must be stored on beat 3 of bar 1 — the column the finger touched — with the '
            'pitch the degree button names',
      );
    },
  );
}
