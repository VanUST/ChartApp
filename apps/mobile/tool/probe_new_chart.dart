// PURPOSE: Prove that a chart written FROM NOTHING can be made, edited, saved as a real `.chart`
//          file, reopened and found again — the journey this application could not make before,
//          because music arrived only by importing an iReal export. It goes the whole way through
//          the same functions the buttons call: `newChartSong` for the beginning, `EditSession` for
//          every edit, `chartFileFor` for the save, the io seam for the bytes on disk and the
//          container's own decoder for the read back.
//
//          IT ALSO PROVES THE DEFECT THE FEATURE WOULD HAVE HIT, by reproducing it: a session whose
//          document id comes from an empty `Song.id` writes a log whose operations name a different
//          document than the file header does, and the container refuses the file. That check is
//          reported as a FAILURE only if encoding SUCCEEDS, so a check that cannot fail is not one.
// INPUTS: None. The chart is built here, and the only file written is a scratch file in the
//         system's temporary directory, which is deleted before exit.
// OUTPUTS: One `[ok]` line per expectation, `[FAIL]` lines with both sides, the created chart's
//          shape and identity, and a final `CHECKS=n FAILURES=m` line. Exit code 0 when every
//          expectation held, 1 otherwise. The full text is kept in `docs/verification/`.
// KEYWORDS: probe, new-chart, from-scratch, d21, save, reopen, round-trip, doc-id, identity,
//           falsification, evidence
//
// Run it from apps/mobile:  dart run tool/probe_new_chart.dart
//
// WHY THIS PROBE WRITES ITS OWN BYTES INSTEAD OF CALLING `saveChartFile`. It used to be possible to
// call the app's io seam from a `dart run` probe, and it is not any more: `chart_source_io.dart`
// imports `file_selector` (since the native file chooser landed), which imports Flutter, which
// needs `dart:ui`, which does not exist outside the Flutter engine. What lives in this file is
// therefore the MODEL half of the journey — the document, the operation log, `chartFileFor`, the
// container codec and the reopen — and the seam that moves bytes to a path is exercised by
// `tool/probe_chart_seam.dart` under `flutter test` and, for real, by the tablet run. The bytes on
// disk here are the same bytes either way: the container is what shape they are.
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_document.dart';

int _failures = 0;
int _checks = 0;

Future<void> main() async {
  stdout.writeln('=== A. the shape of a chart written from scratch ===');
  final Song blank = newChartSong();
  stdout.writeln(
    'newChartSong() -> $blank staff=${blank.staffSet} '
    'key=${blank.key} title="${blank.title}" id="${blank.id}" tempo=${blank.tempo}',
  );
  _same('one section', 1, blank.sections.length);
  _same('the section is labelled A', 'A', '${blank.sections.first.label}');
  _same('eight bars', newChartBarCount, blank.writtenBarCount);
  _same('4/4', '4/4', '${blank.sections.first.bars.first.timeSignature}');
  _same('C major', Key.cMajor, blank.key);
  _same(
    'no chords yet',
    0,
    blank.barsInReadingOrder.fold<int>(
      0,
      (int total, Bar bar) => total + bar.chords.length,
    ),
  );
  _same('no title yet', '', blank.title);
  _same('no document id yet', '', blank.id);
  _same('no tempo yet', 0, blank.tempo);
  _same('no style yet', '', blank.style);
  // D29: the melodic staff is DECLARED by a chart written from scratch, so its bars are drawn with
  // staff lines before a single note exists. The old claim here was `chords only`, which was the
  // defect: a musician starting a tune saw no staff and had nowhere to write the first note.
  _same(
    'the melodic staff is declared',
    newChartDefaultStaffSet,
    blank.staffSet,
  );
  _same(
    'and the chart says so through a pitched staff',
    true,
    blank.staffSet.hasTransposableContent,
  );
  _same('with no note written in any bar yet', true, _noNotesAnywhere(blank));
  // The switch is real: a caller that wants a chords-only chart asks for one, and gets exactly the
  // set every imported chart carries.
  _same(
    'chords only is still reachable, on request',
    StaffSet.chordsOnly,
    newChartSong(staffSet: StaffSet.chordsOnly).staffSet,
  );

  final Song waltz = newChartSong(
    key: const Key(tonic: WrittenNote(NoteLetter.b, -1), mode: Mode.major),
    timeSignature: TimeSignature.threeFour,
    bars: 12,
  );
  stdout.writeln(
    'newChartSong(Bb major, 3/4, 12) -> ${waltz.key} '
    '${waltz.sections.first.bars.first.timeSignature} '
    '${waltz.writtenBarCount} bar(s)',
  );
  _same(
    'a chosen meter reaches every bar',
    true,
    waltz.sections.first.bars.every(
      (Bar bar) => bar.timeSignature == TimeSignature.threeFour,
    ),
  );
  _same('a chosen bar count is honoured', 12, waltz.writtenBarCount);
  _same('a chosen key is honoured', 'Bb major', '${waltz.key}');
  _fails('a section of zero bars is refused', () => newChartSong(bars: 0));

  stdout.writeln('');
  stdout.writeln('=== B. what two charts made from nothing have in common ===');
  final String blankIdentity = chartIdentityOf(blank);
  final String otherBlank = chartIdentityOf(newChartSong());
  stdout.writeln('chartIdentityOf(newChartSong()) = $blankIdentity');
  _same(
    'two charts of identical music share an identity, by decision',
    blankIdentity,
    otherBlank,
  );
  _same(
    'the unnamed document id is the one a file is written under',
    'chartapp-untitled',
    documentIdFor(blank),
  );

  final EditSession renamer = _sessionFor(blank);
  _same(
    'renaming an untouched chart is one edit',
    true,
    renamer.updateSong(title: 'Two', composer: 'Nobody', style: 'Ballad'),
  );
  _same(
    'a rename does NOT change the identity',
    blankIdentity,
    chartIdentityOf(renamer.document.song),
  );
  final EditSession editor0 = _sessionFor(blank);
  editor0.applyChordToCell(
    sectionId: newChartFirstSectionId,
    barIndex: 0,
    beat: 0,
    chord: const Chord(root: ChordRoot(0), quality: ChordQuality.majorTriad),
  );
  _same(
    'ONE chord makes it different music, and a different identity',
    true,
    chartIdentityOf(editor0.document.song) != blankIdentity,
  );
  stdout.writeln(
    'after one chord: ${chartIdentityOf(editor0.document.song)} '
    '(was $blankIdentity)',
  );

  stdout.writeln('');
  stdout.writeln(
    '=== C. the document id, and the failure it would have caused ===',
  );
  // THE FALSIFICATION. This is the code the viewer shipped: the session is named by `Song.id`,
  // which is empty for a chart typed from scratch, while `chartFileFor` names the file after the
  // fallback id. The two disagree and the container refuses the file — so this check FAILS if
  // encoding succeeds.
  final EditSession oldWay = EditSession(
    document: DocumentState(song: blank),
    docId: blank.id,
  );
  oldWay.applyChordToCell(
    sectionId: newChartFirstSectionId,
    barIndex: 0,
    beat: 0,
    chord: const Chord(root: ChordRoot(0), quality: ChordQuality.majorTriad),
  );
  final ChartFile oldFile = chartFileFor(
    oldWay.baseDocument,
    events: oldWay.log,
  );
  stdout.writeln(
    'old way: session.docId="${oldWay.docId}" header.docId="${oldFile.metadata.docId}" '
    'event.docId="${oldWay.log.single.docId}"',
  );
  _refused('a session named by an empty Song.id cannot be saved', oldFile);

  // THE FIX, in the same shape: both sides read the rule from `documentIdFor`.
  final EditSession fixed = _sessionFor(blank);
  fixed.applyChordToCell(
    sectionId: newChartFirstSectionId,
    barIndex: 0,
    beat: 0,
    chord: const Chord(root: ChordRoot(0), quality: ChordQuality.majorTriad),
  );
  final ChartFile fixedFile = chartFileFor(
    fixed.baseDocument,
    events: fixed.log,
  );
  final ChartFileEncodeResult fixedBytes = ChartFileCodec.encode(fixedFile);
  _same('the fixed session saves', true, fixedBytes.bytes.isNotEmpty);
  _same(
    'the header and the operation name one document',
    fixedFile.metadata.docId,
    fixed.log.single.docId,
  );

  stdout.writeln('');
  stdout.writeln(
    '=== D. the whole journey: make it, edit it, save it, reopen it ===',
  );
  final EditSession session = _sessionFor(blank);
  final String sectionA = session.song.sections.first.id;
  // A second section, and bars inside the first: the form of a tune is built by these two.
  _same(
    'insert a bar after the first',
    true,
    session.insertBarAfter(sectionId: sectionA, barIndex: 0),
  );
  _same(
    'insert a bar before the last',
    true,
    session.insertBarBefore(sectionId: sectionA, barIndex: 2),
  );
  final String? sectionB = session.insertSectionAfter(sectionA);
  _same('insert a section after A', true, sectionB != null);
  _same(
    'the new section is labelled B',
    'B',
    '${session.song.sections[1].label}',
  );
  _same(
    'the new section holds one bar',
    1,
    session.song.sections[1].bars.length,
  );
  // Chords, in the first bar of each section.
  _same(
    'a chord in bar 1 of A',
    true,
    session.applyChordToCell(
      sectionId: sectionA,
      barIndex: 0,
      beat: 0,
      chord: const Chord(root: ChordRoot(0), quality: ChordQuality.majorTriad),
    ),
  );
  _same(
    'a second chord in bar 2 of A',
    true,
    session.applyChordToCell(
      sectionId: sectionA,
      barIndex: 1,
      beat: 2,
      chord: const Chord(
        root: ChordRoot(7),
        quality: ChordQuality.dominantSeventh,
      ),
    ),
  );
  _same(
    'a chord in B',
    true,
    session.applyChordToCell(
      sectionId: sectionB!,
      barIndex: 0,
      beat: 0,
      chord: const Chord(root: ChordRoot(9), quality: ChordQuality.minorTriad),
    ),
  );
  // A sign, a word and a rename: the three things the owner's corpus proved he uses.
  _same(
    'a segno on bar 3 of A',
    true,
    session.setBarMark(
      sectionId: sectionA,
      barIndex: 2,
      mark: BarMark.segno,
      present: true,
    ),
  );
  _same(
    'a volta on bar 3 of A',
    true,
    session.setVolta(sectionId: sectionA, barIndex: 2, volta: const Volta(1)),
  );
  final String? cue = session.insertTextCue(
    sectionId: sectionA,
    barIndex: 0,
    text: 'Припев',
  );
  _same('a word written on bar 1 of A', true, cue != null);
  _same(
    'the chart is named through song.update',
    true,
    session.updateSong(
      title: 'Новый чарт',
      composer: 'Иван',
      style: 'Medium Swing',
      tempo: 120,
    ),
  );
  // A STRUCTURED NOTE ON THE SAME CHART AS THE HANDWRITING, which is the acceptance D28 and D29 ask
  // for together: the document must carry both at once, and a save and a reopen must bring both
  // back. The note goes on beat 2 of bar 1 of A with a DURATION AND A PITCH the reader can check,
  // so a round trip that dropped the melody, moved its beat or flattened its value cannot pass by
  // comparing one note.
  _same(
    'a note written on beat 2 of bar 1 of A, alongside the handwriting',
    true,
    session.insertNote(
      sectionId: sectionA,
      barIndex: 0,
      beat: 1,
      pitch: const PitchedNote(note: WrittenNote(NoteLetter.f, 1), octave: 4),
      value: const NoteValue.plain(NoteBase.eighth),
      tiedToNext: true,
    ),
  );
  _same(
    'and the same chart still carries a pitched staff, so the staff lines it is drawn on exist',
    true,
    session.song.staffSet.pitched != null,
  );
  session.apply(
    InkStrokeAddEvent(
      docId: session.docId,
      seq: session.seq,
      index: 0,
      stroke: InkStroke(
        id: 'stroke-1',
        tool: StrokeTool.pen,
        color: '#102a43',
        size: 3,
        anchor: EventAnchor(sectionId: sectionA, bar: 0, beat: 0),
        points: const <InkPoint>[
          InkPoint(x: 2.0, y: 3.0, w: 0.4, t: 0),
          InkPoint(x: 9.0, y: 5.0, w: 0.8, t: 12),
        ],
      ),
    ),
  );
  final DocumentState edited = session.document;
  stdout.writeln(
    'edited: sections=${edited.song.sections.length} bars=${edited.song.writtenBarCount} '
    'chords=${edited.song.barsInReadingOrder.fold<int>(0, (int t, Bar b) => t + b.chords.length)} '
    'marks=${edited.song.sections.first.bars[2].marks} '
    'volta=${edited.song.sections.first.bars[2].volta} '
    'cues=${edited.textCues.length} strokes=${edited.strokes.length} '
    'title="${edited.song.title}" tempo=${edited.song.tempo} '
    'operations=${session.log.length}',
  );

  final Directory directory = Directory.systemTemp.createTempSync(
    'chartapp-new-chart-',
  );
  final String path = '${directory.path}${Platform.pathSeparator}new.chart';
  // The save exactly as the dialog performs it: the BASE document and the operations after it.
  final ChartFile file = chartFileFor(
    session.baseDocument,
    events: session.log,
    modifiedAt: DateTime.utc(2026, 10, 11, 12, 0),
  );
  final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
  final File onDisk = File(path);
  onDisk.writeAsBytesSync(encoded.bytes, flush: true);
  _same('the file exists', true, onDisk.existsSync());
  _same(
    'the file holds what was encoded',
    encoded.bytes.length,
    onDisk.lengthSync(),
  );

  final Uint8List bytes = onDisk.readAsBytesSync();
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(bytes);
  _same('the file is the one that was written', file, decoded.file);
  _same('no warnings on a clean file', 0, decoded.warnings.length);
  _same(
    'the file is written under the untitled id',
    'chartapp-untitled',
    decoded.file.metadata.docId,
  );

  // Reopening is the proof: a session opened the way the viewer opens one must hold the chart that
  // was saved — music, handwriting, marks and words — and not a reduction of it applied twice.
  final EditSession reopened = EditSession(
    document: decoded.file.snapshot,
    docId: decoded.file.metadata.docId,
    seq: decoded.file.events.isEmpty ? 0 : decoded.file.events.last.seq,
    restored: decoded.file.events,
  );
  _same('REOPENED_DOCUMENT_EQUAL', true, reopened.document == edited);
  _same(
    'the sections came back',
    edited.song.sections.length,
    reopened.document.song.sections.length,
  );
  _same(
    'the bars came back',
    edited.song.writtenBarCount,
    reopened.document.song.writtenBarCount,
  );
  _same(
    'the chords came back',
    true,
    _sameBarList(
      edited.song.barsInReadingOrder,
      reopened.document.song.barsInReadingOrder,
    ),
  );
  _same(
    'the marks came back',
    true,
    reopened.document.song.sections.first.bars[2].marks.contains(BarMark.segno),
  );
  _same(
    'the volta came back',
    const Volta(1),
    reopened.document.song.sections.first.bars[2].volta,
  );
  _same(
    'the words came back',
    'Припев',
    reopened.document.textCues.single.text,
  );
  _same('the handwriting came back', 1, reopened.document.strokes.length);
  _same(
    'the handwriting kept its points',
    edited.strokes.single.points.length,
    reopened.document.strokes.single.points.length,
  );
  _same(
    'the handwriting kept its anchor',
    edited.strokes.single.anchor,
    reopened.document.strokes.single.anchor,
  );
  // THE STRUCTURED HALF OF THE SAME DOCUMENT. The note is read back by its ADDRESS, its written
  // pitch and its value, so a reopen that lost the melody or merged it into a chord cannot pass.
  _same(
    'the structured note came back, whole value',
    true,
    reopened.document.song.barsInReadingOrder.first.melody.length == 1 &&
        reopened.document.song.barsInReadingOrder.first.melody.single ==
            edited.song.barsInReadingOrder.first.melody.single,
  );
  _same(
    'the note came back at beat 1, as F#4 tied, and the staff is declared',
    'beat=1 step=0 pitch=F#4 value=eighth tie=true staff=pitched',
    'beat=${reopened.document.song.barsInReadingOrder.first.melody.single.beat} '
        'step=${reopened.document.song.barsInReadingOrder.first.melody.single.step} '
        'pitch=${reopened.document.song.barsInReadingOrder.first.melody.single.pitch} '
        'value=${reopened.document.song.barsInReadingOrder.first.melody.single.value} '
        'tie=${reopened.document.song.barsInReadingOrder.first.melody.single.tiedToNext} '
        'staff=${reopened.document.song.staffSet.pitched == null ? 'none' : 'pitched'}',
  );
  _same('the title came back', 'Новый чарт', reopened.document.song.title);
  _same('the composer came back', 'Иван', reopened.document.song.composer);
  _same('the style came back', 'Medium Swing', reopened.document.song.style);
  _same('the tempo came back', 120, reopened.document.song.tempo);
  _same('the key came back', edited.song.key, reopened.document.song.key);
  _same(
    'the identity of the reopened chart is the identity of the edited one',
    chartIdentityOf(edited.song),
    chartIdentityOf(reopened.document.song),
  );
  _same(
    'reopening does not renumber the log: the next edit continues it',
    session.seq,
    reopened.seq,
  );
  stdout.writeln('reopened: ${reopened.document}');

  directory.deleteSync(recursive: true);
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

/// The session the viewer opens for a chart, so every check here goes through the app's own rule.
EditSession _sessionFor(Song song) => EditSession(
  document: DocumentState(song: song),
  docId: documentIdFor(song),
);

/// Whether two lists of bars are equal, element by element.
///
/// A `List`'s own `==` is identity, so a comparison written with it would report a difference that
/// is not there — the same trap that makes a round trip "pass" while comparing nothing.
bool _sameBarList(List<Bar> left, List<Bar> right) {
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

/// Whether [song] carries no melodic note at all, which is the state a chart written from scratch
/// starts in even though its staff is already declared.
bool _noNotesAnywhere(Song song) {
  for (final Bar bar in song.barsInReadingOrder) {
    if (bar.melody.isNotEmpty) {
      return false;
    }
  }
  return true;
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

/// Runs [act], which must throw, and reports whether it did.
void _fails(String what, Object? Function() act) {
  _checks++;
  try {
    final Object? result = act();
    _failures++;
    stdout.writeln('[FAIL] $what — DID NOT THROW: got $result');
  } catch (error) {
    stdout.writeln('[ok] $what — ${error.runtimeType}');
    stdout.writeln('    $error');
  }
}

/// Records that encoding [file] must be REFUSED by the container, printing what it said when it is.
///
/// A separate helper from [_fails] because this is the one check whose subject is the SUCCESS path:
/// the expectation is that the container notices two documents named in one file.
void _refused(String what, ChartFile file) {
  _checks++;
  try {
    final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
    _failures++;
    stdout.writeln(
      '[FAIL] $what — the container ACCEPTED it, encoding ${encoded.bytes.length} bytes',
    );
  } on ChartFileException catch (error) {
    stdout.writeln('[ok] $what — ${error.runtimeType}');
    stdout.writeln('    ${error.message}');
  }
}
