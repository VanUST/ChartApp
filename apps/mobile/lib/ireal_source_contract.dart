// PURPOSE: Hold the one piece of vocabulary the iReal platform seam needs that means the SAME thing
//          on every platform: the typed way a reader's dismissal of a file chooser is reported. It
//          lives in a file of its own because `ireal_source.dart` conditionally selects one of two
//          implementations at compile time and both implementations must agree on this name;
//          putting it in one of the two implementations would make the other depend on a file it is
//          never compiled with.
// INPUTS: None.
// OUTPUTS: [IRealFileCancelledException], re-exported by `ireal_source.dart` so a caller imports the
//          seam once and gets the vocabulary with it.
// KEYWORDS: ireal, import, seam-contract, platform-neutral, cancellation
//
// WHY A CANCELLATION IS A TYPE AND NOT A MESSAGE. A chooser the reader dismisses has to be told
// apart from a chooser that failed, because only the first is not a fault: the browser can refuse
// to open one outside a user gesture, a file can be unreadable, and an export can carry no
// `irealb://` link — those are failures and the screen says so. "I changed my mind" is the reader's
// own action, and printing it in the error banner would be telling them off for it. The viewer
// catches this type and returns the screen to the state it was in, exactly as the chart dialogs
// already do with `ChartFileCancelledException`.
//
// WHY IT IS NOT THAT EXCEPTION. `ChartFileCancelledException` lives in `chart_source_contract.dart`
// and belongs to the seam that moves a container's bytes; this seam turns a reference into a parsed
// LIBRARY. Folding them together would make one file the contract for two seams that do not compile
// together, and the iReal seam would then depend on the chart seam's vocabulary to say something
// about itself.

/// Reports that the reader dismissed the iReal file chooser, which is an outcome and not a failure.
///
/// The io implementation throws this only on a hand-held, where the reference is ignored and the
/// chooser is the only way in, and on a desktop when the reader presses the chooser button and then
/// changes their mind. It is never thrown for a file that was read and could not be parsed: that is
/// a [FormatException] from the parser and the screen shows it.
///
/// WHAT [message] IS FOR, AND WHAT IT IS NOT. It is the implementing side's own description of what
/// it saw, written for the log and for whoever is reading the seam; it is NOT the sentence the
/// reader is shown, because the catalogue lives on the interface side of this boundary and this file
/// is compiled into code that has no `BuildContext`. The viewer does not print it at all — a
/// dismissal has nothing to say on screen.
class IRealFileCancelledException implements Exception {
  /// Creates a cancellation carrying a developer-facing description of what was dismissed.
  const IRealFileCancelledException(this.message);

  /// What the platform saw, for the log. Never shown to the reader.
  final String message;

  @override
  String toString() => 'IRealFileCancelledException: $message';
}
