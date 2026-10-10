// PURPOSE: Name the one thing about saving and opening a `.chart` file that differs between a
//          browser and a platform with a filesystem — where the bytes come from and where they go —
//          and let the viewer stay unaware of it. This is the second half of the same composition
//          point `ireal_source.dart` is: it supplies the two functions and the answer to "is a
//          reference a path at all", with the same names and a different implementation per
//          platform.
// INPUTS: None. The implementation is chosen at compile time by the conditional export below.
// OUTPUTS: `chartSourceIsFilePath`, `saveChartFile` and `loadChartFile`, each with the same name
//          and the same meaning on both platforms and a different answer on each:
//
//            | Symbol                  | Desktop / mobile            | Browser                  |
//            |-------------------------|-----------------------------|--------------------------|
//            | `chartSourceIsFilePath` | true                        | false                    |
//            | `saveChartFile(path)`   | writes the file at `path`   | not implemented (throws) |
//            | `loadChartFile(path)`   | reads the file at `path`    | not implemented (throws) |
//
// KEYWORDS: chart-file, save, open, conditional-export, platform-seam, composition-root, web, io
//
// WHY THIS IS A SECOND SEAM AND NOT A REUSE OF THE iReal ONE. The iReal seam turns a reference into
// a parsed LIBRARY; this one moves BYTES in both directions. Folding them together would give the
// viewer one function whose argument means "a file to read and parse" in one call and "a file to
// overwrite" in the next, and the browser implementations of the two are different pieces of work.
// The names are deliberately parallel so that a reader who knows one knows the other.
//
// WHY THE BROWSER SIDE IS NOT WRITTEN YET. D20 wants the Chrome/Android path to overwrite in place
// through the File System Access API and the Safari/iOS path to download and re-open, and both need
// a user gesture and a browser to verify against. That work is a separate increment; what matters
// here is that the seam exists, compiles on the web, and changes nothing about the iReal file
// picker that already works there. `chartSourceIsFilePath` is what keeps an unimplemented function
// from ever being called: the viewer shows no `.chart` control where the answer is false.
export 'chart_source_io.dart'
    if (dart.library.js_interop) 'chart_source_web.dart';
