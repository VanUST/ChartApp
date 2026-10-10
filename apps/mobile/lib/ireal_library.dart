// PURPOSE: Turn an iReal export into the list of songs a reader can page through, and load that
//          list from the `.html` file an iReal Pro export usually is. A payload can hold several
//          songs separated by `===` with the last segment being the playlist name, and
//          `parseIRealPayload` deliberately parses ONE song and reports the ambiguity rather than
//          guessing where the next begins — so the enumeration happens here, exactly as
//          `packages/chart_core/tool/probe_ireal.dart` does it.
// INPUTS: A decoded `irealb://` payload, or a path to an `.html` file holding one in an
//         `irealb://` link.
// OUTPUTS: An [IRealLibrary] holding the playlist name and one [IRealSong] per segment, each with
//          its parsed [Song] and the issues the import reported. Loading a path that is missing,
//          unreadable or carries no `irealb://` link throws; the caller is expected to show that
//          message rather than to receive a silent empty library.
// KEYWORDS: ireal, import, playlist, enumeration, file-load, viewer, reader
//
// A SONG WITH A TRANSPOSITION IS IMPORTED AS WRITTEN. `parseIRealPayload` keeps the written key
// and reports the requested transposition as an issue rather than rewriting every chord; this file
// preserves that choice and carries the issue through to the song entry, where the viewer shows it.
// Nothing here re-applies or hides a transposition.

import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// The path the viewer opens when the reader gives it nothing else.
///
/// It is an absolute path on the owner's machine rather than a package asset because the file is
/// outside this repository: the export belongs to the person reading it, not to the source tree.
const String defaultIRealPath = r'C:\Users\1\Downloads\Ракета Русское.html';

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
  String get title => song.title.isEmpty ? 'Untitled' : song.title;

  @override
  String toString() =>
      'IRealSong($index, "$title", ${song.writtenBarCount} bar(s))';
}

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

// PURPOSE: Read the export a reader points at and hand back its songs, which is the only file
//          access the viewer performs.
// INPUTS: path — a path to an `.html` file that contains an `irealb://` link, or to a text file
//         holding the decoded payload's link form.
// OUTPUTS: The parsed [IRealLibrary]. Throws a [FileSystemException] when the path does not exist,
//          and a [FormatException] when it holds no `irealb://` link. Both are ordinary outcomes
//          for a typed path and are meant to be shown, not swallowed.
// KEYWORDS: file, read, irealb-link, decode, total-io, error-reporting
/// Loads the iReal library stored at [path].
Future<IRealLibrary> loadIRealLibraryFromFile(String path) async {
  final File file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('No file exists at this path.', path);
  }
  final String contents = await file.readAsString();
  final RegExpMatch? link = RegExp('irealb://([^"]*)').firstMatch(contents);
  if (link == null) {
    throw FormatException('No irealb:// link was found in this file.', path);
  }
  return parseIRealLibrary(Uri.decodeFull(link.group(1)!));
}
