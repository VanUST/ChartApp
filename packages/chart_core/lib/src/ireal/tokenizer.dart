// PURPOSE: Turn decoded iReal chart notation into a token stream. Tokenising separately from
//          assembling means the awkward part — deciding where one symbol ends and the next begins,
//          when the same letter means different things in different positions — is testable on
//          its own, and the assembler can then be written as a plain switch over token types.
// INPUTS: The decoded music body, as produced by `deobfuscateIrealMusic`.
// OUTPUTS: A list of tokens in reading order, each carrying the character offset it started at so
//          that a diagnostic can point at the input rather than at a token index. Tokenising is
//          total: an unrecognised character becomes an [IRealUnknownToken] rather than an
//          exception, because refusing to tokenise the rest of a chart over one bad byte would
//          lose the other bars too.
// KEYWORDS: ireal, tokenizer, lexer, chart-notation, cell-model, positional-grammar
//
// THE AMBIGUITY THIS FILE EXISTS TO RESOLVE.
//
// The format reuses single letters: `s` is the small-chord-size marker AND the first letter of
// `sus`; `l` restores normal size and also appears inside `alt`; `A` and `a` are a chord root and
// the start of `add` respectively. The rule that separates them is POSITION, not the character:
//
//   - A chord root is an UPPERCASE letter A-G, or W for an invisible root.
//   - Everything after a root is the quality suffix, consumed greedily until a delimiter, so
//     `sus`, `alt`, `add`, `min`, `maj` and digits all end up inside the chord where they belong.
//   - Because `s` and `l` as size markers appear in a position where a root could appear, and
//     neither is a valid root, a leading lowercase `s` or `l` can only be a marker.
//
// So `sEh,A7,` tokenises as: size small, chord `Eh`, separator, chord `A7`, separator. And
// `C7ppF7` tokenises as chord `C7`, slash repeat, slash repeat, chord `F7` — four cells, which is
// exactly one 4/4 bar and matches the worked example in the format document.
import '../song/bar.dart';
import '../song/time_signature.dart';

/// One token of decoded chart notation.
sealed class IRealToken {
  /// Creates a token that began at [offset] in the decoded body.
  const IRealToken(this.offset);

  /// Character offset of this token's first character, for diagnostics.
  final int offset;
}

/// A rehearsal mark or section label, such as `*A`, `*B`, `*i` or `*V`.
final class SectionToken extends IRealToken {
  /// Creates a section token whose label text is [label], without the leading `*`.
  const SectionToken(super.offset, this.label);

  /// The label as written: a letter, `i` for intro, or `V` for verse.
  final String label;
}

/// A time signature, such as `T44`.
final class TimeSignatureToken extends IRealToken {
  /// Creates a time signature token.
  const TimeSignatureToken(super.offset, this.value);

  /// The meter it denotes.
  final TimeSignature value;
}

/// Which side of a bar a barline belongs to.
///
/// The bar model has one [Barline.double] value because the side the bar sits on says whether it
/// is `[` or `]`. The tokenizer has to keep the distinction, because the two mean different
/// things to the assembler: an opening barline decorates the bar about to be built, a closing one
/// ends the bar already being built.
enum BarlineRole {
  /// The barline is drawn at the left edge of the next bar.
  opening,

  /// The barline is drawn at the right edge of the current bar.
  closing,
}

/// A barline.
final class BarlineToken extends IRealToken {
  /// Creates a barline token of [kind] playing [role].
  const BarlineToken(super.offset, this.kind, this.role);

  /// Which barline it is.
  final Barline kind;

  /// Whether it opens the next bar or closes the current one.
  final BarlineRole role;
}

/// An alternative-ending marker, `N0` to `N3`.
final class EndingToken extends IRealToken {
  /// Creates an ending token carrying [number], where 0 is the unnumbered bracket.
  const EndingToken(super.offset, this.number);

  /// The figure in the bracket, or 0 for an unnumbered one.
  final int number;
}

/// The repeat-previous-bar symbol, `x` or `r`.
final class RepeatPreviousToken extends IRealToken {
  /// Creates a repeat-previous token.
  const RepeatPreviousToken(super.offset, this.kind);

  /// Whether it repeats one bar or two.
  final RepeatPrevious kind;
}

/// The slash-repeat symbol, `p`.
final class SlashRepeatToken extends IRealToken {
  /// Creates a slash-repeat token.
  const SlashRepeatToken(super.offset);
}

/// The no-chord symbol, `n`.
final class NoChordToken extends IRealToken {
  /// Creates a no-chord token.
  const NoChordToken(super.offset);
}

/// A chord-size marker, `s` or `l`.
final class ChordSizeToken extends IRealToken {
  /// Creates a chord-size token.
  const ChordSizeToken(super.offset, this.size);

  /// The size that takes effect from here until changed.
  final ChordSize size;
}

/// A symbol drawn on the bar: segno, coda or fermata.
final class MarkToken extends IRealToken {
  /// Creates a mark token.
  const MarkToken(super.offset, this.mark);

  /// Which symbol.
  final BarMark mark;
}

/// Staff text, such as `<D.C. al Coda>` or `<*72Solo>`.
final class StaffTextToken extends IRealToken {
  /// Creates a staff-text token.
  const StaffTextToken(super.offset, this.text, this.verticalPosition);

  /// The text with any vertical-position prefix removed.
  final String text;

  /// The vertical position 0-74 asked for by a `*NN` prefix, or null when none was given.
  ///
  /// Kept as data rather than folded into the text, because the number is a layout instruction and
  /// the text is content; a renderer that had to re-parse the prefix out of the string would be
  /// one round trip away from showing `*72` to a musician.
  final int? verticalPosition;
}

/// Vertical space, one to three `Y` at the start of a system.
final class SystemBreakToken extends IRealToken {
  /// Creates a system-break token of [amount] lines of space.
  const SystemBreakToken(super.offset, this.amount);

  /// How many `Y` were written.
  final int amount;
}

/// One cell of the chart consumed by nothing: a space.
final class CellToken extends IRealToken {
  /// Creates a cell-advance token.
  const CellToken(super.offset);
}

/// A separator that packs the next chord into the current cell instead of the next one, `,`.
final class ChordSeparatorToken extends IRealToken {
  /// Creates a chord-separator token.
  const ChordSeparatorToken(super.offset);
}

/// A chord as written, not yet parsed.
final class ChordToken extends IRealToken {
  /// Creates a chord token carrying the raw [text].
  const ChordToken(super.offset, this.text);

  /// The chord symbol exactly as it appeared.
  final String text;
}

/// A character the grammar does not recognise.
final class UnknownToken extends IRealToken {
  /// Creates an unknown token carrying [character].
  const UnknownToken(super.offset, this.character);

  /// The character that could not be classified.
  final String character;
}

// PURPOSE: Split decoded notation into tokens, recording each one's offset.
// INPUTS: notation — the decoded music body.
// OUTPUTS: The tokens, in reading order. An empty body yields an empty list.
//
//          Every character is consumed exactly once: an unrecognised character produces one
//          UnknownToken rather than being skipped, so that the offsets of all following tokens
//          still line up with the input and a diagnostic can point at a real position. A caller
//          that wants to reject a chart containing unknown characters can count them; a caller
//          that wants to import what it can, can ignore them.
// KEYWORDS: tokenize, longest-match, positional-rule, total-function, diagnostics
/// Splits decoded iReal notation into tokens.
List<IRealToken> tokenizeIReal(String notation) {
  final List<IRealToken> tokens = <IRealToken>[];
  int i = 0;
  while (i < notation.length) {
    final int start = i;
    final String c = notation[i];

    // A chord root is an uppercase A-G, or W for an invisible root. Checked before the marker
    // letters because a root is the only uppercase-A-G case; S, Q, T, N, Y and Z are not roots
    // and so cannot be confused with one.
    if (_isChordRoot(c)) {
      i = _consumeChord(notation, i);
      tokens.add(ChordToken(start, notation.substring(start, i)));
      continue;
    }

    switch (c) {
      case '*':
        // A section label is EXACTLY ONE character. The documented set is `*A`, `*B`, `*C`, `*D`,
        // `*V` and `*i`.
        //
        // Consuming following letters instead — which this tokenizer did first, on the reasoning
        // that the format does not forbid a longer label — swallows the root of the chord that
        // follows, because a chord root is a letter too: `*AB-` became the label `AB` plus a
        // stray `-`. A longer label is not distinguishable from a label followed by a chord, so
        // one character is the only reading that works. The real export caught this at three
        // offsets; no synthetic case had put a chord directly after a section marker.
        i++;
        if (i < notation.length && _isSectionLabelCharacter(notation[i])) {
          i++;
        }
        tokens.add(SectionToken(start, notation.substring(start + 1, i)));

      case 'T':
        // A time signature, `T` followed by two or three digits.
        i++;
        final int digitsStart = i;
        while (i < notation.length && _isDigit(notation[i])) {
          i++;
        }
        final String digits = notation.substring(digitsStart, i);
        tokens.add(TimeSignatureToken(start, _parseTimeSignature(digits)));

      case 'N':
        i++;
        final int endingStart = i;
        while (i < notation.length && _isDigit(notation[i])) {
          i++;
        }
        tokens.add(
          EndingToken(
            start,
            int.tryParse(notation.substring(endingStart, i)) ?? 0,
          ),
        );

      case '|':
        i++;
        tokens.add(BarlineToken(start, Barline.single, BarlineRole.closing));

      case '[':
        i++;
        tokens.add(BarlineToken(start, Barline.double, BarlineRole.opening));

      case ']':
        i++;
        tokens.add(BarlineToken(start, Barline.double, BarlineRole.closing));

      case '{':
        i++;
        tokens.add(
          BarlineToken(start, Barline.repeatStart, BarlineRole.opening),
        );

      case '}':
        i++;
        tokens.add(BarlineToken(start, Barline.repeatEnd, BarlineRole.closing));

      case 'Z':
        i++;
        tokens.add(BarlineToken(start, Barline.finalBar, BarlineRole.closing));

      case 'S':
        i++;
        tokens.add(MarkToken(start, BarMark.segno));

      case 'Q':
        i++;
        tokens.add(MarkToken(start, BarMark.coda));

      case 'f':
        i++;
        tokens.add(MarkToken(start, BarMark.fermata));

      case 'Y':
        // One to three at the start of a system; a longer run is accepted and clamped, because
        // the amount is a layout hint and refusing the chart over a fourth Y would be
        // disproportionate.
        i++;
        int amount = 1;
        while (i < notation.length && notation[i] == 'Y') {
          i++;
          amount++;
        }
        tokens.add(SystemBreakToken(start, amount > 3 ? 3 : amount));

      case '<':
        i++;
        final int textStart = i;
        while (i < notation.length && notation[i] != '>') {
          i++;
        }
        final String raw = notation.substring(textStart, i);
        if (i < notation.length) {
          i++; // consume the closing '>'
        }
        tokens.add(_staffTextToken(start, raw));

      case 'x':
        i++;
        tokens.add(RepeatPreviousToken(start, RepeatPrevious.oneBar));

      case 'r':
        i++;
        tokens.add(RepeatPreviousToken(start, RepeatPrevious.twoBars));

      case 'p':
        i++;
        tokens.add(SlashRepeatToken(start));

      case 'n':
        i++;
        tokens.add(NoChordToken(start));

      case 's':
        i++;
        tokens.add(ChordSizeToken(start, ChordSize.small));

      case 'l':
        i++;
        tokens.add(ChordSizeToken(start, ChordSize.normal));

      case ',':
        i++;
        tokens.add(ChordSeparatorToken(start));

      case ' ':
        i++;
        tokens.add(CellToken(start));

      default:
        i++;
        tokens.add(UnknownToken(start, c));
    }
  }
  return tokens;
}

/// Whether [c] can start a chord: an uppercase letter A-G, or W for an invisible root.
bool _isChordRoot(String c) {
  if (c == 'W') {
    return true;
  }
  final int code = c.codeUnitAt(0);
  return code >= 0x41 && code <= 0x47; // 'A'..'G'
}

/// Whether [c] may appear in a section label.
///
/// Letters and digits only: a label is a name, and allowing a barline or a space into it would
/// swallow the rest of the chart when a file omitted the label entirely.
bool _isSectionLabelCharacter(String c) {
  final int code = c.codeUnitAt(0);
  final bool upper = code >= 0x41 && code <= 0x5A;
  final bool lower = code >= 0x61 && code <= 0x7A;
  return upper || lower || _isDigit(c);
}

/// Whether [c] is an ASCII digit.
bool _isDigit(String c) {
  final int code = c.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// Whether [c] may appear inside a chord's quality suffix.
///
/// The set is the union of the characters the documented qualities use: digits for extensions,
/// `-` for minor, `^` and `v` for major, `o` and `h` for diminished and half-diminished, `+` for
/// augmented, `#`/`x` and `b` for alterations, and the letters of the words `sus`, `add`, `alt`,
/// `min`, `maj`, `dim`, `aug`.
///
/// A character OUTSIDE this set ends the chord, and that is what makes `C7ppF7` four tokens rather
/// than one: `p` is the slash-repeat symbol and no documented quality contains it. Consuming
/// everything up to a delimiter instead — which is what this tokenizer did first — swallowed both
/// slashes into a single nonsense chord, and the format document's own worked example caught it.
const String _qualityCharacters = '0123456789+#-^bohsualtdmijngvx';

/// Whether [c] is a character a quality suffix may contain.
bool _isQualityCharacter(String c) => _qualityCharacters.contains(c);

/// Consumes a whole chord starting at [start], returning the index just past it.
///
/// The root is already known to be at [start]. What follows is an optional accidental, the quality
/// suffix, an optional `/bass`, and an optional `(alternate)`.
///
/// A bracket is ambiguous in this format and is resolved by its CONTENTS, not by the bracket:
/// `Bb7(A7b9)` is an alternate chord because `A7b9` begins with a root, while the documented
/// `7(add13)` is part of the suffix because `add13` does not. Guessing from the bracket alone
/// would either lose a written added tone or invent an alternate chord that is not there.
int _consumeChord(String notation, int start) {
  int i = start + 1;
  if (i < notation.length && (notation[i] == '#' || notation[i] == 'b')) {
    i++;
  }

  while (i < notation.length) {
    final String c = notation[i];
    if (_isQualityCharacter(c)) {
      i++;
      continue;
    }
    if (c == '(') {
      final int close = notation.indexOf(')', i);
      if (close == -1) {
        // An unclosed bracket: consume to the end rather than losing the rest of the chart to one
        // malformed annotation.
        return notation.length;
      }
      final String inside = notation.substring(i + 1, close);
      if (inside.isNotEmpty && _isChordRoot(inside[0])) {
        break; // an alternate chord: leave the bracket for the caller
      }
      i = close + 1; // a parenthesised added tone: part of the suffix
      continue;
    }
    break;
  }

  if (i < notation.length && notation[i] == '/') {
    int j = i + 1;
    if (j < notation.length && _isChordRoot(notation[j])) {
      j++;
      if (j < notation.length && (notation[j] == '#' || notation[j] == 'b')) {
        j++;
      }
      i = j;
    }
    // A slash with no root after it is left outside the chord, so the symbol still round-trips
    // and the next token still starts at a real position.
  }

  if (i < notation.length && notation[i] == '(') {
    final int close = notation.indexOf(')', i);
    return close == -1 ? notation.length : close + 1;
  }
  return i;
}

/// Builds a staff-text token, splitting off a `*NN` vertical-position prefix when present.
StaffTextToken _staffTextToken(int offset, String raw) {
  if (!raw.startsWith('*') || raw.length < 3) {
    return StaffTextToken(offset, raw, null);
  }
  final String two = raw.substring(1, 3);
  final int? position = int.tryParse(two);
  if (position == null) {
    return StaffTextToken(offset, raw, null);
  }
  return StaffTextToken(offset, raw.substring(3), position);
}

/// The time signatures the protocol document lists, keyed by the characters after `T`.
///
/// A table rather than arithmetic, because the format is not consistent about it. Every entry but
/// one is numerator-then-single-digit-denominator — `44` is 4/4 and `68` is 6/8 — but the document
/// lists `T12` as 12/8, which that pattern would read as 1/2. The table follows the document, and
/// an argument it does not list falls back to the pattern, which is what makes `T128` 12/8 as
/// well. The conflict is recorded rather than resolved silently: a chart that really meant 1/2
/// would be read as 12/8.
const Map<String, TimeSignature> _documentedTimeSignatures =
    <String, TimeSignature>{
      '44': TimeSignature(numerator: 4, denominator: 4),
      '34': TimeSignature(numerator: 3, denominator: 4),
      '24': TimeSignature(numerator: 2, denominator: 4),
      '54': TimeSignature(numerator: 5, denominator: 4),
      '64': TimeSignature(numerator: 6, denominator: 4),
      '74': TimeSignature(numerator: 7, denominator: 4),
      '22': TimeSignature(numerator: 2, denominator: 2),
      '32': TimeSignature(numerator: 3, denominator: 2),
      '58': TimeSignature(numerator: 5, denominator: 8),
      '68': TimeSignature(numerator: 6, denominator: 8),
      '78': TimeSignature(numerator: 7, denominator: 8),
      '98': TimeSignature(numerator: 9, denominator: 8),
      '12': TimeSignature(numerator: 12, denominator: 8),
    };

/// Parses a `T` argument such as `44`, `68` or `128` into a meter.
///
/// Looks the argument up in [_documentedTimeSignatures] first and falls back to reading the last
/// character as the denominator and the rest as the numerator. An argument that fits neither
/// returns four-four rather than throwing, because a wrong meter is visible to the musician while
/// a refused import loses the song.
TimeSignature _parseTimeSignature(String digits) {
  final TimeSignature? documented = _documentedTimeSignatures[digits];
  if (documented != null) {
    return documented;
  }
  if (digits.length >= 2) {
    final int? numerator = int.tryParse(digits.substring(0, digits.length - 1));
    final int? denominator = int.tryParse(digits.substring(digits.length - 1));
    if (numerator != null &&
        denominator != null &&
        numerator > 0 &&
        denominator > 0) {
      return TimeSignature(numerator: numerator, denominator: denominator);
    }
  }
  return TimeSignature.fourFour;
}
