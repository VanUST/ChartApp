// PURPOSE: Verify the interaction the selection feature exists for: a tap on the glass names the
//          bar and cell under it, the label above the chart states that position in words, and the
//          painter is handed a selection it can highlight. The tap is aimed from the LAYOUT's own
//          rectangle for the cell, converted through the page scale, so the test fails if the
//          viewer hits the page in the wrong coordinate space — which is the fitted-page bug this
//          feature exists to avoid.
// INPUTS: None. The chart is synthetic, so the test never depends on the owner's export.
// OUTPUTS: Pass/fail per behaviour, plus the viewer's own `viewer.select ...` log lines on stdout.
// KEYWORDS: test, widget, selection, hit-test, tap, fit-scale, page-mode, label, falsifiable
import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
// Flutter's widget-identity `Key` would collide with the musical Key this file names.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

// PURPOSE: Build a one-chord-per-bar chart long enough that FIT must shrink it, so the page scale
//          under test is not 1 and a hit test that ignored the scale would answer differently.
// INPUTS: bars — how many bars the single section holds.
// OUTPUTS: A [Song] in C major, one section labelled A.
// KEYWORDS: fixture, synthetic-song, long-chart, fitted-page
Song longChart(int bars) => Song(
  title: 'Selection $bars',
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

/// Pumps the viewer at [size] logical pixels.
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
      // The application's own delegates, so the screen under test is the one the application
      // builds. `flutter_test` reports `en_US` as the device locale, so this reads the ENGLISH
      // interface, which is what the assertions below name.
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
  return tester.widget<CustomPaint>(finder.first).painter! as ChartPainter;
}

// PURPOSE: Tap a point given in the PAGE's engraved coordinates, by converting it to the surface
//          the painter drew it on and then to a global position in the test window. Aiming from the
//          layout's rectangle rather than from a hard-coded pixel is what makes this a test of the
//          transform: the same cell is at a different pixel on a fitted page.
// INPUTS: tester — the running test. engraved — a point in the page's own coordinates.
// OUTPUTS: Nothing; completes once the tap has been dispatched and the frame settled.
// KEYWORDS: tap, coordinate-transform, page-scale, global-position, aim-from-geometry
Future<void> tapEngraved(WidgetTester tester, Offset engraved) async {
  final Finder painterFinder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  final PageLayout page = shownPainter(tester).page;
  final Offset topLeft = tester.getTopLeft(painterFinder.first);
  final Offset surface = Offset(
    engraved.dx * page.scale,
    engraved.dy * page.scale,
  );
  await tester.tapAt(topLeft + surface);
  await tester.pumpAndSettle();
}

/// The centre of a rectangle, in the page's own coordinates.
Offset centreOf(LayoutRect rect) =>
    Offset(rect.left + rect.size.width / 2, rect.top + rect.size.height / 2);

void main() {
  testWidgets(
    'a tap on a fitted page selects the cell it was aimed at and says so',
    (WidgetTester tester) async {
      await pumpViewer(tester, libraryOf(longChart(200)));

      final ChartPainter before = shownPainter(tester);
      final PageLayout page = before.page;
      expect(
        page.scale,
        lessThan(1),
        reason: 'this test is only meaningful when FIT has shrunk the page',
      );
      expect(before.selection, isNull);

      // A bar near the END of the chart: on a fitted page a hit test that forgot the scale reads
      // the tap as an earlier bar, so a bar near the end makes that mistake visible rather than
      // landing on the right bar by luck.
      final PlacedBar bar = page.bars[page.bars.length - 3];
      final PlacedCell cell = bar.cells[1];
      await tapEngraved(tester, centreOf(cell.bounds));

      final ChartPainter after = shownPainter(tester);
      expect(after.selection, isNotNull);
      expect(after.selection!.sectionId, bar.sectionId);
      expect(after.selection!.barIndex, bar.barIndex);
      expect(after.selection!.beat, 1);
      // Single section, so the global ordinal is the bar index plus one; the model's zero-based
      // beat 1 is the musician's cell 2.
      expect(
        find.text('selected: bar ${bar.barIndex + 1} cell 2'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a tap in the margin between systems clears the selection', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, libraryOf(longChart(200)));
    final PageLayout page = shownPainter(tester).page;

    // Select something first, so the clearing is observable rather than the initial state.
    await tapEngraved(tester, centreOf(page.bars.first.cells.first.bounds));
    expect(find.textContaining('selected: bar 1 cell 1'), findsOneWidget);

    // Then tap the gap between the first two systems, where no bar is.
    final PlacedSystem first = page.systems.first;
    final PlacedSystem second = page.systems[1];
    final double gapY = (first.bounds.bottom + second.bounds.top) / 2;
    await tapEngraved(tester, Offset(page.bars.first.bounds.left + 5, gapY));

    expect(shownPainter(tester).selection, isNull);
    // WAS: expect(find.text('Tap a bar to select it.'), findsOneWidget);
    // CHANGED BECAUSE THE SENTENCE CHANGED, NOT THE BEHAVIOUR. The line now names BOTH things the
    // Select tool does, because the owner reported that he could not find selection at all: with the
    // pen tool in force this same line promised "tap a bar to select it" while a touch drew, so the
    // one sentence a musician reads was describing a tool that was not the one under his hand. What
    // this test pins — a miss between two systems clears the selection — is untouched.
    expect(
      find.text('Tap a bar to select it. A drag moves the sheet.'),
      findsOneWidget,
    );
  });

  testWidgets('PAGES selects on a page whose scale is 1', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, libraryOf(longChart(200)));
    await tester.tap(
      find.byKey(const ValueKey<String>('scene-bar-mode-pages')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    final ChartPainter painter = shownPainter(tester);
    expect(painter.page.scale, 1);

    final PlacedBar bar = painter.page.bars[2];
    final PlacedCell cell = bar.cells[3];
    await tapEngraved(tester, centreOf(cell.bounds));

    final ChartPainter after = shownPainter(tester);
    expect(after.selection!.barIndex, bar.barIndex);
    expect(after.selection!.beat, 3);
    expect(
      find.text('selected: bar ${bar.barIndex + 1} cell 4'),
      findsOneWidget,
    );
  });
}
