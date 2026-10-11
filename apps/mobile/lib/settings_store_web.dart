// PURPOSE: Keep the language choice in the browser's own key/value storage, which is the only
//          synchronous place a page has to remember anything. It is the web half of the seam
//          `settings_store.dart` exposes, and it is honest about what that storage is worth.
// INPUTS: None. The choice is read from and written to the page's origin.
// OUTPUTS: `loadSettingsStore()`, answering with a store over `window.localStorage`. Storage the
//          browser refuses — a blocked-cookie context, some private-browsing modes, a disabled
//          storage partition — is caught on both operations: reads answer null and writes do
//          nothing, so the application starts in the device's language and a change lasts for the
//          session instead of throwing inside a build. The reason is logged once per operation.
// KEYWORDS: settings, language, web, local-storage, js-interop, eviction, d20, degrade-dont-throw
//
// WHY THIS IS NOT A FILE, AND WHAT IT COSTS — THE HONEST ANSWER, because D20 is emphatic that a
// musician's data lives in files and this is not an exception to that rule.
//
// The musician's CHARTS are files here too: `chart_source_web.dart` opens them through the
// browser's chooser and writes them through the File System Access API or a download. A language
// preference is not a chart. It is worth one tap, it means nothing on another device, and it is
// meaningless without the browser that holds it — which is the opposite of every property D20 uses
// to justify file storage.
//
// WHAT IT COSTS, NAMED. Safari clears script-writable storage after seven days without use
// (WebKit 232302, WONTFIX); the one exemption is an application installed to the home screen in
// `standalone` mode, which is the mode D20 distributes the application in. So an INSTALLED
// ChartApp keeps its language; a page merely bookmarked and left alone for a week comes back in
// the device's language. That is the whole of the loss: the musician is shown the same charts
// either way, and switching back is one tap in Settings. Losing a chart is not possible this way,
// which is exactly why the charts are files and this is not.
//
// WHY NOT `showSaveFilePicker` FOR THE SETTING. A file picker per launch, and a permission prompt
// to read one word, would be a worse experience than the seven-day risk it removes — and a
// preference is not something a musician wants to manage as a document.
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'settings_contract.dart';

/// The `window.localStorage` key the choice is stored under, namespaced so it cannot collide with
/// anything else served from the same origin.
const String languageStorageKey = 'chartapp.language';

@JS('window')
external _Window get _window;

@JS('Window')
extension type _Window._(JSObject _) implements JSObject {
  external _Storage get localStorage;
}

@JS('Storage')
extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

/// A [SettingsStore] backed by the page's `localStorage`.
class BrowserSettingsStore implements SettingsStore {
  /// Creates the store. Nothing is read or written until one of the two methods is called.
  BrowserSettingsStore();

  @override
  LanguageChoice? readLanguage() {
    try {
      final String? stored = _window.localStorage.getItem(languageStorageKey);
      return stored == null ? null : LanguageChoice.fromLanguageCode(stored);
    } catch (error) {
      // Storage refused: this is a first-run experience from here on, which is a supported state.
      debugPrint('settings.language.read.failed error=$error');
      return null;
    }
  }

  @override
  void writeLanguage(LanguageChoice choice) {
    try {
      _window.localStorage.setItem(languageStorageKey, choice.storageValue);
      debugPrint('settings.language.write.ok value=${choice.storageValue}');
    } catch (error) {
      // The change is already on screen; this line is why the next launch will not remember it.
      debugPrint('settings.language.write.failed error=$error');
    }
  }
}

/// The store `settings_store.dart` exports for the web target.
SettingsStore loadSettingsStore() => BrowserSettingsStore();
