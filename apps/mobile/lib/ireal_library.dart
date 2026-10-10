// PURPOSE: Turn the text of an iReal export into the list of songs a reader can page through. A
//          payload can hold several songs separated by `===` with the last segment being the
//          playlist name, and `parseIRealPayload` deliberately parses ONE song and reports the
//          ambiguity rather than guessing where the next begins — so the enumeration happens here,
//          exactly as `packages/chart_core/tool/probe_ireal.dart` does it.
// INPUTS: The decoded text of an `irealb://` payload, or the whole text of an export file holding
//         one in an `irealb://` link. Never a path and never a byte stream.
// OUTPUTS: An [IRealLibrary] holding the playlist name and one [IRealSong] per segment, each with
//          its parsed [Song] and the issues the import reported. Text that carries no `irealb://`
//          link throws a [FormatException]; the caller is expected to show that message rather than
//          to receive a silent empty library.
// KEYWORDS: ireal, import, playlist, enumeration, text-parse, platform-free, viewer, reader
//
// A SONG WITH A TRANSPOSITION IS IMPORTED AS WRITTEN. `parseIRealPayload` keeps the written key
// and reports the requested transposition as an issue rather than rewriting every chord; this file
// preserves that choice and carries the issue through to the song entry, where the viewer shows it.
// Nothing here re-applies or hides a transposition.
//
// WHY THERE IS NO FILE ACCESS HERE. This library is the part of loading that is the same in a
// browser and on a desktop, so it stays free of `dart:io` and of the DOM: the web build compiles
// this file, and a browser has no filesystem for `dart:io` to reach. Where the text comes from —
// a typed path or a file the reader picked in the browser — is decided in `ireal_source.dart`,
// which routes to a per-platform implementation. The viewer injects that loader, so it never knows
// which one it got.

import 'package:chart_core/chart_core.dart';

/// One song read out of an iReal payload.
class IRealSong {
  /// Creates an entry for the song at [index] in the payload, with its import [issues].
  const IRealSong({
    required this.index,
    required this.song,
    this.issues = const <IRealParseIssue>[],
  });

  /// The song's zero-based position in the payload, used as its identity in the song list.
  final int index;

  /// The parsed chart, in its written key and with its written chords.
  final Song song;

  /// Everything the import could not represent, including a requested transposition it did not
  /// apply. Empty when the song was read completely.
  final List<IRealParseIssue> issues;

  /// The title to show, which is `Untitled` when the payload carries an empty title field.
  String get title => songDisplayTitle(song);

  @override
  String toString() =>
      'IRealSong($index, "$title", ${song.writtenBarCount} bar(s))';
}

// PURPOSE: Give the name to SHOW for a song, so the one fallback every place a name is printed needs
//          is decided once instead of being repeated at each call site and eventually drifting.
// INPUTS: song — any song, whose title may be empty.
// OUTPUTS: The title, or `Untitled` when it is empty. Never null and never the empty string, so a
//          status line that prints this can never print nothing where a name belongs.
// KEYWORDS: title, fallback, untitled, display-name, one-place
/// Returns [song]'s title, or `Untitled` when it carries none.
String songDisplayTitle(Song song) =>
    song.title.isEmpty ? 'Untitled' : song.title;

/// Every song one payload holds, plus the name of the playlist it came from.
class IRealLibrary {
  /// Creates a library with [songs] read from the playlist called [playlistName].
  const IRealLibrary({required this.playlistName, required this.songs});

  /// The final `===` segment when the payload is a playlist, otherwise the empty string.
  final String playlistName;

  /// The songs, in payload order.
  final List<IRealSong> songs;

  /// Whether the payload carried a `===` playlist name.
  bool get isPlaylist => playlistName.isNotEmpty;

  @override
  String toString() =>
      'IRealLibrary(${songs.length} song(s)${isPlaylist ? ', "$playlistName"' : ''})';
}

// PURPOSE: Enumerate the songs in a decoded payload, so the reader gets all of them instead of the
//          one song the single-song parser is able to return by design.
// INPUTS: decoded — the text after `irealb://` and after `Uri.decodeFull`, i.e. the percent
//         decoding has happened but the music field is still obfuscated. It may be short,
//         malformed or hold several songs.
// OUTPUTS: An [IRealLibrary]. A payload with no `===` is one song. A payload with `===` is a
//          playlist: every segment but the last is parsed and the last is read as the playlist
//          name, following the reference implementation. A segment that carries no music field is
//          still returned as an entry, so a malformed payload is visible as a song with no bars
//          rather than silently vanishing from a 22-song list.
// KEYWORDS: playlist, enumeration, segment-split, payload, total-function
/// Parses a decoded iReal payload into every song it contains.
IRealLibrary parseIRealLibrary(String decoded) {
  final List<String> segments = decoded.split('===');
  final bool isPlaylist = segments.length > 1;
  final String playlistName = isPlaylist ? segments.last : '';
  final List<String> songSegments = isPlaylist
      ? segments.sublist(0, segments.length - 1)
      : segments;

  final List<IRealSong> songs = <IRealSong>[];
  for (int index = 0; index < songSegments.length; index++) {
    final IRealParseResult result = parseIRealPayload(
      songSegments[index],
      documentId: 'ireal-$index',
    );
    songs.add(
      IRealSong(index: index, song: result.song, issues: result.issues),
    );
  }
  return IRealLibrary(playlistName: playlistName, songs: songs);
}

// PURPOSE: Read the `irealb://` link an iReal export wraps its payload in and parse every song it
//          holds, which is the half of loading that does not care where the text came from.
// INPUTS: contents — the whole text of an export (.html wrapper or bare payload text). source — a
//         label for where the text came from (a path on desktop, a file name in a browser), used
//         only to make the thrown [FormatException] point at the file the reader chose. It may be
//         empty, which the exception tolerates.
// OUTPUTS: The parsed [IRealLibrary]. Throws a [FormatException] when [contents] carries no
//          `irealb://` link; the message is meant to be shown, not swallowed. Never throws for an
//          empty [source].
// KEYWORDS: ireal-link, decode, shared-parse, platform-free, error-reporting
/// Parses the iReal export held in [contents], naming [source] if it is not an export.
IRealLibrary parseIRealExport(String contents, {String source = ''}) {
  final RegExpMatch? link = RegExp('irealb://([^"]*)').firstMatch(contents);
  if (link == null) {
    throw FormatException('No irealb:// link was found in this file.', source);
  }
  return parseIRealLibrary(Uri.decodeFull(link.group(1)!));
}
