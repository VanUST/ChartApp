// PURPOSE: Verify the workflow the owner named as the purpose of the product, from the interface:
//          select a RUN of bars with two touches, read what the selection is made of, copy it, paste
//          it at the end, and transpose the pasted run up a semitone — with the page showing the run
//          highlighted and the chart gaining the bars. It is a widget test because the failure this
//          guards against lives in the interface and not in the model: an action that is not reachable
//          or a range the painter was never told about would pass every model test and be useless.
// INPUTS: None. The chart is synthetic, so the test never depends on the owner's export.
// OUTPUTS: Pass/fail per behaviour, plus the viewer's own `viewer.selection.*` log lines on stdout.
// KEYWORDS: test, widget, selection, range, copy, paste, transpose, ink-kept, one-undo, d35, d36
import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
// Flutter's widget-identity `Key` would collide with the musical Key this file names.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

/// A chart of [bars] bars, one section labelled A, a chord on beat 0 of every bar and a second chord
/// on beat 2 of every even bar — enough for a transposition to have something to move and for a cell
/// to be a different address from its bar.
Song _chart(int bars) => Song(
  title: 'Selection clip $bars',
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
            chords: <BeatChord>[
              BeatChord(
                chord: Chord(
                  root: ChordRoot(index),
                  quality: ChordQuality.minorSeventh,
                ),
                beat: 0,
              ),
              if (index.isEven)
                BeatChord(chord: Chord(root: ChordRoot(index + 2)), beat: 2),
            ],
          ),
      ],
    ),
  ],
);

/// A one-song library holding [song].
IRealLibrary _libraryOf(Song song) => IRealLibrary(
  playlistName: '',
  songs: <IRealSong>[IRealSong(index: 0, song: song)],
);

/// Pumps the viewer on a tablet-sized surface in the application's own localizations.
Future<void> _pumpViewer(WidgetTester tester, IRealLibrary library) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
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
ChartPainter _painter(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  return tester.widget<CustomPaint>(finder.first).painter! as ChartPainter;
}

/// Taps a point given in the PAGE's engraved coordinates, converted through the page scale — the
/// same conversion the other selection test uses, so this test aims from geometry and not from a
/// pixel somebody measured once.
Future<void> _tapEngraved(WidgetTester tester, Offset engraved) async {
  final Finder painterFinder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  final PageLayout page = _painter(tester).page;
  final Offset topLeft = tester.getTopLeft(painterFinder.first);
  final Offset surface = Offset(
    engraved.dx * page.scale,
    engraved.dy * page.scale,
  );
  await tester.tapAt(topLeft + surface);
  await tester.pumpAndSettle();
}

/// The centre of a rectangle in the page's own coordinates.
Offset _centreOf(LayoutRect rect) =>
    Offset(rect.left + rect.size.width / 2, rect.top + rect.size.height / 2);

/// Taps the chord-line centre of cell [beat] of [bar].
Future<void> _tapCell(WidgetTester tester, PlacedBar bar, int beat) =>
    _tapEngraved(tester, _centreOf(bar.cells[beat].bounds));

void main() {
  testWidgets('two touches select a run of bars and the page says how much of '
      'it carries structure', (WidgetTester tester) async {
    await _pumpViewer(tester, _libraryOf(_chart(16)));
    final PageLayout page = _painter(tester).page;

    await _tapCell(tester, page.bars[0], 0);
    expect(_painter(tester).selection, isNotNull);
    expect(
      find.byKey(const ValueKey<String>('viewer-selection-extend')),
      findsOneWidget,
      reason: 'the run is armed by a named action, not by a hidden gesture',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-selection-extend')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('viewer-selection-extend-prompt')),
      findsOneWidget,
      reason: 'while the second end is awaited the line says so',
    );

    await _tapCell(tester, page.bars[7], 0);

    final ChartSelection? range = _painter(tester).selectionRange;
    expect(
      range,
      isNotNull,
      reason:
          'the painter is told the run, so the page '
          'can highlight eight bars rather than one',
    );
    expect(range!.sectionId, 'A');
    expect(range.firstBar, 0);
    expect(range.lastBar, 7);
    expect(range.barCount, 8);
    expect(
      find.text('selected: bars 1–8'),
      findsOneWidget,
      reason: 'the label names the run in the musician\'s own counting',
    );
    // THE TWO LEVELS OF QUALITY, IN WORDS. Eight bars carry a chord on beat 0, so all eight
    // transpose; nothing on them is handwriting only. A musician must be able to read that.
    expect(
      find.text('8 bars: structure 8, handwriting only 0, empty 0'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('viewer-selection-transpose')),
      findsOneWidget,
    );
  });

  testWidgets('copy, paste at the end and transpose the pasted run — the '
      'owner\'s four steps, from the interface', (WidgetTester tester) async {
    await _pumpViewer(tester, _libraryOf(_chart(8)));
    final PageLayout page = _painter(tester).page;

    // 1. SELECT bars 1..8.
    await _tapCell(tester, page.bars[0], 0);
    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-selection-extend')),
    );
    await tester.pumpAndSettle();
    await _tapCell(tester, page.bars[7], 0);
    expect(_painter(tester).selectionRange!.barCount, 8);

    // 2. COPY.
    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-selection-copy')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('viewer-selection-paste')),
      findsOneWidget,
      reason: 'the paste action appears once something is copied',
    );
    expect(find.text('copied 8 bars from bar 1'), findsOneWidget);

    // 3. PASTE at the end: the selection still covers the last bar, so the run lands after it.
    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-selection-paste')),
    );
    await tester.pumpAndSettle();
    expect(
      _painter(tester).song.sections.first.bars.length,
      16,
      reason: 'eight copied bars pasted at the end make sixteen',
    );
    expect(find.text('8 bars pasted after bar 8'), findsOneWidget);

    // 4. TRANSPOSE the pasted eight: select them and press the action.
    final PageLayout grown = _painter(tester).page;
    await _tapCell(tester, grown.bars[8], 0);
    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-selection-extend')),
    );
    await tester.pumpAndSettle();
    await _tapCell(tester, grown.bars[15], 0);
    await tester.tap(
      find.byKey(const ValueKey<String>('viewer-selection-transpose')),
    );
    await tester.pumpAndSettle();

    final Song shown = _painter(tester).song;
    expect(
      find.text('moved up a semitone: 8 of 8 bars changed'),
      findsOneWidget,
    );
    expect(
      shown.key,
      Key.cMajor,
      reason: 'a selection transposition does not change the key of the chart',
    );
    expect(
      shown.sections.first.bars[8].chords
          .firstWhere((BeatChord placed) => placed.beat == 0)
          .chord
          .root
          .pitchClass,
      1,
      reason:
          'bar 9 is the copy of bar 1, whose root was C, moved up a semitone',
    );
    expect(
      shown.sections.first.bars[0].chords
          .firstWhere((BeatChord placed) => placed.beat == 0)
          .chord
          .root
          .pitchClass,
      0,
      reason: 'the source bar did not move',
    );
  });

  testWidgets(
    'a run of pure handwriting is selectable, copyable and pasteable, '
    'and is reported as handwriting only',
    (WidgetTester tester) async {
      // A chart with no chord and no note anywhere: this is the owner's own case — four bars of
      // handwriting copied to another place with no recognition in the path.
      final Song bare = Song(
        title: 'Handwriting only',
        key: Key.cMajor,
        tempo: 120,
        sections: <Section>[
          Section(
            id: 'A',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[for (int index = 0; index < 4; index++) Bar()],
          ),
        ],
      );
      await _pumpViewer(tester, _libraryOf(bare));
      final PageLayout page = _painter(tester).page;

      await _tapCell(tester, page.bars[0], 0);
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-selection-extend')),
      );
      await tester.pumpAndSettle();
      await _tapCell(tester, page.bars[3], 0);

      expect(_painter(tester).selectionRange!.barCount, 4);
      expect(
        find.text('4 bars: structure 0, handwriting only 0, empty 4'),
        findsOneWidget,
        reason:
            'the musician is told these bars carry no structure, so nothing '
            'here will transpose',
      );

      // AND THE TRANSPOSITION REFUSES RATHER THAN WRITING AN EMPTY EVENT, before anything is pasted:
      // the line says why, in words, and the chart does not change.
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-selection-transpose')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Nothing was transposed: those bars hold no chord and no note.',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-selection-copy')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-selection-paste')),
      );
      await tester.pumpAndSettle();
      expect(
        _painter(tester).song.sections.first.bars.length,
        8,
        reason: 'four bars of handwriting pasted at the end make eight',
      );
    },
  );
}
