// PURPOSE: Hold the ONE place in this application that talks to the operating system's own file
//          dialog — reading a file the reader chose, and writing one to a destination the reader
//          chose — so that the two conditional-export seams that need it (`chart_source_io.dart` and
//          `ireal_source_io.dart`) cannot come to ask the platform two different questions, and so
//          the single operation the chosen plugin cannot perform is stated in one file.
//          IT IS AN IO-ONLY FILE WITH NO WEB TWIN, deliberately: a browser reaches its own chooser
//          through `chart_source_web.dart` and `ireal_source_web.dart`, which use raw
//          `dart:js_interop` and no plugin at all, so this file is compiled only into a native
//          build and is imported only by the two `_io` implementations.
// INPUTS: The filter a dialog should offer in each of the three vocabularies a platform may read
//         (extensions, MIME types, uniform type identifiers), plus the bytes or the suggested file
//         name a save needs. Nothing here knows what a `.chart`, a `.setlist` or an iReal export is;
//         the extensions are passed in by the seam that does.
// OUTPUTS: `platformFilesCanReadTypedPath`, the answer to "may a reader type the path of a file and
//          have the application open it?" — true on a desktop, false on a hand-held, where scoped
//          storage means another application's directory is unreadable by path whatever path is
//          typed. `chooseFileToRead` answers with the chosen file, or null when the reader changed
//          their mind. `saveBytesToChosenLocation` answers true once the bytes are written and false
//          when the reader dismissed the dialog; on a platform that has no way to ask it throws an
//          [UnsupportedError] naming that gap instead of writing nothing and reporting success.
// KEYWORDS: file-dialog, file-selector, android, scoped-storage, action-create-document,
//           method-channel, desktop, save-location, capability, io-only
//
// WHY THE PLUGIN AND A CHANNEL ARE BOTH HERE, RATHER THAN ONE OR THE OTHER.
//
// `file_selector` is the Flutter team's own federated plugin and it is the canonical route to the
// platform's file dialog; on Android it wraps `ACTION_OPEN_DOCUMENT`, which is the one API that can
// reach another application's `Documents`/`Downloads` without any storage permission, and it hands
// the chosen file back as bytes so a `content://` URI never has to become a path. That is reading,
// and reading is the operation the application cannot do without.
//
// It documents `getSaveLocation` as unsupported on Android and on iOS — its README's feature table,
// and flutter/flutter#168318, where a maintainer confirms that the Android answer is a `content://`
// URI and that "that path is not enough for saving a file", because writing one needs the
// `ContentResolver` stream API. Writing a `.chart` on Android is therefore one
// `ACTION_CREATE_DOCUMENT` intent, which is cheaper to own in this repository than a second plugin
// whose only job would be the same intent. The other end of that channel is
// `android/app/src/main/kotlin/com/chartapp/chartapp/MainActivity.kt`.
//
// WHY THE FILTER IS BUILT PER PLATFORM INSTEAD OF PASSED AS ONE GROUP. `XTypeGroup` carries four
// filter vocabularies and no platform reads all four; the plugin throws an [ArgumentError] when a
// group carries one the running platform cannot honour, and it calls that a programming error
// rather than ignoring it. Windows reads only `extensions`, iOS only `uniformTypeIdentifiers`, and
// macOS reads MIME types only from version 11. `_typeGroup` below is the whole of that translation.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;

/// The channel this application registers in order to write a file where the reader chose.
///
/// The name is also literal in `MainActivity.kt`, which is the only other end of it; a rename on one
/// side alone would fail at the first Android save rather than at build time, so both sides name it
/// in a comment as well as in code.
const MethodChannel _saveChannel = MethodChannel('chartapp/file_save');

/// Whether a reader can name a file by typing its path and have the application open it.
///
/// True on a desktop, where the process may open any file its owner may open; FALSE on Android and
/// iOS, where scoped storage makes another application's `Documents`/`Downloads` unreadable by path
/// altogether — a typed path there is not a slower way to the file, it is not a way to it at all.
/// This is the fact that `iRealSourceIsFilePath` and `chartSourceIsFilePath` report, and it is the
/// fact that decides, on each platform, whether the interface offers a path field or only a chooser.
///
/// A RUNTIME ANSWER INSIDE A COMPILE-TIME SEAM, ON PURPOSE. Which IMPLEMENTATION of a seam is
/// compiled is decided by `dart.library.js_interop` at build time. WHICH HAND-HELD OPERATING SYSTEM
/// is running is a different question, and the two hand-helds share one `dart:io` implementation
/// with the three desktops, differing in exactly this one respect. `dart:io` is available in this
/// file precisely because it is the io half, so the answer is read from the platform rather than
/// guessed from a version string or from a user-agent.
bool get platformFilesCanReadTypedPath =>
    !Platform.isAndroid && !Platform.isIOS;

// PURPOSE: Ask the operating system for a file the reader wants to open, filtered to the kinds this
//          application can read, and hand it back in a form every platform can read from.
// INPUTS: label — the words the dialog shows beside the filter. extensions — the file extensions to
//         offer, without their dots. mimeTypes, uniformTypeIdentifiers — the same filter in the two
//         other vocabularies, used only where the running platform understands them.
// OUTPUTS: The chosen file as an [XFile], whose `readAsString` and `readAsBytes` work on every
//          target INCLUDING ANDROID — the plugin copies the chosen document into the application's
//          own cache and returns the bytes with it, so no caller has to turn a `content://` URI into
//          a path, and no caller may assume `XFile.path` is readable. Null when the reader dismissed
//          the dialog, which is an outcome and not a failure.
// KEYWORDS: open-file, file-picker, type-filter, android-saf, bytes-not-path, cancellation
/// Opens the platform's own file chooser and returns the file the reader chose, or null.
Future<XFile?> chooseFileToRead({
  required String label,
  required List<String> extensions,
  List<String>? mimeTypes,
  List<String>? uniformTypeIdentifiers,
}) => openFile(
  acceptedTypeGroups: <XTypeGroup>[
    _typeGroup(
      label: label,
      extensions: extensions,
      mimeTypes: mimeTypes,
      uniformTypeIdentifiers: uniformTypeIdentifiers,
    ),
  ],
);

// PURPOSE: Ask the operating system where a container should go and write the bytes there, which is
//          the only way an Android build can produce a file the musician can find afterwards.
// INPUTS: suggestedName — the file name to propose, its extension included, which is the only thing
//         this application can say about a destination before one is chosen. bytes — the whole
//         encoded container. The filter arguments are as [chooseFileToRead]'s, and for the same
//         reason.
// OUTPUTS: True once the bytes are written and false when the reader dismissed the dialog — the two
//          are told apart because a dismissal is not an error. Throws an [UnsupportedError] on a
//          platform this application has no way to ask (iOS today), and whatever `dart:io` throws
//          when a desktop path the reader chose cannot be written; neither is swallowed, because a
//          save that went nowhere must never look like a save that worked.
// KEYWORDS: save-file, save-location, action-create-document, method-channel, desktop-path,
//           cancellation, unsupported-platform
/// Asks the platform where to save a file and writes [bytes] there.
Future<bool> saveBytesToChosenLocation({
  required String suggestedName,
  required Uint8List bytes,
  required String label,
  required List<String> extensions,
  List<String>? mimeTypes,
  List<String>? uniformTypeIdentifiers,
}) async {
  // Android first, because it is the platform whose save dialog the plugin does not provide and so
  // the one this application has to provide itself.
  if (Platform.isAndroid) {
    final bool saved =
        await _saveChannel.invokeMethod<bool>('saveDocument', <String, Object?>{
          'name': suggestedName,
          'bytes': bytes,
        }) ??
        false;
    debugPrint(
      'files.save.android name_chars=${suggestedName.length} '
      'bytes=${bytes.length} saved=$saved',
    );
    return saved;
  }
  if (Platform.isIOS) {
    // NAMED, NOT FAKED. `file_selector` implements no save dialog on iOS and this application
    // registers no iOS channel for one, so there is nothing here to call. A silent no-op would look
    // like a save that worked; this reaches the reader as the typed failure the dialog already
    // knows how to print.
    throw UnsupportedError(
      'Choosing a save location is not supported on iOS: file_selector implements no save dialog '
      'there and this application registers no channel for one.',
    );
  }
  final List<XTypeGroup> groups = <XTypeGroup>[
    _typeGroup(
      label: label,
      extensions: extensions,
      mimeTypes: mimeTypes,
      uniformTypeIdentifiers: uniformTypeIdentifiers,
    ),
  ];
  final FileSaveLocation? location = await getSaveLocation(
    acceptedTypeGroups: groups,
    suggestedName: suggestedName,
  );
  if (location == null) {
    debugPrint(
      'files.save.desktop.cancelled name_chars=${suggestedName.length}',
    );
    return false;
  }
  await File(location.path).writeAsBytes(bytes, flush: true);
  debugPrint(
    'files.save.desktop.ok name_chars=${suggestedName.length} '
    'bytes=${bytes.length}',
  );
  return true;
}

/// Builds the single filter group a dialog is offered, in the vocabulary this platform reads.
///
/// Each platform understands a different subset of `XTypeGroup`'s four filter fields and the plugin
/// raises an `ArgumentError` for any it does not, so this translation is a correctness requirement
/// rather than tidiness. `extensions` is passed everywhere because every platform reads it.
XTypeGroup _typeGroup({
  required String label,
  required List<String> extensions,
  List<String>? mimeTypes,
  List<String>? uniformTypeIdentifiers,
}) {
  // Android and Linux read extensions and MIME types; Windows reads extensions alone; iOS reads
  // uniform type identifiers alone; macOS reads extensions and uniform type identifiers, and MIME
  // types only from version 11 — leaving them off there costs nothing, since the extension already
  // filters the dialog.
  final bool readsMimeTypes = Platform.isAndroid || Platform.isLinux;
  final bool readsUniformTypes = Platform.isIOS || Platform.isMacOS;
  return XTypeGroup(
    label: label,
    extensions: extensions,
    mimeTypes: readsMimeTypes ? mimeTypes : null,
    uniformTypeIdentifiers: readsUniformTypes ? uniformTypeIdentifiers : null,
  );
}
