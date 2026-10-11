// PURPOSE: Put real files on disk for a HEADLESS BROWSER to be driven with: the iReal export the
//          page imports, the same tunes in another order, and a `.setlist` programme saved by the
//          same code the Save button calls, with two damaged copies derived from it. A browser can
//          only be handed files that already exist, and the page cannot be asked to produce the one
//          it is supposed to open before it has opened it; the export and the reordered export come
//          from the payload `probe_setlist_seam.dart` prints identities for, so the numbers the
//          browser computes can be compared with the numbers the native run computed.
// INPUTS: argv[0] — the directory to write into. Created when it does not exist.
// OUTPUTS: `setlist-export.html`, `setlist-export-reordered.html` (iReal export pages, each carrying
//          one `irealb://` link), `valid.setlist`, `truncated.setlist` and `damaged.setlist`, one
//          line per file with its absolute path and byte count, and one line per song with the
//          identity the app will compute for it.
// KEYWORDS: fixtures, setlist-file, ireal-export, browser-verification, truncated, corrupted,
//           identity, dart-run, headless
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/setlist_document.dart';
import 'package:chartapp/setlist_import.dart';

import 'probe_setlist_seam.dart'
    show threeSongPlaylistPayload, threeSongPlaylistReorderedPayload;

void main(List<String> arguments) {
  final Directory directory = Directory(
    arguments.isNotEmpty ? arguments.first : 'build/setlist_fixtures',
  );
  directory.createSync(recursive: true);

  final String payload = threeSongPlaylistPayload();
  final IRealLibrary library = parseIRealLibrary(payload);
  final File export = _writeExport(
    directory,
    'setlist-export.html',
    payload,
    'Test Playlist',
  );
  final File reordered = _writeExport(
    directory,
    'setlist-export-reordered.html',
    threeSongPlaylistReorderedPayload(),
    'Test Playlist',
  );

  // The programme the browser will build and save, written here through the SAME builder and codec
  // the Save button uses, so the open path can be exercised against a file the page did not write.
  final SetlistSession session = SetlistSession(
    setlist: importedSetlist(library),
  );
  session.rename('Friday night');
  session.updateItem(0, transposeSem: 2, notes: 'count off');
  final SetlistFile file = setlistFileFor(
    session,
    modifiedAt: DateTime.utc(2026, 10, 11, 21),
  );
  final Uint8List valid = SetlistFileCodec.encode(file).bytes;
  final File validFile = _write(directory, 'valid.setlist', valid);
  final File truncatedFile = _write(
    directory,
    'truncated.setlist',
    Uint8List.sublistView(valid, 0, valid.length ~/ 2),
  );
  final Uint8List damaged = Uint8List.fromList(valid);
  damaged[containerPrefixLength + 9] ^= 0xFF;
  final File damagedFile = _write(directory, 'damaged.setlist', damaged);

  final Setlist reopened = SetlistFileCodec.decode(valid).file.reducedSetlist;
  stdout.writeln(
    'fixture programme="${reopened.title}" entries=${reopened.items.length} '
    'operations=${file.events.length}',
  );

  // A programme built from tunes that are NOT in the export above, so a browser run can open it
  // beside the loaded library and show what the musician reads for an entry whose chart is not
  // there: the row stays, named `(missing chart)`, and the count is said above the list.
  final IRealLibrary foreign = parseIRealLibrary(_foreignPayload());
  final SetlistFile foreignFile = setlistFileFor(
    SetlistSession(setlist: importedSetlist(foreign)),
    modifiedAt: DateTime.utc(2026, 10, 11, 21),
  );
  final File foreignWritten = _write(
    directory,
    'foreign.setlist',
    SetlistFileCodec.encode(foreignFile).bytes,
  );
  final Setlist foreignSetlist = foreignFile.snapshot;
  stdout.writeln(
    'fixture foreign entries=${foreignSetlist.items.length} '
    'identities=${foreignSetlist.items.map((SetlistItem i) => i.chartIdentity).toList()}',
  );
  for (final IRealSong song in library.songs) {
    stdout.writeln(
      'fixture song index=${song.index} id="${song.song.id}" '
      'identity=${song.identity} title="${song.title}"',
    );
  }
  stdout.writeln(
    'fixture entry order=${reopened.items.map((SetlistItem i) => i.documentId).toList()} '
    'identities=${reopened.items.map((SetlistItem i) => i.chartIdentity).toList()}',
  );
  for (final File written in <File>[
    export,
    reordered,
    validFile,
    truncatedFile,
    damagedFile,
    foreignWritten,
  ]) {
    stdout.writeln(
      'file=${written.absolute.path} bytes=${written.lengthSync()}',
    );
  }
}

// PURPOSE: Build the payload of a programme whose charts are nowhere in the exported playlist, so the
//          missing-chart decision can be shown in a browser rather than only asserted in code.
// INPUTS: None.
// OUTPUTS: A decoded payload of two tunes in keys the exported playlist does not use.
// KEYWORDS: fixture, foreign-programme, missing-chart, browser-verification, negative-case
String _foreignPayload() {
  final List<String> segments = <String>[
    for (final (String title, String notation) in <(String, String)>[
      ('Some Other Tune', '*AT44G^ |C^ |D7 |G^ Z'),
      ('Another Tune', '*AT44A-7 |D7 |G^ |C^ Z'),
    ])
      <String>[
        '$title=Composer==Swing=C=0=',
        '$irealMusicPrefix${obfuscateIrealMusic(notation)}=Swing=120=1',
      ].join(),
  ];
  return '${segments.join('===')}===Some Other Playlist';
}

// PURPOSE: Write one iReal export page around a payload, in the shape an iReal Pro export uses: an
//          HTML file whose body carries one `irealb://` link.
// INPUTS: directory — where to write. name — the file name. payload — the decoded payload, which is
//         percent-encoded into the link. title — the page title.
// OUTPUTS: The written file. The percent-encoding is what keeps a payload with characters the URL
//          grammar reserves from being truncated at the first one.
// KEYWORDS: fixture, ireal-export, html, percent-encoding, uri
File _writeExport(
  Directory directory,
  String name,
  String payload,
  String title,
) => _write(
  directory,
  name,
  Uint8List.fromList(<int>[
    ...'<!DOCTYPE html>\n<html lang="en">\n<head><meta charset="utf-8">'
            '<title>$title</title></head>\n<body>\n'
            '<a href="irealb://${Uri.encodeComponent(payload)}">$title</a>\n'
            '</body>\n</html>\n'
        .codeUnits,
  ]),
);

// PURPOSE: Write one fixture and refuse to pretend it worked.
// INPUTS: directory — where to write. name — the file name. bytes — the whole file.
// OUTPUTS: The written file, after it has been read back to the same length; a short write would
//          otherwise produce a browser run whose failure pointed at the wrong thing.
// KEYWORDS: write, verify, fixture, io
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
