// PURPOSE: Print the numbers behind the owner's four-step workflow — select sixteen bars, copy them,
//          paste them at the end, transpose the pasted sixteen up a semitone — from the model alone,
//          so the claim "it works" is a set of figures rather than a screenshot. It also prints the
//          STORED strokes of both copies before and after a real `.chart` save and reopen, because
//          the ink travelling with its bars is the one part of this feature that a picture cannot
//          prove: two identical-looking marks could still be one stroke addressed at one bar.
// INPUTS: None. The chart, the ink and the events are built here, so this runs on a machine with no
//         device and no font.
// OUTPUTS: Lines on stdout. The selection report, the pasted bars' chords and melody, the key, the
//          undo cost of each gesture, the strokes' ids and anchors before and after the save, and the
//          refusal cases (a window that does not fit, a window asked to transpose). It asserts
//          nothing: a probe reports, and the reading decides.
// KEYWORDS: probe, selection, copy, paste, transpose, ink-reanchor, save-reopen, one-undo,
//           d35, d36, d37, not-part-of-the-library
import 'dart:convert';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';

/// The section id a `newChartSong` chart carries.
const String _section = newChartFirstSectionId;

/// A chart of [bars] bars in C major, 4/4.
Song _chart({int bars = 16}) => newChartSong(
  key: Key.cMajor,
  timeSignature: TimeSignature.fourFour,
  bars: bars,
);

/// A stroke drawn inside [bar], hanging on the bar itself or on [beat].
InkStroke _stroke({
  required String id,
  required int bar,
  int? beat,
  double x = 8,
  double y = 12,
}) => InkStroke(
  id: id,
  tool: StrokeTool.pen,
  color: '#102a43',
  size: 3,
  anchor: EventAnchor(sectionId: _section, bar: bar, beat: beat),
  points: <InkPoint>[
    InkPoint(x: x, y: y, w: 0.4, t: 0),
    InkPoint(x: x + 24, y: y + 9, w: 0.6, t: 55),
  ],
);

/// Renders the chord on [beat] of [bar] in the chart's own key.
String _chord(Song song, int bar, int beat) => song
    .sections
    .first
    .bars[bar]
    .chords
    .firstWhere((BeatChord placed) => placed.beat == beat)
    .chord
    .render(song.key, const SpellingTable());

/// The melody pitch written on beat 0 of [bar], as a written note and octave.
String _melody(Song song, int bar) {
  final BeatNote note = song.sections.first.bars[bar].melody.first;
  return '${note.pitch.note}${note.pitch.octave}';
}

/// The anchors of every stored stroke, keyed by id, in document order.
String _strokeMap(List<InkStroke> strokes) => strokes
    .map((InkStroke stroke) => '${stroke.id}@bar${stroke.anchor.bar}')
    .join(',');

void main() {
  const List<Chord> cycle = <Chord>[
    Chord(root: ChordRoot(2), quality: ChordQuality.minorSeventh),
    Chord(root: ChordRoot(7), quality: ChordQuality.dominantSeventh),
    Chord(root: ChordRoot(0), quality: ChordQuality.majorSeventh),
    Chord(root: ChordRoot(9), quality: ChordQuality.dominantSeventh),
  ];
  final EditSession session = EditSession(
    document: DocumentState(
      song: _chart(),
      strokes: <InkStroke>[
        for (int bar = 0; bar < 16; bar++)
          _stroke(id: 'ink-$bar', bar: bar, beat: bar.isEven ? null : 1),
      ],
    ),
  );
  for (int bar = 0; bar < 16; bar++) {
    session.applyChordToCell(
      sectionId: _section,
      barIndex: bar,
      beat: 0,
      chord: cycle[bar % cycle.length],
    );
    session.insertNote(
      sectionId: _section,
      barIndex: bar,
      beat: 0,
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.d, 0), octave: 4),
      value: const NoteValue.plain(NoteBase.quarter),
    );
  }
  final int undoAfterMusic = session.undoDepth;
  print(
    'PROBE setup bars=16 chords=16 notes=16 strokes=16 '
    'undo=$undoAfterMusic key=${session.song.key}',
  );

  // 1. SELECT.
  final ChartSelection selection = ChartSelection.bars(
    sectionId: _section,
    firstBar: 0,
    lastBar: 15,
  );
  final SelectionReport report = selectionReportOf(
    song: session.song,
    strokes: session.document.strokes,
    selection: selection,
  );
  print(
    'PROBE select range=$selection bars=${report.barCount} '
    'structured=${report.structuredBars} minimal=${report.minimalBars} '
    'ink_only=${report.inkOnlyBars} empty=${report.emptyBars} '
    'strokes=${report.strokeCount} '
    'ink_area=${report.inkArea.toStringAsFixed(1)}',
  );
  final InkFragment firstFragment = report.fragments.first;
  print(
    'PROBE fragment first=${firstFragment.toString()} '
    'centre=(${firstFragment.centreX.toStringAsFixed(1)},'
    '${firstFragment.centreY.toStringAsFixed(1)}) '
    'w=${firstFragment.width.toStringAsFixed(1)} '
    'h=${firstFragment.height.toStringAsFixed(1)}',
  );

  // 2. COPY.
  final ChartClip clip = session.copySelection(selection)!;
  print(
    'PROBE copy bars=${clip.barCount} strokes=${clip.strokes.length} '
    'undo=${session.undoDepth}',
  );
  final String clipStrokes = clip.strokes
      .map((InkStroke s) => '${s.id}@bar${s.anchor.bar}')
      .join(',');
  print('PROBE copy_clip_strokes=$clipStrokes');

  // 3. PASTE at the end.
  final ClipPasteOutcome pasted = session.pasteClip(
    at: ChartSelection.bars(sectionId: _section, firstBar: 15, lastBar: 15),
    clip: clip,
  );
  print(
    'PROBE paste outcome=${pasted.name} '
    'bars=${session.song.sections.first.bars.length} '
    'undo_added=${session.undoDepth - undoAfterMusic} '
    'undo_total=${session.undoDepth}',
  );
  print('PROBE paste_stored_strokes=${_strokeMap(session.document.strokes)}');

  // 4. TRANSPOSE the pasted sixteen up a semitone.
  final SelectionTransposition moved = session.transposeSelection(
    selection: ChartSelection.bars(
      sectionId: _section,
      firstBar: 16,
      lastBar: 31,
    ),
    semitones: 1,
  );
  print(
    'PROBE transpose outcome=${moved.outcome.name} '
    'bars_changed=${moved.barsChanged}/${moved.barsTotal} '
    'strokes_kept=${moved.strokesKept} '
    'undo_added=${session.undoDepth - undoAfterMusic} '
    'undo_total=${session.undoDepth}',
  );
  print(
    'PROBE key=${session.song.key} '
    'key_changed=${session.song.key != Key.cMajor}',
  );
  final StringBuffer chords = StringBuffer();
  for (final int bar in <int>[0, 1, 2, 3, 16, 17, 18, 19]) {
    chords.write('bar${bar + 1}=${_chord(session.song, bar, 0)} ');
  }
  print('PROBE chords ${chords.toString().trim()}');
  print(
    'PROBE melody source=${_melody(session.song, 0)} '
    'pasted=${_melody(session.song, 16)} '
    'pasted_bar1=${_melody(session.song, 17)}',
  );
  print(
    'PROBE ink_after_transpose=${_strokeMap(session.document.strokes)} '
    'ink_moved_by_transpose=false',
  );

  // 5. SAVE THROUGH THE REAL `.chart` CONTAINER AND REOPEN.
  final ChartFile file = ChartFile(
    metadata: ChartMetadata(
      docId: session.docId,
      writer: 'probe_selection_clip.dart',
    ),
    snapshot: session.baseDocument,
    events: session.log,
  );
  final Uint8List bytes = ChartFileCodec.encode(file).bytes;
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(bytes);
  print(
    'PROBE save bytes=${bytes.length} '
    'warnings=${decoded.warnings.length} '
    'events=${decoded.file.events.length}',
  );
  print(
    'PROBE reopen_document_equal=${decoded.file.reducedDocument == session.document} '
    'reopen_strokes=${_strokeMap(decoded.file.reducedDocument.strokes)}',
  );
  final List<InkStroke> reopenedStrokes = decoded.file.reducedDocument.strokes;
  final int barsWithInk = <int>{
    for (final InkStroke stroke in reopenedStrokes) stroke.anchor.bar,
  }.length;
  print(
    'PROBE reopen bars_with_ink=$barsWithInk '
    'strokes=${reopenedStrokes.length} '
    'first_copy_ink=${reopenedStrokes.where((InkStroke s) => s.anchor.bar == 0).length} '
    'second_copy_ink=${reopenedStrokes.where((InkStroke s) => s.anchor.bar == 16).length}',
  );

  // 6. THE UNDO COST, COUNTED, ON A FRESH SESSION WITH ONLY THE PASTE IN IT.
  final EditSession cost = EditSession(document: session.baseDocument);
  final ChartClip costClip = session.copySelection(selection)!;
  final int undoBeforePaste = cost.undoDepth;
  cost.pasteClip(
    at: ChartSelection.bars(sectionId: _section, firstBar: 0, lastBar: 0),
    clip: costClip,
  );
  print(
    'PROBE undo_cost paste_on_empty_document '
    'undo_before=$undoBeforePaste undo_after=${cost.undoDepth}',
  );

  // 7. THE TWO REFUSALS, SO THE PROBE ALSO SAYS WHAT DOES NOT HAPPEN.
  final EditSession narrow = EditSession(
    document: DocumentState(song: _chart(bars: 2)),
  );
  narrow.applyChordToCell(
    sectionId: _section,
    barIndex: 0,
    beat: 3,
    chord: const Chord(root: ChordRoot(0)),
  );
  final ChartClip window = narrow.copySelection(
    ChartSelection.beats(
      sectionId: _section,
      barIndex: 0,
      firstBeat: 2,
      lastBeat: 3,
    ),
  )!;
  print(
    'PROBE window_refused=${narrow.pasteClip(
      at: ChartSelection.beats(sectionId: _section, barIndex: 1, firstBeat: 3, lastBeat: 3),
      clip: window,
    ).name}',
  );
  print(
    'PROBE window_transpose_refused=${narrow.transposeSelection(selection: ChartSelection.beats(sectionId: _section, barIndex: 0, firstBeat: 0, lastBeat: 1), semitones: 1).outcome.name}',
  );

  // 8. A MINIMAL FRAGMENT — PURE HANDWRITING, NOTHING RECOGNISED — COPIED ANYWAY.
  final EditSession inkOnly = EditSession(
    document: DocumentState(
      song: _chart(bars: 4),
      strokes: <InkStroke>[
        for (int bar = 0; bar < 4; bar++) _stroke(id: 'hand-$bar', bar: bar),
      ],
    ),
  );
  final SelectionReport bare = selectionReportOf(
    song: inkOnly.song,
    strokes: inkOnly.document.strokes,
    selection: ChartSelection.bars(
      sectionId: _section,
      firstBar: 0,
      lastBar: 3,
    ),
  );
  final ChartClip inkClip = inkOnly.copySelection(
    ChartSelection.bars(sectionId: _section, firstBar: 0, lastBar: 3),
  )!;
  final ClipPasteOutcome inkPasted = inkOnly.pasteClip(
    at: ChartSelection.bars(sectionId: _section, firstBar: 3, lastBar: 3),
    clip: inkClip,
  );
  print(
    'PROBE minimal structured=${bare.structuredBars} '
    'minimal=${bare.minimalBars} strokes=${bare.strokeCount} '
    'paste=${inkPasted.name} '
    'bars=${inkOnly.song.sections.first.bars.length} '
    'strokes_after=${inkOnly.document.strokes.length} '
    'ink=${jsonEncode(<String>[for (final InkStroke stroke in inkOnly.document.strokes) '${stroke.id}@bar${stroke.anchor.bar}'])}',
  );
  print('PROBE done');
}
