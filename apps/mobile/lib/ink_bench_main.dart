// PURPOSE: A second entrypoint whose only job is to measure ink latency on the device that can
//          produce the number. It exists as its own `main()` so a bench APK can be built with
//          `flutter build apk --target=lib/ink_bench_main.dart` and installed without the editor's
//          screens, its state, or its startup work being on the measured path.
// INPUTS: None. Everything the bench knows comes from the ink platform's measurement surface.
// OUTPUTS: Runs the bench. It prints one JSON object per measured sample to stdout, writes the same
//          lines plus a run info file to the platform's app-specific external directory, and shows
//          the verdict on screen.
//
// HOW TO READ THE RESULT: `--metric touchToPresentMs --group-by pointerType`, which is the command
// `docs/ux/test-protocol.md` documents. The stylus figure (p95 <= 45 ms) can only be produced by a
// person drawing with the S Pen: an injected touch has no stylus source, no pressure and no tilt.
// KEYWORDS: entrypoint, bench, ink-latency, second-main, apk-target
import 'package:flutter/material.dart';
import 'package:ink_native/ink_native.dart';

import 'ink_bench/bench_app.dart';

/// Starts the ink latency bench.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Installs the no-op implementation only where a real one has not claimed the slot. On Android
  // the generated plugin registrant has already registered InkNativeAndroid by this point, so this
  // call is what keeps a desktop build of this entrypoint from throwing when the screen reads
  // `InkNativePlatform.instance`.
  registerInkFallback();
  runApp(const InkBenchApp());
}
