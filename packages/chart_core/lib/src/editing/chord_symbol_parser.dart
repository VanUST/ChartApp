// PURPOSE: Turn the chord symbol a musician TYPES — `Dm7`, `G7`, `Cmaj7`, `F#7#11`, `Bb7(b9)/F`
//          — into the chord model, so that writing a chord is one action instead of three separate
//          decisions. Owner decision D28 records why: a jazz musician NAMES a chord by writing it,
//          and the palette's root-then-quality-then-extension sequence charges him a tap for each
//          part of a word he already knows how to spell.
// INPUTS: The typed symbol as text. Nothing else: a chord stores a SOUNDING root, and a typed
//         accidental is the instruction that decides how it is written, so there is no key to
//         consult. Only a root typed with NO accidental is left to the chart's own key when the
//         symbol is rendered.
// OUTPUTS: A [ChordSymbolParse] that either carries a [Chord] or carries a REASON it could not be
//          read. A refusal is never a silently different chord: the first character that cannot be
//          placed ends the parse with a reason naming it. This is the rule `parseIRealChord`
//          already follows for an import, applied to typing, where the musician is present and can
//          be told what was wrong.
// KEYWORDS: chord-symbol, typed-input, fast-entry, chord-parser, root, accidental, slash-bass,
//           alternate-chord, refusal-reason, d28
//
// WHY THIS IS A SECOND PARSER AND NOT A CALL TO `parseIRealChord`.
//
// `parseIRealChord` is the IMPORT's reader and it has a different job. It takes the format's opaque
// suffix — the token is preserved verbatim because a chart written by a newer iReal must survive an
// import — and it reports a failure as a bare null, because the importer counts nulls and moves on.
// Typing needs the opposite on both counts: the musician is told WHICH character failed and why,
// and a typed suffix must be a suffix the model can hold, because a typed chord is an edit the
// musician asked for rather than data that must be preserved. It also accepts the spellings a
// musician actually types, which the format's own grammar does not carry: `-` for minor, `Δ` and
// `^` for major seventh, and `°` and `ø` for diminished and half-diminished.
//
// WHAT THE MODEL CANNOT HOLD, SAID PLAINLY.
//
// A chord stores a root as a SOUNDING pitch class plus a three-valued `SpellingPreference` (A8), so
// an arbitrary written root is not representable: `Cb` and `B` are one pitch class and a
// preference cannot say "write this one on a C". The parser therefore preserves the typed
// accidental's DIRECTION (flat or sharp) by setting `SpellingPreference` whenever the key would
// otherwise choose the other direction, and a root typed on a letter the key does not use may come
// back on the key's own letter. This is a named limitation of the model and not of this parser, and
// the alternative — a fifth field pinning one spelling forever — would make a chord that no longer
// transposes consistently.
import '../chord.dart';
import '../pitch.dart';
import '../spelling_table.dart';

/// What a typed chord symbol produced: a chord, or the reason it could not be read.
///
/// A value rather than a nullable [Chord] because a typed symbol has to be ANSWERED — a musician
/// who types `Cmaj7x` must be told which character stopped it, and a null gives the sheet nothing
/// to say. The two cases are the whole result: there is no "partially understood" chord, because a
/// chord silently missing its extension is exactly the class of defect the blank major-triad chip
/// was (see `chordQualityLabel`).
sealed class ChordSymbolParse {
  /// Const constructor for the two cases.
  const ChordSymbolParse();

  /// The chord that was read, or null when nothing was.
  Chord? get chord;

  /// Whether a chord was read.
  bool get ok => chord != null;
}

/// A symbol that was read into [chord].
class ChordSymbolRead extends ChordSymbolParse {
  /// Creates a successful parse.
  const ChordSymbolRead(this.chord);

  @override
  final Chord chord;

  @override
  String toString() => 'read($chord)';
}

/// A symbol that could not be read, with a reason a musician can act on.
class ChordSymbolRefusal extends ChordSymbolParse {
  /// Creates a refusal naming [reason] and, when there is one, the [character] that stopped it.
  const ChordSymbolRefusal(this.reason, {this.character});

  /// Why the symbol could not be read. It is a REASON rather than a sentence, so both languages say
  /// it through the catalogue and the core stays free of presentation.
  final ChordSymbolReason reason;

  /// The character the parse stopped on, or null when the input as a whole was the problem (an
  /// empty symbol, for instance).
  final String? character;

  @override
  Chord? get chord => null;

  @override
  String toString() =>
      'refused(${reason.name}${character == null ? '' : ' at "$character"'})';
}

/// Why a typed chord symbol could not be read.
///
/// An enum rather than a string so the sheet can put the reason into the catalogue, and so a new
/// reason cannot be added without the switch that renders it being told.
enum ChordSymbolReason {
  /// Nothing was typed.
  empty,

  /// The symbol does not begin with one of the seven note letters.
  notANoteLetter,

  /// A bracket was opened and not closed.
  unclosedBracket,

  /// The symbol ends at a slash: it names a bass note and then does not write one.
  ///
  /// A slash followed by anything that is not a chord root is part of the quality suffix — `C6/9` is
  /// a sixth chord with an added ninth — and is preserved verbatim rather than refused, because the
  /// suffix is opaque by design. What is refused is a slash with NOTHING after it, where the reader
  /// would otherwise have to invent either a bass or a quality out of the punctuation.
  badBass,

  /// The root's accidental is malformed: more than two in a row, or a mixed pair such as `b#`.
  badAccidental,

  /// The symbol was read, but the cell it was aimed at cannot hold a chord — the bar is gone or the
  /// beat is outside it. Reported as a refusal rather than as a success with nothing appended,
  /// because a musician who typed a chord is owed the answer "it did not go in".
  cellNotWritable,
}

/// The letter a typed chord root names, or null when [character] is not one.
///
/// Lowercase is accepted, because a musician typing quickly on a soft keyboard does not always hold
/// shift, and `dm7` and `Dm7` name the same chord. The rest of the symbol stays case-sensitive:
/// `M` and `m` are different qualities and the model writes them differently.
NoteLetter? typedRootLetter(String character) => switch (character) {
  'C' || 'c' => NoteLetter.c,
  'D' || 'd' => NoteLetter.d,
  'E' || 'e' => NoteLetter.e,
  'F' || 'f' => NoteLetter.f,
  'G' || 'g' => NoteLetter.g,
  'A' || 'a' => NoteLetter.a,
  'B' || 'b' => NoteLetter.b,
  _ => null,
};

// PURPOSE: Answer whether a character that starts a bracket or follows a slash is a chord ROOT,
//          which is a stricter question than "is it a note letter" and has to be, because one
//          character is both.
// INPUTS: character — the character to test.
// OUTPUTS: True for an UPPERCASE A–G, false for everything else, including a lowercase letter.
//
//          WHY UPPERCASE, AND WHY THIS IS LOAD-BEARING. `b` is the letter B and it is also the flat
//          sign, and the chord grammar uses the same character for both: `Bb7` is B-flat seven and
//          `(b9)` is a flat ninth. A bracket was decided by asking `typedRootLetter` — which answered
//          yes for the `b` of `(b9)` — so `Bb7(b9)` was read as Bb7 with an ALTERNATE chord of B9 and
//          rendered `Bb7(B9)`: a symbol nobody wrote, produced by a reader that looked as if it had
//          accepted the input. The answer is that a bracket or a slash introduces a chord ROOT, and a
//          chord root is written with a capital letter in this format's own grammar and in every
//          chart this project has seen, while a flat is lowercase. Two questions, two functions.
// KEYWORDS: chord-symbol, root-detection, bracket, slash-bass, lowercase-flat-ambiguity
/// Whether [character] is an uppercase note letter, and therefore a chord root.
bool isTypedChordRoot(String character) {
  if (character.length != 1) {
    return false;
  }
  final int code = character.codeUnitAt(0);
  return code >= 0x41 && code <= 0x47;
}

// PURPOSE: Read one typed chord symbol into the model, telling the musician what stopped it when it
//          cannot be read. It is the single entrance to typed chord entry, so the sheet, a future
//          keyboard handler and any probe all read a symbol the same way.
// INPUTS: text — what was typed, with any surrounding whitespace ignored. key — the key the chart
//         is written in, which decides how a root with no typed accidental is spelled.
// OUTPUTS: A [ChordSymbolRead] carrying the chord, or a [ChordSymbolRefusal] naming the reason and
//          the offending character. Nothing throws: bad input is an ordinary answer here, because
//          it arrives from a person.
//
//          WHAT IT ACCEPTS. A root letter with an optional `b`/`#` (including a double one); a
//          quality suffix the model can carry as a token (`m`, `-`, `maj`, `M`, `Δ`, `^`, `7`, `m7`,
//          `m7b5`, `dim`, `°`, `ø`, `aug`, `sus4`, `add9`, `7b9`, `7#11`, `maj7#11` …); an optional
//          `/bass` slash chord; and an optional `(alternate chord)` in parentheses, which the model
//          carries as a nested chord. The suffix is taken VERBATIM once it is known to be
//          placeable, so a tension this project has never heard of still round-trips through a
//          save.
// KEYWORDS: chord-symbol, parsing, typed-input, root, quality, slash-bass, alternate, refusal
/// Reads the typed chord symbol [text], spelled in [key].
ChordSymbolParse readTypedChord(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const ChordSymbolRefusal(ChordSymbolReason.empty);
  }
  int index = 0;

  final NoteLetter? rootLetter = typedRootLetter(trimmed[index]);
  if (rootLetter == null) {
    return ChordSymbolRefusal(
      ChordSymbolReason.notANoteLetter,
      character: trimmed[index],
    );
  }
  index++;
  final int rootAlter = _readAccidental(trimmed, index);
  if (rootAlter.abs() > 2) {
    return ChordSymbolRefusal(
      ChordSymbolReason.badAccidental,
      character: trimmed[index],
    );
  }
  if (rootAlter != 0) {
    index += rootAlter.abs();
  }
  final int rootPitchClass = normalizePitchClass(
    rootLetter.naturalPitchClass + rootAlter,
  );

  // The quality runs to the first `/` that is followed by a NOTE LETTER, or to a `(` that holds a
  // chord root. Everything else — `6/9`, `(b9)`, `add13` — belongs to the suffix and is preserved
  // verbatim.
  //
  // WHY THE SLASH IS DECIDED BY WHAT FOLLOWS IT, AND NOT BY THE SLASH ALONE. `C6/9` is a sixth chord
  // with an added ninth and `Cmaj7/A` is a chord over a bass note; the two spellings are the same
  // character and different music. The model already carries this exact distinction — a quality is an
  // opaque token, a bass is a sounding root — so the parser has to make it, and it makes it on the
  // contents for the same reason the bracket is decided that way: the punctuation alone does not
  // carry it.
  //
  // AND A SLASH AT THE END OF THE SYMBOL IS NOT A SUFFIX. `C/` is a chord with the bass left off, so
  // the bass reader below must see the slash and refuse it as `badBass`. It used to be consumed into
  // the suffix instead, because the break happened only when a note letter followed: `C/` was read as
  // the root C with the quality `/` and rendered `C/`, a symbol nobody wrote, produced by a reader
  // that looked as if it had accepted the input — the same failure the bracket and the lowercase flat
  // are decided against elsewhere in this file. A trailing slash has nothing after it, so it cannot
  // start a suffix and it cannot name a bass; refusing it is the only answer that is not an invention.
  final int qualityStart = index;
  while (index < trimmed.length) {
    final String character = trimmed[index];
    if (character == '/') {
      final int next = index + 1;
      if (next >= trimmed.length || isTypedChordRoot(trimmed[next])) {
        break;
      }
      index++;
      continue;
    }
    if (character == '(') {
      final int close = trimmed.indexOf(')', index);
      if (close == -1) {
        return ChordSymbolRefusal(
          ChordSymbolReason.unclosedBracket,
          character: character,
        );
      }
      final String inside = trimmed.substring(index + 1, close);
      if (inside.isNotEmpty && isTypedChordRoot(inside[0])) {
        break;
      }
      index = close + 1;
      continue;
    }
    index++;
  }
  final String suffix = trimmed.substring(qualityStart, index);

  ChordRoot? bass;
  if (index < trimmed.length && trimmed[index] == '/') {
    index++;
    if (index >= trimmed.length) {
      return const ChordSymbolRefusal(ChordSymbolReason.badBass);
    }
    final NoteLetter? bassLetter = isTypedChordRoot(trimmed[index])
        ? typedRootLetter(trimmed[index])
        : null;
    if (bassLetter == null) {
      return ChordSymbolRefusal(
        ChordSymbolReason.badBass,
        character: trimmed[index],
      );
    }
    index++;
    final int bassAlter = _readAccidental(trimmed, index);
    if (bassAlter.abs() > 2) {
      return ChordSymbolRefusal(
        ChordSymbolReason.badAccidental,
        character: trimmed[index],
      );
    }
    if (bassAlter != 0) {
      index += bassAlter.abs();
    }
    bass = bassAlter == 0
        ? ChordRoot(normalizePitchClass(bassLetter.naturalPitchClass))
        : _rootFor(
            normalizePitchClass(bassLetter.naturalPitchClass + bassAlter),
            bassAlter,
          );
  }

  Chord? alternate;
  final int open = trimmed.indexOf('(', index);
  if (open != -1) {
    final int close = trimmed.lastIndexOf(')');
    if (close > open) {
      final ChordSymbolParse inner = readTypedChord(
        trimmed.substring(open + 1, close),
      );
      final Chord? above = inner.chord;
      if (above == null) {
        // A nested alternate that cannot be read makes the OUTER symbol a refusal too: returning a
        // chord whose alternate was silently dropped would lose the symbol the musician typed.
        return inner;
      }
      alternate = above;
    }
  }

  return ChordSymbolRead(
    Chord(
      root: rootAlter == 0
          ? ChordRoot(rootPitchClass)
          : _rootFor(rootPitchClass, rootAlter),
      quality: ChordQuality(suffix),
      bass: bass,
      alternate: alternate,
    ),
  );
}

// PURPOSE: Build a chord root from a sounding pitch class and the accidental the musician actually
//          typed, pinning the spelling to the direction that was typed.
// INPUTS: pitchClass — the sounding root. typedAlter — the accidental the musician typed, negative
//         for a flat, positive for a sharp. Zero is handled by the caller, which is why this takes
//         only the two cases that carry an instruction.
// OUTPUTS: A [ChordRoot] whose `SpellingPreference` is sharp for a typed `#` and flat for a typed
//          `b`, so the symbol renders the way it was written in every key.
//
//          WHY THE KEY IS NOT AN INPUT, WHICH IS THE WHOLE POINT OF THIS FUNCTION. The key's
//          spelling rule is the DEFAULT a chart falls back on when nothing has been said; a typed
//          accidental IS something said, and the earlier version of this function consulted the key
//          first and kept `automatic` whenever the key's answer merely failed to contradict the
//          typed one — so `F#7` typed into C major rendered as `Gb7`. The direction is not a
//          tie-break against the key; it replaces it.
// KEYWORDS: chord-root, spelling-preference, typed-spelling, direction-overrides-key
ChordRoot _rootFor(int pitchClass, int typedAlter) => ChordRoot(
  pitchClass,
  preference: typedAlter > 0
      ? SpellingPreference.sharp
      : SpellingPreference.flat,
);

/// The accidental at [index], or 0 when there is none.
///
/// A `b` is read as a flat and a `#` as a sharp; two identical ones are a double flat or a double
/// sharp, which is the widest the model's own `shortestAlter` ever produces. The result is signed
/// and its MAGNITUDE is the number of characters consumed, so the caller advances the offset and
/// derives the alteration from one call. A mixed pair such as `b#` reads as a single flat followed
/// by a sharp, and the sharp then lands in the quality suffix and is preserved as written — it is
/// not silently dropped, which is the rule this parser follows everywhere.
///
/// ONE AMBIGUITY, RESOLVED THE WAY THE FORMAT RESOLVES IT: a `b` directly after a letter could be a
/// flat or the first character of a quality, and `Bb` is B-flat while `Bbm` is B-flat minor. The
/// root's accidental is consumed first and the suffix takes what follows, exactly as
/// `parseIRealChord` does, so the two readers agree about the same string.
int _readAccidental(String text, int index) {
  if (index >= text.length) {
    return 0;
  }
  final int direction = switch (text[index]) {
    '#' => 1,
    'b' => -1,
    _ => 0,
  };
  if (direction == 0) {
    return 0;
  }
  final String next = index + 1 < text.length ? text[index + 1] : '';
  if (next == text[index]) {
    return direction * 2;
  }
  return direction;
}
