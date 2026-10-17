// PURPOSE: Turn one chord symbol from a chart into the chord model. Kept apart from the tokenizer
//          because the two do different jobs: the tokenizer decides where a symbol ends, this
//          decides what it means, and a chord whose meaning is unsupported should fail here
//          without costing the caller the rest of the chart.
// INPUTS: A chord symbol as written, such as `Bb7`, `F#/C#`, `D-`, `Bh7,` (the trailing separator
//         is not expected — the tokenizer strips it) or `Bb7(A7b9)/F`.
// OUTPUTS: A Chord, or NULL when the symbol uses a feature the model does not yet carry. Null
//          rather than an exception or a wrong chord: an invisible root or a suffix this model
//          cannot hold must be reported, not silently flattened into a chord that sounds wrong
//          and looks plausible. The caller counts nulls and reports them; it does not drop them.
//          Every chord that IS returned carries the root and slash bass spelled exactly as the
//          symbol wrote them (see [_rootOf]): the key is not consulted, and a chart written in
//          sharps comes back in sharps.
// KEYWORDS: ireal, chord-parser, chord-symbol, slash-chord, alternate-chord, unsupported-feature,
//           written-spelling
//
// WHY THE SUFFIX IS NOT VALIDATED.
//
// The documented quality list has changed between app versions and the protocol page still shows
// one that the current chord-symbol page disagrees with. A parser that accepted only a known set
// would refuse to import a chart written by a newer iReal Pro than the parser, and the failure
// would be total rather than local. The suffix is therefore preserved as an opaque token, which is
// also what lets a symbol this project has never heard of survive an import and an export
// unchanged.
//
// THE ROOT'S SPELLING IS PRESERVED FOR THE SAME REASON THE SUFFIX IS, and it is the same kind of
// data: the musician wrote `F#h` and not `Gbh`. Storing only the sounding pitch class and asking
// the key to spell it later produced exactly that swap on the owner's own export — `F#h` came back
// `Gbh` and `A/C#` came back `A/Db` in a chart in A minor — because a flat-preferring key answers a
// chromatic pitch with a flat. The spelling is written into the model at the point it is read.
import '../chord.dart';
import '../pitch.dart';
import '../spelling_table.dart';

/// Parses [text] as an iReal chord symbol.
///
/// Returns null when the symbol cannot be represented: currently that means an invisible root
/// (`W`, written as in `W/A` to show a bass note with no chord above it), which the chord model
/// has no field for. Everything else the documented grammar allows is accepted.
Chord? parseIRealChord(String text) {
  if (text.isEmpty) {
    return null;
  }
  int i = 0;

  final String rootLetter = text[i];
  if (rootLetter == 'W') {
    // Recognised and deliberately refused, rather than misread as a pitch called W. Recorded as a
    // known gap in the decision journal; a caller that meets one counts it.
    return null;
  }

  final NoteLetter? rootNote = _letterOf(rootLetter);
  if (rootNote == null) {
    return null;
  }
  i++;
  final int rootAlter = _consumeAccidental(text, i);
  if (rootAlter != 0) {
    i++;
  }
  final ChordRoot root = _rootOf(rootNote, rootAlter);

  // The quality runs to the first `/`, or to a `(` that holds a chord root. A bracket holding
  // anything else is a parenthesised added tone and belongs to the suffix, which is how the
  // documented `7(add13)` is told apart from the documented `Bb7(A7b9)`. The distinction is made
  // on the contents because the bracket alone does not carry it.
  final int qualityStart = i;
  while (i < text.length) {
    final String c = text[i];
    if (c == '/') {
      break;
    }
    if (c == '(') {
      final int close = text.indexOf(')', i);
      if (close == -1) {
        i = text.length;
        break;
      }
      final String inside = text.substring(i + 1, close);
      if (inside.isNotEmpty && _letterOf(inside[0]) != null) {
        break;
      }
      i = close + 1;
      continue;
    }
    i++;
  }
  final ChordQuality quality = ChordQuality(text.substring(qualityStart, i));

  ChordRoot? bass;
  if (i < text.length && text[i] == '/') {
    i++;
    if (i < text.length) {
      final NoteLetter? bassNote = _letterOf(text[i]);
      if (bassNote != null) {
        i++;
        final int bassAlter = _consumeAccidental(text, i);
        if (bassAlter != 0) {
          i++;
        }
        bass = _rootOf(bassNote, bassAlter);
      }
      // A slash followed by something that is not a letter leaves the bass unset and lets the
      // remaining characters be examined as an alternate, which is what a malformed symbol most
      // likely meant. Nothing is dropped silently: the characters end up inside the quality or
      // the alternate rather than disappearing.
    }
  }

  Chord? alternate;
  final int open = text.indexOf('(', i);
  if (open != -1) {
    final int close = text.lastIndexOf(')');
    if (close > open) {
      // Recursive: an alternate is a whole chord, and the format does not forbid one that carries
      // its own alternate. A nested alternate that cannot be represented makes the OUTER chord
      // null too, because returning a chord whose alternate was silently dropped would lose a
      // symbol the musician wrote.
      alternate = parseIRealChord(text.substring(open + 1, close));
      if (alternate == null) {
        return null;
      }
    }
  }

  return Chord(root: root, quality: quality, bass: bass, alternate: alternate);
}

// PURPOSE: Build a chord root — or a slash bass — from the letter and the accidental THE SOURCE
//          WROTE, so the chord remembers how it was spelled instead of handing that decision to a
//          key a second time. This is the one function in the import that turns a written note into
//          model data, and it exists so root and bass cannot differ in how they record a spelling.
// INPUTS: letter — the letter the symbol showed (A to G, never `W`, which is refused above).
//         alter — the accidental that followed it, in semitones: -1 for `b`, +1 for `#`, 0 for a
//         bare letter.
// OUTPUTS: A ChordRoot whose sounding pitch is `letter + alter` reduced to a pitch class, whose
//          [ChordRoot.written] is exactly that letter-and-alteration pair, and whose preference is
//          the same direction expressed the way the spelling table understands it — sharp for `#`,
//          flat for `b`, automatic for a bare letter, where "automatic" asks no key either because
//          a bare letter IS the written spelling.
//
//          WHY BOTH FIELDS AND NOT ONLY THE PREFERENCE. A preference is a DIRECTION and cannot
//          express a letter: in A minor the pitch class 11 is the key's own B, so the table answers
//          `B` for it whatever direction it is given, and a written `Cb` would come back wrong. The
//          written note is therefore the authority and the preference is the fallback a caller
//          keeps for a root that has no written note at all.
// KEYWORDS: ireal, chord-root, slash-bass, spelling, written-note, accidental, no-key-consulted
ChordRoot _rootOf(NoteLetter letter, int alter) => ChordRoot(
  letter.naturalPitchClass + alter,
  written: WrittenNote(letter, alter),
  preference: alter > 0
      ? SpellingPreference.sharp
      : alter < 0
      ? SpellingPreference.flat
      : SpellingPreference.automatic,
);

/// Returns the accidental at [index], or 0 when there is none.
///
/// Exactly ONE accidental is consumed. The format's documented root list carries only single ones,
/// so a second `b` or `#` is left where it is and ends up inside the quality suffix, preserved as
/// written. The consequence is stated plainly rather than hidden: a double-flat root would sound a
/// semitone above the way it is written. That is a recorded limitation, not a silent one, and the
/// symbol still round-trips through an import and an export unchanged.
int _consumeAccidental(String text, int index) {
  if (index >= text.length) {
    return 0;
  }
  if (text[index] == '#') {
    return 1;
  }
  if (text[index] == 'b') {
    return -1;
  }
  return 0;
}

/// Maps an uppercase letter character to a NoteLetter, or null when it is not one.
NoteLetter? _letterOf(String character) {
  switch (character) {
    case 'C':
      return NoteLetter.c;
    case 'D':
      return NoteLetter.d;
    case 'E':
      return NoteLetter.e;
    case 'F':
      return NoteLetter.f;
    case 'G':
      return NoteLetter.g;
    case 'A':
      return NoteLetter.a;
    case 'B':
      return NoteLetter.b;
    default:
      return null;
  }
}
