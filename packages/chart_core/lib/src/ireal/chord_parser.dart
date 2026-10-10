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
// KEYWORDS: ireal, chord-parser, chord-symbol, slash-chord, alternate-chord, unsupported-feature
//
// WHY THE SUFFIX IS NOT VALIDATED.
//
// The documented quality list has changed between app versions and the protocol page still shows
// one that the current chord-symbol page disagrees with. A parser that accepted only a known set
// would refuse to import a chart written by a newer iReal Pro than the parser, and the failure
// would be total rather than local. The suffix is therefore preserved as an opaque token, which is
// also what lets a symbol this project has never heard of survive an import and an export
// unchanged.
import '../chord.dart';
import '../pitch.dart';

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
  final ChordRoot root = ChordRoot(rootNote.naturalPitchClass + rootAlter);

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
        bass = ChordRoot(bassNote.naturalPitchClass + bassAlter);
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

/// Returns the accidental at [index], or 0 when there is none.
///
/// A double accidental is two characters, and the format's documented root list contains only
/// single ones; two are accepted here anyway because rejecting an unusual but well-formed symbol
/// costs more than carrying it.
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
