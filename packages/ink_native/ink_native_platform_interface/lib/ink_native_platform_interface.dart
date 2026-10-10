// PURPOSE: Publish the ink platform contract from one import, so implementations and the app
//          agree on a single entry point rather than reaching into src/.
// INPUTS: None.
// OUTPUTS: The ink value types, the palm-width rule they are judged by, and the
//          InkNativePlatform abstract class.
// KEYWORDS: barrel, public-api, ink-native, platform-interface
library;

export 'src/ink_native_platform.dart';
export 'src/ink_types.dart';
export 'src/palm_rule.dart';
