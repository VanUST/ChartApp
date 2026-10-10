// PURPOSE: Give the app one import for ink and guarantee that the platform accessor is always
//          usable, so a build without a pen surface renders the editor without ink rather than
//          throwing from a getter the UI cannot reasonably guard.
// INPUTS: None.
// OUTPUTS: The ink contract types re-exported from the platform interface, plus the fallback
//          implementation and the function that installs it.
// KEYWORDS: ink-native, app-facing, fallback-registration, desktop, web, graceful-degradation
library;

import 'package:ink_native_platform_interface/ink_native_platform_interface.dart';

import 'src/unsupported_ink_platform.dart';

export 'package:ink_native_platform_interface/ink_native_platform_interface.dart';

export 'src/unsupported_ink_platform.dart';

// PURPOSE: Ensure `InkNativePlatform.instance` resolves on a platform with no native ink
//          surface, so the editor can query ink support without first catching an exception.
// INPUTS: None.
// OUTPUTS: Nothing. Registers [UnsupportedInkPlatform] if, and only if, nothing is registered
//          yet, so a real platform implementation is never overwritten. Safe to call more than
//          once. Call it before the first ink call, after `WidgetsFlutterBinding.ensureInitialized`.
//
//          On the web this is the only registration that happens: the generated web plugin
//          registrant is empty because no web implementation of the contract exists yet, so
//          `supportsInk` answers false afterwards. That is the intended, honest answer — the
//          browser ink surface is a separate spike (owner decision D20), not this fallback
//          pretending to be one.
// KEYWORDS: registration, fallback, idempotent, bootstrap, web
/// Installs the no-op ink implementation when no platform implementation claimed the slot.
void registerInkFallback() {
  if (!InkNativePlatform.isRegistered) {
    InkNativePlatform.instance = UnsupportedInkPlatform();
  }
}
