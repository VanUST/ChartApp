// PURPOSE: Give a chart an identity that is a fact about its MUSIC, so that a programme can name a
//          tune and still find it after the session ends, after the export is imported again and
//          after the tune is renamed. The identity is a short string derived from the chart's own
//          written content — its key, its staves and its bars — and from nothing else.
// INPUTS: A [Song]. Nothing else is read: no file, no clock, no position in a payload, no id.
// OUTPUTS: A stable string such as `song-v1-3f1a9c024bd7e815`, and the canonical content object the
//          string is derived from, so a reader can see exactly what is covered. Pure: the same song
//          gives the same string on every platform and in every process, because the derivation
//          uses only addition, multiplication and remainder on integers below 2^53 — never a
//          bitwise operation, whose width differs between the native and the JavaScript runtime.
// KEYWORDS: identity, content-hash, fingerprint, chart, programme, re-import, rename-safe,
//           platform-independent, pure-dart
//
// WHAT THE IDENTITY IS DERIVED FROM, AND WHY THAT IS THE LINE.
//
// The subject is the WRITTEN MUSIC: the key, the staff set, and every section's label and bars, with
// each bar's chords, melody, percussion, barlines, volta, repeat signs, marks and staff text. Two
// charts with the same subject are the same tune as far as this app is concerned.
//
// Section ids are NOT part of it: an id is an address an anchor resolves through, not music, and a
// chart whose sections were re-imported under fresh ids is the same chart. Marks are written SORTED
// rather than in the set's iteration order, because the order they are painted in is presentation:
// two bars carrying the same three signs are the same bar.
//
// WHAT IS EXCLUDED, AND WHY IT IS EXACTLY THE METADATA BLOCK.
//
// `Song.id`, `title`, `composer`, `style` and `tempo` are excluded. The first is the identity being
// computed, so including it would make the function depend on its own answer. The other four are
// the whole of `SongMetadata`, which is the block `song.update` replaces: they are the fields a
// musician edits when they rename a tune, and a rename that changed a chart's identity would
// detach it from every programme that named it. Excluding the block rather than three of its four
// fields is what makes that a property of the code rather than of a list someone must remember to
// keep in step.
//
// WHAT IT IS STABLE ACROSS.
//   - a session: nothing recomputes it, and it is a pure function of content, so a saved programme
//     reopened in a later session reaches the same string;
//   - importing the same export again, including from a file with a different name;
//   - a DIFFERENT export containing the same tunes in a different ORDER, or with others removed:
//     the identity never reads a position;
//   - renaming a tune, and any other `song.update` — the metadata block is not covered;
//   - re-encoding the chart: the subject is built from the model through `ModelJson`, so two equal
//     songs produce equal canonical bytes.
//
// WHAT IT IS NOT STABLE AGAINST, BY DECISION.
//
//   - A chart whose MUSIC is genuinely edited — a chord changed, a bar inserted, a section label
//     rewritten, the key transposed, a staff added — has different content, and is therefore a
//     DIFFERENT identity with the same derived form. That is deliberate: the identity says "this is
//     the tune as it was", and a programme entry that named the old content must not silently
//     resolve to music the musician never chose. The consequence is real and is not hidden: after
//     such an edit, a saved programme finds no chart for that entry and says so (see
//     `SetlistItem.chartIdentity` and the app's missing-chart rule) rather than playing the wrong
//     tune or dropping the row.
//   - Two DIFFERENT tunes whose written music is identical — the same changes in the same key under
//     two titles, or two identical copies of one chart — get the SAME identity. This is the
//     collision the function is defined to have: it identifies music, not documents. A programme
//     naming one of them resolves to the first loaded chart carrying that music.
//   - A future change to the derivation. The algorithm's name is inside the string (`song-v1-`), so
//     an id written by a later build is recognisable rather than merely wrong, but it will not match
//     an id from this one.
//
// WHY THE FINGERPRINT IS NOT A CRYPTOGRAPHIC HASH, AND WHAT THAT COSTS.
//
// This package has no runtime dependencies, by design, so there is no SHA-256 to call. The
// fingerprint is two independent polynomial hashes modulo the Mersenne prime 2^31-1, with bases
// below 2^21 so that `base * state` stays inside the 53 bits a JavaScript number represents exactly
// (`chart_core` runs in a browser). Two 31-bit values are rendered side by side as sixteen hex
// characters, so the fingerprint is 62 bits. For a library of ten thousand charts the chance any two
// colliding is about 5e-12 by the birthday bound; the cost of a collision is a programme entry
// resolving to the wrong chart, which the app cannot detect, so the number is stated rather than
// implied. It is not resistant to an adversary constructing two charts with one fingerprint; nobody
// is attacking a musician's setlist, and saying so is cheaper than pretending otherwise.
library;

import 'dart:convert';

import '../oplog/oplog.dart';
import '../song/bar.dart';
import '../song/section.dart';
import '../song/song.dart';

/// The prefix every identity carries: the algorithm's name and its version.
///
/// It is part of the string rather than a separate field so that an identity written by one build
/// can be recognised by another without a lookup, and so that a future derivation is a new prefix
/// rather than a silent change of meaning for the strings already in somebody's files.
const String chartIdentityPrefix = 'song-v1-';

/// The canonical content object an identity is derived from.
///
/// Returned as the model's own JSON (through [ModelJson]) rather than as a bespoke encoding, so that
/// the bytes an identity is computed over and the bytes a `.chart` file stores for the same values
/// come from one implementation and cannot disagree. `id`, `title`, `composer`, `style` and `tempo`
/// are absent, and section ids are absent, for the reasons stated in this library's header.
///
/// A song with no sections has an empty `sections` list, which is an ordinary chart of no music and
/// not an error.
Map<String, Object?> canonicalChartContent(Song song) => <String, Object?>{
  'key': ModelJson.key(song.key),
  'staffSet': ModelJson.staffSet(song.staffSet),
  'sections': <Object?>[
    for (final Section section in song.sections)
      <String, Object?>{
        'label': ModelJson.sectionLabel(section.label),
        'bars': <Object?>[
          for (final Bar bar in section.bars) _canonicalBar(bar),
        ],
      },
  ],
};

// PURPOSE: Derive the identity of the music in [song], so that a programme can name a chart by what
//          it contains rather than by where it sat in an export.
// INPUTS: song — any song, including one with no sections and one whose metadata is empty.
// OUTPUTS: `song-v1-` followed by sixteen lower-case hex characters. Deterministic and
//          platform-independent: the same song gives the same string on every run, on every
//          platform, with no clock, no file and no random seed involved. Two equal songs give equal
//          identities, which is the property a round trip relies on; the ways two UNEQUAL songs can
//          nevertheless agree are stated in this library's header.
// KEYWORDS: identity, fingerprint, content-address, deterministic, platform-independent, total
/// Returns the content-derived identity of [song].
String chartIdentityOf(Song song) =>
    '$chartIdentityPrefix${_fingerprint(jsonEncode(canonicalChartContent(song)))}';

// PURPOSE: Answer whether a string was produced by this build's derivation, so a caller holding an
//          id of unknown origin — an entry in an older `.setlist`, or a `documentId` from a payload
//          — can tell an identity from a session id without guessing from its length.
// INPUTS: value — any string, including the empty one.
// OUTPUTS: True when [value] begins with [chartIdentityPrefix]. It says nothing about whether the
//          identity is one this library would produce for any song; it is a shape test, not a
//          verification.
// KEYWORDS: identity, shape-test, prefix, legacy-detection, not-a-verification
/// Whether [value] looks like an identity this library produces.
bool isChartIdentity(String value) => value.startsWith(chartIdentityPrefix);

// PURPOSE: Write one bar in the canonical form, with its mark set in a fixed order, so that two
//          bars carrying the same signs produce the same bytes whatever order they were added in.
// INPUTS: bar — any bar.
// OUTPUTS: The bar's JSON exactly as [ModelJson] writes it, except that `marks` is sorted by name.
// KEYWORDS: canonical-form, bar, marks, sorted, order-independent
Map<String, Object?> _canonicalBar(Bar bar) {
  final Map<String, Object?> json = ModelJson.bar(bar);
  final List<Object?> marks = json['marks']! as List<Object?>;
  final List<String> names = <String>[
    for (final Object? mark in marks) mark! as String,
  ]..sort();
  json['marks'] = names;
  return json;
}

// PURPOSE: Turn canonical text into a short, fixed-width fingerprint that is the same string on
//          every Dart runtime, which is the constraint that shapes the whole derivation.
// INPUTS: text — the JSON text of a canonical content object. May be empty.
// OUTPUTS: Sixteen lower-case hex characters: two 31-bit polynomial hashes, modulo 2^31-1, with
//          different bases and different initial states, each rendered as eight hex characters.
//
//          WHY NO BITWISE OPERATION APPEARS HERE. On the Dart VM an `int` is 64 bits and `&`, `|`,
//          `<<` and `>>>` operate on that width; on the web an `int` is a JavaScript number, where
//          those same operators are 32-bit and their result is signed. A fingerprint built from
//          them would therefore be one string in the app on a tablet and a different one in the
//          same app in a browser, which would break exactly the promise this library makes. Only
//          addition, multiplication and remainder are used, and the state is kept below 2^31 while
//          the base is below 2^21, so every intermediate product is below 2^52 and exact in a
//          double. Those three operations mean the same thing on both runtimes.
//
//          An empty input is legal and gives the fingerprint of the empty string rather than
//          throwing: a song with no sections is still a song.
// KEYWORDS: fingerprint, polynomial-hash, rabin, mersenne-prime, platform-independent, no-bitwise
String _fingerprint(String text) {
  // 2^31 - 1, a Mersenne prime. The modulus is what keeps the state inside 31 bits.
  const int prime = 2147483647;
  // Both bases are below 2^21, so `state * base` stays below 2^52 for every state below `prime`.
  const int baseA = 2097143; // 2^21 - 9
  const int baseB = 524287; // 2^19 - 1
  int stateA = 1;
  int stateB = 1;
  for (final int byte in utf8.encode(text)) {
    stateA = (stateA * baseA + byte) % prime;
    stateB = (stateB * baseB + byte) % prime;
  }
  return '${stateA.toRadixString(16).padLeft(8, '0')}'
      '${stateB.toRadixString(16).padLeft(8, '0')}';
}
