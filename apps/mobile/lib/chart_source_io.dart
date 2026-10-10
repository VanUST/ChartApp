// PURPOSE: Give a platform with a filesystem the two things [chart_source] promises: write a
//          container the caller encoded to the path the reader named, and read the bytes of a
//          container back. It is the desktop/mobile half of the conditional export, so it is the
//          only place in the app that moves `.chart` bytes through `dart:io`.
// INPUTS: A path the reader typed or edited, and the bytes `ChartFileCodec` produced.
// OUTPUTS: [chartSourceIsFilePath] is true, [chartSourceSaveMode] always answers
//          [ChartSaveMode.namedPath], [saveChartFile] completes once the bytes are on disk, and
//          [loadChartFile] answers with the file's bytes. A missing file throws a
//          [FileSystemException] and an unwritable path throws whatever `dart:io` throws; both are
//          ordinary outcomes for a typed path and are meant to be shown, not swallowed.
// KEYWORDS: chart-file, save, open, dart-io, conditional-import, io-implementation, save-mode
import 'dart:io';
import 'dart:typed_data';

import 'chart_source_contract.dart';

/// Whether a reader can name a `.chart` file by a filesystem path on this platform.
///
/// True here, which is what makes the chart dialog show a path field whose contents address the
/// file directly. False in the browser, where the same field holds a file NAME to offer the
/// chooser, because a page cannot name a file it has not been handed.
const bool chartSourceIsFilePath = true;

// PURPOSE: Report how a save reaches the reader's disk on this platform, so the chart dialog can
//          say what pressing Save will do without knowing which platform it is running on.
// INPUTS: None.
// OUTPUTS: Always [ChartSaveMode.namedPath]. A filesystem has no second mechanism to choose
//          between: the path the reader typed IS the destination, and writing it again replaces the
//          same file, which is the property the browser has to reproduce or admit it lacks.
// KEYWORDS: save-mode, named-path, platform-capability, no-runtime-check
/// Whether a save here replaces the named file, which on a filesystem it always does.
ChartSaveMode chartSourceSaveMode() => ChartSaveMode.namedPath;

// PURPOSE: Write a container to the file the reader named, which is the only write the app performs
//          on a chart document.
// INPUTS: path — where to write, as the reader typed it. bytes — the whole container.
// OUTPUTS: A future that completes when the bytes are flushed to disk. Throws whatever `dart:io`
//          throws when the path cannot be written — a missing parent directory, a read-only
//          location, a name that is a directory — because the reader needs the real reason on
//          screen and a wrapped one would only hide it.
// KEYWORDS: file, write, flush, chart-file, error-reporting
/// Writes [bytes] to the file at [path], replacing whatever was there.
Future<void> saveChartFile(String path, Uint8List bytes) async {
  final File file = File(path);
  await file.writeAsBytes(bytes, flush: true);
}

// PURPOSE: Read the container the reader named, so the app can decode it.
// INPUTS: path — the file to read, as the reader typed it.
// OUTPUTS: The file's bytes. Throws a [FileSystemException] naming the path when nothing exists
//          there, matching the iReal loader's behaviour so both seams fail the same way.
// KEYWORDS: file, read, bytes, chart-file, missing-file
/// Reads the container stored at [path].
Future<Uint8List> loadChartFile(String path) async {
  final File file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('No file exists at this path.', path);
  }
  return file.readAsBytes();
}
