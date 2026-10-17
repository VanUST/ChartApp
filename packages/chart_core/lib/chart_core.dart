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
// autosave and a future sync all replay, the two containers that serialise a document — `.chart`
// for a chart and `.setlist` for a programme, each its snapshot plus its operation tail, both over
// the one envelope in `src/container/container_frame.dart` — and the identity a programme names a
// chart by, derived from the chart's own music in `src/identity/chart_identity.dart`. Also the two
// editing values that join
// those: the chord palette a cell offers, and the session that applies an edit through the log.
// The ink domain joins them at the same level: the canonical stroke form is already in the
// catalogue above, and `src/ink/` adds the pure decisions a live capture needs — whether a
// contact may draw (`InkPalmRule`), where a stroke's anchor landed on a page
// (`resolveEventAnchor`), which anchor a stroke that begins anywhere on the page is stored against
// (`resolveInkAnchor`: the cell under it, the bar, or the nearest bar when it began in a margin,
// between two systems or on the staff) and which stroke a touch is on when the eraser asks
// (`hitTestInkErase`) — plus the assembler that turns live samples into a canonical stroke, so all
// of them are checkable with `dart test` and none of them needs a device.
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
// Still absent by design: nothing that reaches a device. The two containers store bytes and return
// bytes; resolving a path, opening a file and invoking a browser's file chooser are the app's job,
// through its own conditional-export seam.
//
// The `.setlist` container is no longer absent. A programme is stored as a snapshot plus a
// `setlist.*` operation tail in the SAME envelope `.chart` uses — `container_frame.dart` — and what
// an entry names is decided by `src/identity/chart_identity.dart`: a chart's own music, not the
// position it sat at in an import and not its title.

/// ChartApp's pure-Dart chart domain.
library;

export 'src/anchored_place.dart';
export 'src/chord.dart';
export 'src/container/chart_file.dart';
export 'src/container/setlist_file.dart';
export 'src/editing/bar_range.dart';
export 'src/editing/chord_palette.dart';
export 'src/editing/chord_symbol_parser.dart';
export 'src/editing/ink_stroke_builder.dart';
export 'src/editing/meter_input.dart';
export 'src/editing/selection.dart';
export 'src/identity/chart_identity.dart';
export 'src/ink/barline_detector.dart';
export 'src/ink/ink_hit.dart';
export 'src/ink/melody_note_reader.dart';
export 'src/ink/melody_note_writer.dart';
export 'src/ink/page_anchor.dart';
export 'src/ink/palm_rule.dart';
export 'src/ireal/chord_parser.dart';
export 'src/ireal/obfuscation.dart';
export 'src/ireal/parser.dart';
export 'src/ireal/payload.dart';
export 'src/ireal/tokenizer.dart';
export 'src/key.dart';
export 'src/key_vocabulary.dart';
export 'src/layout/chart_header.dart';
export 'src/layout/geometry.dart';
export 'src/layout/hit_test.dart';
export 'src/layout/layout_engine.dart';
export 'src/layout/layout_style.dart';
export 'src/layout/melody_staff.dart';
export 'src/layout/meter_sign.dart';
export 'src/layout/page_layout.dart';
export 'src/layout/staff_text_display.dart';
export 'src/layout/text_metrics.dart';
export 'src/oplog/oplog.dart';
export 'src/pitch.dart';
export 'src/setlist_scene.dart';
export 'src/song/bar.dart';
export 'src/song/new_chart.dart';
export 'src/song/note.dart';
export 'src/song/note_value.dart';
export 'src/song/play_order.dart';
// SHIM, AND THE ONLY SHIMMED EXPORT IN THIS FILE: `src/song/pseudo_grid.dart` lets a caller that
// still speaks in beats recover a beat and a step from a mark's place. It is temporary by
// construction, it is documented as temporary where it is declared, and the stage that teaches the
// layout to read the offset deletes both this line and that file. Nothing else in this package may
// grow a dependency on it.
export 'src/song/pseudo_grid.dart';
export 'src/song/section.dart';
export 'src/song/song.dart';
export 'src/song/staff.dart';
export 'src/song/time_signature.dart';
export 'src/spelling_table.dart';
export 'src/transposer.dart';
export 'src/transposition.dart';
