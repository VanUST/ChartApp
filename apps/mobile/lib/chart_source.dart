// PURPOSE: Name the two things about saving and opening a `.chart` file that differ between a
//          browser and a platform with a filesystem — where the bytes come from and where they go,
//          and what a save does to a file that already exists — and let the viewer stay unaware of
//          it. This is the second half of the same composition point `ireal_source.dart` is: it
//          supplies two functions and two answers about the platform, with the same names and a
//          different implementation per platform.
// INPUTS: None. The implementation is chosen at compile time by the conditional export below.
// OUTPUTS: `chartSourceIsFilePath`, `chartSourceSaveMode`, `saveChartFile` and `loadChartFile`,
//          each with the same name and the same meaning on both platforms and a different answer on
//          each:
//
//            | Symbol                   | Desktop / mobile                 | Browser
//            |--------------------------|----------------------------------|--------------------------------
//            | `chartSourceIsFilePath`  | true                             | false
//            | `chartSourceSaveMode()`  | namedPath                        | rewriteInPlace, else download
//            | `saveChartFile(name)`    | writes the file at that path     | re-writes the chosen file, else downloads
//            | `loadChartFile(path)`    | reads the file at that path      | opens the browser's chooser
//
//          `ChartSaveMode` and `ChartFileCancelledException`, the vocabulary both implementations
//          must agree on, are re-exported from `chart_source_contract.dart` so a caller imports the
//          seam once.
// KEYWORDS: chart-file, save, open, conditional-export, platform-seam, composition-root, web, io,
//           file-system-access, download, d20
//
// WHY THIS IS A SECOND SEAM AND NOT A REUSE OF THE iReal ONE. The iReal seam turns a reference into
// a parsed LIBRARY; this one moves BYTES in both directions. Folding them together would give the
// viewer one function whose argument means "a file to read and parse" in one call and "a file to
// overwrite" in the next, and the browser implementations of the two are different pieces of work.
// The names are deliberately parallel so that a reader who knows one knows the other.
//
// WHY THE PATH ARGUMENT STILL EXISTS ON A PLATFORM THAT HAS NO PATH. A browser page cannot name a
// file: it can only be handed one by the reader. The argument therefore carries the file NAME to
// offer the picker and the download, which is the only thing a page can say about a destination
// before the reader picks one. Keeping one signature means the dialog has one save call and one open
// call on every platform, and `chartSourceIsFilePath` is what tells it whether that argument is a
// path to be typed or a name to be proposed — a field labelled accordingly, not a hidden control.
//
// WHERE THE HONESTY LIVES. `chartSourceSaveMode` is the answer to "will this replace my file or make
// me a new one?", and it is decided by the implementation because only the implementation can see
// the browser's own API. The dialog renders the answer and never guesses it; a platform with a
// filesystem answers `namedPath` because it always replaces the file it was told to.
export 'chart_source_contract.dart';

export 'chart_source_io.dart'
    if (dart.library.js_interop) 'chart_source_web.dart';
