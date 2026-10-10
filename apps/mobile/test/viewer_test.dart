// PURPOSE: Verify that the viewer turns a payload into a rendered page, using a payload built in
//          this file rather than the owner's export. The owner's file proves the reader works on
//          one machine; this test proves the wiring without depending on it.
// INPUTS: None.
// OUTPUTS: Pass/fail per behaviour.
// KEYWORDS: test, widget, viewer, synthetic-payload, chart-painter, rendered-page
import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// PURPOSE: Build a one-song payload in the export's ten-field layout, so the test exercises the
//          same parse path the reader's file does.
// INPUTS: None. The notation is written here in the chart grammar and obfuscated with the library's
//         own encoder, so the payload cannot drift from the codec.
// OUTPUTS: A decoded payload string with a title, a composer, a style, a key, a music field and a
//          tempo. Ten fields, so no completeness issue is reported.
// KEYWORDS: fixture, synthetic-payload, obfuscation, ten-field-layout
String syntheticPayload() {
  const String notation = '*AT44C^ |F^ |G7 |C^ Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  return 'Test Tune=Test Composer==Medium Swing=C=0=$music=Medium Swing=120=1';
}

void main() {
  test('the synthetic payload parses into one four-bar song', () {
    final IRealLibrary library = parseIRealLibrary(syntheticPayload());

    expect(library.songs, hasLength(1));
    expect(library.songs.single.song.writtenBarCount, 4);
    expect(library.songs.single.issues, isEmpty);
  });

  testWidgets('the viewer renders a page for a synthetic payload', (
    WidgetTester tester,
  ) async {
    final IRealLibrary library = parseIRealLibrary(syntheticPayload());

    await tester.pumpWidget(
      MaterialApp(
        home: IRealViewerScreen(
          loader: (String path) async => library,
          initialPath: 'synthetic',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The song appears in the list and in the pane header.
    expect(find.text('Test Tune'), findsWidgets);

    final Finder painterFinder = find.byWidgetPredicate(
      (Widget widget) =>
          widget is CustomPaint && widget.painter is ChartPainter,
    );
    expect(painterFinder, findsOneWidget);

    final ChartPainter painter =
        tester.widget<CustomPaint>(painterFinder).painter! as ChartPainter;
    expect(painter.page.bars, hasLength(4));
    expect(painter.page.systems.first.sectionLabel, 'A');
    expect(
      painter.page.bars.first.chords.first.chord.render(
        painter.song.key,
        const SpellingTable(),
      ),
      'C^',
    );
  });
}
