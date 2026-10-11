// PURPOSE: Give a platform with a filesystem the two things [ireal_source] promises: the path the
//          reader starts from, and a loader that reads that path. It is the desktop/mobile half of
//          the conditional export, so it is the only place in the app that turns an iReal export
//          into text through `dart:io`.
// INPUTS: A path to an `.html` file that contains an `irealb://` link, or to a text file holding a
//         payload's link form.
// OUTPUTS: [iRealSourceIsFilePath] is true, [defaultIRealPath] is the export the owner keeps
//          outside this repository, and [loadIRealLibrary] answers with the parsed library. A path
//          that is missing throws a [FileSystemException] and text with no `irealb://` link throws
//          a [FormatException]; both are ordinary outcomes for a typed path and are meant to be
//          shown, not swallowed.
// KEYWORDS: ireal, import, file-load, dart-io, conditional-import, io-implementation
import 'dart:io';

import 'ireal_library.dart';

/// The path the viewer opens when the reader gives it nothing else.
///
/// **EMPTY, AND IT MUST STAY EMPTY.** This used to be an absolute path pointing into one developer's
/// home directory, on the reasoning that the export belongs to the person reading it. That reasoning
/// was right about the file and wrong about the machine: the path was compiled into the Android build
/// and does not exist on a tablet, so the application opened on a red `FileSystemException` naming a
/// directory that was never there — the first thing a musician would see. A default that names a file
/// can only be correct on the machine it was written on. An empty default means the viewer asks
/// instead of guessing. See `iRealSourceIsFilePath` for how the reader then names it.
const String defaultIRealPath = '';

/// Whether a reader can name an iReal export by a filesystem path on this platform.
///
/// True here, which is what makes the viewer show its path field and load the starting path on the
/// first frame. False in the browser, where the field would name nothing and the file has to be
/// picked.
const bool iRealSourceIsFilePath = true;

// PURPOSE: Read the export a reader points at and hand back its songs, which is the only file
//          access the viewer performs on this platform.
// INPUTS: reference — a path to an `.html` file that contains an `irealb://` link, or to a text
//         file holding the decoded payload's link form.
// OUTPUTS: The parsed [IRealLibrary]. Throws a [FileSystemException] when nothing exists at
//          [reference] and a [FormatException] when it holds no `irealb://` link. Neither is
//          wrapped or swallowed: the viewer shows the message.
// KEYWORDS: file, read, irealb-link, decode, io-implementation, error-reporting
/// Loads the iReal library stored at [reference] on a platform with a filesystem.
Future<IRealLibrary> loadIRealLibrary(String reference) async {
  final File file = File(reference);
  if (!file.existsSync()) {
    throw FileSystemException('No file exists at this path.', reference);
  }
  return parseIRealExport(await file.readAsString(), source: reference);
}
