// PURPOSE: Give the bench its own application root, so the benchmark entrypoint shows only the
//          bench and nothing from the editor. Keeping it out of the app's own root is what makes
//          `flutter build apk --target=lib/ink_bench_main.dart` produce a bench-only APK without
//          touching any other screen.
// INPUTS: None.
// OUTPUTS: A Material application whose home is the bench screen.
// KEYWORDS: bench-app, second-entrypoint, isolation, material-app
library;

import 'package:flutter/material.dart';

import 'bench_screen.dart';

/// The bench application root.
class InkBenchApp extends StatelessWidget {
  /// Creates the bench application root.
  const InkBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ink latency bench',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5D8A)),
      ),
      home: const BenchScreen(),
    );
  }
}
