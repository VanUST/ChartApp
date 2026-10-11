// PURPOSE: Name the setting store for whatever platform this build is for, so that no caller in the
//          application ever has to ask which platform it is on. The conditional export at the
//          bottom is the whole of that decision, taken by the compiler, exactly as
//          `chart_source.dart` decides where a container's bytes come from.
// INPUTS: None. The implementation is chosen at compile time.
// OUTPUTS: `loadSettingsStore()`, and everything `settings_contract.dart` declares — the interface
//          and the [LanguageChoice] it stores.
// KEYWORDS: settings, language, conditional-export, platform-seam, composition-root, d20
//
// WHY THE STORE IS BUILT IN `main()` AND PASSED IN RATHER THAN REACHED FOR FROM THE WIDGET TREE.
// The same reason `loader` and `initialPath` are parameters of `ChartApp`: a widget test pumps the
// real shell without touching the real machine, and the platform-specific file — the only part that
// knows a filesystem or a `localStorage` exists — stays out of the widget layer entirely.
export 'settings_contract.dart';

export 'settings_store_io.dart'
    if (dart.library.js_interop) 'settings_store_web.dart';
