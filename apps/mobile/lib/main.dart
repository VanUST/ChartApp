// PURPOSE: Start the ChartApp application and establish the three facts the rest of the widget tree
//          relies on: the Flutter binding exists, the ink platform accessor resolves on every
//          target, and the interface knows which language it is drawn in. The screen it shows is the
//          iReal reader, which draws an imported chart so the importer can be checked against the
//          application the file came from.
// INPUTS: An optional [IRealLibraryLoader] and starting reference, so a test can compose the
//         application with a synthetic payload instead of the owner's file, and an optional
//         [SettingsStore], so a test can run without touching — or reading — a settings file on the
//         machine. The loader and the reference both default to what `ireal_source.dart` selects
//         for the running platform; the store defaults to one that keeps nothing, and `main()`
//         passes the platform's real one.
// OUTPUTS: Runs the application. The home screen is [IRealViewerScreen], inside a [MaterialApp]
//          whose locale, delegates and supported locales decide every interface string in it.
// KEYWORDS: entrypoint, bootstrap, ink-fallback, composition-root, localization, language-choice,
//           locale-resolution, ireal-reader, viewer, web, settings
import 'package:flutter/material.dart';
import 'package:ink_native/ink_native.dart';

import 'ireal_source.dart';
import 'l10n/app_localizations.dart';
import 'settings_contract.dart';
import 'settings_store.dart' show loadSettingsStore;
import 'viewer_screen.dart';

/// Whether the running build has a native ink surface.
///
/// Read after [registerInkFallback] has run, so this is a value rather than an exception on
/// every platform. False wherever no platform package has claimed the slot: Linux, Windows, iOS
/// (whose package is still scaffolding) and the web (whose implementation is a separate spike —
/// owner decision D20 — not this fallback pretending to be one). True on Android, where the
/// generated registrant installs `InkNativeAndroid` before `main`. The answer is read from the
/// registered implementation rather than derived from `Platform`, so it cannot drift from which
/// package actually registered.
bool get inkIsAvailable => InkNativePlatform.instance.supportsInk;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerInkFallback();
  // The one place a platform store is built. It is read synchronously here, before the first frame,
  // so the interface is never painted in one language and then swapped to another.
  runApp(ChartApp(settings: loadSettingsStore()));
}

/// The application root.
///
/// It owns exactly one piece of state — the language choice — because that is the one fact that has
/// to be decided ABOVE the [MaterialApp] rather than below it: the locale is an input to the widget
/// that provides every translation in the tree.
class ChartApp extends StatefulWidget {
  /// Creates the application root.
  ///
  /// [loader] and [initialPath] are injected so a widget test can boot the real shell against a
  /// synthetic library; the defaults read whichever file the reader names — through a typed path
  /// where that addresses one, and through the platform's own chooser everywhere else, because
  /// `ireal_source.dart` supplies the implementation and `defaultIRealPath` is empty so that the
  /// application asks instead of guessing. [settings] is injected so a test never reads or
  /// writes the machine's real preference file; the default keeps nothing past the process.
  const ChartApp({
    super.key,
    this.loader = loadIRealLibrary,
    this.initialPath = defaultIRealPath,
    this.settings,
  });

  /// How the viewer turns a reference into a library.
  final IRealLibraryLoader loader;

  /// The reference the viewer's source bar starts with.
  final String initialPath;

  /// Where the language choice is kept between runs, or null for a store that keeps nothing.
  ///
  /// NOT A CONST DEFAULT, because the default store holds the value it was given and a `const`
  /// constructor cannot have a field that changes. Nulling it and building the fallback in the
  /// state keeps `ChartApp`'s own constructor `const` — which is what lets a caller write
  /// `const ChartApp()` — while a widget test still gets a store that touches no file.
  final SettingsStore? settings;

  @override
  State<ChartApp> createState() => _ChartAppState();
}

/// The application's own state: the language choice, and nothing else.
class _ChartAppState extends State<ChartApp> {
  /// Where the choice is kept, which is the injected store or one that forgets.
  late final SettingsStore _settings =
      widget.settings ?? VolatileSettingsStore();

  /// The language the interface is drawn in, seeded from what is on the device.
  ///
  /// Read ONCE, here, rather than on every build: a store that was consulted per frame would make
  /// the language a function of file I/O, and a half-written file would be able to change the
  /// interface mid-session. The choice changes when the settings sheet says so and at no other
  /// time.
  late LanguageChoice _language =
      _settings.readLanguage() ?? LanguageChoice.system;

  // PURPOSE: Adopt the language the musician picked in the settings sheet, and remember it.
  // INPUTS: choice — the row they tapped, which may be the one already in force.
  // OUTPUTS: Nothing. Rebuilds with the new locale, so the sheet's own strings and every string
  //          under it change on the next frame; then persists the choice, which is what makes it
  //          survive a restart. The write is last on purpose: a store that fails must not be able
  //          to stop the choice from taking effect on screen.
  // KEYWORDS: language, runtime-switch, persistence, rebuild, effect-before-durability
  void _chooseLanguage(LanguageChoice choice) {
    setState(() => _language = choice);
    _settings.writeLanguage(choice);
    // The stored token, so this line and the store's own line name the value identically.
    debugPrint('settings.language.changed value=${choice.storageValue}');
  }

  @override
  Widget build(BuildContext context) {
    final String? code = _language.languageCode;
    return MaterialApp(
      // The brand name, identical in both languages, and read by the operating system rather than
      // by the musician inside this application.
      title: 'ChartApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5D8A)),
      ),
      // A NULL LOCALE IS THE FEATURE, not an omission: it hands the decision to Flutter's locale
      // resolution, which consults `supportedLocales` against the device's own language list. That
      // is what makes a Russian device open in Russian with nobody touching a switch. An explicit
      // choice replaces it and from then on outranks the device.
      locale: code == null ? null : Locale(code),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: IRealViewerScreen(
        loader: widget.loader,
        initialPath: widget.initialPath,
        language: _language,
        onLanguageChanged: _chooseLanguage,
      ),
    );
  }
}
