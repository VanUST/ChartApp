// PURPOSE: Give the browser the two things [ireal_source] promises — a loader and an answer to
//          "is a reference a filesystem path?" — where no filesystem and no path exist. The reader
//          picks a file through the browser's own chooser and the browser hands its text over; the
//          viewer is fed through the same `IRealLibraryLoader` it already injects, so it does not
//          know which implementation it got.
// INPUTS: A reference string the loader ignores, plus the reader's choice in the browser's file
//         chooser.
// OUTPUTS: [iRealSourceIsFilePath] is false, [defaultIRealPath] is the empty string (there is no
//          path to offer), and [loadIRealLibrary] answers with the library parsed from the chosen
//          file. Throws a [FormatException] when the reader dismisses the chooser or the file
//          holds no `irealb://` link, and whatever the DOM throws when the file cannot be read.
// KEYWORDS: ireal, import, web, file-picker, js-interop, conditional-import, web-implementation
//
// WHY THE REFERENCE ARGUMENT IS IGNORED. The viewer's seam is `IRealLibraryLoader`,
// `Future<IRealLibrary> Function(String)`, and keeping that ONE seam is deliberate: the browser
// cannot name a file by path at all, so the argument has nothing to carry. The alternative — a
// second, parameterless seam used only on the web — would mean the viewer has two loading paths
// and every future caller has to know which one is live.
//
// WHY RAW `dart:js_interop` AND NOT `dart:html`. `dart:html` is excluded from `--wasm` builds, and
// a wasm build is the direction a web-first product wants; it would also be a second rendering
// target to keep honest. `dart:js_interop` is in the SDK, so this costs no dependency, and the
// handful of DOM members used here are declared below rather than pulled in wholesale.
//
// KNOWN LIMIT, STATED RATHER THAN HIDDEN. A dismissed chooser is reported through the `cancel`
// event, which the browsers this app targets all fire (Chrome/Edge 113+, Firefox 91+, Safari
// 16.4+). On an older browser no event arrives at all, so the load would stay in its busy state
// until another try; this is not papered over with a timeout, because a timeout would have to
// guess how long a person may browse for their file.
import 'dart:async';
import 'dart:js_interop';

import 'ireal_library.dart';

/// No filesystem path to offer, because a browser has no path to give.
///
/// The viewer reads this only when [iRealSourceIsFilePath] is true, so on the web its value is
/// never shown; the empty string is here to keep one symbol meaning one thing across platforms.
const String defaultIRealPath = '';

/// Whether a reader can name an iReal export by a filesystem path on this platform.
///
/// False: a browser cannot name a file the reader has not chosen, so this is what makes the viewer
/// show a file-picker button instead of a path field, and what keeps it from calling the loader
/// before the reader has acted — a chooser opened outside a user gesture is refused by the
/// browser.
const bool iRealSourceIsFilePath = false;

// PURPOSE: Read the export the reader picks in the browser's file chooser and hand back its songs,
//          which is the only file access the viewer performs on this platform.
// INPUTS: reference — ignored; see the library header for why the seam still takes it.
// OUTPUTS: The parsed [IRealLibrary]. Throws a [FormatException] when the reader dismisses the
//          chooser, when no file is present, or when the chosen file holds no `irealb://` link.
// KEYWORDS: file-picker, click, user-gesture, js-interop, ireal-link, web-implementation
/// Opens the browser's file chooser and loads the iReal library in the chosen file.
Future<IRealLibrary> loadIRealLibrary(String reference) async {
  final _HtmlInputElement input = _document.createElement('input');
  input
    ..setAttribute('style', 'display:none')
    ..type = 'file'
    ..accept = '.html,.htm,text/html';
  // Attached before clicking because a detached input is refused by some browsers, and removed in
  // the `finally` below so the page is left exactly as it was found.
  final _HtmlElement? body = _document.body;
  body?.appendChild(input);

  final Completer<void> settled = Completer<void>();
  bool cancelled = false;
  input.onchange = (() {
    if (!settled.isCompleted) {
      settled.complete();
    }
  }).toJS;
  input.oncancel = (() {
    cancelled = true;
    if (!settled.isCompleted) {
      settled.complete();
    }
  }).toJS;

  try {
    // Reached before the first `await`, so this still runs inside the click that started the
    // load: a chooser opened outside a user gesture is refused by the browser.
    input.click();
    await settled.future;
    if (cancelled) {
      throw const FormatException('No file was chosen.');
    }
    final _FileList? files = input.files;
    if (files == null || files.length == 0) {
      throw const FormatException('No file was chosen.');
    }
    final _WebFile? file = files.item(0);
    if (file == null) {
      throw const FormatException('No file was chosen.');
    }
    final String contents = (await file.text().toDart).toDart;
    return parseIRealExport(contents, source: file.name);
  } finally {
    body?.removeChild(input);
  }
}

// The DOM surface this file touches, declared here instead of depending on `package:web`. Each
// extension type names the JavaScript class it wraps; the members are only those the picker needs.

@JS('document')
external _Document get _document;

@JS('Document')
extension type _Document._(JSObject _) implements JSObject {
  external _HtmlInputElement createElement(String tagName);
  external _HtmlElement? get body;
}

@JS('HTMLElement')
extension type _HtmlElement._(JSObject _) implements JSObject {
  external void appendChild(JSObject node);
  external void removeChild(JSObject node);
}

@JS('HTMLInputElement')
extension type _HtmlInputElement._(JSObject _) implements JSObject {
  external void setAttribute(String name, String value);
  external set type(String value);
  external set accept(String value);
  external set onchange(JSFunction? value);
  external set oncancel(JSFunction? value);
  external _FileList? get files;
  external void click();
}

@JS('FileList')
extension type _FileList._(JSObject _) implements JSObject {
  external int get length;
  external _WebFile? item(int index);
}

@JS('File')
extension type _WebFile._(JSObject _) implements JSObject {
  external String get name;
  external JSPromise<JSString> text();
}
