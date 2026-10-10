// PURPOSE: Mark the boundary of the ChartApp chart domain and publish its public surface, so
//          that a change to the chord model is visible in one place and the package's promise —
//          no Flutter, no database, no platform channel — stays checkable.
// INPUTS: None.
// OUTPUTS: The pitch, key, spelling-table, chord and transposer types.
// KEYWORDS: chart-core, public-api, barrel, domain-boundary, pure-dart
//
// What lives here: written pitch and pitch classes, keys and their signatures, the rule that
// resolves enharmonic spelling, the chord model, and transposition.
//
// What must never live here: flutter, storage_drift, ink_native or any platform channel. The
// package's value rests on `dart test` running every one of its tests on a machine with no
// device, no emulator and no Android SDK, and the dependency list in pubspec.yaml is empty to
// keep that true. Every file in this library is pure: no I/O, no clock, no globals.
//
// Still absent by design, and deliberately not stubbed: the song model, the layout engine, the
// file codecs and the op-log. Those are informed by spikes S1 (iReal codec) and S4 (layout); a
// song model invented before them would fix their shape on a guess.

/// ChartApp's pure-Dart chart domain.
library;

export 'src/chord.dart';
export 'src/key.dart';
export 'src/pitch.dart';
export 'src/spelling_table.dart';
export 'src/transposer.dart';
