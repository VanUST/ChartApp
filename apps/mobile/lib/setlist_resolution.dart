// PURPOSE: Decide which loaded chart a programme entry names, in one place, so the sheet's rows, the
//          play action, the scene meaning, the missing-chart count and a `dart run` probe cannot
//          disagree about the answer — and so the rule can be exercised without a window.
// INPUTS: The loaded [IRealLibrary] and a [SetlistItem].
// OUTPUTS: The loaded [IRealSong] the entry names, or null when this library holds none, plus the
//          count of entries that answer null. Flutter-free and `dart:io`-free, so it runs under
//          plain `dart run` in `apps/mobile/tool/probe_setlist_seam.dart` against the same code the
//          app uses.
// KEYWORDS: setlist, programme, resolution, chart-identity, document-id, missing-chart, flutter-free
//
// WHY AN ENTRY IS RESOLVED BY IDENTITY, AND WHAT THE DOCUMENT ID IS STILL FOR.
//
// An entry carries two names for its chart. `documentId` is the id the chart's own operation log is
// keyed by, which an iReal import assigns from the song's POSITION in the payload: exact for the
// library the programme was built from, and meaningless beside a different export.
// `chartIdentity` is a fact about the chart's music, and it is what survives a session, a re-import
// and a rename.
//
// THE GUARANTEE: an entry that carries an identity can only ever resolve to a chart whose music it
// names. The identity is not a tie-breaker among candidates chosen some other way — it is a
// requirement, and a library that holds no chart with that music resolves the entry to nothing.
//
// What the document id still does is DISAMBIGUATE BETWEEN charts that have the same music. Two
// identical charts in one playlist — the same changes under two titles, which is a real thing in an
// export — share an identity by construction, and without a second fact the app could not tell which
// of the two an entry meant; nor could it, when the same library is still loaded, keep showing each
// row under its own title. So a chart matching BOTH names wins over one matching the identity alone.
// That is the only power the document id has over an entry that carries an identity: it can choose
// between charts the identity already admits, and it can never admit one the identity refuses.
//
// When an entry carries NO identity — one written before identities were persisted, or built by hand
// in a test — the document id is all there is, and it is used exactly as it was before identities
// existed. That is a deliberate, named limit rather than a silent one: such an entry is safe only
// against the export it was built from.
//
// Section ids aside, nothing here reads a title: a musician renaming a tune changes neither name, so
// a programme that named it still finds it.
import 'package:chart_core/chart_core.dart';

import 'ireal_library.dart';

// PURPOSE: Find the loaded chart one programme entry names.
// INPUTS: library — the songs that are loaded. item — the entry, whose identity is required when it
//         carries one and whose document id chooses between charts that carry the same music.
// OUTPUTS: The matching [IRealSong], or null when the library holds no chart with the entry's music
//          — never a chart the identity refuses, whichever document id that chart holds. Never
//          throws: a missing chart is an ordinary state the caller reports, and an entry that
//          resolves to nothing is still a real entry with a real position in the running order.
// KEYWORDS: resolution, chart-identity, document-id-disambiguation, missing-chart, ranked-match
/// Returns the loaded chart [item] names, or null when this library holds none.
IRealSong? resolveSetlistItem(IRealLibrary library, SetlistItem item) {
  if (item.chartIdentity.isEmpty) {
    for (final IRealSong entry in library.songs) {
      if (entry.song.id == item.documentId) {
        return entry;
      }
    }
    return null;
  }
  IRealSong? byIdentityOnly;
  for (final IRealSong entry in library.songs) {
    if (entry.identity != item.chartIdentity) {
      continue;
    }
    if (entry.song.id == item.documentId) {
      return entry;
    }
    byIdentityOnly ??= entry;
  }
  return byIdentityOnly;
}

// PURPOSE: Count the entries of a programme that name no chart the loaded library holds, so one
//          sentence can say how many there are instead of a musician counting rows.
// INPUTS: library — the loaded songs. items — the programme's entries, in order.
// OUTPUTS: How many of [items] resolve to nothing through [resolveSetlistItem]. Zero for a programme
//          built from the library that is loaded, and what the musician reads after opening a
//          `.setlist` file beside a library that does not hold every chart it names.
// KEYWORDS: missing-chart, count, honest-report, programme
/// Returns how many of [items] name no chart [library] holds.
int missingSetlistItemCount(IRealLibrary library, Iterable<SetlistItem> items) {
  int missing = 0;
  for (final SetlistItem item in items) {
    if (resolveSetlistItem(library, item) == null) {
      missing++;
    }
  }
  return missing;
}
