// PURPOSE: Decide what a saved document's file is CALLED, once, so that a chart and a programme
//          cannot come to propose a name in two different ways. Both containers are addressed by a
//          string the reader supplies — a path on a platform with a filesystem, a file name to
//          offer the browser's chooser and download elsewhere — and in both cases the app has to
//          propose something sensible before the reader has typed anything.
// INPUTS: A path to sit beside (usually the source the document came from), a title, and the
//         extension the container uses.
// OUTPUTS: [extensionPathBeside] replaces the path's extension, or appends one when the path had
//          none; [documentFileNameFor] sanitizes the title into something a filesystem and a
//          browser both accept and appends the extension. Both handle the empty input by returning
//          what they can: an empty path has nothing to sit beside, so it answers the empty string.
// KEYWORDS: file-name, path, extension, sanitize, suggested-name, empty-input, shared
import 'package:chart_core/chart_core.dart';

// PURPOSE: Derive the path of a saved document that sits beside its source, so a dialog's field
//          starts with something sensible instead of empty.
// INPUTS: sourcePath — the source file's path, which may be empty in a browser or a label such as
//         a probe's synthetic reference. extension — the container's extension, with its dot, such
//         as `.chart` or `.setlist`.
// OUTPUTS: The same path with its extension replaced by [extension], or with [extension] appended
//          when it had none. An empty input gives an empty output, because there is nothing to sit
//          beside. A dot in a DIRECTORY name is not treated as an extension: the search starts
//          after the last separator.
// KEYWORDS: path, default, extension, beside, empty-input, separator-aware
/// Returns [sourcePath] with its extension replaced by [extension].
String extensionPathBeside(String sourcePath, String extension) {
  if (sourcePath.isEmpty) {
    return '';
  }
  final int separator = sourcePath.lastIndexOf(RegExp(r'[\\/]'));
  final int dot = sourcePath.lastIndexOf('.');
  if (dot > separator) {
    return '${sourcePath.substring(0, dot)}$extension';
  }
  return '$sourcePath$extension';
}

// PURPOSE: Derive the file name to offer when there is no source path to sit beside, which is the
//          browser's ordinary case: the source was chosen through a chooser and left no path behind,
//          so a dialog would otherwise open with an empty field and a reader with nothing to accept.
// INPUTS: title — the document's own name, which may be empty, may contain characters a filesystem
//         refuses, and may already end in the extension. extension — the container's extension,
//         with its dot. fallback — the token to use when nothing usable survives sanitizing; it is
//         part of a FILE NAME and is therefore never a localized word (see below).
// OUTPUTS: The title with every character illegal in a file name replaced by `_` and [extension]
//          appended, or `fallback + extension` when nothing usable is left. A NAMELESS DOCUMENT
//          THEREFORE PROPOSES `untitled.chart` / `untitled.setlist` IN EVERY LANGUAGE, and that is
//          the opposite of the rule the interface follows. The extension is appended rather than
//          sniffed: a musician who titled a tune "Ballad.chart" still gets a `Ballad.chart.chart`,
//          because guessing that the title was meant as a name would rename their song's file after
//          their song.
// KEYWORDS: file-name, download, suggested-name, sanitize, empty-title, fallback, data-not-interface
//
// WHY THE FALLBACK IS ENGLISH WHILE THE LABEL FOR THE SAME CHART IS RUSSIAN. Two different things
// are being written for two different readers. `l10n.untitled` is the FRAME: a word the interface
// draws for a musician, in the musician's language, on a screen that does not leave this device.
// `untitled.chart` is the PAYLOAD'S NAME: a token an operating system stores, a mail client
// attaches, another machine reads, and a shell may have to quote. It travels where our catalogue
// does not, so it stays an ASCII token and is never translated; a Cyrillic `Без названия.chart`
// would survive Windows and then meet a filesystem, a build script or a mail gateway that mangles
// it, and the same client would see a different file name on every machine it passed through. The
// same line is drawn for notation: the frame is ours, the payload travels.
/// Returns a usable file name for a document called [title].
String documentFileNameFor(
  String title,
  String extension, {
  String fallback = 'untitled',
}) {
  final String cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .trim();
  if (cleaned.isEmpty) {
    return '$fallback$extension';
  }
  return '$cleaned$extension';
}

/// A usable `.setlist` path sitting beside [sourcePath].
String setlistPathBeside(String sourcePath) =>
    extensionPathBeside(sourcePath, setlistFileExtension);

/// A usable `.setlist` file name for a programme called [title].
String setlistFileNameFor(String title) =>
    documentFileNameFor(title, setlistFileExtension);
