// PURPOSE: Start the ChartApp application and establish the two facts the rest of the widget tree
//          relies on: the Flutter binding exists, and the ink platform accessor resolves on every
//          target. The screen it shows is the iReal reader, which draws an imported chart so the
//          importer can be checked against the application the file came from.
// INPUTS: An optional [IRealLibraryLoader] and starting path, so a test can compose the application
//         with a synthetic payload instead of the owner's file.
// OUTPUTS: Runs the application. The home screen is [IRealViewerScreen].
// KEYWORDS: entrypoint, bootstrap, ink-fallback, composition-root, ireal-reader, viewer
import 'package:flutter/material.dart';
import 'package:ink_native/ink_native.dart';

import 'ireal_library.dart';
import 'viewer_screen.dart';

/// Whether the running build has a native ink surface.
///
/// Read after [registerInkFallback] has run, so this is a value rather than an exception on
/// every platform: false on Linux and Windows, and currently also on iOS and Android, because
/// neither platform package implements the contract yet (see their lib/ headers).
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
  /// synthetic library; the defaults are the reader's own file.
  const ChartApp({
    super.key,
    this.loader = loadIRealLibraryFromFile,
    this.initialPath = defaultIRealPath,
  });

  /// How the viewer turns a path into a library.
  final IRealLibraryLoader loader;

  /// The path the viewer's text field starts with.
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
