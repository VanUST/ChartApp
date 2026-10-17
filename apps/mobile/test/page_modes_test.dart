// PURPOSE: Verify the two surface controls a performer reads on stage: the scene bar that states
//          position, tempo, style, key and repeats, and the FIT / PAGES toggle that decides whether
//          a whole song is on one page or paginated. The charts are built in this file — a synthetic
//          song of repeatable length — so the test never reads the owner's export.
// INPUTS: None. Page sizes are set per test, so "tablet" and "phone" are the window widths the
//         viewer is actually given.
// OUTPUTS: Pass/fail per behaviour.
// KEYWORDS: test, widget, scene-bar, fit, pages, page-mode, repeat-summary, legibility-floor
import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/scene_bar.dart';
import 'package:chartapp/viewer_screen.dart';
// Flutter's widget-identity `Key` would collide with the musical Key this file names.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

// PURPOSE: Build a one-chord-per-bar chart of a requested length, so a test can decide how much
//          music has to fit on the surface.
// INPUTS: bars — how many bars. repeats — whether the passage carries a repeat sign and an
//         alternative ending, which the scene bar must summarise. title — what to call the tune, so
//         two songs in one library are distinguishable by name.
// OUTPUTS: A [Song] in C major at 120 bpm whose single section is labelled A.
// KEYWORDS: fixture, synthetic-song, bar-count, repeat-sign, volta
Song syntheticSong({required int bars, bool repeats = false, String? title}) =>
    Song(
      title: title ?? 'Synthetic $bars',
      composer: 'Test Composer',
      style: 'Medium Swing',
      key: Key.cMajor,
      tempo: 120,
      sections: <Section>[
        Section(
          id: 'A',
          label: const SectionLabel.letter('A'),
          bars: <Bar>[
            for (int index = 0; index < bars; index++)
              Bar(
                chords: <ChordMark>[
                  ChordMark(
                    place: cellAt(0),
                    chord: Chord(root: ChordRoot(0)),
                  ),
                ],
                openingBarline: repeats && index == 0
                    ? Barline.repeatStart
                    : Barline.single,
                closingBarline: repeats && index == bars - 1
                    ? Barline.repeatEnd
                    : Barline.single,
                volta: repeats && index == bars - 2 ? const Volta(1) : null,
              ),
          ],
        ),
      ],
    );

/// A one-song library holding [song].
IRealLibrary libraryOf(Song song) => IRealLibrary(
  playlistName: '',
  songs: <IRealSong>[IRealSong(index: 0, song: song)],
);

/// Pumps the viewer at [size] logical pixels, so the default page mode sees the width under test.
Future<void> pumpViewer(
  WidgetTester tester,
  IRealLibrary library, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      // The application's own delegates and locales, so the screen under test is the one the
      // application builds. `flutter_test` reports `en_US` for the device locale, so these tests
      // read the ENGLISH interface, which is what their assertions name.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: IRealViewerScreen(
        loader: (String path) async => library,
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
  return tester.widget<CustomPaint>(finder).painter! as ChartPainter;
}

void main() {
  // The interface strings the two calls below are compared against are the ENGLISH ones, so the
  // English catalogue is passed explicitly rather than left to a default. Nothing asserted here
  // changed when the lines became translatable: `repeatSummary` grew a parameter, and the words it
  // must produce are the same.
  final AppLocalizations english = lookupAppLocalizations(const Locale('en'));

  test(
    'the repeat summary states an absence as `none` and counts what is written',
    () {
      expect(repeatSummary(syntheticSong(bars: 4), english), 'none');
      expect(
        repeatSummary(syntheticSong(bars: 4, repeats: true), english),
        '1× · 1 volta',
      );
    },
  );

  testWidgets(
    'the scene bar states position, tempo, style, repeats and the page mode',
    (WidgetTester tester) async {
      final IRealLibrary library = IRealLibrary(
        playlistName: 'Rocket',
        songs: <IRealSong>[
          IRealSong(
            index: 0,
            song: syntheticSong(bars: 8, repeats: true, title: 'First Tune'),
          ),
          IRealSong(
            index: 1,
            song: syntheticSong(bars: 8, title: 'Second Tune'),
          ),
        ],
      );
      await pumpViewer(tester, library);

      // The first song of two.
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Medium Swing'), findsOneWidget);
      expect(find.text('1× · 1 volta'), findsOneWidget);
      expect(find.text('C major · 0 st'), findsOneWidget);

      // Selecting the second song moves the position; that is the playlist position D8 asks for.
      await tester.tap(find.text('Second Tune'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('none'), findsOneWidget);
    },
  );

  testWidgets('a tablet opens in FIT and puts the whole song on one page', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, libraryOf(syntheticSong(bars: 200)));

    expect(find.byType(PageView), findsNothing);
    final ChartPainter painter = shownPainter(tester);
    expect(painter.page.bars, hasLength(200));
    expect(painter.page.scale, lessThan(1));
  });

  testWidgets('PAGES paginates the same song after one tap', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, libraryOf(syntheticSong(bars: 200)));
    expect(shownPainter(tester).page.bars, hasLength(200));

    await tester.tap(
      find.byKey(const ValueKey<String>('scene-bar-mode-pages')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(shownPainter(tester).page.bars.length, lessThan(200));
    expect(shownPainter(tester).page.scale, 1);

    // And back to FIT with one more tap.
    await tester.tap(find.byKey(const ValueKey<String>('scene-bar-mode-fit')));
    await tester.pumpAndSettle();
    expect(shownPainter(tester).page.bars, hasLength(200));
  });

  // THIS TEST FORMERLY ASSERTED THE DEFECT, AND THAT IS SAID HERE RATHER THAN QUIETLY EDITED AWAY.
  // It read `expect(find.byType(PageView), findsNothing)` beside the message: it asserted that a song
  // FIT could not fit produced NO CHART AT ALL. That is exactly what a musician was given at 915x412,
  // and the assertion was not wrong about the old behaviour — the behaviour was wrong. The FIT
  // fallback (docs/sdd.md A50) makes the old assertion unsatisfiable by design, so the expectation is
  // rewritten to the new contract: PAGES with the explanation over it. It is rewritten rather than
  // deleted, and it still checks the message, because a fallback that drew nothing but kept the words
  // would pass a test that only looked for the words.
  testWidgets(
    'a song that cannot fit legibly falls back to pages and says why',
    (WidgetTester tester) async {
      await pumpViewer(tester, libraryOf(syntheticSong(bars: 900)));

      expect(find.byType(PageView), findsOneWidget);
      expect(shownPainter(tester).page.bars, isNotEmpty);
      expect(shownPainter(tester).page.scale, 1);
      expect(find.textContaining('does not fit on one page'), findsOneWidget);
      expect(find.textContaining('Shown as pages instead'), findsOneWidget);
    },
  );

  testWidgets('a phone-width window opens in PAGES', (
    WidgetTester tester,
  ) async {
    await pumpViewer(
      tester,
      libraryOf(syntheticSong(bars: 8)),
      size: const Size(599, 900),
    );

    expect(find.byType(PageView), findsOneWidget);
  });
}
