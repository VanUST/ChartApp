// PURPOSE: Name the one thing about loading an iReal export that differs between a browser and a
//          desktop — where the reader gets the file from — and let every other file stay unaware
//          of it. The viewer injects `IRealLibraryLoader`, so this library is the composition
//          point rather than a second seam: it supplies the loader, the starting reference and
//          whether a reference is a path at all.
// INPUTS: None. The implementation is chosen at compile time by the conditional export below.
// OUTPUTS: `iRealSourceIsFilePath`, `defaultIRealPath` and `loadIRealLibrary`, each with the same
//          name and the same meaning on both platforms and a different answer on each:
//
//            | Symbol                    | Desktop / mobile        | Browser             |
//            |---------------------------|-------------------------|---------------------|
//            | `iRealSourceIsFilePath`   | true                    | false               |
//            | `defaultIRealPath`        | the owner's export path | ''                  |
//            | `loadIRealLibrary(ref)`   | reads the file at `ref` | opens a file picker |
//
// KEYWORDS: ireal, import, conditional-export, platform-seam, composition-root, web, io
//
// WHY A CONDITIONAL EXPORT AND NOT A RUNTIME CHECK. `dart:io` cannot be imported into a browser
// build at all, so a `Platform.isWindows` branch inside one file would not compile on the web even
// though the branch is never taken. Choosing the implementation at compile time is what lets the
// web build exclude the filesystem entirely, and `dart.library.js_interop` is the condition rather
// than `dart.library.html` because the browser implementation uses the modern JS interop that a
// future `--wasm` build can also compile, while `dart:html` cannot.
export 'ireal_source_io.dart'
    if (dart.library.js_interop) 'ireal_source_web.dart';
