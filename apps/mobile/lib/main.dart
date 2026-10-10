// PURPOSE: Start the ChartApp application and establish the two facts the rest of the widget tree
//          relies on: the Flutter binding exists, and the ink platform accessor resolves on every
//          target. The screen it shows is the iReal reader, which draws an imported chart so the
//          importer can be checked against the application the file came from.
// INPUTS: An optional [IRealLibraryLoader] and starting reference, so a test can compose the
//         application with a synthetic payload instead of the owner's file. Both default to what
//         `ireal_source.dart` selects for the running platform: a path and a filesystem loader on
//         desktop and mobile, a file chooser in a browser.
// OUTPUTS: Runs the application. The home screen is [IRealViewerScreen].
// KEYWORDS: entrypoint, bootstrap, ink-fallback, composition-root, ireal-reader, viewer, web
import 'package:flutter/material.dart';
import 'package:ink_native/ink_native.dart';

import 'ireal_source.dart';
import 'viewer_screen.dart';

/// Whether the running build has a native ink surface.
///
/// Read after [registerInkFallback] has run, so this is a value rather than an exception on
/// every platform. False wherever no platform package has claimed the slot: Linux, Windows, iOS
/// (whose package is still scaffolding) and the web (whose implementation is a separate spike —
/// owner decision D20 — not this fallback pretending to be one). True on Android, where the
/// generated registrant installs `InkNativeAndroid` before `main`. The answer is read from the
/// registered implementation rather than derived from `Platform`, so it cannot drift from which
/// package actually registered.
bool get inkIsAvailable => InkNativePlatform.instance.supportsInk;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerInkFallback();
  runApp(const ChartApp());
}

/// The application root.
class ChartApp extends StatelessWidget {
  /// Creates the application root.
  ///
  /// [loader] and [initialPath] are injected so a widget test can boot the real shell against a
  /// synthetic library; the defaults are the reader's own file on a platform with a filesystem and
  /// the browser's file chooser in a browser.
  const ChartApp({
    super.key,
    this.loader = loadIRealLibrary,
    this.initialPath = defaultIRealPath,
  });

  /// How the viewer turns a reference into a library.
  final IRealLibraryLoader loader;

  /// The reference the viewer's source bar starts with.
  final String initialPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChartApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5D8A)),
      ),
      home: IRealViewerScreen(loader: loader, initialPath: initialPath),
    );
  }
}
