// PURPOSE: Turn iReal Pro's obfuscated music body into readable chart notation and back. The
//          format is not encrypted and not base64: it is a fixed mirroring permutation applied
//          to 50-character blocks, followed by three literal token substitutions. Implementing
//          it here, rather than in the importer, keeps the transformation independently testable
//          and makes the round trip a property rather than a hope.
// INPUTS: A music body with the leading magic prefix already removed, or a decoded body to
//         scramble again. Both are plain strings; neither may contain a NUL.
// OUTPUTS: The decoded notation, or the scrambled body. Decoding is total: a body of any length
//          decodes to a string of the same length in characters, and a body shorter than two
//          blocks passes through the permutation untouched. Nothing throws.
// KEYWORDS: ireal, obfuscation, obfusc50, deobfuscation, music-body, round-trip, codec
//
// WHY THE PERMUTATION IS A MIRROR AND NOT A SWAP. The transformation is
//
//     out[i]      = input[49 - i]   for i in 0..4    (positions 0-4 mirror 45-49)
//     out[i]      = input[49 - i]   for i in 10..23  (positions 10-23 mirror 26-39)
//
// which REVERSES each of those two groups rather than exchanging them. A prose summary that says
// "swap positions 0..4 with 45..49" describes a different, also-involutive function, and applying
// it produces plausible-looking garbage: the decoded text still contains the substitution tokens
// `ZL` and `XyQ` because the characters never reached the positions the substitutions expect.
// This was measured — the swap version was implemented first and failed on a real file, and the
// mirror version from the reference implementation worked on the first attempt.
//
// WHY THE ROUND TRIP IS CHECKED. Both a mirror and a swap are involutions, so "applying it twice
// returns the input" cannot tell them apart. Only decoding real data distinguishes them, which is
// why the test suite carries a body captured from an actual iReal export.

/// The magic prefix that identifies a music field inside a song's field list.
///
/// Exactly ten characters. An off-by-one here is the most dangerous mistake in this format: the
/// body still decodes to something that looks like chords, so the corrupt result is not obviously
/// wrong and every chord in the song is silently shifted.
const String irealMusicPrefix = '1r34LbKcu7';

/// The permutation's block size in characters.
const int irealObfuscationBlockSize = 50;

/// The literal substitutions applied after the permutation, in the order they must be applied.
///
/// Order matters on the way in and is reversed on the way out. `Kcl` expands to `| x`, `LZ` to
/// ` |` and `XyQ` to three spaces; nothing overlaps, so neither direction can cascade.
const Map<String, String> irealSubstitutions = <String, String>{
  'Kcl': '| x',
  'LZ': ' |',
  'XyQ': '   ',
};

// PURPOSE: Reverse the block permutation for one full block, leaving every position outside the
//          two mirrored groups where it was.
// INPUTS: block — a string of exactly [irealObfuscationBlockSize] characters.
// OUTPUTS: The mirrored block. Shorter input is returned unchanged rather than throwing, so a
//          caller that mis-slices gets an unchanged block instead of a crash inside an import
//          loop; positions 5-9, 24-25 and 40-44 are never touched.
// KEYWORDS: permutation, mirror, involution, block
/// Mirrors the two groups of [block], leaving every other position as written.
String mirrorIrealBlock(String block) {
  if (block.length != irealObfuscationBlockSize) {
    return block;
  }
  final List<String> out = block.split('');
  for (int i = 0; i < 5; i++) {
    out[i] = block[49 - i];
    out[49 - i] = block[i];
  }
  for (int i = 10; i < 24; i++) {
    out[i] = block[49 - i];
    out[49 - i] = block[i];
  }
  return out.join();
}

// PURPOSE: Decode an iReal music body so that the chart grammar can be parsed from readable
//          notation.
// INPUTS: scrambled — the music field with [irealMusicPrefix] already stripped.
// OUTPUTS: The decoded notation, with `Kcl`, `LZ` and `XyQ` already expanded.
//
//          A trailing block of 50 or 51 characters is NOT permuted. That is not an edge case but
//          part of the format: the reference implementations stop when the remainder would be too
//          short to be a real block, so the last block stays as written. Both reference
//          implementations agree, and they express it differently — one loops while the remainder
//          exceeds 50 and skips a block with fewer than two characters after it, the other loops
//          while it exceeds 51.
// KEYWORDS: decode, deobfuscate, music-body, trailing-block, total-function
/// Decodes an obfuscated iReal music body into readable chart notation.
String deobfuscateIrealMusic(String scrambled) {
  final StringBuffer out = StringBuffer();
  String remaining = scrambled;
  while (remaining.length > irealObfuscationBlockSize + 1) {
    out.write(
      mirrorIrealBlock(remaining.substring(0, irealObfuscationBlockSize)),
    );
    remaining = remaining.substring(irealObfuscationBlockSize);
  }
  out.write(remaining);

  String decoded = out.toString();
  for (final MapEntry<String, String> entry in irealSubstitutions.entries) {
    decoded = decoded.replaceAll(entry.key, entry.value);
  }
  return decoded;
}

// PURPOSE: Re-obfuscate a decoded body, so that a body this project produces can be handed back to
//          iReal Pro and so that the round trip can be asserted as a property.
// INPUTS: notation — a decoded music body.
// OUTPUTS: The scrambled body, of the same character length as the input. Substitutions are undone
//          in the reverse of the decoding order, then the same mirroring is applied block by
//          block — the permutation is its own inverse, so no separate scrambling function exists.
// KEYWORDS: encode, obfuscate, round-trip, involution, export
/// Re-obfuscates decoded notation into an iReal music body.
String obfuscateIrealMusic(String notation) {
  String scrambled = notation;
  for (final MapEntry<String, String> entry
      in irealSubstitutions.entries.toList().reversed) {
    scrambled = scrambled.replaceAll(entry.value, entry.key);
  }

  final StringBuffer out = StringBuffer();
  String remaining = scrambled;
  while (remaining.length > irealObfuscationBlockSize + 1) {
    out.write(
      mirrorIrealBlock(remaining.substring(0, irealObfuscationBlockSize)),
    );
    remaining = remaining.substring(irealObfuscationBlockSize);
  }
  out.write(remaining);
  return out.toString();
}
