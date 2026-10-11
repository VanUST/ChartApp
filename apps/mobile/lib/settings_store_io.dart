// PURPOSE: Keep the language choice in a small file beside the platform's other configuration, on
//          every target that has a filesystem — desktop, Android, iOS. It is the native half of the
//          seam `settings_store.dart` exposes.
// INPUTS: None. The directory is derived from the environment the process started with.
// OUTPUTS: `loadSettingsStore()`, answering with a store that reads and writes
//          `settings.json` under the platform's configuration directory. A directory that cannot be
//          created, a file that cannot be read and a file that cannot be written all DEGRADE rather
//          than throw: the store still works on screen, it just forgets. The reason is logged.
// KEYWORDS: settings, file, json, sync-io, app-data, degrade-dont-throw, d20
//
// WHY A FILE OF OUR OWN AND NOT A PREFERENCES PLUGIN. The choice is one string. A plugin would add
// a native dependency, a platform channel and a package to keep current, and on the web it would
// put the same value in `localStorage` anyway — where the reason to use it is the browser's, not a
// plugin's. Two conditional-import files and one JSON object cost less than that and are the
// pattern this application already uses for every other platform difference.
//
// WHY SYNC. See [SettingsStore]: the choice is read before the first frame, so the interface never
// paints in a language and then swaps. The file is tens of bytes, read once per launch.
//
// WHERE IT LIVES, AND WHY THAT IS NOT A CHART DIRECTORY. This is the platform's own place for
// configuration — `%APPDATA%\ChartApp` on Windows, `~/Library/Application Support/ChartApp` on
// macOS, `$XDG_CONFIG_HOME/ChartApp` (or `~/.config/ChartApp`) elsewhere. It is deliberately NOT
// beside the `.chart` files, because D20 makes those the musician's documents: moving or deleting
// them must not touch a setting, and a setting must never be mistaken for one.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'settings_contract.dart';

/// The name of the file the choice is kept in, under the platform's configuration directory.
const String settingsFileName = 'settings.json';

/// The key the choice is stored under.
///
/// A key rather than a bare string, so the file has room for a second setting without every reader
/// of the first having to be changed.
const String languageSettingKey = 'language';

/// The platform's configuration directory for this application, or null when none can be named.
///
/// Null is possible in a stripped-down service context with no home directory; [FileSettingsStore]
/// then keeps nothing past the process and logs why.
Directory? chartAppConfigDirectory() {
  final Map<String, String> env = Platform.environment;
  String? base;
  if (Platform.isWindows) {
    base = env['APPDATA'];
  } else if (Platform.isMacOS) {
    final String? home = env['HOME'];
    base = home == null ? null : '$home/Library/Application Support';
  } else {
    base = env['XDG_CONFIG_HOME'];
    final String? home = env['HOME'];
    if (base == null && home != null) {
      base = '$home/.config';
    }
  }
  if (base == null || base.isEmpty) {
    return null;
  }
  return Directory('$base${Platform.pathSeparator}ChartApp');
}

/// A [SettingsStore] backed by one small JSON file.
class FileSettingsStore implements SettingsStore {
  /// Creates a store over [directory], or over the platform's configuration directory when it is
  /// null.
  FileSettingsStore({Directory? directory})
    : _directory = directory ?? chartAppConfigDirectory();

  final Directory? _directory;

  /// The settings file, or null when no directory could be determined.
  File? get _file {
    final Directory? directory = _directory;
    if (directory == null) {
      return null;
    }
    return File('${directory.path}${Platform.pathSeparator}$settingsFileName');
  }

  @override
  LanguageChoice? readLanguage() {
    final File? file = _file;
    if (file == null) {
      return null;
    }
    try {
      if (!file.existsSync()) {
        return null;
      }
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final Object? value = decoded[languageSettingKey];
      return value is String ? LanguageChoice.fromLanguageCode(value) : null;
    } catch (error) {
      // A settings file that cannot be read is not a reason to refuse to start: the application
      // falls back to the device's language, which is what a first run does anyway.
      debugPrint('settings.language.read.failed error=$error');
      return null;
    }
  }

  @override
  void writeLanguage(LanguageChoice choice) {
    final File? file = _file;
    if (file == null) {
      debugPrint('settings.language.write.skipped reason=no-config-directory');
      return;
    }
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode(<String, Object?>{languageSettingKey: choice.storageValue}),
      );
      debugPrint('settings.language.write.ok value=${choice.storageValue}');
    } catch (error) {
      // Named rather than hidden: the change is already on screen, so the musician is not told, but
      // the next launch will come back in the device's language and this line is why.
      debugPrint('settings.language.write.failed error=$error');
    }
  }
}

/// The store `settings_store.dart` exports for a native target.
///
/// A function rather than a top-level value so that a widget test, which never calls it, cannot
/// construct a filesystem store by accident.
SettingsStore loadSettingsStore() => FileSettingsStore();
