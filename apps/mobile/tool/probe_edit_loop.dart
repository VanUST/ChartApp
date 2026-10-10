// PURPOSE: Prove the edit loop at the point where its three independent parts meet, without a
//          window and without a device: the chord palette's contents, the operation the palette's
//          choice produces, the reducer that folds it, the inverse that takes it back, and the
//          `.chart` container that writes the result and reads it back. Every check here crosses a
//          seam the app also crosses — `EditSession` is the class the viewer holds and
//          `chartFileFor` is the function the Save button calls — so a green run is about the loop
//          and not about a reimplementation of it.
// INPUTS: None. The chart is synthetic, so nothing is read from the owner's machine and nothing is
//         downloaded.
// OUTPUTS: One line per check on stdout, the document the loop produced, and a summary line with
//          the check and failure counts as the exit code. The comparisons that matter are stated in
//          full: DOC_EQUAL before/after undo, ROUND_TRIP_DOCUMENT_EQUAL, and the operation types
//          the log holds at each step. This file imports no Flutter, which is why plain `dart run`
//          executes it.
//
//          THE ROUND TRIP IS PROVED WITH A TAIL THAT IS NOT IDEMPOTENT, BY REOPENING. The saved
//          session carries a bar taken out, a bar put in, a style and a tempo, and a stroke; a
//          `chord.update` would be harmless applied twice, which is how this probe was green while
//          a real edited chart could not be reopened. The snapshot written is the session's base
//          document, and the check that counts is REOPENED_DOCUMENT_EQUAL — a session opened from
//          the file holds the chart that was saved.
// KEYWORDS: probe, edit-loop, chord-palette, op-log, undo, redo, exact-restore, chart-file,
//           round-trip, reopen, non-idempotent, evidence, dart-io
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_document.dart';
import 'package:chartapp/chart_source.dart';

int _failures = 0;
int _checks = 0;

/// The section the probe edits, and the bar and cell inside it.
///
/// Bar 1 of the chart — index 0 of the first section — because that is the bar the render instrument
/// edits, and the two readings are meant to describe the same edit: the probe says what the document
/// holds, the instrument says what the page drew.
const String _section = 'A';
const int _bar = 0;
const int _beat = 2;

Future<void> main() async {
  final EditSession session = EditSession(
    document: DocumentState(song: probeChart()),
  );
  stdout.writeln(
    'edit.doc docId=${session.docId} bars=${session.song.writtenBarCount} '
    'key=${session.song.key}',
  );

  // --- 1. THE PALETTE ------------------------------------------------------------------------
  final List<ChordRootChoice> roots = chordRootChoicesFor(session.song.key);
  _same('palette.root_count=12', 12, roots.length);
  _same(
    'palette.pitch_classes_are_distinct',
    true,
    roots.map((ChordRootChoice r) => r.pitchClass).toSet().length ==
        roots.length,
  );
  stdout.writeln(
    'palette.roots ${roots.map((ChordRootChoice r) => '${r.written}(${r.degreeLabel})').join(' ')}',
  );
  _same(
    'palette.degrees_are_1_to_7_then_b2_b3_b5_b6_b7',
    '1 2 3 4 5 6 7 b2 b3 b5 b6 b7',
    roots.map((ChordRootChoice r) => r.degreeLabel).join(' '),
  );
  // A major triad is written with an EMPTY suffix, which is how a chart writes `C` and not `Cmaj`,
  // so the token list starts with an empty string. It is printed as `maj` here only so that the
  // line is readable; the tokens themselves are compared, not the label.
  _same(
    'palette.qualities',
    'maj/m/7/m7/maj7/m7b5/dim',
    chordPaletteQualities
        .map((ChordQuality q) => q.token.isEmpty ? 'maj' : q.token)
        .join('/'),
  );
  // The tonic chord of a key with a signature, so the palette's spelling is checked where the key
  // signature and not the chromatic rule is doing the work. The chromatic degrees are spelled flat
  // by the palette, so in E major one of them collides in SOUNDING pitch with a degree the key
  // already names and lands on that letter: b5 of E is the pitch class of Bb, written Bb, and b2 is
  // the pitch class of F, written F. That collision is the reason this probe prints the letters
  // rather than only counting them.
  final Key eMajor = Transposer().transposeKey(Key.cMajor, 4);
  final List<ChordRootChoice> eRoots = chordRootChoicesFor(eMajor);
  stdout.writeln(
    'palette.key=$eMajor '
    '${eRoots.map((ChordRootChoice r) => '${r.written}(${r.degreeLabel})').join(' ')}',
  );
  _same(
    'palette.sharp_key_uses_the_keys_own_letters_then_flats',
    'E F# G# A B C# D# F G Bb C D',
    eRoots.map((ChordRootChoice r) => '${r.written}').join(' '),
  );

  // --- 2. MUTATION GOES THROUGH THE LOG ------------------------------------------------------
  final DocumentState beforeEdit = session.document;
  final BeatChord? held = session.existingChordAt(
    sectionId: _section,
    barIndex: _bar,
    beat: _beat,
  );
  _same(
    'cell_holds_a_chord_before_the_edit',
    'Dm7',
    _render(held?.chord, beforeEdit.song.key),
  );
  final ChordRootChoice flatThree = roots.firstWhere(
    (ChordRootChoice r) => r.pitchClass == 3,
  );
  final bool applied = session.applyChordToCell(
    sectionId: _section,
    barIndex: _bar,
    beat: _beat,
    chord: chordOf(flatThree, ChordQuality.majorSeventh),
    size: held?.size ?? ChordSize.normal,
  );
  _same('apply.reported_applied', true, applied);
  _same(
    'apply.log_types',
    'chord.update',
    session.log.map((ChartEvent e) => e.type).join(','),
  );
  _same('apply.seq', 1, session.seq);
  final BeatChord? changed = session.existingChordAt(
    sectionId: _section,
    barIndex: _bar,
    beat: _beat,
  );
  _same(
    'cell_holds_the_chosen_chord_after_the_edit',
    'Ebmaj7',
    _render(changed?.chord, session.song.key),
  );
  // The cell's own chord is replaced, so the chords beside it keep their names AND their addresses:
  // a chord that moved to another cell would be a different edit entirely.
  _same(
    'the_neighbouring_cell_is_untouched',
    'Cmaj7',
    _render(
      session
          .existingChordAt(sectionId: _section, barIndex: _bar, beat: 0)
          ?.chord,
      session.song.key,
    ),
  );
  _same(
    'the_bars_chords_are_in_cell_order',
    'Cmaj7@0.0,Ebmaj7@2.0',
    _addresses(session),
  );
  final DocumentState afterEdit = session.document;

  // --- 3. UNDO RESTORES EXACTLY --------------------------------------------------------------
  _same('undo.available', true, session.canUndo);
  final bool undone = session.undo();
  _same('undo.reported', true, undone);
  final DocumentState afterUndo = session.document;
  stdout.writeln('undo.before=$beforeEdit');
  stdout.writeln('undo.after =$afterUndo');
  stdout.writeln(
    'undo.compare song_equal=${beforeEdit.song == afterUndo.song} '
    'strokes=${beforeEdit.strokes.length}==${afterUndo.strokes.length} '
    'annotations=${beforeEdit.annotations.length}==${afterUndo.annotations.length} '
    'cues=${beforeEdit.textCues.length}==${afterUndo.textCues.length}',
  );
  _same('DOC_EQUAL before_edit_and_after_undo', true, beforeEdit == afterUndo);
  _same(
    'UNDO_EXACT the_edited_cell_is_the_original_chord_again',
    'Cmaj7@0.0,Dm7@2.0',
    _addresses(session),
  );
  _same(
    'undo_log_types',
    'chord.update,chord.update',
    session.log.map((ChartEvent e) => e.type).join(','),
  );
  _same('undo.seq', 2, session.seq);
  _same('undo.redo_available', true, session.canRedo);

  // --- 4. REDO IS THE INVERSE OF THE INVERSE --------------------------------------------------
  final bool redone = session.redo();
  _same('redo.reported', true, redone);
  _same(
    'REDO the_edited_cell_is_the_chosen_chord_again',
    'Cmaj7@0.0,Ebmaj7@2.0',
    _addresses(session),
  );
  // The redo must land on the same document the edit produced — not merely on a document whose one
  // edited cell agrees — which is what makes "undo then redo" a round trip of the document.
  _same(
    'REDO_DOC_EQUAL after_edit_and_after_redo',
    true,
    afterEdit == session.document,
  );
  _same(
    'redo_log_types',
    'chord.update,chord.update,chord.update',
    session.log.map((ChartEvent e) => e.type).join(','),
  );
  _same('redo.seq', 3, session.seq);

  // --- 5. A CELL WITH NO CHORD: INSERT, DELETE, AND THE GAP RULE ------------------------------
  final EditSession empty = EditSession(
    document: DocumentState(song: probeChart()),
  );
  _same(
    'empty_cell_has_no_chord',
    true,
    empty.existingChordAt(sectionId: _section, barIndex: _bar, beat: 1) == null,
  );
  final bool inserted = empty.applyChordToCell(
    sectionId: _section,
    barIndex: _bar,
    beat: 1,
    chord: chordOf(
      roots.firstWhere((ChordRootChoice r) => r.pitchClass == 7),
      ChordQuality.dominantSeventh,
    ),
  );
  _same('insert.reported_applied', true, inserted);
  _same(
    'insert.log_types',
    'chord.insert',
    empty.log.map((ChartEvent e) => e.type).join(','),
  );
  _same(
    'insert.order_is_by_cell',
    'Cmaj7@0.0,G7@1.0,Dm7@2.0',
    _addresses(empty),
  );
  empty.undo();
  _same(
    'delete_by_undo_closes_the_gap',
    'Cmaj7@0.0,Dm7@2.0',
    _addresses(empty),
  );
  _same(
    'delete.DOC_EQUAL',
    true,
    empty.document == DocumentState(song: probeChart()),
  );

  // --- 6. NON-IDEMPOTENT EDITS, BECAUSE AN IDEMPOTENT TAIL HIDES THE DEFECT --------------------
  //
  // Everything above changed a chord, and a `chord.update` applied twice replaces the chord at its
  // address with the same value the second time — so a reader that ran the tail a second time would
  // still produce the right chart, and this probe was green on a property it never tested. The
  // operations below are the ones where a second application is a DIFFERENT document: a bar taken
  // out, a bar put in, a style and a tempo, and a stroke — whose second application is refused
  // outright, because the document already holds a stroke with that id.
  final int barsBeforeEdits = session.song.writtenBarCount;
  final int barsInSection = session.song.sectionById(_section)!.bars.length;
  _same(
    'edit.delete_bar_applied',
    true,
    session.deleteBar(sectionId: _section, barIndex: 0),
  );
  _same(
    'edit.insert_bar_applied',
    true,
    session.insertBarAfter(sectionId: _section, barIndex: 0),
  );
  _same(
    'edit.song_update_applied',
    true,
    session.updateSong(style: 'Ballad', tempo: 90),
  );
  session.apply(
    InkStrokeAddEvent(
      docId: session.docId,
      seq: session.seq,
      index: 0,
      stroke: InkStroke(
        id: 'ink-edit-probe',
        tool: StrokeTool.pen,
        color: '#102a43',
        size: 3,
        anchor: EventAnchor(sectionId: _section, bar: 0, beat: 0),
        points: const <InkPoint>[
          InkPoint(x: 1.5, y: 2.5, w: 0.4, t: 0),
          InkPoint(x: 8.0, y: 4.0, w: 0.8, t: 11),
        ],
      ),
    ),
  );
  final DocumentState savedDocument = session.document;
  stdout.writeln(
    'edit.base_bars=${session.baseDocument.song.writtenBarCount} '
    'bars_before=$barsBeforeEdits bars_section_before=$barsInSection '
    'bars_after=${savedDocument.song.writtenBarCount} '
    'section_bars_after=${savedDocument.song.sectionById(_section)!.bars.length} '
    'strokes=${savedDocument.strokes.length} '
    'style=${savedDocument.song.style} tempo=${savedDocument.song.tempo} '
    'operations=${session.log.length} '
    'types=${session.log.map((ChartEvent event) => event.type).toList()}',
  );

  // --- 6b. THE SNAPSHOT IS THE BASE, AND REOPENING IS THE PROOF --------------------------------
  //
  // The snapshot written is the session's BASE document — the state before its log — because the
  // container's document is the snapshot PLUS the operations. Writing the CURRENT document here,
  // with the log beside it, is what let this probe pass while a chart with an inserted bar and a
  // stroke could not be reopened at all.
  final ChartFile file = chartFileFor(
    session.baseDocument,
    events: session.log,
    modifiedAt: DateTime.utc(2026, 10, 10, 19, 30),
  );
  final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
  final Directory directory = Directory.systemTemp.createTempSync(
    'chartapp-edit-probe-',
  );
  final String path = '${directory.path}${Platform.pathSeparator}edit.chart';
  await saveChartFile(path, encoded.bytes);
  final Uint8List read = await loadChartFile(path);
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(read);
  stdout.writeln(
    'roundtrip.bytes=${encoded.bytes.length} '
    'operations_saved=${file.events.length} '
    'operations_read=${decoded.file.events.length} '
    'warnings=${decoded.warnings.length} '
    'docId_saved=${file.metadata.docId} docId_read=${decoded.file.metadata.docId}',
  );
  _same('roundtrip.file_equals_the_file_that_was_saved', file, decoded.file);
  _same('no_warnings', 0, decoded.warnings.length);
  _same(
    'roundtrip.snapshot_is_the_base_document',
    session.baseDocument,
    decoded.file.snapshot,
  );
  _same(
    'roundtrip.tail_is_the_operations',
    true,
    _sameEvents(decoded.file.events, session.log),
  );
  _same(
    'ROUND_TRIP_DOCUMENT_EQUAL',
    true,
    savedDocument == decoded.file.reducedDocument,
  );
  _same(
    'ROUND_TRIP_SONG_EQUAL',
    true,
    savedDocument.song == decoded.file.reducedDocument.song,
  );
  _same(
    'ROUND_TRIP_operation_types',
    session.log.map((ChartEvent event) => event.type).join(','),
    decoded.file.events.map((ChartEvent event) => event.type).join(','),
  );
  _same(
    'ROUND_TRIP_bar_addresses',
    _addresses(session),
    _addressesOf(decoded.file.reducedDocument),
  );

  // A SESSION OPENED THE WAY THE VIEWER OPENS ONE must hold the chart that was saved: same bars,
  // same strokes, same style and tempo. This is the proof; the comparisons above are bookkeeping.
  final EditSession reopenedSession = EditSession(
    document: decoded.file.snapshot,
    docId: decoded.file.metadata.docId,
    seq: decoded.file.events.last.seq,
    restored: decoded.file.events,
  );
  _same(
    'REOPENED_DOCUMENT_EQUAL',
    true,
    reopenedSession.document == savedDocument,
  );
  _same(
    'REOPENED_bar_count',
    savedDocument.song.writtenBarCount,
    reopenedSession.song.writtenBarCount,
  );
  _same(
    'REOPENED_stroke_count',
    savedDocument.strokes.length,
    reopenedSession.document.strokes.length,
  );
  _same(
    'REOPENED_style_and_tempo',
    '${savedDocument.song.style}/${savedDocument.song.tempo}',
    '${reopenedSession.song.style}/${reopenedSession.song.tempo}',
  );
  stdout.writeln(
    'reopened bars=${reopenedSession.song.writtenBarCount} '
    'strokes=${reopenedSession.document.strokes.length} '
    'style=${reopenedSession.song.style} tempo=${reopenedSession.song.tempo} '
    'seq=${reopenedSession.seq}',
  );

  // --- 7. A SESSION CONTINUES THE LOG IT READ -------------------------------------------------
  _same(
    'resume.log_is_the_file_tail',
    true,
    _sameEvents(reopenedSession.log, session.log),
  );
  final bool resumed = reopenedSession.applyChordToCell(
    sectionId: _section,
    barIndex: _bar,
    beat: _beat,
    chord: chordOf(flatThree, ChordQuality.minorSeventh),
  );
  _same('resume.applied', true, resumed);
  _same(
    'resume.seq_continues',
    decoded.file.events.last.seq + 1,
    reopenedSession.seq,
  );
  _same(
    'resume.log_tail_is_appended',
    session.log.length + 1,
    reopenedSession.log.length,
  );
  final ChartFileEncodeResult resumedEncoded = ChartFileCodec.encode(
    chartFileFor(reopenedSession.baseDocument, events: reopenedSession.log),
  );
  final ChartFile resumedDecoded = ChartFileCodec.decode(resumedEncoded.bytes)
      .file;
  _same(
    'resume.a_file_written_after_reopening_is_read_again',
    true,
    reopenedSession.document == resumedDecoded.reducedDocument,
  );

  directory.deleteSync(recursive: true);
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

/// The synthetic chart this probe edits: two sections, each bar carrying a chord on its first cell
/// and, on the bar's third cell, a follow-on chord that the edit replaces.
Song probeChart() => Song(
  id: 'chartapp-edit-probe',
  title: 'Edit probe',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    for (final String id in <String>[_section, 'B'])
      Section(
        id: id,
        label: SectionLabel.letter(id),
        bars: <Bar>[
          for (int index = 0; index < 2; index++)
            Bar(
              chords: <BeatChord>[
                BeatChord(
                  chord: Chord(
                    root: ChordRoot(index),
                    quality: ChordQuality.majorSeventh,
                  ),
                  beat: 0,
                ),
                BeatChord(
                  chord: Chord(
                    root: ChordRoot(index + 2),
                    quality: ChordQuality.minorSeventh,
                  ),
                  beat: 2,
                ),
              ],
            ),
        ],
      ),
  ],
);

/// Renders [chord] in [key], or `none` when there is no chord.
String _render(Chord? chord, Key key) =>
    chord == null ? 'none' : chord.render(key, const SpellingTable());

/// The edited bar's chords as `name@beat`, in model order, so an address change is visible.
String _addresses(EditSession session) =>
    _addressesOf(session.document, sectionId: _section, barIndex: _bar);

/// The chords of one bar of [document], as `name@beat`, or of the probe's edited bar by default.
String _addressesOf(
  DocumentState document, {
  String sectionId = _section,
  int barIndex = _bar,
}) {
  final Bar? bar = document.song.barAt(sectionId, barIndex);
  if (bar == null) {
    return 'no-bar';
  }
  return bar.chords
      .map(
        (BeatChord placed) =>
            '${placed.chord.render(document.song.key, const SpellingTable())}'
            '@${placed.beat}.${placed.step}',
      )
      .join(',');
}

/// Records one expectation, printing both sides when it fails.
void _same(String what, Object? expected, Object? actual) {
  _checks++;
  if (expected == actual) {
    stdout.writeln('[ok] $what');
    return;
  }
  _failures++;
  stdout.writeln('[FAIL] $what');
  stdout.writeln('    expected: $expected');
  stdout.writeln('    actual:   $actual');
}

/// Whether two operation tails hold equal events in the same order.
///
/// A `List`'s own `==` is identity, so a tail compared with it would report a difference that is not
/// there — the same class of mistake as trusting an idempotent tail to prove a round trip.
bool _sameEvents(List<ChartEvent> left, List<ChartEvent> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
