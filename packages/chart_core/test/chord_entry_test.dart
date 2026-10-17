// PURPOSE: Pin the two places a chord ENTERS the model, at the point where a mistake stops being a
//          cosmetic one: the label a palette chip shows, and the reader that turns a typed symbol
//          into a chord. Both exist because of defects that shipped.
//
//          THE BLANK CHIP. A chip in the chord palette's quality row was labelled with the quality's
//          TOKEN, and a major triad's token is the EMPTY STRING — that is correct notation, because a
//          chart writes a major triad as the root alone (`C`, never `Cmaj`). The data was right, the
//          button was blank: a musician tapped a chip with nothing written on it and the app wrote a
//          chord he had not chosen. The token and the label are two different fields
//          (`ChordQuality.token` and `chordQualityLabel`), and this file checks they stay two.
//
//          THE GUESSED CHORD. The owner's constraint for this project is that handwriting may be not
//          musical at all — «записи могут быть вообще не нотными. Например слова, или какие то иные
//          пометки. Такое не надо никогда конвертировать» — and a chord reader that takes the first
//          thing that looks like a letter and builds a chord from it is exactly the mechanism that
//          would convert a scribbled word into music nobody wrote. The reader's contract is a REFUSAL
//          with a reason, never a silently different chord, and the half of that contract the model
//          cannot give (a quality is an opaque token by design) is stated here rather than pretended
//          away: see the last case.
//
//          WHY IT MATTERS THAT THESE ARE ASSERTED RATHER THAN EYEBALLED. A blank button and a guessed
//          chord both LOOK like the feature working — the palette is drawn, the chord is written — and
//          the person who finds out is the musician at the stand, in performance.
// INPUTS: None. Keys, qualities and symbols are all constructed here.
// OUTPUTS: Pass/fail per behaviour, plus `chord.*` lines on stdout naming what every chip shows and
//          what every symbol was read as or refused for, so a failure shows the vocabulary rather
//          than only a boolean.
// KEYWORDS: test, chord-palette, chip-label, blank-button, chord-symbol, typed-input, refusal,
//           never-guess, handwriting-not-music
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The key the palette cases are measured in, so a chip's label and the chart text it writes can be
/// compared without a transposition in between.
const Key _key = Key.cMajor;

/// The spelling rule the chart text of a chord is rendered with, matching the engine's default.
const SpellingTable _table = SpellingTable();

/// The label a chip would show for [quality], read through the palette's own vocabulary.
String _labelOf(ChordQuality quality) => chordQualityLabel(quality);

/// Symbols that are NOT chord symbols, and that a reader must therefore refuse.
///
/// The list is the class of thing a recognition model hands back when the page holds words rather
/// than music, plus the malformed symbols a hurried musician types: nothing here is a chord, so a
/// reader that answers with a chord has invented one.
///
/// A SYMBOL THAT IS KNOWN TO BE OUTSIDE THE READER'S REACH IS NAMED IN THE LAST CASE instead of
/// being listed here, because a test that asserted a refusal this reader does not make would be
/// enforcing a vocabulary that does not exist yet.
const List<String> _notChordSymbols = <String>[
  '',
  '   ',
  'Привет',
  'hello',
  'xyz',
  '1234',
  '!!!',
  'H7',
  'I7',
  'Solo',
  '(C)',
  'C(',
  'C(b9',
  'C/',
  'Cmaj7/',
];

/// Symbols that ARE chord symbols, as a jazz musician types them, and the chart text each must read
/// back as. Without this half, a reader that refused everything would pass the cases above.
const List<(String, String)> _chordSymbols = <(String, String)>[
  ('Dm7', 'Dm7'),
  ('G7', 'G7'),
  ('Cmaj7', 'Cmaj7'),
  ('F#7#11', 'F#7#11'),
  ('A-7', 'A-7'),
  ('Cmaj7/A', 'Cmaj7/A'),
  ('Bb7(b9)', 'Bb7(b9)'),
  ('C6/9', 'C6/9'),
];

void main() {
  group('the chord palette', () {
    test('every chip a musician can tap has a label on it', () {
      // THE DEFECT, STATED AS THE RULE IT BROKE: a chip's label is the ONLY thing that says what the
      // chip writes, so an empty label is a button that lies by saying nothing. The major triad's
      // token is empty — correctly, because a chart writes `C` and not `Cmaj` — which is why the
      // label cannot be the token.
      final List<String> labels = <String>[];
      for (final ChordQuality quality in chordPaletteQualities) {
        final String label = _labelOf(quality);
        labels.add(label);
        stdout.writeln(
          'chord.chip quality=${quality.token.isEmpty ? '(empty token)' : quality.token} '
          'label="$label"',
        );
        expect(
          label,
          isNotEmpty,
          reason:
              'the chip for "${quality.token}" would be a BLANK button: this is the defect that '
              'shipped when the chip was labelled with the quality token, and a blank chip writes '
              'a chord the musician did not choose',
        );
        expect(
          label.trim(),
          label,
          reason: 'a label of spaces is a blank label',
        );
      }
      // Two chips with one label would be two buttons saying the same thing, which is a choice a
      // musician cannot make. The palette's qualities are one vocabulary, so their labels are one
      // vocabulary too.
      expect(
        labels.toSet().length,
        labels.length,
        reason: 'two chips with the same label offer a choice that cannot be told apart',
      );
      expect(
        labels.length,
        chordPaletteQualities.length,
        reason: 'one label per quality, none skipped',
      );
    });

    test('the chip label and the chord it writes are two fields, not one', () {
      // THE PROOF THAT THE FIX WAS THE RIGHT ONE AND NOT A SPELLING CHANGE: the chip labelled `maj`
      // writes a chord whose CHART TEXT is the root alone. The two strings differ for the major
      // triad and agree for everything else, which is exactly what makes them two fields.
      final ChordRootChoice root = chordRootChoicesFor(_key).first;
      final Chord major = chordOf(root, ChordQuality.majorTriad);
      final Chord minor = chordOf(root, ChordQuality.minorTriad);
      stdout.writeln(
        'chord.chip-roundtrip root=${root.written} '
        'major_label="${_labelOf(ChordQuality.majorTriad)}" '
        'major_text="${major.render(_key, _table)}" '
        'minor_label="${_labelOf(ChordQuality.minorTriad)}" '
        'minor_text="${minor.render(_key, _table)}"',
      );
      expect(
        ChordQuality.majorTriad.token,
        isEmpty,
        reason: 'a major triad is written with no suffix — `C`, not `Cmaj` — and that is notation',
      );
      expect(
        _labelOf(ChordQuality.majorTriad),
        isNotEmpty,
        reason: 'and its chip still has to say what tapping it will do',
      );
      expect(
        major.render(_key, _table),
        'C',
        reason: 'the chord a major-triad chip writes is the root alone',
      );
      expect(
        _labelOf(ChordQuality.minorTriad),
        'm',
        reason: 'a chip whose token is readable shows the token, so the row reads `maj m 7 m7`',
      );
      expect(minor.render(_key, _table), 'Cm');
      expect(
        _labelOf(ChordQuality.majorTriad),
        isNot(ChordQuality.majorTriad.token),
        reason: 'the label and the token must stay different values, or the blank chip comes back',
      );
    });
  });

  group('the typed chord reader', () {
    test('a symbol that is not a chord is REFUSED, with the reason named', () {
      // THE OWNER'S CONSTRAINT, ENFORCED WHERE IT CAN BE: ink may be words, and nothing may turn a
      // word into a chord. This reader is the only entrance from text into the chord model, so its
      // answer to text that is not a chord is the answer that decides whether a future recognition
      // model could quietly write music nobody played.
      for (final String symbol in _notChordSymbols) {
        final ChordSymbolParse parse = readTypedChord(symbol);
        final bool refused = !parse.ok;
        final String detail = parse is ChordSymbolRefusal
            ? '${parse.reason.name}'
                  '${parse.character == null ? '' : ' at "${parse.character}"'}'
            : 'read as ${parse.chord!.render(_key, _table)}';
        stdout.writeln('chord.refuse "$symbol" => $detail');
        expect(
          refused,
          isTrue,
          reason:
              '"$symbol" is not a chord symbol, so the reader must refuse it: a reader that '
              'answered with a chord invented music, and $detail is what it invented',
        );
        final ChordSymbolRefusal refusal = parse as ChordSymbolRefusal;
        expect(
          refusal.reason,
          isNot(ChordSymbolReason.cellNotWritable),
          reason:
              'the refusal must be about the SYMBOL and not about the cell it was aimed at, or '
              'the musician is told the wrong thing',
        );
      }
    });

    test('every symbol a musician actually types is read back as written', () {
      // The other half of the contract: a reader that refused everything would pass the case above
      // and be useless. A jazz musician writes `Dm7`, `G7`, `Cmaj7`, `F#7#11`, `A-7`, `C6/9` — this
      // is the vocabulary D28's "one action, not three" is built on.
      for (final (String typed, String expected) in _chordSymbols) {
        final ChordSymbolParse parse = readTypedChord(typed);
        final Chord? chord = parse.chord;
        final String rendered = chord == null
            ? 'refused'
            : chord.render(_key, _table);
        stdout.writeln('chord.read "$typed" => $rendered');
        expect(
          rendered,
          expected,
          reason:
              '"$typed" is how a musician names a chord, so it must be read as itself rather '
              'than refused or altered',
        );
      }
    });

    test('a symbol beginning with a note letter is preserved verbatim, never guessed into a chord', () {
      // THE BOUNDARY OF THIS READER, STATED RATHER THAN LEFT TO BE DISCOVERED. A chord's quality is
      // an OPAQUE TOKEN in the model — a chart written by a newer iReal may carry a suffix this
      // project has never heard of, and D28's one-action entry must round-trip what is typed — so
      // `Fine` is read as the root F with the suffix `ine`, exactly as `C7x` is read as C with `7x`.
      // That is NOT a validation and it must never be treated as one: the reader does not guess a
      // chord from a word, it preserves the word where a human can see it. A recognition model
      // belongs behind a vocabulary check that does not exist yet; this case is what says so.
      for (final String word in <String>['Fine', 'C7x', 'Coda']) {
        final ChordSymbolParse parse = readTypedChord(word);
        final Chord? chord = parse.chord;
        final String rendered = chord == null
            ? 'refused'
            : chord.render(_key, _table);
        stdout.writeln(
          'chord.preserve "$word" => $rendered '
          'quality="${chord?.quality.token ?? '(refused)'}"',
        );
        expect(
          rendered,
          anyOf(word, 'refused'),
          reason:
              'a symbol this reader cannot classify must come back as itself or be refused; a '
              'reader that normalised "$word" into a chord nobody wrote would be the mechanism '
              'the owner forbade',
        );
        if (chord != null) {
          expect(
            chord.quality.token,
            isNotEmpty,
            reason:
                'the unclassified part is carried in the quality token, where it stays visible: '
                'a silently empty quality would turn "$word" into the major triad on its root',
          );
        }
      }
    });
  });
}
