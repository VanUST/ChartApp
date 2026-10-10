// PURPOSE: Prove the app's own save/open seam against real files on disk: an iReal-imported song is
//          turned into a `.chart` document by the same function the Save button calls, written
//          through the same io seam the button uses, read back through the same seam, and decoded
//          into the song it started as. A codec round trip inside `chart_core` says nothing about
//          whether the app wires it up; this does.
// INPUTS: None. The fixture is a synthetic iReal payload built here, so nothing is read from the
//         owner's machine.
// OUTPUTS: One block per check on stdout, a summary line and an exit code: 0 when every check held,
//          1 when one did not. Every expected failure prints the exception TYPE and MESSAGE it
//          caught. This file imports no Flutter, which is why plain `dart run` can execute it.
// KEYWORDS: probe, chart-file, app-seam, save, open, round-trip, dart-io, evidence
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_document.dart';
import 'package:chartapp/chart_source.dart';
import 'package:chartapp/ireal_library.dart';

int _failures = 0;
int _checks = 0;

Future<void> main() async {
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
    entry.song,
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

  directory.deleteSync(recursive: true);
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
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

/// The ten-field iReal payload the viewer test uses, so the probe starts from a real import rather
/// than from a hand-built Song.
String syntheticPayload() {
  const String notation = '*AT44C^ |F^ |G7 |C^ Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  return 'Test Tune=Test Composer==Medium Swing=C=0=$music=Medium Swing=120=1';
}

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
