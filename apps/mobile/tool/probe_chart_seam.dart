// PURPOSE: Prove the app's own save/open seam against real files on disk: an iReal-imported song is
//          turned into a `.chart` document by the same function the Save button calls, written
//          through the same io seam the button uses, read back through the same seam, and decoded
//          into the song it started as. A codec round trip inside `chart_core` says nothing about
//          whether the app wires it up; this does.
//
//          IT ALSO SAVES AN EDITED SESSION, WITH A TAIL THAT IS NOT IDEMPOTENT, AND REOPENS IT. That
//          is the case a musician meets and the one this seam was blind to: the checks below the
//          first block store a document with NO tail, and a tail of chord updates happens to be
//          harmless when applied twice, so both said the round trip worked while a chart with an
//          inserted bar, a deleted bar, a changed tempo and a handwritten stroke could not be
//          reopened at all. A bar insert applied twice is two bars; a stroke applied twice is
//          refused; those are the operations this probe now carries.
// INPUTS: None. The fixture is a synthetic iReal payload built in `probe_payloads.dart`, so nothing
//         is read from the owner's machine.
// OUTPUTS: One block per check on stdout and a summary line, `CHECKS=n FAILURES=m`. Every expected
//          failure prints the exception TYPE and MESSAGE it caught. This file imports no Flutter,
//          which is why plain `dart run` can execute it.
//
//          **THE LAST SENTENCE OF OUTPUTS IS CORRECTED HERE AND IS LEFT STANDING ABOVE, the same
//          form `docs/sdd.md` A30 and A52 use for a claim that became false.** "This file imports
//          no Flutter, which is why plain `dart run` can execute it" was true when it was written
//          and is false since A55: this file reaches `chart_source.dart` -> `chart_source_io.dart`,
//          which imports `file_selector` and `flutter/foundation`, so
//          `dart run tool/probe_chart_seam.dart` now dies with `Dart library 'dart:ui' is not
//          available on this platform`. The probe is therefore written as a `flutter test` file --
//          the shape `probe_native_path.dart` proves works -- and it is run from `apps/mobile`:
//
//              flutter test tool/probe_chart_seam.dart
//
//          `flutter test` runs the engine headless, so the probe opens no window. It no longer calls
//          `exit()`: the same failures that used to make it exit 1 now fail the test, which is what
//          makes `flutter test` exit non-zero, and the summary line is still printed.
// KEYWORDS: probe, chart-file, app-seam, save, open, round-trip, reopen, non-idempotent, dart-io,
//           flutter-test, headless, evidence
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_document.dart';
import 'package:chartapp/chart_source.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:flutter_test/flutter_test.dart';

import 'probe_payloads.dart';

int _failures = 0;
int _checks = 0;

void main() {
  test(
    'the app save/open seam, on real files, with a tail that is not idempotent',
    () async {
      addTearDown(_report);
      await _proveTheSeam();
    },
  );
}

// PURPOSE: Run every check this probe carries, in the order a musician meets the save/open seam. The
//          body is kept separate from `main` so the reshape to `flutter test` changed only the frame
//          around it: every check, and the counters they are reported with, are the ones that were
//          here when this file was a `dart run` probe.
// INPUTS: None.
// OUTPUTS: A future that completes when the last check has been reported. It calls no `exit()`; the
//          verdict is the assertion `_report` makes when the test tears down.
// KEYWORDS: probe-body, save, open, round-trip, reopen, no-exit
Future<void> _proveTheSeam() async {
  stdout.writeln('chartSourceIsFilePath=$chartSourceIsFilePath');

  final IRealLibrary library = parseIRealLibrary(syntheticPayload());
  final IRealSong entry = library.songs.single;
  stdout.writeln(
    'imported="${entry.title}" bars=${entry.song.writtenBarCount} '
    'key=${entry.song.key} tempo=${entry.song.tempo}',
  );

  final Directory directory = Directory.systemTemp.createTempSync(
    'chartapp-probe-',
  );
  final String path = '${directory.path}${Platform.pathSeparator}probe.chart';
  stdout.writeln('path=$path');

  // --- SAVE, exactly as the button does it -----------------------------------------------------
  final ChartFile document = chartFileFor(
    DocumentState(song: entry.song),
    modifiedAt: DateTime.utc(2026, 10, 10, 19, 30),
  );
  final ChartFileEncodeResult encoded = ChartFileCodec.encode(document);
  await saveChartFile(path, encoded.bytes);
  final File onDisk = File(path);
  _same('the file exists after save', true, onDisk.existsSync());
  _same(
    'the file holds the encoded byte count',
    encoded.bytes.length,
    onDisk.lengthSync(),
  );
  final Uint8List firstBytes = onDisk.readAsBytesSync();
  _same(
    'the file begins with the .chart magic',
    true,
    _bytesEqual(chartFileMagic, firstBytes.sublist(0, chartFileMagic.length)),
  );
  stdout.writeln(
    'saved bytes=${encoded.bytes.length} warnings=${encoded.warnings.length}',
  );

  // --- OPEN, exactly as the button does it ------------------------------------------------------
  final Uint8List read = await loadChartFile(path);
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(read);
  final Song reopened = decoded.file.reducedDocument.song;
  _same(
    'the decoded file equals the document that was saved',
    document,
    decoded.file,
  );
  _same(
    'the chart read back is the chart that was saved',
    entry.song,
    reopened,
  );
  _same('title survives', entry.song.title, reopened.title);
  _same('composer survives', entry.song.composer, reopened.composer);
  _same('style survives', entry.song.style, reopened.style);
  _same('key survives', entry.song.key, reopened.key);
  _same('tempo survives', entry.song.tempo, reopened.tempo);
  _same('staff set survives', entry.song.staffSet, reopened.staffSet);
  _same(
    'bar count survives',
    entry.song.writtenBarCount,
    reopened.writtenBarCount,
  );
  _same(
    'the first bar survives chord for chord',
    true,
    _sameList<BeatChord>(
      entry.song.barsInReadingOrder.first.chords,
      reopened.barsInReadingOrder.first.chords,
    ),
  );
  _same('no warnings on a clean file', 0, decoded.warnings.length);

  // --- A missing path is a reportable failure, not an empty document ----------------------------
  await _fails(
    'reading a path that does not exist',
    () => loadChartFile('${directory.path}${Platform.pathSeparator}nope.chart'),
  );

  // --- A file damaged on disk is refused, not turned into an empty chart ------------------------
  final Uint8List valid = onDisk.readAsBytesSync();
  onDisk.writeAsBytesSync(valid.sublist(0, valid.length ~/ 2));
  await _fails('decoding a file truncated on disk', () => readAndDecode(path));

  final Uint8List corrupted = Uint8List.fromList(valid);
  corrupted[chartFilePrefixLength + 9] ^= 0xFF;
  onDisk.writeAsBytesSync(corrupted);
  await _fails('decoding a file corrupted on disk', () => readAndDecode(path));

  onDisk.writeAsBytesSync(<int>[...valid, 0x00, 0x01]);
  await _fails(
    'decoding a file with two bytes appended',
    () => readAndDecode(path),
  );

  await saveChartFile(path, valid);
  final Uint8List restored = await loadChartFile(path);
  _same(
    'the file is whole again after the damage',
    true,
    _bytesEqual(valid, restored),
  );

  // --- THE APP-SHAPED ROUND TRIP, WITH A TAIL THAT IS NOT IDEMPOTENT ----------------------------
  //
  // The checks above save a document with NO tail, which is the one case where the writer's shape
  // cannot be wrong. The button saves a SESSION: a base document plus the operations made since it.
  // This section saves exactly that, with edits chosen because applying them twice gives a
  // DIFFERENT document — a bar put in, a bar taken out, a tempo changed and a stroke added — and it
  // proves the round trip the way a musician meets it: save, close, open, and find the same chart.
  //
  // Why these four and not a chord change: a `chord.update` is idempotent by address, so a reader
  // that applied the tail twice would produce the right chart and hide the defect. That is how this
  // seam was green while a real edited chart could not be reopened at all.
  final String sectionId = entry.song.sections.first.id;
  final EditSession session = EditSession(
    document: DocumentState(song: entry.song),
  );
  final String insertedBar = 'ink-seam-1';
  _same(
    'the session inserted a bar',
    true,
    session.insertBarAfter(sectionId: sectionId, barIndex: 0),
  );
  _same(
    'the session deleted a bar',
    true,
    session.deleteBar(sectionId: sectionId, barIndex: 2),
  );
  _same(
    'the session changed the tempo',
    true,
    session.updateSong(style: 'Ballad', tempo: 90),
  );
  session.apply(
    InkStrokeAddEvent(
      docId: session.docId,
      seq: session.seq,
      index: 0,
      stroke: InkStroke(
        id: insertedBar,
        tool: StrokeTool.pen,
        color: '#102a43',
        size: 3,
        anchor: EventAnchor(sectionId: sectionId, bar: 1, beat: 0),
        points: const <InkPoint>[
          InkPoint(x: 2.0, y: 3.0, w: 0.4, t: 0),
          InkPoint(x: 9.0, y: 5.0, w: 0.8, t: 12),
        ],
      ),
    ),
  );
  final DocumentState edited = session.document;
  stdout.writeln(
    'edit.base_bars=${session.baseDocument.song.writtenBarCount} '
    'edited_bars=${edited.song.writtenBarCount} '
    'strokes=${edited.strokes.length} '
    'style=${edited.song.style} tempo=${edited.song.tempo} '
    'operations=${session.log.length} '
    'types=${session.log.map((ChartEvent event) => event.type).toList()}',
  );

  final String editedPath =
      '${directory.path}${Platform.pathSeparator}edited.chart';
  final ChartFile editedFile = chartFileFor(
    // THE BASE, NOT THE CURRENT DOCUMENT. The container's document is the snapshot PLUS the
    // operations, so the snapshot has to be the state before them.
    session.baseDocument,
    events: session.log,
    modifiedAt: DateTime.utc(2026, 10, 10, 19, 30),
  );
  await saveChartFile(editedPath, ChartFileCodec.encode(editedFile).bytes);
  final ChartFileDecodeResult reread = await readAndDecode(editedPath);

  _same(
    'the reread snapshot is the state the session started from',
    session.baseDocument,
    reread.file.snapshot,
  );
  _same(
    'the reread tail is the operations that were made',
    true,
    _sameList<ChartEvent>(reread.file.events, session.log),
  );
  _same(
    'the reread document is the document that was saved',
    edited,
    reread.file.reducedDocument,
  );

  // THE PROOF IS REOPENING, NOT ARITHMETIC: a session opened the way the viewer opens one must hold
  // the chart that was saved, bar for bar, stroke for stroke and style for style.
  final EditSession reopenedSession = EditSession(
    document: reread.file.snapshot,
    docId: reread.file.metadata.docId,
    seq: reread.file.events.last.seq,
    restored: reread.file.events,
  );
  _same(
    'REOPENED_DOCUMENT_EQUAL the reopened chart is the saved chart',
    true,
    reopenedSession.document == edited,
  );
  _same(
    'the reopened chart has the same bars',
    edited.song.writtenBarCount,
    reopenedSession.document.song.writtenBarCount,
  );
  _same(
    'the reopened chart has the same strokes',
    edited.strokes.length,
    reopenedSession.document.strokes.length,
  );
  _same(
    'the reopened chart carries the edited style and tempo',
    'Ballad/90',
    '${reopenedSession.document.song.style}/'
        '${reopenedSession.document.song.tempo}',
  );
  stdout.writeln(
    'reopened bars=${reopenedSession.document.song.writtenBarCount} '
    'strokes=${reopenedSession.document.strokes.length} '
    'style=${reopenedSession.document.song.style} '
    'tempo=${reopenedSession.document.song.tempo} '
    'seq=${reopenedSession.seq}',
  );

  // The temporary directory's removal is registered rather than written here so that it happens
  // even when a check throws. Nothing this probe wrote is left behind for the test run to see.
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
}

/// Prints the check and failure counts, then turns them into the test's verdict, so a probe that
/// runs but reports a failure cannot be mistaken for a passing one.
void _report() {
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  expect(_failures, 0, reason: 'every check in this probe must hold');
}

/// Reads the file at [path] and decodes it, which is what the Open button does in two steps.
Future<ChartFileDecodeResult> readAndDecode(String path) async {
  final Uint8List bytes = await loadChartFile(path);
  return ChartFileCodec.decode(bytes);
}

/// Whether two lists hold equal elements in the same order.
///
/// A `List`'s own `==` is identity, so comparing two equal-by-value lists with it would report a
/// difference that is not there — the same trap that makes a round-trip comparison pass while
/// comparing nothing.
bool _sameList<T>(List<T> left, List<T> right) {
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

/// Whether two byte lists hold the same bytes.
bool _bytesEqual(List<int> left, List<int> right) {
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

// The ten-field iReal payload this probe starts from now lives in `probe_payloads.dart`, because
// the `dart run` fixture writer has to import it without importing this Flutter-reaching file.

/// Records one expectation, printing both sides when it fails.
void _same(String what, Object? expected, Object? actual) {
  _checks++;
  final bool ok = expected == actual;
  if (!ok) {
    _failures++;
    stdout.writeln('[FAIL] $what');
    stdout.writeln('    expected: $expected');
    stdout.writeln('    actual:   $actual');
    return;
  }
  stdout.writeln('[ok] $what');
}

/// Runs [act], which must fail, and prints the typed failure it produced.
Future<void> _fails(String what, Future<Object?> Function() act) async {
  _checks++;
  try {
    final Object? result = await act();
    _failures++;
    stdout.writeln('[$what] DID NOT FAIL: got $result');
  } on ChartFileException catch (error) {
    stdout.writeln('[$what] ${error.runtimeType}');
    stdout.writeln('    ${error.message}');
  } on FileSystemException catch (error) {
    stdout.writeln('[$what] FileSystemException');
    stdout.writeln('    ${error.message} (${error.path})');
  } catch (error) {
    _failures++;
    stdout.writeln(
      '[$what] UNTYPED ${error.runtimeType}: $error -- a raw failure escaped the seam',
    );
  }
}
