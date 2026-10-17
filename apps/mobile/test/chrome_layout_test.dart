// PURPOSE: Measure what the owner's "make the top block open and close" decision actually bought,
//          in the only currency the document has: the pane's logical width and height, and how much
//          of a real chart fits in it. It exists because a screenshot can show a bigger page without
//          showing that it is bigger, and because this project has three times caught a claim about
//          a layout that sounded measured and was not.
//
//          WHY THE PANE AND NOT THE PAGE. `FIT` engraves from the pane's width AND its verdict
//          depends on the pane's height (`viewer_screen.dart` says so beside `_buildPages`), so a
//          chart that fell back to pages before may fit in one page after — and that is a WIN only
//          if it is measured, not asserted. The pane is the rectangle the shell gives the document,
//          which is the `viewer-document-frame` the shell draws.
//
//          WHY THE TABLET'S OWN NUMBERS. The owner works on a 1752x2800 tablet at 340 dpi held in
//          LANDSCAPE, which is 1318 x 824 logical pixels of window. A test pumped at any other size
//          would be measuring a surface nobody uses, and the whole question is about HIS screen.
// INPUTS: None. The chart is synthetic and the layout is deterministic, so this runs on any machine
//         with no device and no font.
// OUTPUTS: Pass/fail on the two claims that matter — the hidden pane is strictly larger on both
//          axes, and the chart does not lose a system to gain the room — plus the numbers each claim
//          rests on, printed so the arithmetic can be read rather than only trusted.
// KEYWORDS: test, layout, chrome-hidden, pane-measurement, fit-verdict, tablet-landscape,
//           owner-decision, measurable-claim
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

/// The owner's tablet, in logical pixels: 1752x2800 at 340 dpi, held in LANDSCAPE.
const Size _tabletLandscape = Size(2800 / 2.125, 1752 / 2.125);

/// A chart long enough that the pane's height decides how much of it is on screen: four sections of
/// sixteen bars, which is the shape of the tunes this application is for.
Song longChart() => Song(
  id: 'chrome-layout',
  title: 'Chrome layout',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 132,
  sections: <Section>[
    for (int section = 0; section < 4; section++)
      Section(
        id: 'S$section',
        label: SectionLabel.letter(String.fromCharCode(65 + section)),
        bars: <Bar>[
          for (int index = 0; index < 16; index++)
            Bar(
              chords: <ChordMark>[
                ChordMark(
                  place: cellAt(0),
                  chord: Chord(
                    root: ChordRoot(index % 12),
                    quality: ChordQuality.majorSeventh,
                  ),
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

/// The pane the shell has given the document, as the shell itself frames it.
Size paneSize(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey<String>('viewer-document-frame')));

/// The system count of the chart currently on screen, which is what the pane's height buys.
int systemCount(WidgetTester tester) => chartPage(tester).systems.length;

/// The chart's own scale, which is what the pane's height buys in FIT: the same music, engraved
/// bigger, which is the whole reason a performer wants the room.
double pageScale(WidgetTester tester) => chartPage(tester).scale;

/// The page the chart painter is currently drawing.
PageLayout chartPage(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  return (tester.widget<CustomPaint>(finder).painter! as ChartPainter).page;
}

void main() {
  testWidgets('hiding the chrome gives the document more pane on a tablet', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = _tabletLandscape;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IRealViewerScreen(
          loader: (String path) async => libraryOf(longChart()),
          initialPath: 'synthetic',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Size shown = paneSize(tester);
    final int shownSystems = systemCount(tester);
    final double shownScale = pageScale(tester);
    stdout.writeln(
      'chrome.test.shown window=${_tabletLandscape.width.toStringAsFixed(1)}x'
      '${_tabletLandscape.height.toStringAsFixed(1)} '
      'pane=${shown.width.toStringAsFixed(1)}x${shown.height.toStringAsFixed(1)} '
      'area=${(shown.width * shown.height).toStringAsFixed(0)} '
      'systems=$shownSystems scale=${shownScale.toStringAsFixed(4)}',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
    );
    await tester.pumpAndSettle();

    final Size hidden = paneSize(tester);
    final int hiddenSystems = systemCount(tester);
    final double hiddenScale = pageScale(tester);
    stdout.writeln(
      'chrome.test.hidden '
      'pane=${hidden.width.toStringAsFixed(1)}x${hidden.height.toStringAsFixed(1)} '
      'area=${(hidden.width * hidden.height).toStringAsFixed(0)} '
      'systems=$hiddenSystems scale=${hiddenScale.toStringAsFixed(4)} '
      'gain_w=${(hidden.width - shown.width).toStringAsFixed(1)} '
      'gain_h=${(hidden.height - shown.height).toStringAsFixed(1)} '
      'gain_area_pct=${(((hidden.width * hidden.height) / (shown.width * shown.height) - 1) * 100).toStringAsFixed(1)}',
    );

    expect(
      hidden.width,
      greaterThan(shown.width),
      reason: 'the library rail costs the document its whole width',
    );
    expect(
      hidden.height,
      greaterThan(shown.height),
      reason: 'the top block costs the document its whole height',
    );
    expect(
      hiddenSystems,
      greaterThanOrEqualTo(shownSystems),
      reason: 'the room is a gain, not a trade: a taller pane must not lose the chart a system',
    );

    // Back again, and the numbers must be the ones the shown state started with: a toggle that
    // does not restore what it hid is a state the musician cannot leave.
    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
    );
    await tester.pumpAndSettle();
    final Size restored = paneSize(tester);
    stdout.writeln(
      'chrome.test.restored '
      'pane=${restored.width.toStringAsFixed(1)}x${restored.height.toStringAsFixed(1)}',
    );
    expect(restored.width, shown.width);
    expect(restored.height, shown.height);
  });

  testWidgets('the short landscape surface keeps a whole system in both states', (
    WidgetTester tester,
  ) async {
    // THE TRAP THIS PROJECT ALREADY PAID FOR. `viewer_screen.dart` records that the full scene bar
    // has already wrapped to two rows and left the chart pane 65 logical pixels tall, and
    // `_isBarCompact` / `sceneBarTabletHeight` exist because of it. A hideable top block makes that
    // failure both easier to avoid and easier to hide: at this window the chart pane can only hold a
    // system at all if the shell spends its height well, and the collapsed state must not be the one
    // that strands it.
    //
    // 915 x 412 is the built web application's size in A49, where the two-row bar left the pane 65
    // logical pixels. ONE SYSTEM IS `pageMargin + sectionLabelHeight + barHeight` = 98 logical
    // pixels, which is the file's own number and the floor this case is measured against.
    const double oneSystemPx = 98;
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IRealViewerScreen(
          loader: (String path) async => libraryOf(longChart()),
          initialPath: 'synthetic',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Size shown = paneSize(tester);
    stdout.writeln(
      'chrome.test.short.shown pane=${shown.width.toStringAsFixed(1)}x'
      '${shown.height.toStringAsFixed(1)} systems=${systemCount(tester)}',
    );
    expect(
      shown.height,
      greaterThan(oneSystemPx),
      reason: 'the shown state must not strand the chart below one system',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
    );
    // ONE FRAME, NOT `pumpAndSettle`: the transitional state is the one this test is about, and a
    // transition that passed through a stranded layout would be invisible after it settled.
    await tester.pump();
    final Size transitional = paneSize(tester);
    await tester.pumpAndSettle();
    final Size hidden = paneSize(tester);
    stdout.writeln(
      'chrome.test.short.transition pane=${transitional.width.toStringAsFixed(1)}x'
      '${transitional.height.toStringAsFixed(1)}',
    );
    stdout.writeln(
      'chrome.test.short.hidden pane=${hidden.width.toStringAsFixed(1)}x'
      '${hidden.height.toStringAsFixed(1)} systems=${systemCount(tester)}',
    );
    expect(hidden.height, greaterThan(shown.height));
    expect(
      hidden.height,
      greaterThan(oneSystemPx),
      reason: 'the collapsed state must not strand the chart either',
    );
    expect(
      transitional.height,
      greaterThan(oneSystemPx),
      reason:
          'THE TRANSITION IS A STATE TOO: a frame that reflowed the bar into two rows would strand '
          'the chart there, and a settled screenshot would never show it',
    );
  });
}
