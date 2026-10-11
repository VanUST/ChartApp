// PURPOSE: Put real `.chart` files on disk for a BROWSER to be driven with, because a headless
//          browser can only be handed a file that already exists: the container is built by the
//          same `chartFileFor` and `ChartFileCodec` the Save button uses, and the two damaged copies
//          are derived from the valid one so that a browser run can show what the musician sees when
//          a file is truncated or has a byte flipped. Without this, the only way to get a `.chart`
//          file into the page would be to save one from the page, which cannot test the open path
//          against a file the page did not write.
//
//          IT WRITES A TAIL THAT IS NOT IDEMPOTENT, deliberately. A file whose operation tail is a
//          few chord changes decodes correctly even when the reader applies it twice, so it would
//          prove nothing about the browser's open path; a bar inserted, a bar deleted and a song
//          renamed are the operations that made this exact defect visible on the native path.
// INPUTS: An optional output directory as the first argument, defaulting to `build/chart_fixtures`
//         under the current directory. The directory is created when it does not exist.
// OUTPUTS: Three files — `valid.chart`, `truncated.chart` (half of the valid bytes) and
//          `damaged.chart` (one header byte flipped, which the container's CRC must catch) — and one
//          line per file with its absolute path and byte count, so a browser-driving tool can be
//          given the path without a second lookup. Imports no Flutter, which is why plain `dart run`
//          can execute it.
// KEYWORDS: fixtures, chart-file, browser-verification, truncated, corrupted, non-idempotent,
//           dart-run, headless
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_document.dart';
import 'package:chartapp/ireal_library.dart';

import 'probe_payloads.dart' show syntheticPayload;

void main(List<String> arguments) {
  final Directory directory = Directory(
    arguments.isNotEmpty ? arguments.first : 'build/chart_fixtures',
  );
  directory.createSync(recursive: true);

  final IRealLibrary library = parseIRealLibrary(syntheticPayload());
  final IRealSong entry = library.songs.single;
  final String sectionId = entry.song.sections.first.id;

  final EditSession session = EditSession(
    document: DocumentState(song: entry.song),
  );
  session.insertBarAfter(sectionId: sectionId, barIndex: 0);
  session.deleteBar(sectionId: sectionId, barIndex: 2);
  session.updateSong(style: 'Ballad', tempo: 90);

  final ChartFile file = chartFileFor(
    session.baseDocument,
    events: session.log,
    modifiedAt: DateTime.utc(2026, 10, 10, 19, 30),
  );
  final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
  final Uint8List valid = encoded.bytes;

  final File validFile = _write(directory, 'valid.chart', valid);

  final Uint8List truncated = Uint8List.sublistView(
    valid,
    0,
    valid.length ~/ 2,
  );
  final File truncatedFile = _write(directory, 'truncated.chart', truncated);

  final Uint8List damaged = Uint8List.fromList(valid);
  damaged[chartFilePrefixLength + 9] ^= 0xFF;
  final File damagedFile = _write(directory, 'damaged.chart', damaged);

  final Song reopened = ChartFileCodec.decode(valid).file.reducedDocument.song;
  stdout.writeln(
    'fixture song="${entry.song.title}" bars=${entry.song.writtenBarCount} '
    'reopened_bars=${reopened.writtenBarCount} '
    'reopened_style=${reopened.style} reopened_tempo=${reopened.tempo} '
    'operations=${session.log.length} warnings=${encoded.warnings.length}',
  );
  for (final File written in <File>[validFile, truncatedFile, damagedFile]) {
    stdout.writeln(
      'file=${written.absolute.path} bytes=${written.lengthSync()}',
    );
  }
}

// PURPOSE: Write one fixture and refuse to pretend it worked.
// INPUTS: directory — where to write. name — the file name. bytes — the whole file.
// OUTPUTS: The written file, after it has been read back to the same length; a short write would
//          otherwise produce a browser run whose failure pointed at the wrong thing.
// KEYWORDS: write, verify, fixture, io
/// Writes [bytes] as [name] inside [directory] and returns the file.
File _write(Directory directory, String name, Uint8List bytes) {
  final String separator = Platform.pathSeparator;
  final File file = File('${directory.path}$separator$name');
  file.writeAsBytesSync(bytes, flush: true);
  if (file.lengthSync() != bytes.length) {
    throw FileSystemException(
      'the fixture was written short: expected ${bytes.length} bytes.',
      file.path,
    );
  }
  return file;
}
