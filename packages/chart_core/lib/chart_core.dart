// PURPOSE: Mark the boundary of the ChartApp chart domain and publish its public surface, so
//          that a change to the model is visible in one place and the package's promise — no
//          Flutter, no database, no platform channel — stays checkable.
// INPUTS: None.
// OUTPUTS: The pitch, key, spelling-table and chord types, the smallest song model that can hold a
//          bar, the iReal import path, the layout engine and the page hit test, the document event
//          catalogue that undo, autosave and the ink layer all replay, and the two containers that
//          serialise a document.
// KEYWORDS: chart-core, public-api, barrel, domain-boundary, pure-dart
//
// WHAT THIS LIBRARY IS FOR NOW. The application does three things: it loads an iReal chart, it lets
// a musician write on the page with a pen and erase what he wrote, and it saves the result. Every
// type here exists to serve one of those three, and the surface is deliberately the smallest set
// that can:
//
//   * LOAD AN iReal CHART. `src/ireal/` reads an `irealb://` payload through de-obfuscation, the
//     tokenizer and the parser into a Song. The parser still produces CHORDS, and the chord model
//     (`src/chord.dart`, `src/pitch.dart`, `src/key.dart`, `src/spelling_table.dart`) is kept whole
//     because of it: an import that dropped what the file says would not be an import. A chord is
//     READ and DRAWN and nothing else — the symbols are placed by the layout engine and put on the
//     page by the renderer, and no code path in the application can add, change or delete one.
//   * DRAW ITS BARS. `src/layout/` turns a Song into positioned pages of bar rectangles with the
//     chord symbols in their chord rows, and `src/layout/hit_test.dart` answers which bar a touch
//     names. A bar's WIDTH follows the chords its file gave it, because that is the page the
//     musician recognises, and the symbols are placed at the coordinates those chords already
//     carry.
//   * HOLD HANDWRITING ON THOSE BARS. `src/ink/` holds the pure decisions a live capture needs —
//     whether a contact may draw (`InkPalmRule`), which anchor a stroke that begins anywhere on the
//     page is stored against (`resolveInkAnchor`: the bar under it, or the nearest bar when it began
//     in a margin), and which stroke a touch is on when the eraser asks (`hitTestInkErase`) — plus
//     the assembler that turns live samples into a canonical stroke (`src/editing/`). All of them
//     are checkable with `dart test` and none of them needs a device.
//   * SAVE. `src/container/` stores a document as a snapshot plus an operation tail, in one
//     envelope (`src/container/container_frame.dart`); `.chart` is the chart and `.setlist` the
//     programme. The containers take bytes and return bytes: resolving a path, opening a file and
//     invoking a browser's file chooser are the app's job.
//
// THE OP-LOG IS THE ONLY WRITER. Every value the application stores is reached by appending an
// event to the log in `src/oplog/`, undo is an append of the inverses, and an inverse carries the
// WHOLE previous value rather than a delta — so replaying a document's tail reproduces it exactly.
// The catalogue is a sealed hierarchy, which is why the files that hold it are one library split
// into parts: the compiler then demands a case in the reducer and a case in the codec for every
// event, rather than letting a new event family be applied by nobody.
//
// WHAT IS DELIBERATELY ABSENT, because the owner cut the application back to its basics and asked
// for the musical editing to be deleted rather than hidden. There is no note model, no melodic or
// percussion staff, no play-order expansion, no selection or clipboard, no transposition, no
// chord-symbol ENTRY, no meter or bar insertion, and no barline recognition. Those files are gone
// from the tree, and the tests that covered them are gone with them. The history holds them, which is
// where the owner wants them until the rest is rewritten. A chord is still DRAWN, because a reader
// that cannot show the chords it loaded is not a reader; what is absent is every way to enter,
// change or delete one.
//
// AND WHAT CAME BACK, NAMED SO THAT IT IS NOT MISTAKEN FOR THE OLD TREE. The chart HEADER is back
// (`src/layout/chart_header.dart`): the owner asked for the key and the meter to be on the page
// again, because a chart that does not state what key it is in is a chart he has to look away from.
// It is a LINE OF TEXT drawn above the first system, and it decides nothing — the meter it prints is
// a label, not a divider, and no width, position or pagination in the engine is computed from it.
//
// WHAT MUST NEVER LIVE HERE: flutter, storage_drift, ink_native or any platform channel. The
// package's value rests on `dart test` running every one of its tests on a machine with no device,
// no emulator and no Android SDK, and the dependency list in pubspec.yaml is empty to keep that
// true. Every file in this library is pure: no I/O, no clock, no globals.

/// ChartApp's pure-Dart chart domain.
library;

export 'src/anchored_place.dart';
export 'src/chord.dart';
export 'src/container/chart_file.dart';
export 'src/container/setlist_file.dart';
export 'src/editing/ink_stroke_builder.dart';
export 'src/identity/chart_identity.dart';
export 'src/ink/ink_hit.dart';
export 'src/ink/page_anchor.dart';
export 'src/ink/palm_rule.dart';
export 'src/ireal/chord_parser.dart';
export 'src/ireal/obfuscation.dart';
export 'src/ireal/parser.dart';
export 'src/ireal/payload.dart';
export 'src/ireal/tokenizer.dart';
export 'src/key.dart';
export 'src/layout/chart_header.dart';
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
export 'src/song/section.dart';
export 'src/song/song.dart';
export 'src/song/time_signature.dart';
export 'src/spelling_table.dart';
