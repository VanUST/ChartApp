// PURPOSE: Verify the page modes that REMAIN: the mode a surface is given by its own width, and the
//          FIT fallback that shows a song too long to fit legibly as pages with a band saying why.
//          The charts are built in this file — a synthetic song of repeatable length — so the test
//          never reads the owner's export.
//
//          TWO CASES THAT STOOD HERE ARE DELETED WITH THEIR SUBJECT, NOT REWRITTEN TO PASS
//          (`docs/sdd.md` A83). They were «the scene bar states position, tempo, style, repeats and
//          the page mode» and «PAGES paginates the same song after one tap». The first read the
//          scene bar's musical fields, which the reset deleted: the bar is now the magnification and
//          nothing else. The second pressed the scene bar's PAGES and FIT controls, and THOSE
//          CONTROLS NO LONGER EXIST — the musician no longer chooses a mode, the surface does. A
//          test of a control that is gone is a memory of a feature, not a check of one; what proves
//          the mode today is the three cases below, which read the mode the surface was actually
//          given and the fallback that overrides it.
// INPUTS: None. Page sizes are set per test, so "tablet" and "phone" are the window widths the
//         viewer is actually given.
// OUTPUTS: Pass/fail per behaviour, plus `page.test` lines naming the mode and the scale the pane
//          produced, so the numbers the assertions rest on can be read rather than only trusted.
// KEYWORDS: test, widget, fit, pages, page-mode-by-surface, fit-fallback, legibility-floor
import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
// Flutter's widget-identity `Key` would collide with the musical Key this file names.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

// PURPOSE: Build a one-chord-per-bar chart of a requested length, so a test can decide how much
//          music has to fit on the surface.
// INPUTS: bars — how many bars. It is the only knob left: the repeat marks and the title this
//         fixture used to carry existed to feed the scene bar's summary line, and that line is
//         deleted with the rest of the bar's musical fields.
// OUTPUTS: A [Song] in C major at 120 bpm whose single section is labelled A.
// KEYWORDS: fixture, synthetic-song, bar-count
Song syntheticSong(int bars) => Song(
  title: 'Synthetic $bars',
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
                place: placeAt(0),
                chord: Chord(root: ChordRoot(0)),
              ),
            ],
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
  testWidgets('a tablet opens in FIT and puts the whole song on one page', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, libraryOf(syntheticSong(200)));

    expect(find.byType(PageView), findsNothing);
    final ChartPainter painter = shownPainter(tester);
    expect(painter.page.bars, hasLength(200));
    expect(painter.page.scale, lessThan(1));
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
      await pumpViewer(tester, libraryOf(syntheticSong(900)));

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
      libraryOf(syntheticSong(8)),
      size: const Size(599, 900),
    );

    expect(find.byType(PageView), findsOneWidget);
  });
}
