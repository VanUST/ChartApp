// PURPOSE: Answer, in a browser, the two questions [chart_source] asks: whether a `.chart` file can
//          be named by a path, and how its bytes move. The answer to the first is what keeps the
//          second from ever being called: the viewer shows no `.chart` control where there is no
//          path, so an unimplemented browser save cannot be reached by the reader.
// INPUTS: A path the caller would name on a platform that has one, and the bytes of a container.
// OUTPUTS: [chartSourceIsFilePath] is false, and both functions complete with an
//          [UnsupportedError] that says what is missing and why. Neither is a silent no-op: a
//          caller that reaches one has a bug, and it should hear about it rather than appear to
//          save a chart that went nowhere.
// KEYWORDS: chart-file, web, browser, not-implemented, unsupported, conditional-import, d20
//
// WHY THIS IS NOT A BROWSER IMPLEMENTATION YET. D20 splits the browser path in two: Chrome and
// Android overwrite in place through the File System Access API, while Safari and iOS download a
// new file and re-open one through a chooser. Both need a user gesture, both need a real browser to
// verify against, and this deployment forbids starting a process that opens a window — so writing
// it now would be code nobody could run. The iReal file picker in `ireal_source_web.dart` is
// untouched and keeps working; this file adds nothing to the web build's behaviour.
import 'dart:typed_data';

/// Whether a reader can name a `.chart` file by a filesystem path on this platform.
///
/// False: a browser cannot name a file the reader has not chosen, and cannot overwrite one it has
/// not been handed. The viewer reads this and shows no chart control in a browser rather than
/// offering one that would fail.
const bool chartSourceIsFilePath = false;

// PURPOSE: Report that browser saving is a separate increment, instead of pretending to save.
// INPUTS: path — ignored; there is no path to honour in a browser. bytes — ignored.
// OUTPUTS: A future that fails with an [UnsupportedError] naming what is missing. The `async`
//          keyword is deliberate: the caller gets a failed future it can await, in the same shape
//          as the io implementation's success, rather than a synchronous throw from a seam that is
//          declared asynchronous.
// KEYWORDS: web, not-implemented, fail-loud, file-system-access, download
/// Always fails: saving a `.chart` file in a browser is not implemented.
Future<void> saveChartFile(String path, Uint8List bytes) async {
  throw UnsupportedError(
    'Saving a .chart file in a browser is not implemented. D20 needs the File '
    'System Access API to overwrite in place on Chrome and a download on '
    'Safari; that is a separate increment, and the chart controls stay hidden '
    'until it exists.',
  );
}

// PURPOSE: Report that browser opening is a separate increment, instead of pretending to open.
// INPUTS: path — ignored, for the same reason as [saveChartFile].
// OUTPUTS: A future that fails with an [UnsupportedError] naming what is missing.
// KEYWORDS: web, not-implemented, fail-loud, file-chooser
/// Always fails: opening a `.chart` file in a browser is not implemented.
Future<Uint8List> loadChartFile(String path) async {
  throw UnsupportedError(
    'Opening a .chart file in a browser is not implemented. It needs a chooser '
    'that hands back bytes rather than text, as a separate increment.',
  );
}
