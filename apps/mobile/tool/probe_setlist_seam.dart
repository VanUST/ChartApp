// PURPOSE: Prove, end to end and through the app's own code, that a programme saved to a `.setlist`
//          file still finds every chart it names after the export is imported again — in another
//          order, after a rename, and with the file having been through the platform's own save and
//          open seam. This is the identity proof: a codec round trip inside `chart_core` says
//          nothing about whether the app resolves an entry to a chart, and the resolution rule
//          (`setlist_resolution.dart`) is exercised here through the same function the viewer calls.
//
//          IT ALSO SAVES AN EDITED PROGRAMME, WITH A TAIL THAT IS NOT IDEMPOTENT, AND REOPENS IT,
//          and it refuses a damaged file on disk with the typed message the container produced.
// INPUTS: None. The exports are synthetic payloads built here with the library's own obfuscator, so
//         nothing is read from the owner's machine.
// OUTPUTS: One block per check on stdout, then a summary line and an exit code: 0 when every check
//          held, 1 when one did not. This file imports no Flutter, which is why plain `dart run` can
//          execute it.
// KEYWORDS: probe, setlist-file, chart-identity, re-import, reorder, rename, missing-chart,
//           corruption, app-seam, dart-io, evidence
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_source.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/setlist_document.dart';
import 'package:chartapp/setlist_import.dart';
import 'package:chartapp/setlist_resolution.dart';

int _failures = 0;
int _checks = 0;

Future<void> main() async {
  stdout.writeln('chartSourceIsFilePath=$chartSourceIsFilePath');
  final Directory directory = Directory.systemTemp.createTempSync(
    'chartapp-setlist-probe-',
  );
  final String path = '${directory.path}${Platform.pathSeparator}probe.setlist';

  try {
    await _identityProof(directory, path);
  } finally {
    directory.deleteSync(recursive: true);
  }

  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

/// The whole proof, in the order a musician meets it.
Future<void> _identityProof(Directory directory, String path) async {
  // --- A. IMPORT, BUILD, EDIT, SAVE -------------------------------------------------------------
  _section('A. import an export, build a programme, edit it, save it');
  final IRealLibrary first = parseIRealLibrary(_playlist(_threeSongs));
  _same('the export imported three songs', 3, first.songs.length);
  for (final IRealSong song in first.songs) {
    stdout.writeln(
      'song index=${song.index} id="${song.song.id}" '
      'identity=${song.identity} title="${song.title}"',
    );
  }
  final SetlistSession session = SetlistSession(
    setlist: importedSetlist(first),
  );
  _same(
    'the imported programme has an entry per song',
    3,
    session.items.length,
  );
  _same(
    'every entry carries an identity',
    true,
    session.items.every((SetlistItem item) => item.chartIdentity.isNotEmpty),
  );
  // A tail that is NOT idempotent if applied twice: a rename, a transposition and a move.
  _same('the programme was renamed', true, session.rename('Friday night'));
  _same(
    'entry 0 was transposed',
    true,
    session.updateItem(0, transposeSem: 2, notes: 'count off'),
  );
  _same('entry 2 was moved to the front', true, session.moveItem(2, 0));
  final SetlistFile file = setlistFileFor(
    session,
    modifiedAt: DateTime.utc(2026, 10, 11, 21),
  );
  final SetlistFileEncodeResult encoded = SetlistFileCodec.encode(file);
  await saveSetlistFile(path, encoded.bytes);
  final File onDisk = File(path);
  _same('the file exists after save', true, onDisk.existsSync());
  _same(
    'the file holds the encoded byte count',
    encoded.bytes.length,
    onDisk.lengthSync(),
  );
  stdout.writeln(
    'saved bytes=${encoded.bytes.length} operations=${session.log.length} '
    'entries=${session.items.length}',
  );

  // --- B. RE-IMPORT THE SAME EXPORT AND REOPEN --------------------------------------------------
  _section('B. import the SAME export again, reopen the programme');
  final IRealLibrary second = parseIRealLibrary(_playlist(_threeSongs));
  final SetlistFileDecodeResult reopened = await _readAndDecode(path);
  _same('the reopened file is the file that was saved', file, reopened.file);
  _same('no warnings on a clean file', 0, reopened.warnings.length);
  final Setlist programme = reopened.file.reducedSetlist;
  _same(
    'REOPENED_PROGRAMME_EQUAL the reopened programme is the saved one',
    true,
    programme == session.setlist,
  );
  _same(
    'the reopened programme keeps its name and its intervals',
    'Friday night/2/count off',
    '${programme.title}/${programme.items[1].transposeSem}/'
        '${programme.items[1].notes}',
  );
  _same(
    'the move survived the round trip',
    'ireal-2',
    programme.items.first.documentId,
  );
  _same(
    'every entry finds its chart',
    0,
    missingSetlistItemCount(second, programme.items),
  );
  stdout.writeln(
    'reopened entries=${programme.items.length} '
    'resolution=${_resolutionLine(second, programme)}',
  );

  // --- C. RE-IMPORT A REORDERED EXPORT ----------------------------------------------------------
  _section('C. import a REORDERED export, reopen the same programme');
  final IRealLibrary reordered = parseIRealLibrary(
    _playlist(_threeSongsReversed),
  );
  _same('the reordered export imported three songs', 3, reordered.songs.length);
  _same(
    'the reordered export really is in another order',
    false,
    _identityLine(first) == _identityLine(reordered),
  );
  _same(
    'the same charts are all present',
    true,
    <String>{for (final IRealSong s in first.songs) s.identity}.containsAll(
      <String>{for (final IRealSong s in reordered.songs) s.identity},
    ),
  );
  _same(
    'every entry still finds its chart',
    0,
    missingSetlistItemCount(reordered, programme.items),
  );
  _same(
    'each entry finds a chart with ITS OWN music, not whatever sits at its document id',
    true,
    _everyEntryNamesItsOwnMusic(reordered, programme),
  );
  stdout.writeln(
    'reordered resolution=${_resolutionLine(reordered, programme)}\n'
    '           identities=${_identityLine(reordered)}',
  );

  // --- D. RENAME A CHART ------------------------------------------------------------------------
  _section('D. rename a chart, then resolve the same programme against it');
  final IRealSong target = second.songs.firstWhere(
    (IRealSong song) => song.identity == programme.items.first.chartIdentity,
  );
  final EditSession rename = EditSession(
    document: DocumentState(song: target.song),
  );
  _same(
    'the chart was renamed through the same event a rename uses',
    true,
    rename.updateSong(title: 'Renamed by the musician', composer: 'Someone'),
  );
  final IRealLibrary renamed = IRealLibrary(
    playlistName: second.playlistName,
    songs: <IRealSong>[
      for (final IRealSong song in second.songs)
        if (song.index == target.index)
          IRealSong(
            index: song.index,
            song: rename.document.song,
            issues: song.issues,
            chartIdentity: song.identity,
          )
        else
          song,
    ],
  );
  _same(
    'the identity of the renamed chart is unchanged',
    target.identity,
    chartIdentityOf(rename.document.song),
  );
  _same(
    'every entry still finds its chart',
    0,
    missingSetlistItemCount(renamed, programme.items),
  );
  stdout.writeln(
    'renamed resolution=${_resolutionLine(renamed, programme)} '
    'identity=${chartIdentityOf(rename.document.song)}',
  );

  // --- E. A DIFFERENT EXPORT: THE MISSING-CHART DECISION ----------------------------------------
  _section('E. a DIFFERENT export: the entries that find nothing are KEPT');
  final IRealLibrary other = parseIRealLibrary(_playlist(_otherSongs));
  final int missing = missingSetlistItemCount(other, programme.items);
  _same(
    'every entry of the programme finds nothing in the other export',
    3,
    missing,
  );
  _same(
    'AND the programme is still the whole programme',
    3,
    programme.items.length,
  );
  _same(
    'AND every entry is still saved with the identity it had',
    true,
    programme.items.every((SetlistItem item) => item.chartIdentity.isNotEmpty),
  );
  stdout.writeln(
    'different export: missing=$missing of ${programme.items.length}; '
    'the musician reads "(missing chart)" on each row and the count above the '
    'list. Entries: ${programme.items.map((SetlistItem i) => i.documentId).toList()}',
  );

  // --- F. AN EDITED CHART IS A DIFFERENT IDENTITY ----------------------------------------------
  _section('F. a genuine edit of the music is a different identity');
  final EditSession edited = EditSession(
    document: DocumentState(song: target.song),
  );
  _same(
    'a bar was inserted through the real edit path',
    true,
    edited.insertBarAfter(
      sectionId: target.song.sections.first.id,
      barIndex: 0,
    ),
  );
  _same(
    'the edited chart has different content',
    false,
    chartIdentityOf(edited.document.song) == target.identity,
  );
  final IRealLibrary editedLibrary = IRealLibrary(
    playlistName: '',
    songs: <IRealSong>[
      IRealSong(
        index: 0,
        song: edited.document.song,
        chartIdentity: chartIdentityOf(edited.document.song),
      ),
    ],
  );
  _same(
    'so an entry naming the original finds nothing in a library holding the edit',
    1,
    missingSetlistItemCount(editedLibrary, <SetlistItem>[
      programme.items.first,
    ]),
  );
  stdout.writeln(
    'edited identity=${chartIdentityOf(edited.document.song)} '
    'original=${target.identity} -> MISSING, by decision, not by accident',
  );

  // --- G. TWO CHARTS WITH THE SAME MUSIC --------------------------------------------------------
  //
  // The identity names MUSIC, so two copies of one tune share it. That is the collision the function
  // is defined to have, and the reason `resolveSetlistItem` still looks at the document id: it may
  // only choose BETWEEN charts the identity already admits. This section is the check that the
  // ranking does what the documentation claims, because "it is obvious from the code" is exactly the
  // kind of claim a later edit breaks silently.
  _section(
    'G. two charts with identical music: identity admits, document id chooses',
  );
  final Song twinSource = first.songs.first.song;
  final Song twinCopy = Song(
    id: 'ireal-9',
    title: 'The Same Tune, filed twice',
    composer: twinSource.composer,
    style: twinSource.style,
    key: twinSource.key,
    tempo: twinSource.tempo,
    sections: twinSource.sections,
    staffSet: twinSource.staffSet,
  );
  final String twinIdentity = chartIdentityOf(twinSource);
  _same(
    'the two charts really do share one identity',
    twinIdentity,
    chartIdentityOf(twinCopy),
  );
  final IRealLibrary twins = IRealLibrary(
    playlistName: 'Twins',
    songs: <IRealSong>[
      IRealSong(index: 0, song: twinSource, chartIdentity: twinIdentity),
      IRealSong(
        index: 1,
        song: twinCopy,
        chartIdentity: chartIdentityOf(twinCopy),
      ),
    ],
  );
  _same(
    'an entry naming the SECOND copy resolves to the second, not the first',
    1,
    resolveSetlistItem(
      twins,
      SetlistItem(documentId: 'ireal-9', chartIdentity: twinIdentity),
    )?.index,
  );
  _same(
    'an entry whose document id is gone still resolves by identity, to the first',
    0,
    resolveSetlistItem(
      twins,
      SetlistItem(
        documentId: 'a-position-this-library-never-had',
        chartIdentity: twinIdentity,
      ),
    )?.index,
  );
  _same(
    'an entry whose MUSIC is not here resolves to NOTHING, whatever its document id says',
    null,
    resolveSetlistItem(
      twins,
      SetlistItem(
        documentId: 'ireal-9',
        chartIdentity: 'song-v1-0000000000000000',
      ),
    )?.index,
  );

  // --- H. A DAMAGED FILE ON DISK ---------------------------------------------------------------
  _section(
    'H. a damaged file on disk is refused, and never arrives as an empty programme',
  );
  final Uint8List valid = onDisk.readAsBytesSync();
  await _refusesOnDisk(
    path,
    valid.sublist(0, valid.length ~/ 2),
    'truncated on disk',
  );
  await _refusesOnDisk(
    path,
    _withByteXored(valid, containerPrefixLength + 9),
    'one header byte flipped on disk',
  );
  await _refusesOnDisk(
    path,
    Uint8List.fromList(<int>[...valid, 0x00, 0x01]),
    'two bytes appended on disk',
  );
  await _refusesOnDisk(
    path,
    _withByteSet(valid, 8, 0x02),
    'version flipped to 2',
  );
  await saveSetlistFile(path, valid);
  final Uint8List restored = await loadSetlistFile(path);
  _same(
    'the file is whole again after the damage',
    true,
    _bytesEqual(valid, restored),
  );
}

// ---------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------

/// `C^ | F^ | G7 | C^`, the chart the first export leads with.
const String _charleston = '*AT44C^ |F^ |G7 |C^ Z';

/// `D^ | E7 | D^ | E7`.
const String _fourBarsInD = '*AT44D^ |E7 |D^ |E7 Z';

/// `F^ | Bb7 | F^ | C7`.
const String _fourBarsInF = '*AT44F^ |Bb7 |F^ |C7 Z';

/// The export the programme is built from, in this order.
const List<(String, String)> _threeSongs = <(String, String)>[
  ('First Tune', _charleston),
  ('Second Tune', _fourBarsInD),
  ('Third Tune', _fourBarsInF),
];

/// The SAME three tunes, in another order, which is what a differently ordered export is.
const List<(String, String)> _threeSongsReversed = <(String, String)>[
  ('Third Tune', _fourBarsInF),
  ('First Tune', _charleston),
  ('Second Tune', _fourBarsInD),
];

/// A different export entirely: different tunes, so nothing the programme names is in it.
const List<(String, String)> _otherSongs = <(String, String)>[
  ('Some Other Tune', '*AT44G^ |C^ |D7 |G^ Z'),
  ('Another Tune', '*AT44A-7 |D7 |G^ |C^ Z'),
];

// PURPOSE: Build a playlist payload from a list of (title, notation) pairs, through the library's
//          own obfuscator so the fixture cannot drift from the codec.
// INPUTS: songs — the titles and notations, in the order the export should carry them.
// OUTPUTS: A decoded iReal payload whose last `===` segment is the playlist name.
// KEYWORDS: fixture, playlist, payload, obfuscation, positional-ids
String _playlist(List<(String, String)> songs) {
  final List<String> segments = <String>[
    for (final (String title, String notation) in songs)
      <String>[
        '$title=Composer==Swing=C=0=',
        '$irealMusicPrefix${obfuscateIrealMusic(notation)}=Swing=120=1',
      ].join(),
  ];
  return '${segments.join('===')}===Test Playlist';
}

// PURPOSE: Hand the export this probe is built around to another harness — the fixture writer a
//          browser run is driven with — so the identities printed here and the identities the
//          BROWSER computes are computed from the same bytes.
// INPUTS: None.
// OUTPUTS: The decoded payload of a three-song playlist in a fixed order.
// KEYWORDS: fixture, shared-payload, browser-verification, cross-platform, identity
/// The three-song export this probe builds its programme from.
String threeSongPlaylistPayload() => _playlist(_threeSongs);

/// The same three tunes in another order, which is what a re-import is checked against.
String threeSongPlaylistReorderedPayload() => _playlist(_threeSongsReversed);

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

/// Reads the file at [path] and decodes it, which is what the Open button does in two steps.
Future<SetlistFileDecodeResult> _readAndDecode(String path) async {
  final Uint8List bytes = await loadSetlistFile(path);
  return SetlistFileCodec.decode(bytes);
}

/// Writes [bytes] to [path] and reports the typed failure decoding it produces.
///
/// A decode that RETURNS is the failure this check exists for, and an empty programme is the worst
/// case: it looks exactly like a programme somebody had not built yet.
Future<void> _refusesOnDisk(String path, Uint8List bytes, String what) async {
  _checks++;
  await saveSetlistFile(path, bytes);
  try {
    final SetlistFileDecodeResult result = await _readAndDecode(path);
    _failures++;
    stdout.writeln('[$what] DID NOT FAIL');
    stdout.writeln(
      '    returned a programme with ${result.file.snapshot.items.length} '
      'entr(y/ies) and ${result.file.events.length} operation(s)',
    );
  } on ContainerException catch (error) {
    stdout.writeln('[$what] ${error.runtimeType}');
    stdout.writeln('    ${error.message}');
  } catch (error) {
    _failures++;
    stdout.writeln(
      '[$what] UNTYPED ${error.runtimeType}: $error -- a raw failure escaped the seam',
    );
  }
}

/// The identity of each song in [library], in order, so two libraries can be compared by music.
String _identityLine(IRealLibrary library) =>
    library.songs.map((IRealSong song) => song.identity).join(',');

/// Which loaded song index each entry of [programme] resolves to, or `MISSING`.
String _resolutionLine(IRealLibrary library, Setlist programme) => <String>[
  for (int index = 0; index < programme.items.length; index++)
    '$index->${resolveSetlistItem(library, programme.items[index])?.index ?? 'MISSING'}',
].join(' ');

/// Whether every entry resolves to a chart whose MUSIC the entry itself names.
///
/// This is the claim the reorder case turns on: resolving to *a* chart is not enough, because the
/// document ids are positional and an entry could still be pointing at the wrong tune.
bool _everyEntryNamesItsOwnMusic(IRealLibrary library, Setlist programme) {
  for (final SetlistItem item in programme.items) {
    final IRealSong? found = resolveSetlistItem(library, item);
    if (found == null || found.identity != item.chartIdentity) {
      return false;
    }
  }
  return true;
}

/// Returns a copy of [bytes] with the byte at [index] XORed with 0xFF.
Uint8List _withByteXored(Uint8List bytes, int index) {
  final Uint8List copy = Uint8List.fromList(bytes);
  copy[index] ^= 0xFF;
  return copy;
}

/// Returns a copy of [bytes] with the byte at [index] replaced by [value].
Uint8List _withByteSet(Uint8List bytes, int index, int value) {
  final Uint8List copy = Uint8List.fromList(bytes);
  copy[index] = value;
  return copy;
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

/// Prints a section heading.
void _section(String title) {
  stdout.writeln('');
  stdout.writeln('===== $title =====');
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
