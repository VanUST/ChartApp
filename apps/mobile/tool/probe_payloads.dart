// PURPOSE: Hold the synthetic iReal payloads the save/open seam probes and the browser fixture
//          writers both build from, in one file that imports no Flutter. The payloads must be
//          importable by a plain `dart run` fixture writer AND by a `flutter test` probe, and the
//          seam probes can no longer be imported from a `dart run` script because they reach
//          `dart:ui` through the app's io seam since `file_selector` landed (A55). This file is the
//          seam between those two kinds of instrument: the payload is shared, the Flutter reach is
//          not.
// INPUTS: None. Every payload is built here from a literal notation string through the library's own
//         obfuscator, so no fixture can drift from the codec.
// OUTPUTS: `syntheticPayload()` — the ten-field payload the viewer test uses; `playlistPayload()` —
//          a decoded playlist payload built from (title, notation) pairs; and the two fixed
//          three-song payloads `threeSongPlaylistPayload()` and
//          `threeSongPlaylistReorderedPayload()`.
// KEYWORDS: fixture, payload, ireal-export, shared, flutter-free, dart-run, browser-verification
import 'package:chart_core/chart_core.dart';

/// The ten-field iReal payload the viewer test uses, so a probe starts from a real import rather
/// than from a hand-built Song.
String syntheticPayload() {
  const String notation = '*AT44C^ |F^ |G7 |C^ Z';
  final String music = '$irealMusicPrefix${obfuscateIrealMusic(notation)}';
  return 'Test Tune=Test Composer==Medium Swing=C=0=$music=Medium Swing=120=1';
}

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

// PURPOSE: Build a playlist payload from a list of (title, notation) pairs, through the library's
//          own obfuscator so the fixture cannot drift from the codec. Public because the probes
//          that use it are in other files, which is also why it lives in this Flutter-free file
//          rather than beside one of them.
// INPUTS: songs — the titles and notations, in the order the export should carry them. An empty list
//         produces a payload with no song segment and the playlist name alone.
// OUTPUTS: A decoded iReal payload whose last `===` segment is the playlist name.
// KEYWORDS: fixture, playlist, payload, obfuscation, positional-ids
String playlistPayload(List<(String, String)> songs) {
  final List<String> segments = <String>[
    for (final (String title, String notation) in songs)
      <String>[
        '$title=Composer==Swing=C=0=',
        '$irealMusicPrefix${obfuscateIrealMusic(notation)}=Swing=120=1',
      ].join(),
  ];
  return '${segments.join('===')}===Test Playlist';
}

/// The three-song export `probe_setlist_seam.dart` builds its programme from.
String threeSongPlaylistPayload() => playlistPayload(_threeSongs);

/// The same three tunes in another order, which is what a re-import is checked against.
String threeSongPlaylistReorderedPayload() =>
    playlistPayload(_threeSongsReversed);
