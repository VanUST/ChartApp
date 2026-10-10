// PURPOSE: Mark the boundary of the ChartApp chart domain and publish its public surface, so
//          that a change to the model is visible in one place and the package's promise — no
//          Flutter, no database, no platform channel — stays checkable.
// INPUTS: None.
// OUTPUTS: The pitch, key, spelling-table, chord, transposition and song-model types.
// KEYWORDS: chart-core, public-api, barrel, domain-boundary, pure-dart
//
// What lives here: written pitch and pitch classes, keys and their signatures, the rule that
// resolves enharmonic spelling, the chord model, transposition, and the song structure that
// addresses a bar.
//
// The song model stores the WRITTEN form only. The order a tune is played in — repeats,
// alternative endings, navigation — is a pure function over this model, so there is no second
// copy of the music to disagree with the first.
//
// What must never live here: flutter, storage_drift, ink_native or any platform channel. The
// package's value rests on `dart test` running every one of its tests on a machine with no
// device, no emulator and no Android SDK, and the dependency list in pubspec.yaml is empty to
// keep that true. Every file in this library is pure: no I/O, no clock, no globals.
//
// Still absent by design, and deliberately not stubbed: the layout engine, the file codecs and
// the op-log. The layout engine's shape is measured by spike S4, and the codecs' by S1; writing
// either before those measurements would fix its design on a guess.

/// ChartApp's pure-Dart chart domain.
library;

export 'src/chord.dart';
export 'src/key.dart';
export 'src/layout/geometry.dart';
export 'src/layout/layout_engine.dart';
export 'src/layout/layout_style.dart';
export 'src/layout/page_layout.dart';
export 'src/layout/text_metrics.dart';
export 'src/pitch.dart';
export 'src/song/bar.dart';
export 'src/song/section.dart';
export 'src/song/song.dart';
export 'src/song/time_signature.dart';
export 'src/spelling_table.dart';
export 'src/transposer.dart';
