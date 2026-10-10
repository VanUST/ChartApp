// PURPOSE: Give a platform with a filesystem the two things [chart_source] promises: write a
//          container the caller encoded to the path the reader named, and read the bytes of a
//          container back. It is the desktop/mobile half of the conditional export, so it is the
//          only place in the app that moves `.chart` bytes through `dart:io`.
// INPUTS: A path the reader typed or edited, and the bytes `ChartFileCodec` produced.
// OUTPUTS: [chartSourceIsFilePath] is true, [saveChartFile] completes once the bytes are on disk,
//          and [loadChartFile] answers with the file's bytes. A missing file throws a
//          [FileSystemException] and an unwritable path throws whatever `dart:io` throws; both are
//          ordinary outcomes for a typed path and are meant to be shown, not swallowed.
// KEYWORDS: chart-file, save, open, dart-io, conditional-import, io-implementation
import 'dart:io';
import 'dart:typed_data';

/// Whether a reader can name a `.chart` file by a filesystem path on this platform.
///
/// True here, which is what makes the viewer show the chart path field and its Save and Open
/// buttons. False in the browser, where there is no path to type and those controls are hidden
/// rather than offered and then refused.
const bool chartSourceIsFilePath = true;

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
