// PURPOSE: Pin the tokenizer's positional rules and the chord parser's reading of a symbol. The
//          tokenizer is where the format's letter reuse is resolved, so its behaviour on the
//          document's own worked examples is the evidence that the rules are right rather than
//          merely plausible.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation. Several cases are taken verbatim from the iReal Pro
//          protocol document, including the bar that is exactly four cells long.
// KEYWORDS: test, ireal, tokenizer, chord-parser, cell-model, worked-example, hand-derived
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The token kinds of [notation], as a compact list for readable expectations.
List<String> kindsOf(String notation) => <String>[
  for (final IRealToken token in tokenizeIReal(notation))
    switch (token) {
      SectionToken() => 'section:${token.label}',
      TimeSignatureToken() => 'time:${token.value}',
      BarlineToken() => 'bar:${token.kind.name}/${token.role.name}',
      EndingToken() => 'ending:${token.number}',
      RepeatPreviousToken() => 'repeatPrev:${token.kind.name}',
      SlashRepeatToken() => 'slash',
      NoChordToken() => 'nc',
      ChordSizeToken() => 'size:${token.size.name}',
      MarkToken() => 'mark:${token.mark.name}',
      StaffTextToken() =>
        'text:${token.text}${token.verticalPosition == null ? '' : '@${token.verticalPosition}'}',
      SystemBreakToken() => 'break:${token.amount}',
      CellToken() => 'cell',
      ChordSeparatorToken() => 'sep',
      ChordToken() => 'chord:${token.text}',
      UnknownToken() => 'unknown:${token.character}',
    },
];

void main() {
  group('tokenizer resolves letter reuse by position', () {
    test('a bar of two chords with two slashes is four cells, as the document shows', () {
      // The document's own example: |C7ppF7| is one 4/4 bar, so the two `p` symbols must each
      // consume a cell. That is what makes `p` a cell-consuming token rather than a decoration.
      expect(kindsOf('C7ppF7'), <String>[
        'chord:C7',
        'slash',
        'slash',
        'chord:F7',
      ]);
    });

    test('a comma separates chords without consuming a cell', () {
      // A7,p,p,p, is also four cells: the commas add nothing.
      expect(kindsOf('A7,p,p,p,'), <String>[
        'chord:A7',
        'sep',
        'slash',
        'sep',
        'slash',
        'sep',
        'slash',
        'sep',
      ]);
    });

    test('a leading s or l is a size marker, never a quality', () {
      // The ambiguity the positional rule exists for: `s` starts `sus`, but it can only start a
      // chord suffix AFTER a root, and it is not a root, so here it can only be a marker.
      expect(kindsOf('sEh,A7,'), <String>[
        'size:small',
        'chord:Eh',
        'sep',
        'chord:A7',
        'sep',
      ]);
      expect(kindsOf('lD- D-/C'), <String>[
        'size:normal',
        'chord:D-',
        'cell',
        'chord:D-/C',
      ]);
    });

    test('sus and alt are part of the chord, not markers', () {
      expect(kindsOf('G7sus4'), <String>['chord:G7sus4']);
      expect(kindsOf('C7alt'), <String>['chord:C7alt']);
      expect(kindsOf('Csus'), <String>['chord:Csus']);
    });

    test('an accidental belongs to the root', () {
      expect(kindsOf('Bbh7, Bb7(A7b9)'), <String>[
        'chord:Bbh7',
        'sep',
        'cell',
        'chord:Bb7(A7b9)',
      ]);
    });
  });

  group('tokenizer reads the structural symbols', () {
    test('barlines carry which side of the bar they belong to', () {
      // `[` and `]` differ only by side, and the assembler needs the difference: one decorates
      // the bar about to be built, the other ends the bar being built.
      expect(kindsOf('|'), <String>['bar:single/closing']);
      expect(kindsOf('['), <String>['bar:double/opening']);
      expect(kindsOf(']'), <String>['bar:double/closing']);
      expect(kindsOf('{'), <String>['bar:repeatStart/opening']);
      expect(kindsOf('}'), <String>['bar:repeatEnd/closing']);
      expect(kindsOf('Z'), <String>['bar:finalBar/closing']);
    });

    test('time signatures take the last digit as the denominator', () {
      // T68 is 6/8, not 6/80.
      expect(kindsOf('T44'), <String>['time:4/4']);
      expect(kindsOf('T34'), <String>['time:3/4']);
      expect(kindsOf('T68'), <String>['time:6/8']);
      expect(kindsOf('T78'), <String>['time:7/8']);
      // The documented list is not internally consistent: it gives T12 as 12/8, while the
      // numerator-then-denominator pattern every other entry follows would read it as 1/2. The
      // document wins, and T128 reaches the same answer by the pattern.
      expect(kindsOf('T12'), <String>['time:12/8']);
      expect(kindsOf('T128'), <String>['time:12/8']);
      expect(kindsOf('T98'), <String>['time:9/8']);
    });

    test('a parenthesised added tone stays in the suffix, an alternate chord does not', () {
      // The bracket alone does not say which it is; the contents do. `add13` is not a chord root,
      // `A7b9` is.
      expect(kindsOf('C7(add13)'), <String>['chord:C7(add13)']);
      expect(kindsOf('Bb7(A7b9)'), <String>['chord:Bb7(A7b9)']);
    });

    test('sections, endings, marks, space and position', () {
      expect(kindsOf('*A'), <String>['section:A']);
      expect(kindsOf('*i'), <String>['section:i']);
      expect(kindsOf('*V'), <String>['section:V']);
      // A section label is one character, so the chord root that follows stays a chord root. This
      // is the case the real export failed on: reading the label greedily made `*AB-` into the
      // label `AB` plus a stray `-`.
      expect(kindsOf('*AB-'), <String>['section:A', 'chord:B-']);
      expect(kindsOf('[*iB- '), <String>[
        'bar:double/opening',
        'section:i',
        'chord:B-',
        'cell',
      ]);
      expect(kindsOf('N1'), <String>['ending:1']);
      expect(kindsOf('N0'), <String>['ending:0']);
      expect(kindsOf('S'), <String>['mark:segno']);
      expect(kindsOf('Q'), <String>['mark:coda']);
      expect(kindsOf('f'), <String>['mark:fermata']);
      expect(kindsOf('YYY'), <String>['break:3']);
    });

    test('repeat symbols and no-chord', () {
      expect(kindsOf('x'), <String>['repeatPrev:oneBar']);
      expect(kindsOf('r'), <String>['repeatPrev:twoBars']);
      expect(kindsOf('n'), <String>['nc']);
    });

    test('staff text keeps a vertical position apart from the words', () {
      // The number is a layout instruction and the words are content; folding them together
      // would be one round trip away from showing `*72` to a musician.
      expect(kindsOf('<D.C. al Coda>'), <String>['text:D.C. al Coda']);
      expect(kindsOf('<*72Solo>'), <String>['text:Solo@72']);
      expect(kindsOf('<Fine>'), <String>['text:Fine']);
    });

    test('an unrecognised character becomes a token, not an exception', () {
      // Refusing to tokenise the rest of a chart over one bad byte would lose the other bars.
      expect(kindsOf('C@E'), <String>['chord:C', 'unknown:@', 'chord:E']);
    });

    test('every token carries an offset into the input', () {
      const String notation = '*A|C7';
      final List<IRealToken> tokens = tokenizeIReal(notation);
      expect(tokens.map((IRealToken t) => t.offset).toList(), <int>[0, 2, 3]);
      // And the offsets point at the characters that produced them.
      expect(notation[tokens[0].offset], '*');
      expect(notation[tokens[1].offset], '|');
      expect(notation[tokens[2].offset], 'C');
    });

    test('the tokens reconstruct the input exactly', () {
      // What this proves: no character is LOST. Slicing the input by the recorded offsets and
      // reassembling it returns the input character for character, so a tokenizer that skipped a
      // byte would fail here.
      //
      // What this does NOT prove, stated because it was checked rather than assumed: it would not
      // have caught the two boundary bugs found in this tokenizer. `C7ppF7` collapsing into one
      // chord token still reconstructs to `C7ppF7`, and `*AB-` splitting into the label `AB` plus
      // a stray `-` still reconstructs to `*AB-`. Both are wrong BOUNDARIES, not lost characters.
      // Those were caught by the exact token-kind assertions above and, for the section label,
      // only by the real export. A property that holds for a wrong tokenisation is worth having
      // and is not worth overstating.
      //
      // The corpus includes a form this tokenizer does not fully understand — a bass written after
      // an alternate chord — because the property must hold there too: the characters are kept as
      // an unrecognised token rather than dropped, which is what keeps every following offset
      // pointing at a real position.
      const List<String> corpus = <String>[
        '*A|C7ppF7|',
        '[*iB- |x |E- |x ]{*AB- |x |A |D,B/D# |E- |B- |C#,F# |B-,F#,  ||',
        'T44{*AC ^7 |A-7 |D-9 |G7#5 Z',
        'T44{C |A- |N1D- |G7 } |N2D- G7 |C6 Z',
        'sEh,A7,lD- D-/C Bb7(A7b9) <Fine> <*72Solo> Q f S Y YY',
        'Bb7(A7b9)/F',
        'C@E',
        '',
      ];
      for (final String notation in corpus) {
        final List<IRealToken> tokens = tokenizeIReal(notation);
        final StringBuffer rebuilt = StringBuffer();
        for (int index = 0; index < tokens.length; index++) {
          final int end = index + 1 < tokens.length
              ? tokens[index + 1].offset
              : notation.length;
          rebuilt.write(notation.substring(tokens[index].offset, end));
        }
        expect(rebuilt.toString(), notation, reason: notation);
      }
    });

    test('an empty body is an empty token list', () {
      expect(tokenizeIReal(''), isEmpty);
    });
  });

  group('chord parser', () {
    test('a bare root is a major triad with an empty suffix', () {
      final Chord? chord = parseIRealChord('C');
      expect(chord, isNotNull);
      expect(chord!.root.pitchClass, 0);
      expect(chord.quality.token, '');
      expect(chord.bass, isNull);
      expect(chord.alternate, isNull);
    });

    test('the suffix is preserved whole, however long', () {
      // The documented vocabulary has changed between versions, so the suffix is opaque. A parser
      // that knew only one version's list would refuse a chart from a newer app.
      expect(parseIRealChord('D-')!.quality.token, '-');
      expect(parseIRealChord('C7b9')!.quality.token, '7b9');
      expect(parseIRealChord('Bh7')!.quality.token, 'h7');
      expect(parseIRealChord('C^7#11')!.quality.token, '^7#11');
      expect(parseIRealChord('C7susb9b13')!.quality.token, '7susb9b13');
    });

    test(
      'an accidental on the root changes the sounding pitch but not the letter',
      () {
        final Chord? bFlat = parseIRealChord('Bb7');
        expect(bFlat!.root.pitchClass, 10);
        expect(bFlat.quality.token, '7');

        final Chord? fSharp = parseIRealChord('F#');
        expect(fSharp!.root.pitchClass, 6);
      },
    );

    test('a slash chord sets the bass', () {
      final Chord? chord = parseIRealChord('F/C');
      expect(chord!.root.pitchClass, 5);
      expect(chord.bass!.pitchClass, 0);

      final Chord? altered = parseIRealChord('B-/A');
      // B is pitch class 11, the suffix is one token, and the bass is A, pitch class 9.
      expect(altered!.root.pitchClass, 11);
      expect(altered.quality.token, '-');
      expect(altered.bass!.pitchClass, 9);
    });

    test('an alternate chord is a nested chord', () {
      final Chord? chord = parseIRealChord('Bb7(A7b9)');
      expect(chord!.root.pitchClass, 10);
      expect(chord.quality.token, '7');
      expect(chord.alternate, isNotNull);
      expect(chord.alternate!.root.pitchClass, 9);
      expect(chord.alternate!.quality.token, '7b9');
    });

    test('an alternate with its own bass is read whole', () {
      final Chord? chord = parseIRealChord('C(Db^7/F)');
      expect(chord!.alternate!.bass!.pitchClass, 5);
      expect(chord.alternate!.quality.token, '^7');
    });

    test('an invisible root is refused rather than misread as a pitch', () {
      // `W/A` means a bass note with no chord above it. The model has no field for that, so the
      // symbol is reported rather than flattened into a chord that sounds wrong and looks right.
      expect(parseIRealChord('W/A'), isNull);
      expect(parseIRealChord(''), isNull);
      expect(parseIRealChord('X7'), isNull);
    });

    test(
      'parsing and rendering round trips for spellings the key agrees with',
      () {
        const SpellingTable table = SpellingTable();
        for (final String symbol in <String>[
          'C',
          'D-',
          'Eb7',
          'F^7',
          'G7',
          'A-',
          'Bb7',
          'C/E',
          'D-7/G',
          'Bb7(A7b9)',
        ]) {
          final Chord? chord = parseIRealChord(symbol);
          expect(chord, isNotNull, reason: symbol);
          expect(chord!.render(Key.cMajor, table), symbol, reason: symbol);
        }
      },
    );

    test(
      'a spelling the key disagrees with still parses to the right pitch',
      () {
        // C major spells pitch class 6 as Gb, so F#/C# renders as Gb/Db. The PITCH is what parsing
        // must preserve; the spelling is the key's business. Asserting both separately is what
        // keeps a future spelling change from looking like a parsing bug.
        final Chord? chord = parseIRealChord('F#/C#');
        expect(chord!.root.pitchClass, 6);
        expect(chord.bass!.pitchClass, 1);
        expect(chord.render(Key.cMajor, const SpellingTable()), 'Gb/Db');
        expect(
          chord.render(
            const Key(tonic: WrittenNote(NoteLetter.d, 0), mode: Mode.major),
            const SpellingTable(),
          ),
          'F#/C#',
          reason: 'D major spells both notes with sharps',
        );
      },
    );
  });
}
