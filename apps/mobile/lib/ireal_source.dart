// PURPOSE: Name the one thing about loading an iReal export that differs between a desktop and a
//          hand-held or a browser — where the reader gets the file from — and let every other file
//          stay unaware of it. The viewer injects `IRealLibraryLoader`, so this library is the
//          composition point rather than a second seam: it supplies the loader, the starting
//          reference, whether a typed path is a way to name a file at all, and the chooser a desktop
//          uses to fill that reference in for the reader.
// INPUTS: None. The implementation is chosen at compile time by the conditional export below.
// OUTPUTS: `iRealSourceIsFilePath`, `iRealSourceIsBrowser`, `defaultIRealPath`, `loadIRealLibrary`
//          and `chooseIRealReference`, each with the same name and the same meaning on every
//          platform and a different answer on each:
//
//            | Symbol                  | Desktop            | Hand-held          | Browser           |
//            |-------------------------|--------------------|--------------------|-------------------|
//            | `iRealSourceIsFilePath` | true               | false              | false             |
//            | `iRealSourceIsBrowser`  | false              | false              | true              |
//            | `defaultIRealPath`      | ''                 | ''                 | ''                |
//            | `loadIRealLibrary(ref)` | reads the file at  | opens the chooser  | opens the chooser |
//            |                         | `ref`, or opens    | (the reference is  | (the reference is |
//            |                         | the chooser when   | ignored)           | ignored)          |
//            |                         | `ref` is empty     |                    |                   |
//            | `chooseIRealReference()`| opens the chooser, | null — the chooser | null — the        |
//            |                         | answers its path   | is reached through | browser has its   |
//            |                         |                    | the loader         | own button        |
//
//          `IRealFileCancelledException`, the vocabulary both implementations must agree on, is
//          re-exported from `ireal_source_contract.dart` so a caller imports the seam once.
// KEYWORDS: ireal, import, conditional-export, platform-seam, composition-root, web, io, chooser,
//           scoped-storage, android
//
// WHY A CONDITIONAL EXPORT AND NOT A RUNTIME CHECK. `dart:io` cannot be imported into a browser
// build at all, so a `Platform.isWindows` branch inside one file would not compile on the web even
// though the branch is never taken. Choosing the implementation at compile time is what lets the
// web build exclude the filesystem entirely, and `dart.library.js_interop` is the condition rather
// than `dart.library.html` because the browser implementation uses the modern JS interop that a
// future `--wasm` build can also compile, while `dart:html` cannot.
//
// WHY `iRealSourceIsFilePath` IS NOW A RUNTIME ANSWER ON THE IO SIDE, AND WHY THAT IS THE FIX RATHER
// THAN A DRIFT. It used to be a compile-time `true` wherever `dart:io` existed, on the reasoning
// that a platform with a filesystem lets its reader type a path. That reasoning is true of a desktop
// and false of the owner's tablet: Android scoped storage means this application cannot read another
// application's `Documents`/`Downloads` by path, the manifest declares no storage permission, and a
// musician does not know the absolute path of their own export in the first place. The screen the
// defect produced was honest and useless — a field nobody can fill and no music. The flag therefore
// answers the question it always claimed to answer, "may the reader type a path and have it work?",
// from the platform's real capability; see `platformFilesCanReadTypedPath` in `native_file_dialog.dart`.
export 'ireal_source_contract.dart';

export 'ireal_source_io.dart'
    if (dart.library.js_interop) 'ireal_source_web.dart';
