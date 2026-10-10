// PURPOSE: Verify the behaviour the application shell actually promises: it boots, it reports
//          ink availability truthfully for the platform it is running on, and it does not throw
//          merely because no native ink implementation exists.
// INPUTS: None.
// OUTPUTS: Pass/fail per behaviour.
// KEYWORDS: test, widget, ink-fallback, graceful-degradation, smoke
import 'package:chartapp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_native/ink_native.dart';

void main() {
  testWidgets(
    'the shell reports ink as unavailable when only the fallback is registered',
    (WidgetTester tester) async {
      // Force the state under test rather than depending on which platform runs the suite.
      InkNativePlatform.instance = UnsupportedInkPlatform();

      await tester.pumpWidget(const ChartApp());

      expect(find.text('Ink: unavailable'), findsOneWidget);
      expect(find.text('Editor arrives in Phase 2'), findsOneWidget);
    },
  );

  testWidgets('the shell renders without a registered ink implementation', (
    WidgetTester tester,
  ) async {
    // registerInkFallback is what main() calls before runApp; without it the accessor throws,
    // so this test pins that the fallback is sufficient to boot.
    registerInkFallback();

    await tester.pumpWidget(const ChartApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(inkIsAvailable, isFalse);
  });
}
