// PURPOSE: Give a native platform the things [chart_source] promises: write a container the caller
//          encoded to the place the reader named, and read the bytes of a container back. It is the
//          native half of the conditional export, so it is the only place in the app that moves
//          container bytes on a native target — a `.chart` file and a `.setlist` file alike, through
//          one read and one write, and on Android through the operating system's own save dialog,
//          which is the only way a file can be put somewhere the musician can find it again.
// INPUTS: A reference the reader named — a PATH on a desktop, where a path is a way to name a file,
//         and a proposed FILE NAME on a hand-held, where it is not — and the bytes a container codec
//         produced. The two formats differ in exactly one visible place: the extension the dialog
//         filters on.
// OUTPUTS: [chartSourceIsFilePath] answers whether that reference is a path on THIS platform — true
//          on a desktop, false on Android and iOS, where scoped storage makes a typed path useless.
//          [chartSourceSaveMode] answers [ChartSaveMode.namedPath] on a desktop, where the path the
//          reader typed IS the destination, and [ChartSaveMode.chosenLocation] on a hand-held, where
//          the system's dialog chooses it. The two save functions complete once the bytes are
//          written and throw a [ChartFileCancelledException] when the reader dismisses the system
//          dialog; the two load functions answer with the file's bytes. A missing path throws a
//          [FileSystemException] and an unwritable path throws whatever `dart:io` throws — both are
//          ordinary outcomes for a typed path and are meant to be shown, not swallowed.
// KEYWORDS: chart-file, setlist-file, save, open, dart-io, conditional-import, io-implementation,
//           save-mode, file-picker, android, scoped-storage, action-create-document
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'chart_source_contract.dart';
import 'native_file_dialog.dart';

/// Whether a reader can name a `.chart` file by a filesystem path on this platform.
///
/// True on a desktop, which is what makes the chart dialog show a path field whose contents address
/// the file directly. FALSE on Android and iOS, where no path a reader could type addresses a file
/// this application may open; the dialog then labels the field as a file NAME and offers the
/// system's choosers, which is the same thing the browser does and for the same reason. See
/// `platformFilesCanReadTypedPath` for why this is read from the platform at runtime while the
/// implementation around it is chosen at compile time.
bool get chartSourceIsFilePath => platformFilesCanReadTypedPath;

// PURPOSE: Report how a save reaches the reader's storage on this platform, so the chart dialog can
//          say what pressing Save will do without knowing which platform it is running on.
// INPUTS: None.
// OUTPUTS: [ChartSaveMode.namedPath] on a desktop, where the path the reader typed IS the
//          destination and writing it again replaces the same file. [ChartSaveMode.chosenLocation]
//          on Android and iOS, where the system's own save dialog picks the folder and the name, so
//          each save asks again. It never returns the two browser modes: this file is not compiled
//          into a browser.
// KEYWORDS: save-mode, named-path, chosen-location, platform-capability, no-runtime-guess
/// How a save reaches storage here: the file the reader named, or the one the system chooses.
ChartSaveMode chartSourceSaveMode() => platformFilesCanReadTypedPath
    ? ChartSaveMode.namedPath
    : ChartSaveMode.chosenLocation;

// PURPOSE: Write a container to the place the reader named — the path they typed on a desktop, or the
//          destination the system's own save dialog returns on a hand-held — which is the only write
//          the app performs on a chart document.
// INPUTS: reference — where to write: a path on a desktop, a proposed file NAME on a hand-held.
//         bytes — the whole container.
// OUTPUTS: A future that completes when the bytes are flushed. Throws a
//          [ChartFileCancelledException] when the reader dismisses the system's save dialog — an
//          outcome, not a fault — and whatever `dart:io` throws when a desktop path cannot be
//          written (a missing parent directory, a read-only location, a name that is a directory),
//          because the reader needs the real reason on screen and a wrapped one would only hide it.
// KEYWORDS: file, write, flush, chart-file, error-reporting, chosen-location
/// Writes [bytes] to the file [reference] names, or to the file the reader chooses.
Future<void> saveChartFile(String reference, Uint8List bytes) =>
    _saveBytes(reference, bytes, '.chart', 'chart');

// PURPOSE: Read the container the reader named, so the app can decode it.
// INPUTS: reference — the file to read: a path a desktop can resolve, ignored by a hand-held, which
//         asks the reader through the system's own chooser because there is no path to resolve.
// OUTPUTS: The file's bytes. Throws a [FileSystemException] naming the path when a desktop path
//          holds nothing, matching the iReal loader's behaviour so both seams fail the same way, and
//          a [ChartFileCancelledException] when the reader dismisses the chooser.
// KEYWORDS: file, read, bytes, chart-file, missing-file, file-picker, cancellation
/// Reads the container stored at [reference], or the one the reader chooses.
Future<Uint8List> loadChartFile(String reference) =>
    _loadBytes(reference, '.chart', 'chart');

// PURPOSE: Write a programme through the same code the chart write uses, so a `.setlist` file and a
//          `.chart` file cannot behave differently on any storage.
// INPUTS: reference — where to write, as [saveChartFile] takes it. bytes — the whole setlist
//         container.
// OUTPUTS: A future that completes when the bytes are flushed, or throws exactly what
//          [saveChartFile] throws. Only the extension and the word in the log line differ.
// KEYWORDS: file, write, flush, setlist-file, error-reporting, one-implementation
/// Writes [bytes] to the file [reference] names, or to the file the reader chooses.
Future<void> saveSetlistFile(String reference, Uint8List bytes) =>
    _saveBytes(reference, bytes, setlistFileExtension, 'setlist');

// PURPOSE: Read a programme the reader named, so the app can decode it.
// INPUTS: reference — the file to read, as [loadChartFile] takes it.
// OUTPUTS: The file's bytes, or the same typed failures [loadChartFile] reports, differing only in
//          the extension the chooser filters on.
// KEYWORDS: file, read, bytes, setlist-file, missing-file, one-implementation
/// Reads the container stored at [reference], or the one the reader chooses.
Future<Uint8List> loadSetlistFile(String reference) =>
    _loadBytes(reference, setlistFileExtension, 'setlist');

// PURPOSE: Add the extension and the log word as parameters to one body rather than writing two
//          bodies, because what differs between a chart and a programme is the FORMAT and not the
//          platform, and a second body is a second place for the two to drift apart.
// INPUTS: reference and bytes as their public callers take them. extension — the container's own
//         extension, with its dot, used in the log. kind — the word the log line reports.
// OUTPUTS: As [saveChartFile]: completes when the bytes are on storage, throws
//          [ChartFileCancelledException] on a dismissed dialog, and otherwise whatever the platform
//          throws.
// KEYWORDS: save, one-implementation, extension, structured-log, chosen-location
Future<void> _saveBytes(
  String reference,
  Uint8List bytes,
  String extension,
  String kind,
) async {
  final String target = reference.trim();
  if (platformFilesCanReadTypedPath) {
    // A desktop path IS the destination, and a save that named no file is refused by the dialog
    // before it gets here rather than turning into an empty file name.
    await File(target).writeAsBytes(bytes, flush: true);
    debugPrint('$kind.save.path bytes=${bytes.length}');
    return;
  }
  final bool saved = await saveBytesToChosenLocation(
    suggestedName: target.isEmpty
        ? 'untitled$extension'
        : _withExtension(target, extension),
    bytes: bytes,
    label: kind == 'chart' ? 'Chart file' : 'Programme file',
    extensions: <String>[_withoutDot(extension)],
  );
  if (!saved) {
    throw const ChartFileCancelledException('No file was chosen.');
  }
  debugPrint('$kind.save.chosen bytes=${bytes.length}');
}

// PURPOSE: Add the extension and the log word as parameters to one body rather than writing two,
//          on the same reasoning as [_saveBytes].
// INPUTS: reference as its public callers take it. extension — the container's own extension, with
//         its dot. kind — the word the log line reports.
// OUTPUTS: The file's bytes, or the same typed failures the public callers document.
// KEYWORDS: open, one-implementation, extension, structured-log, file-picker, cancellation
Future<Uint8List> _loadBytes(
  String reference,
  String extension,
  String kind,
) async {
  final String target = reference.trim();
  if (platformFilesCanReadTypedPath) {
    final File file = File(target);
    if (!file.existsSync()) {
      throw FileSystemException('No file exists at this path.', target);
    }
    debugPrint('$kind.open.path path_chars=${target.length}');
    return file.readAsBytes();
  }
  final XFile? chosen = await chooseFileToRead(
    label: kind == 'chart' ? 'Chart file' : 'Programme file',
    extensions: <String>[_withoutDot(extension)],
  );
  if (chosen == null) {
    throw const ChartFileCancelledException('No file was chosen.');
  }
  final Uint8List bytes = await chosen.readAsBytes();
  debugPrint('$kind.open.chosen bytes=${bytes.length}');
  return bytes;
}

/// The extension of [name] without its leading dot, which is the form an `XTypeGroup` wants.
String _withoutDot(String extension) =>
    extension.startsWith('.') ? extension.substring(1) : extension;

/// [name] with [extension] appended unless it already ends with it, so a file the reader named
/// without its extension is not proposed back as `song.chart.chart`.
String _withExtension(String name, String extension) =>
    name.toLowerCase().endsWith(extension.toLowerCase())
    ? name
    : '$name$extension';
