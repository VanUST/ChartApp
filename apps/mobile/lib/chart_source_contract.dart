// PURPOSE: Hold the two pieces of vocabulary the `.chart` platform seam needs that mean the SAME
//          thing on every platform: which kind of destination a save actually has, and the typed
//          way a reader's dismissal of a file chooser is reported. They live in a file of their own
//          because `chart_source.dart` conditionally selects one of two implementations at compile
//          time and both implementations must agree on these names; putting them in one of the two
//          implementations would make the other depend on a file it is never compiled with.
// INPUTS: None.
// OUTPUTS: [ChartSaveMode] and [ChartFileCancelledException], re-exported by `chart_source.dart`
//          so a caller imports the seam once and gets the vocabulary with it.
// KEYWORDS: chart-file, save, open, seam-contract, platform-neutral, cancellation, d20
//
// WHY THE MODE IS A CONTRACT AND NOT A UI DECISION. The chart dialog has to tell the musician what
// pressing Save will do BEFORE it does it: on a desktop it replaces the file at the path they typed,
// in one browser it re-writes the file they chose last time, and in another every press hands them a
// brand-new file. Those are three different promises and a single "saved" is a lie about two of them.
// The implementation decides which one is in force — it is the only side that can see whether the
// browser has the API — and the dialog only renders the sentence.

/// What a save on this platform does with the bytes, which is what the reader is told it will do.
enum ChartSaveMode {
  /// The reader names a file by a path and a save replaces that path's contents.
  ///
  /// This is a platform with a filesystem: the desktop and mobile builds, through
  /// `chart_source_io.dart`. Saving twice writes the same file twice.
  namedPath,

  /// The browser can re-write a file the reader has already chosen, through the File System Access
  /// API, so a second save updates the same file in place.
  ///
  /// The first save still asks where the file goes, because a page may not name a file it has not
  /// been handed; every save after that reuses the handle the first one returned, which is what
  /// makes autosave possible at all.
  rewriteInPlace,

  /// The browser cannot update a file in place, so each save hands the reader a new copy.
  ///
  /// The browser's own download machinery chooses where the copy lands and may rename it when a
  /// file of that name already exists. The reader is told this rather than discovering it.
  download,
}

/// Reports that the reader dismissed a chooser, which is an outcome and not a failure.
///
/// It is a type of its own because "I changed my mind" and "the browser refused" need different
/// words on screen: a cancellation is the reader's own action and reporting it as an error would be
/// telling them off for it. The io implementation never throws this — it takes a path and has no
/// chooser to dismiss — so catching it is how a caller stays correct on both platforms.
///
/// WHAT [message] IS FOR, AND WHAT IT IS NOT. It is the implementing side's own description of what
/// it saw, written for the log and for whoever is reading the seam; it is NOT the sentence the
/// reader is shown. A file dialog words the outcome from its message catalogue, because the
/// catalogue lives on the interface side of this boundary — this file is compiled into a runner
/// that has no `BuildContext` and no `AppLocalizations` — and because the same dismissal has to be
/// worded in whichever language the reader chose.
class ChartFileCancelledException implements Exception {
  /// Creates a cancellation carrying a developer-facing description of what was dismissed.
  const ChartFileCancelledException(this.message);

  /// What the platform saw, for the log. Never shown to the reader: the dialog words the outcome.
  final String message;

  @override
  String toString() => 'ChartFileCancelledException: $message';
}
