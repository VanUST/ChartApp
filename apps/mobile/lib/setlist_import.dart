// PURPOSE: Turn the playlist an iReal export carries into the programme model, so the owner's real
//          data — songs that arrive in order under a playlist name — lands in a setlist document
//          rather than only in a list of loaded charts. This is the bridge between the two
//          identities the app holds: a setlist entry names a chart, and an imported song has the
//          identity the importer gave it.
// INPUTS: The loaded [IRealLibrary], in payload order, with its playlist name.
// OUTPUTS: A [Setlist] whose title is the playlist name and whose entries name every song, in the
//          order the export carried them, with no transposition and no notes. The songs are not
//          copied: an entry holds the chart's IDENTITY, not its music, which is what lets one chart
//          appear in several programmes without being duplicated.
// KEYWORDS: setlist, import, ireal, playlist, bridge, document-identity, rename-safe
//
// HOW THE TWO IDENTITIES LINE UP, AND WHERE THE JOIN IS HONEST.
//
// A [SetlistItem] names a chart by `documentId`; an imported song carries `Song.id`, which
// `parseIRealLibrary` sets to `ireal-<index>` through `parseIRealPayload`. The bridge is therefore
// `entry.documentId == song.id`, and it is exact for the library that is loaded.
//
// IT IS RENAME-SAFE. The trap the join has to avoid is keying on the title: a musician renaming a
// chart would leave every setlist entry pointing at a name no song has, and the programme would
// silently empty itself. A rename goes through `song.update`, which replaces the song's metadata and
// keeps its `id` (see `SongUpdateEvent` / `transposeSong`, both of which carry the id through), so an
// entry keeps naming the same chart after the chart is renamed.
//
// IT IS POSITIONAL, AND THAT IS THE HONEST LIMIT. `ireal-0`, `ireal-1`, … are positions in the
// export, not durable identities: re-importing a DIFFERENT export reuses those ids for different
// songs. A setlist saved to a `.setlist` file and opened beside another export would therefore point
// at the wrong charts. Nothing here invents a stronger join — a content hash or a generated uuid —
// because the app has no place to persist one yet: the `.setlist` container is deliberately out of
// scope, so a setlist lives exactly as long as the library it was built from, and within that life
// the positional id is exact. This is a named limitation rather than a silent one.
//
// WHY THE SETLIST IS BUILT EVEN FOR A SINGLE SONG. A payload with no `===` is one song, but it is
// still a programme of one, and building it uniformly means the scene path has no special case to
// get wrong; the title is simply empty, which is the model's own "not yet named" state.
import 'package:chart_core/chart_core.dart';

import 'ireal_library.dart';

/// Builds the setlist the loaded iReal playlist describes.
Setlist importedSetlist(IRealLibrary library) => Setlist(
  id: _setlistIdFor(library),
  title: library.playlistName,
  items: <SetlistItem>[
    for (final IRealSong entry in library.songs)
      SetlistItem(documentId: entry.song.id),
  ],
);

// PURPOSE: Give the imported programme a stable identity of its own, so its events name one
//          document and cannot collide with a chart's own id.
// INPUTS: library — the loaded playlist, whose name is used when it has one.
// OUTPUTS: `playlist-<name>` when the payload carried a name, and `ireal-playlist` otherwise. The
//          `playlist-` prefix keeps it visibly distinct from the `ireal-<n>` chart ids, so a
//          setlist event can never be mistaken for a chart's and the two logs stay separable.
// KEYWORDS: setlist-id, document-id, namespace, collision-safety, untitled-fallback
String _setlistIdFor(IRealLibrary library) {
  final String name = library.playlistName.trim();
  return name.isEmpty ? 'ireal-playlist' : 'playlist-$name';
}
