// PURPOSE: Verify the behaviour the application shell actually promises: it boots to the iReal
//          reader, it renders without a native ink implementation, and it reports ink availability
//          truthfully for the platform it runs on.
// INPUTS: None.
// OUTPUTS: Pass/fail per behaviour.
// KEYWORDS: test, widget, ink-fallback, graceful-degradation, smoke, viewer
//
// The loader is injected so these tests never read the owner's file: the shell's behaviour is what
// is under test here, not the presence of a chart on one machine.
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/main.dart';
import 'package:chartapp/viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_native/ink_native.dart';

/// A loader that answers with an empty library, so no file is read.
Future<IRealLibrary> emptyLibrary(String path) async =>
    const IRealLibrary(playlistName: '', songs: <IRealSong>[]);

void main() {
  testWidgets(
    'the shell reports ink as unavailable when only the fallback is registered',
    (WidgetTester tester) async {
      // Force the state under test rather than depending on which platform runs the suite.
      InkNativePlatform.instance = UnsupportedInkPlatform();

      await tester.pumpWidget(ChartApp(loader: emptyLibrary));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(IRealViewerScreen), findsOneWidget);
      expect(inkIsAvailable, isFalse);
    },
  );

  testWidgets('the shell renders without a registered ink implementation', (
    WidgetTester tester,
  ) async {
    // registerInkFallback is what main() calls before runApp; without it the accessor throws,
    // so this test pins that the fallback is sufficient to boot.
    registerInkFallback();

    await tester.pumpWidget(ChartApp(loader: emptyLibrary));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(IRealViewerScreen), findsOneWidget);
    expect(inkIsAvailable, isFalse);
  });
}
