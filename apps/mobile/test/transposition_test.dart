// PURPOSE: Verify the transposition control a musician actually uses: the key badge opens a
//          twelve-key grid, picking a key transposes the chart and its label, the interval is shown
//          in semitones, and two taps are enough. The payload is built in this file, so the test
//          never reads the owner's export.
// INPUTS: None. The chart is one song written in D major with the same chords the owner's
//         ground-truth song uses at the point the transposition is checked, so "D^ becomes E^ and
//         E7 becomes F#7" is asserted on chords rather than on a rendered image.
// OUTPUTS: Pass/fail per behaviour.
// KEYWORDS: test, widget, transposition, key-grid, two-taps, semitone-interval, spelling-policy
import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
// Flutter's widget-identity `Key` would collide with the musical Key this file names.
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

/// The key the synthetic chart is written in: D major, as the owner's ground-truth song is.
const Key _dMajor = Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major);

// PURPOSE: Build a one-song payload in D major with the chord pair the ground truth checks, in the
//          export's ten-field layout, so the widget test exercises the real import path.
// INPUTS: None. The notation is written here and obfuscated with the library's own encoder, so the
//         payload cannot drift from the codec.
// OUTPUTS: A decoded payload string whose one song is `D^ | E7 | D^ | E7`, tempo 120, style
//          Medium Swing.
// KEYWORDS: fixture, synthetic-payload, d-major, obfuscation, ten-field-layout
String syntheticDPayload() {
  const String notation = '*AT44D^ |E7 |D^ |E7 Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  return 'Test Tune=Test Composer==Medium Swing=D=0=$music=Medium Swing=120=1';
}

/// The painter the viewer is currently showing.
ChartPainter _shownPainter(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  return tester.widget<CustomPaint>(finder).painter! as ChartPainter;
}

void main() {
  const SpellingTable table = SpellingTable();

  test(
    'the synthetic payload is in D major with D^ and E7 in the first two bars',
    () {
      final Song song = parseIRealLibrary(syntheticDPayload())
          .songs
          .single
          .song;
      expect(song.key, _dMajor);
      expect(song.barsInReadingOrder, hasLength(4));
      expect(
        song.barsInReadingOrder[0].chords.first.chord.render(song.key, table),
        'D^',
      );
      expect(
        song.barsInReadingOrder[1].chords.first.chord.render(song.key, table),
        'E7',
      );
    },
  );

  test('the twelve-key grid puts E two semitones above D and spells the rest practically', () {
    final List<TranspositionTarget> targets = const TranspositionGrid().targets(
      _dMajor,
    );
    expect(targets, hasLength(12));
    expect(
      targets.every((TranspositionTarget target) => target.available),
      isTrue,
    );

    final Map<int, TranspositionTarget> bySemitones =
        <int, TranspositionTarget>{
          for (final TranspositionTarget target in targets)
            target.semitones: target,
        };
    expect(bySemitones, hasLength(12));
    expect(bySemitones[0]!.key, _dMajor);
    expect(bySemitones[2]!.key.toString(), 'E major');
    // Up a semitone from D is written Eb, not D# major, which is nine sharps and off the circle.
    expect(bySemitones[1]!.key.tonic.toString(), 'Eb');
    expect(bySemitones[1]!.key.isPracticallySpelled, isTrue);
    // Down two semitones is C major, and the tritone up is Ab, not G# major.
    expect(bySemitones[-2]!.key.toString(), 'C major');
    expect(bySemitones[6]!.key.tonic.toString(), 'Ab');
    // A key that cannot be spelled in either direction is reported unavailable, which is what the
    // grid disables. The twelve pitch classes are all spellable for D major, so this is stated on a
    // key whose own tonic is off the practical circle instead.
    const Key dSharpMajor = Key(
      tonic: WrittenNote(NoteLetter.d, 1),
      mode: Mode.major,
    );
    expect(dSharpMajor.isPracticallySpelled, isFalse);
  });

  test('transposing the song up two semitones moves the key and the chords, not the written copy', () {
    final Song written = parseIRealLibrary(syntheticDPayload())
        .songs
        .single
        .song;
    final Key target = const TranspositionGrid()
        .targets(_dMajor)
        .firstWhere((TranspositionTarget entry) => entry.semitones == 2)
        .key;
    final Song moved = transposeSong(written, 2, toKey: target);

    expect(moved.key.toString(), 'E major');
    expect(moved.barsInReadingOrder, hasLength(4));
    expect(
      moved.barsInReadingOrder[0].chords.first.chord.render(moved.key, table),
      'E^',
    );
    expect(
      moved.barsInReadingOrder[1].chords.first.chord.render(moved.key, table),
      'F#7',
    );
    // Same bars, same beats.
    expect(
      moved.barsInReadingOrder[1].chords.first.beat,
      written.barsInReadingOrder[1].chords.first.beat,
    );
    // The written chart is untouched.
    expect(written.key, _dMajor);
    expect(
      written.barsInReadingOrder[0].chords.first.chord.render(
        written.key,
        table,
      ),
      'D^',
    );
    expect(
      written.barsInReadingOrder[1].chords.first.chord.render(
        written.key,
        table,
      ),
      'E7',
    );
  });

  testWidgets(
    'two taps transpose the chart: the key badge, then E in the grid',
    (WidgetTester tester) async {
      final IRealLibrary library = parseIRealLibrary(syntheticDPayload());
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

      // The chart opens in its written key, with the interval stated as the musician says it.
      expect(find.text('D major · 0 st'), findsOneWidget);
      expect(_shownPainter(tester).song.key, _dMajor);

      // Tap one: the key badge opens the grid.
      await tester.tap(
        find.byKey(const ValueKey<String>('scene-bar-key-badge')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('key-grid')), findsOneWidget);
      expect(find.text('Transpose — written in D major'), findsOneWidget);

      // Tap two: E. That is the whole transposition budget.
      await tester.tap(find.text('E'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('key-grid')), findsNothing);
      expect(find.text('E major · +2 st'), findsOneWidget);
      final ChartPainter painter = _shownPainter(tester);
      expect(painter.song.key.toString(), 'E major');
      expect(
        painter.page.bars.first.chords.first.chord.render(
          painter.song.key,
          table,
        ),
        'E^',
      );
      expect(
        painter.page.bars[1].chords.first.chord.render(painter.song.key, table),
        'F#7',
      );
    },
  );

  testWidgets('dismissing the grid leaves the chart in its written key', (
    WidgetTester tester,
  ) async {
    final IRealLibrary library = parseIRealLibrary(syntheticDPayload());
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

    await tester.tap(find.byKey(const ValueKey<String>('scene-bar-key-badge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('D major · 0 st'), findsOneWidget);
    expect(_shownPainter(tester).song.key, _dMajor);
  });
}
