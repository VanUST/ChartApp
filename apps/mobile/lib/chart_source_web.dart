// PURPOSE: Give a browser the things [chart_source] promises — save a container and read one back,
//          for a `.chart` file and for a `.setlist` file alike — where no filesystem and no path
//          exist, and answer honestly which of the two browser save mechanisms is actually in force.
//          Opening goes through the browser's own chooser; saving re-writes in place through the
//          File System Access API where the browser has it, and otherwise hands the reader a
//          download, saying which one it did.
// INPUTS: name — the file name to offer, which is the only thing a browser can be told about a
//         destination before the reader picks one; bytes — the whole encoded container. For the two
//         load functions, the argument is carried for the seam's shape and ignored, exactly as the
//         iReal picker ignores its reference, because a browser page cannot name a file at all. The
//         two formats differ in exactly one visible place: the extension the chooser filters on.
// OUTPUTS: [chartSourceIsFilePath] is false, [chartSourceSaveMode] reports the mechanism this
//          browser actually has, the two save functions complete once the bytes have left the page,
//          and the two load functions answer with the chosen file's bytes. A dismissed chooser
//          throws a [ChartFileCancelledException]; a browser that refuses the chosen file throws
//          whatever the DOM throws. Neither is a silent no-op: a save that went nowhere must not
//          look like a save that worked.
// KEYWORDS: chart-file, setlist-file, web, browser, js-interop, file-system-access, download,
//           capability-check, d20, file-picker, conditional-export
//
// WHY THERE ARE TWO SAVE MECHANISMS AND NOT ONE.
//
// D20 wants a `.chart` file the musician can keep, and the two browsers this app is aimed at do not
// offer the same way to do that. Chromium's File System Access API hands back a HANDLE to the file
// the reader chose, and that handle can be written again and again — which is what an autosave
// depends on. WebKit has no such handle; the most a page can do is create a Blob and let the
// browser's download machinery put a copy on disk, which means every save is a NEW file.
//
// The two are detected rather than guessed. `showSaveFilePicker` is looked for ON THE WINDOW with
// JavaScript's own `in`, so the answer is the browser's, not a user-agent string's: a browser that
// ships the API gets the in-place path even if its name is not on any list, and a browser that lacks
// it gets the download path even if its name is. The user-agent string is deliberately not read —
// it is spoofable, it names versions rather than capabilities, and Chrome on Android is the exact
// case that proves it: it carries Chrome's name and does NOT have this API, so a name-based rule
// would promise in-place re-writing to the one platform that cannot do it.
//
// WHAT CANNOT BE DONE HERE, STATED RATHER THAN HIDDEN.
//   - The keyboard cannot be driven from the page. A chooser must be opened inside a user gesture,
//     so both entry points call into the DOM before their first `await`; a future autosave that
//     wanted to CREATE a handle without a gesture would be refused by the browser, and that is a
//     property of the browser, not an oversight here.
//   - A dismissed chooser is reported through the `cancel` event (Chrome/Edge 113+, Firefox 91+,
//     Safari 16.4+) and by the picker's `AbortError` for the save path. On an older browser no
//     event arrives and the read would stay busy; no timeout is invented, for the same reason the
//     iReal picker has none — a timeout would have to guess how long a person may browse.
//   - Revoking the download's object URL is deferred rather than immediate. Revoking it in the same
//     turn as the click has been observed to cancel the download that had only just been queued.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:chart_core/chart_core.dart';
import 'package:flutter/foundation.dart';

import 'chart_source_contract.dart';

/// Whether a reader can name a `.chart` file by a filesystem path on this platform.
///
/// False: a browser cannot name a file the reader has not chosen, and cannot overwrite one it has
/// not been handed. The chart dialog reads this to decide between a path field and a file-name
/// field, not to hide itself: saving and opening both work here, through the browser's choosers.
const bool chartSourceIsFilePath = false;

/// The property the File System Access API's save picker hangs off `window`.
///
/// Named once so the capability check and the call cannot drift apart: a member that is called
/// under one name and tested under another would either throw or silently take the download path.
const String _savePickerMember = 'showSaveFilePicker';

/// The file handles this page has already been given, keyed by the name the reader accepted.
///
/// The map is the whole of the in-place mechanism: the FIRST save picks a file and stores its
/// handle, and every later save under the same name re-writes that handle without a picker and
/// without a gesture, which is what autosave will need. It is per-page state and is meant to be:
/// a handle is a capability the browser granted to this page, and it does not survive a reload
/// because the browser does not hand it back.
final Map<String, _FileSystemFileHandle> _handlesByName =
    <String, _FileSystemFileHandle>{};

// PURPOSE: Report which save mechanism this browser actually has, so the chart dialog can say what
//          pressing Save will do before it is pressed.
// INPUTS: None. The answer comes from the window, not from the reader or from the URL.
// OUTPUTS: [ChartSaveMode.rewriteInPlace] when `showSaveFilePicker` is on the window — the browser
//          can re-write a file it has been given — and [ChartSaveMode.download] otherwise. It never
//          returns [ChartSaveMode.namedPath]: a page has no path to name.
// KEYWORDS: capability-check, file-system-access, download, save-mode, js-interop
/// Whether this browser can re-write a chart file in place, decided by the API's presence.
ChartSaveMode chartSourceSaveMode() => _window.has(_savePickerMember)
    ? ChartSaveMode.rewriteInPlace
    : ChartSaveMode.download;

// PURPOSE: Put a container where the reader can keep it, using the strongest mechanism the browser
//          has: an in-place re-write of a file already chosen, or a fresh download when it has none.
// INPUTS: name — the file name to offer the picker and to give the download; empty is refused by the
//         caller before it gets here, because neither mechanism can put a nameless file anywhere a
//         person can find it. bytes — the whole encoded container.
// OUTPUTS: A future that completes once the browser has taken the bytes. A picker the reader
//          dismisses throws [ChartFileCancelledException]; a remembered handle that can no longer be
//          written throws whatever the DOM throws and is forgotten before it does, so the next save
//          asks for a file instead of failing the same way again. On the download path nothing is
//          awaited, because the browser reports nothing back about a download it accepted.
// KEYWORDS: save, file-system-access, create-writable, download, blob, handle-reuse, user-gesture
/// Saves [bytes] under [name], re-writing in place where that is possible.
Future<void> saveChartFile(String name, Uint8List bytes) =>
    _saveNamed(name, bytes, kind: 'chart');

// PURPOSE: Save a programme through the very same mechanism, so a `.setlist` file in a browser is
//          handed over exactly like a `.chart` file and the sentences the dialog shows stay true
//          for both.
// INPUTS: name — the file name to offer. bytes — the whole encoded setlist container.
// OUTPUTS: The same future and the same failures as [saveChartFile], differing only in the log line
//          that records which of the two was written.
// KEYWORDS: save, setlist-file, file-system-access, download, handle-reuse, one-mechanism
/// Saves [bytes] under [name], re-writing in place where that is possible.
Future<void> saveSetlistFile(String name, Uint8List bytes) =>
    _saveNamed(name, bytes, kind: 'setlist');

// PURPOSE: Add one `kind` parameter to [saveChartFile]'s body rather than writing a second one
//          beside it, because the mechanism is a property of the BROWSER and not of the document.
// INPUTS: name, bytes as above. kind — the word the log line reports, so the two formats can be
//         told apart in a trace without a second implementation to keep in step.
// OUTPUTS: As [saveChartFile].
// KEYWORDS: save, one-mechanism, structured-log, kind
Future<void> _saveNamed(
  String name,
  Uint8List bytes, {
  required String kind,
}) async {
  final String target = name.trim();
  final _FileSystemFileHandle? remembered = _handlesByName[target];
  if (remembered != null) {
    try {
      await _writeThrough(remembered, bytes, mode: 'in-place', kind: kind);
    } catch (_) {
      // A remembered handle is the page's only way back to that file, and one whose permission was
      // revoked — or whose file was moved or deleted — fails for ever. Dropping it means the next
      // Save asks the reader for a file again instead of failing the same way every time; the
      // failure itself is still rethrown so the dialog can show what the browser said.
      _handlesByName
        ..remove(target)
        ..remove(remembered.name);
      rethrow;
    }
    return;
  }
  if (chartSourceSaveMode() == ChartSaveMode.rewriteInPlace) {
    // Called before the first `await` so the picker is still inside the click that started the
    // save: a browser refuses to open a file chooser outside a user gesture.
    final JSPromise<_FileSystemFileHandle> picked = _window.showSaveFilePicker(
      _saveOptions(target),
    );
    final _FileSystemFileHandle handle;
    try {
      handle = await picked.toDart;
    } catch (error) {
      if (_isAbort(error)) {
        debugPrint('$kind.save.web.cancelled name_chars=${target.length}');
        throw const ChartFileCancelledException('No file was chosen.');
      }
      rethrow;
    }
    // Stored under BOTH names: the reader may have renamed the file in the picker, and the next
    // save will arrive with the name the dialog holds, which is the suggested one.
    _handlesByName[target] = handle;
    _handlesByName[handle.name] = handle;
    await _writeThrough(handle, bytes, mode: 'picked', kind: kind);
    return;
  }
  _download(target, bytes, kind: kind);
}

// PURPOSE: Read the container the reader picks in the browser's chooser and hand back its bytes,
//          which is the only file read this seam performs on this platform.
// INPUTS: path — ignored; a page cannot resolve a path, and the seam keeps the argument so that the
//         viewer has ONE save/open shape rather than one per platform.
// OUTPUTS: The chosen file's bytes. Throws a [ChartFileCancelledException] when the reader dismisses
//          the chooser or no file is present, and whatever the DOM throws when the file cannot be
//          read.
// KEYWORDS: open, file-picker, click, user-gesture, array-buffer, js-interop, typed-failure
/// Opens the browser's file chooser and reads the chosen `.chart` file.
Future<Uint8List> loadChartFile(String path) =>
    _pickBytes('.chart', kind: 'chart');

// PURPOSE: Read the `.setlist` file the reader picks, through the same chooser the chart read uses.
// INPUTS: path — ignored, as above.
// OUTPUTS: The chosen file's bytes, or the same typed failures [loadChartFile] reports. The only
//          difference is the extension the chooser filters on.
// KEYWORDS: open, setlist-file, file-picker, typed-failure, one-mechanism
/// Opens the browser's file chooser and reads the chosen `.setlist` file.
Future<Uint8List> loadSetlistFile(String path) =>
    _pickBytes(setlistFileExtension, kind: 'setlist');

// PURPOSE: Open a file chooser filtered to one extension and read the chosen file, so the two
//          formats differ in one argument rather than in two implementations of the DOM dance.
// INPUTS: accept — the extension the chooser filters on, with its dot. kind — the word the log line
//         reports.
// OUTPUTS: The chosen file's bytes. Throws a [ChartFileCancelledException] when the reader dismisses
//          the chooser or no file is present, and whatever the DOM throws when the file cannot be
//          read. The bytes are copied out of the JavaScript heap before they are returned, so no
//          caller can hold a view into memory the browser is free to move.
// KEYWORDS: file-picker, click, user-gesture, array-buffer, accept-filter, one-mechanism
Future<Uint8List> _pickBytes(String accept, {required String kind}) async {
  final _HtmlElement element = _document.createElement('input');
  final _HtmlInputElement input = _HtmlInputElement._(element);
  input
    ..setAttribute('style', 'display:none')
    ..type = 'file'
    ..accept = accept;
  // Attached before clicking because a detached input is refused by some browsers, and removed in
  // the `finally` below so the page is left exactly as it was found.
  final _HtmlElement? body = _document.body;
  body?.appendChild(element);

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
    // Reached before the first `await`, so this still runs inside the click that started the load:
    // a chooser opened outside a user gesture is refused by the browser.
    input.click();
    await settled.future;
    if (cancelled) {
      debugPrint('$kind.open.web.cancelled');
      throw const ChartFileCancelledException('No file was chosen.');
    }
    final _FileList? files = input.files;
    final _WebFile? file = files == null || files.length == 0
        ? null
        : files.item(0);
    if (file == null) {
      throw const ChartFileCancelledException('No file was chosen.');
    }
    final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
    final Uint8List bytes = Uint8List.fromList(Uint8List.view(buffer.toDart));
    debugPrint(
      '$kind.open.web.ok bytes=${bytes.length} name_chars=${file.name.length}',
    );
    return bytes;
  } finally {
    body?.removeChild(element);
  }
}

// PURPOSE: Re-write a file the page already holds the handle to, which is the in-place half of D20's
//          save: a stream is opened over the handle, given the whole container, and closed.
// INPUTS: handle — a handle the browser granted this page, either just picked or remembered from an
//         earlier save. bytes — the whole container, written as one typed array. mode — the word the
//         log line reports, so a lucky path and a re-write can be told apart afterwards. kind — the
//         word that says whether a chart or a programme was written.
// OUTPUTS: A future that completes once the stream is closed. A write that throws still closes the
//          stream, because an unclosed writable keeps the file locked; the failure is then rethrown
//          so the dialog can show it.
// KEYWORDS: file-system-access, create-writable, stream, close-on-failure, in-place, structured-log
/// Writes [bytes] through [handle], closing the stream even when the write fails.
Future<void> _writeThrough(
  _FileSystemFileHandle handle,
  Uint8List bytes, {
  required String mode,
  required String kind,
}) async {
  final _FileSystemWritableFileStream writable = await handle
      .createWritable()
      .toDart;
  try {
    await writable.write(bytes.toJS).toDart;
  } finally {
    await writable.close().toDart;
  }
  debugPrint(
    '$kind.save.web mode=$mode bytes=${bytes.length} '
    'name_chars=${handle.name.length}',
  );
}

// PURPOSE: Hand the container to the reader as a download, which is the only save a browser without
//          the File System Access API can perform.
// INPUTS: name — the file name the browser will propose. bytes — the whole container. kind — the
//         word that says whether a chart or a programme was written.
// OUTPUTS: Nothing; the download is fire-and-forget because the browser reports nothing about one.
//          The object URL is revoked after a delay rather than immediately, because revoking it in
//          the same turn as the click has been observed to cancel the download.
// KEYWORDS: download, blob, object-url, anchor-click, revoke-deferred, safari-fallback
/// Downloads [bytes] as a file called [name].
void _download(String name, Uint8List bytes, {required String kind}) {
  final JSObject blob = _blob(bytes);
  final JSObject urlApi = globalContext['URL'] as JSObject;
  final JSString objectUrl = urlApi.callMethod<JSString>(
    'createObjectURL'.toJS,
    blob,
  );
  final _HtmlElement element = _document.createElement('a');
  final _HtmlAnchorElement anchor = _HtmlAnchorElement._(element);
  anchor
    ..href = objectUrl.toDart
    ..download = name;
  final _HtmlElement? body = _document.body;
  body?.appendChild(element);
  try {
    anchor.click();
  } finally {
    element.remove();
    Timer(const Duration(seconds: 60), () {
      urlApi.callMethod<JSAny?>('revokeObjectURL'.toJS, objectUrl);
    });
  }
  debugPrint(
    '$kind.save.web mode=download bytes=${bytes.length} '
    'name_chars=${name.length}',
  );
}

// PURPOSE: Wrap the container's bytes in the JavaScript `Blob` the download anchor needs, without
//          pulling in a dependency for one call.
// INPUTS: bytes — the whole container.
// OUTPUTS: A `Blob` holding exactly those bytes. The typed array is copied into the JavaScript heap
//          by `toJS`, so the blob does not alias Dart memory that may move.
// KEYWORDS: blob, constructor, js-interop, typed-array, no-dependency
/// Returns a JavaScript `Blob` over [bytes].
JSObject _blob(Uint8List bytes) {
  final JSFunction constructor = globalContext['Blob'] as JSFunction;
  // The constructor takes ONE argument — an array of parts — so the typed array is wrapped in a
  // JavaScript array and that array is the single argument. Passing the bytes directly would call
  // `new Blob(uint8array)`, which is not the signature and would not throw where it is easy to see.
  return constructor.callAsConstructorVarArgs<JSObject>(<JSAny?>[
    <JSAny?>[bytes.toJS].toJS,
  ]);
}

// PURPOSE: Build the options object for the save picker, naming the file the reader will see.
// INPUTS: suggestedName — the name to propose; the reader may change it.
// OUTPUTS: A JavaScript object with that one field. No `types` filter is passed on purpose: an
//          unknown MIME type in a filter makes the browser reject the whole options object, and the
//          `.chart` extension is already enough for both the picker and the download.
// KEYWORDS: show-save-file-picker, suggested-name, options-object, jsify
/// Returns the picker options proposing [suggestedName].
JSObject _saveOptions(String suggestedName) =>
    <String, Object?>{'suggestedName': suggestedName}.jsify()! as JSObject;

// PURPOSE: Tell "the reader changed their mind" apart from "the browser refused", because the two
//          need different words on screen and only the first is not a fault.
// INPUTS: error — whatever the rejected picker promise delivered.
// OUTPUTS: True when the rejection carries the DOM's `AbortError` name. A rejection that is not a
//          JavaScript object at all is answered by its text, because a string rejection is legal
//          JavaScript and must not be reported as a failure to save.
// KEYWORDS: abort-error, dom-exception, cancellation, error-classification
/// Whether [error] is the browser's own "the reader dismissed the picker" rejection.
bool _isAbort(Object error) {
  try {
    // Read as the string it is rather than checking the interop type first: `is JSString` is a
    // runtime check between two JavaScript types, which the analyzer rejects as not
    // platform-consistent, while `getProperty<JSString?>` asks the engine to hand the value over as
    // that type and throws when it is not one.
    final JSString? name = (error as JSObject).getProperty<JSString?>(
      'name'.toJS,
    );
    if (name != null && name.toDart == 'AbortError') {
      return true;
    }
  } catch (_) {
    // A rejection that is not a JavaScript object at all falls through to its own text below.
  }
  return error.toString().contains('AbortError');
}

// The DOM surface this file touches, declared here instead of depending on `package:web`. Each
// extension type names the JavaScript class it wraps; the members are only those the seam needs.

@JS('window')
external _Window get _window;

@JS('document')
external _Document get _document;

@JS('Window')
extension type _Window._(JSObject _) implements JSObject {
  external JSPromise<_FileSystemFileHandle> showSaveFilePicker(
    JSObject options,
  );
}

@JS('Document')
extension type _Document._(JSObject _) implements JSObject {
  external _HtmlElement createElement(String tagName);
  external _HtmlElement? get body;
}

@JS('HTMLElement')
extension type _HtmlElement._(JSObject _) implements JSObject {
  external void setAttribute(String name, String value);
  external void appendChild(JSObject node);
  external void removeChild(JSObject node);
  external void remove();
}

@JS('HTMLAnchorElement')
extension type _HtmlAnchorElement._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
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
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('FileSystemFileHandle')
extension type _FileSystemFileHandle._(JSObject _) implements JSObject {
  external String get name;
  external JSPromise<_FileSystemWritableFileStream> createWritable();
}

@JS('FileSystemWritableFileStream')
extension type _FileSystemWritableFileStream._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
}
