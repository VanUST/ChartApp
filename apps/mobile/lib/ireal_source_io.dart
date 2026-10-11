// PURPOSE: Give a platform with a filesystem the things [ireal_source] promises: the reference the
//          reader starts from, a loader that reaches the file that reference names OR the platform's
//          own chooser when there is no reference to follow, and the chooser a desktop uses to fill
//          that reference in. It is the native half of the conditional export, so it is the only
//          place in the app that turns an iReal export into text on a native target.
// INPUTS: A reference that is a path to an `.html` file containing an `irealb://` link (or to a text
//         file holding a payload's link form), or the empty string when the reader is to be asked.
// OUTPUTS: [iRealSourceIsFilePath] answers whether a typed path is a way to name the file on THIS
//          platform — true on a desktop and false on Android and iOS, where scoped storage makes
//          another application's directory unreadable by path. [defaultIRealPath] is empty.
//          [loadIRealLibrary] answers with the parsed library, reading the named path where one is
//          given and opening the platform's chooser otherwise. [chooseIRealReference] answers with
//          the path the reader chose, or null when the platform has no path to hand back or the
//          reader dismissed the dialog. A path that is missing throws a [FileSystemException], text
//          with no `irealb://` link throws a [FormatException], and a dismissed chooser throws an
//          [IRealFileCancelledException]; all three are ordinary outcomes and are meant to be shown
//          or ignored rather than swallowed.
// KEYWORDS: ireal, import, file-load, dart-io, conditional-import, io-implementation,
//           file-picker, scoped-storage, android, cancellation
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'ireal_library.dart';
import 'ireal_source_contract.dart';
import 'native_file_dialog.dart';

/// The path the viewer opens when the reader gives it nothing else.
///
/// **EMPTY, AND IT MUST STAY EMPTY.** This used to be an absolute path pointing into one developer's
/// home directory, on the reasoning that the export belongs to the person reading it. That reasoning
/// was right about the file and wrong about the machine: the path was compiled into the Android build
/// and does not exist on a tablet, so the application opened on a red `FileSystemException` naming a
/// directory that was never there — the first thing a musician would see. A default that names a file
/// can only be correct on the machine it was written on. An empty default means the viewer asks
/// instead of guessing: on a desktop through the path field or its chooser, on a hand-held through
/// the chooser alone.
const String defaultIRealPath = '';

/// Whether a reader can name an iReal export by a filesystem path on this platform.
///
/// True on a desktop, where the reader may type a path and the process may open it; FALSE on Android
/// and iOS, where a path the reader could type does not address a file this application may read.
/// This is what makes the viewer show its path field and load the starting path on the first frame
/// on a desktop, and what makes it show a file-picker button instead — with no field to fill — on a
/// hand-held and in a browser. See `platformFilesCanReadTypedPath` for why the answer is read from
/// the platform at runtime while the implementation around it is chosen at compile time.
bool get iRealSourceIsFilePath => platformFilesCanReadTypedPath;

/// Whether this build runs as a page in a browser.
///
/// NO, HERE — and the constant states it because the viewer has two sentences that must be worded
/// for where the application is running rather than for what it can do: the empty-state hint, which
/// in a browser is the only place a musician is told the file is never uploaded, and the settings
/// sheet's note about where the language choice is kept. Both used to be derived from "there is no
/// path", which was the same fact while the only two platforms were a desktop and a browser, and is
/// NOT the same fact now that the owner's tablet is a third platform with no path and no page
/// either. Named for what it is so no future reader has to re-derive that.
const bool iRealSourceIsBrowser = false;

// PURPOSE: Reach the export the reader means — the one at [reference] where a path is a way to name
//          it, otherwise the one the platform's own chooser hands over — and hand back its songs,
//          which is the only file access the viewer performs on a native target.
// INPUTS: reference — a path to an `.html` file that contains an `irealb://` link, or to a text file
//         holding the decoded payload's link form. Empty, or ignored entirely, where no typed path
//         is possible.
// OUTPUTS: The parsed [IRealLibrary]. Throws a [FileSystemException] when a non-empty path on a
//          desktop holds nothing, a [FormatException] when the text holds no `irealb://` link, and
//          an [IRealFileCancelledException] when the reader dismisses the chooser. None is wrapped
//          or swallowed: the viewer shows the first two and returns quietly from the third.
// KEYWORDS: file, read, irealb-link, decode, io-implementation, file-picker, error-reporting
/// Loads the iReal library the reference names, or the one the reader chooses.
Future<IRealLibrary> loadIRealLibrary(String reference) async {
  final String path = reference.trim();
  // A path is followed only where a path can actually be read. On a hand-held a non-empty reference
  // is still ignored rather than attempted, because the field that would have produced it is not
  // shown and a `FileSystemException` for a path the reader never typed would say nothing true.
  if (platformFilesCanReadTypedPath && path.isNotEmpty) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('No file exists at this path.', path);
    }
    debugPrint('ireal.load.path path_chars=${path.length}');
    return parseIRealExport(await file.readAsString(), source: path);
  }
  final XFile? chosen = await _chooseExport();
  if (chosen == null) {
    throw const IRealFileCancelledException('No file was chosen.');
  }
  debugPrint('ireal.load.chooser name_chars=${chosen.name.length}');
  return parseIRealExport(await chosen.readAsString(), source: chosen.name);
}

// PURPOSE: Let a desktop fill the reference in for the reader instead of making them type it, which
//          is the only platform where a reference is a path worth writing down.
// INPUTS: None; the reader's choice in the platform's own chooser.
// OUTPUTS: The absolute path of the export the reader chose, or null when they dismissed the dialog
//          or when this platform has no path to hand back. NULL IS BOTH ANSWERS ON A HAND-HELD, and
//          that is deliberate rather than lazy: there the reference cannot carry a chosen file out
//          of the loader at all, because the plugin copies the document into this application's
//          cache and the chooser is reached through `loadIRealLibrary` instead. The control that
//          calls this is built only where [iRealSourceIsFilePath] is true, so a hand-held never
//          reaches the ambiguous answer.
// KEYWORDS: reference, choose, desktop, path-field, cancellation
/// Opens the platform's file chooser and answers the path it returned, or null.
Future<String?> chooseIRealReference() async {
  if (!platformFilesCanReadTypedPath) {
    return null;
  }
  final XFile? chosen = await _chooseExport();
  return chosen?.path;
}

/// Opens the platform's chooser filtered to the files an iReal export can be, so the two callers
/// above offer the reader the same dialog.
Future<XFile?> _chooseExport() => chooseFileToRead(
  label: 'iReal export',
  extensions: const <String>['html', 'htm', 'txt'],
  mimeTypes: const <String>['text/html', 'text/plain'],
  uniformTypeIdentifiers: const <String>['public.html', 'public.plain-text'],
);
