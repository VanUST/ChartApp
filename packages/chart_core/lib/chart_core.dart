// PURPOSE: Mark the boundary of the ChartApp chart domain and publish its public surface, so
//          that a change to the model is visible in one place and the package's promise — no
//          Flutter, no database, no platform channel — stays checkable.
// INPUTS: None.
// OUTPUTS: The pitch, key, spelling-table, chord, transposition and song-model types.
// KEYWORDS: chart-core, public-api, barrel, domain-boundary, pure-dart
//
// What lives here: written pitch and pitch classes, keys and their signatures, the rule that
// resolves enharmonic spelling, the chord model, transposition, the song structure that addresses
// a bar, the iReal import path from an `irealb://` payload through de-obfuscation and notation to
// a Song, the layout engine and the page hit test, the document event catalogue that undo,
// autosave and a future sync all replay, the `.chart` container that serialises one document —
// its snapshot and its operation tail — to bytes and back, and the two editing values that join
// those: the chord palette a cell offers, and the session that applies an edit through the log.
// The ink domain joins them at the same level: the canonical stroke form is already in the
// catalogue above, and `src/ink/` adds the pure decisions a live capture needs — whether a
// contact may draw (`InkPalmRule`), where a stroke's anchor landed on a page
// (`resolveEventAnchor`) and which stroke a touch is on when the eraser asks (`hitTestInkErase`)
// — plus the assembler that turns live samples into a canonical stroke, so all of them are
// checkable with `dart test` and none of them needs a device.
//
// The song model stores the WRITTEN form only. The order a tune is played in — repeats,
// alternative endings, navigation — is a pure function over this model, so there is no second
// copy of the music to disagree with the first. `derivePlayOrder` is that function for repeats,
// alternative endings and repeat-previous bars; it does not interpret navigation words, which
// stay verbatim staff text, and it reports what it decided rather than leaving a reader to guess.
//
// What must never live here: flutter, storage_drift, ink_native or any platform channel. The
// package's value rests on `dart test` running every one of its tests on a machine with no
// device, no emulator and no Android SDK, and the dependency list in pubspec.yaml is empty to
// keep that true. Every file in this library is pure: no I/O, no clock, no globals. The container
// follows that rule by taking bytes and returning bytes: resolving a path, opening a file and
// invoking a browser's file chooser are the app's job, through its own conditional-export seam.
//
// Still absent by design: the `.setlist` container. A setlist is a different kind of document — it
// names songs rather than containing one — and the codec here deliberately refuses a setlist
// operation inside a chart file rather than growing a second document type it does not model yet.

/// ChartApp's pure-Dart chart domain.
library;

export 'src/chord.dart';
export 'src/container/chart_file.dart';
export 'src/editing/chord_palette.dart';
export 'src/editing/ink_stroke_builder.dart';
export 'src/ink/ink_hit.dart';
export 'src/ink/page_anchor.dart';
export 'src/ink/palm_rule.dart';
export 'src/ireal/chord_parser.dart';
export 'src/ireal/obfuscation.dart';
export 'src/ireal/parser.dart';
export 'src/ireal/payload.dart';
export 'src/ireal/tokenizer.dart';
export 'src/key.dart';
export 'src/layout/geometry.dart';
export 'src/layout/hit_test.dart';
export 'src/layout/layout_engine.dart';
export 'src/layout/layout_style.dart';
export 'src/layout/page_layout.dart';
export 'src/layout/staff_text_display.dart';
export 'src/layout/text_metrics.dart';
export 'src/oplog/oplog.dart';
export 'src/pitch.dart';
export 'src/song/bar.dart';
export 'src/song/note.dart';
export 'src/song/note_value.dart';
export 'src/song/play_order.dart';
export 'src/song/section.dart';
export 'src/song/song.dart';
export 'src/song/staff.dart';
export 'src/song/time_signature.dart';
export 'src/spelling_table.dart';
export 'src/transposer.dart';
export 'src/transposition.dart';
