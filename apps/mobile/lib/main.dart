// PURPOSE: Start the ChartApp application and establish the two facts the rest of the widget
//          tree relies on: the Flutter binding exists, and the ink platform accessor resolves
//          on every target. Without the second step, opening the editor on a desktop build
//          would throw from a getter the UI has no reasonable way to guard.
// INPUTS: None.
// OUTPUTS: Runs the application. The shell it shows is a Phase 0 placeholder: it reports
//          whether ink is available and otherwise states that the editor arrives in Phase 2.
// KEYWORDS: entrypoint, bootstrap, ink-fallback, composition-root, phase-0
import 'package:flutter/material.dart';
import 'package:ink_native/ink_native.dart';

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
  const ChartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChartApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5D8A)),
      ),
      home: const EditorPlaceholder(),
    );
  }
}

/// The Phase 0 editor shell.
class EditorPlaceholder extends StatelessWidget {
  /// Creates the placeholder shell.
  const EditorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ChartApp')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              inkIsAvailable ? 'Ink: available' : 'Ink: unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Editor arrives in Phase 2'),
          ],
        ),
      ),
    );
  }
}
