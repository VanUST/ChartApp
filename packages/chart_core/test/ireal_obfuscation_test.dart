// PURPOSE: Pin the iReal de-obfuscation, and in particular the distinction that a prose summary of
//          it gets wrong: the permutation MIRRORS two groups of positions rather than exchanging
//          them. Both are involutions, so a round-trip test cannot tell them apart — only exact
//          positions and real data can, and both are asserted here.
// INPUTS: None for the synthetic cases. The real-data case reads a path from the IREAL_FIXTURE
//         environment variable and is skipped when it is unset.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, ireal, obfuscation, mirror-vs-swap, round-trip, trailing-block, real-data
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A 50-character block whose every position is identifiable: position i holds the digit i mod 10.
String identifiableBlock() =>
    String.fromCharCodes(List<int>.generate(50, (int i) => 0x30 + (i % 10)));

void main() {
  group('the permutation mirrors rather than swaps', () {
    // With a mirror, out[i] = in[49 - i] inside each group, so position 0 receives position 49.
    // With a swap, position 0 would receive position 45 instead. These four assertions are the
    // only thing in this suite that distinguishes the two, and the difference is not academic:
    // the swap version leaves the substitution tokens behind in decoded real data.
    const int firstGroup = 0;
    const int firstGroupMirror = 49;
    const int secondGroup = 10;
    const int secondGroupMirror = 39;

    test('position 0 receives the far end of its group, not its near end', () {
      final String block = identifiableBlock();
      final String mirrored = mirrorIrealBlock(block);
      // Block position 49 holds '9'; position 45 holds '5'. A mirror gives '9'.
      expect(mirrored[firstGroup], '9');
      expect(block[firstGroupMirror], '9');
      expect(block[45], '5');
      expect(
        mirrored[firstGroup],
        isNot('5'),
        reason: 'a swap would put position 45 here',
      );
    });

    test('the far end of the first group receives position 0', () {
      final String mirrored = mirrorIrealBlock(identifiableBlock());
      expect(mirrored[49], '0');
      expect(
        mirrored[49],
        isNot('4'),
        reason: 'a swap would put position 4 here',
      );
    });

    test('the second group mirrors the same way', () {
      final String block = identifiableBlock();
      final String mirrored = mirrorIrealBlock(block);
      // Position 10 receives position 39 ('9'); position 39 receives position 10 ('0').
      expect(block[secondGroupMirror], '9');
      expect(block[secondGroup], '0');
      expect(mirrored[secondGroup], '9');
      expect(mirrored[secondGroupMirror], '0');
    });

    test('positions between the groups are untouched', () {
      final String block = identifiableBlock();
      final String mirrored = mirrorIrealBlock(block);
      for (final int untouched in <int>[
        5,
        6,
        7,
        8,
        9,
        24,
        25,
        40,
        41,
        42,
        43,
        44,
      ]) {
        expect(
          mirrored[untouched],
          block[untouched],
          reason: 'position $untouched',
        );
      }
    });

    test('applying it twice returns the input', () {
      // Necessary but not sufficient — a swap also survives this — which is why the position
      // assertions above exist.
      final String block = identifiableBlock();
      expect(mirrorIrealBlock(mirrorIrealBlock(block)), block);
    });

    test(
      'a block of the wrong length is returned unchanged rather than throwing',
      () {
        expect(mirrorIrealBlock('abc'), 'abc');
        expect(mirrorIrealBlock(''), '');
      },
    );
  });

  group('substitutions', () {
    test('the three tokens expand to the characters they stand for', () {
      expect(deobfuscateIrealMusic('KclLZXyQ'), '| x |   ');
    });

    test('order does not cascade because the tokens do not overlap', () {
      // '| x' contains '|', ' ' and 'x'; ' |' contains ' ' and '|'; the three spaces stand alone.
      // No expansion can create a string that a later expansion matches.
      expect(deobfuscateIrealMusic('Kcl'), '| x');
      expect(deobfuscateIrealMusic('LZ'), ' |');
      expect(deobfuscateIrealMusic('XyQ'), '   ');
    });
  });

  group('the trailing block rule', () {
    test('a body of at most 51 characters is not permuted at all', () {
      // Both reference implementations leave a final block of 50 or 51 characters as written.
      // A body that short therefore decodes to itself, minus the substitutions.
      final String short = identifiableBlock();
      expect(deobfuscateIrealMusic(short), short);
      expect(deobfuscateIrealMusic('${short}A'), '${short}A');
    });

    test('a body of 52 characters permutes only its first block', () {
      final String block = identifiableBlock();
      final String body = '${block}AB';
      // The first 50 characters are permuted; the remaining two are appended as written.
      expect(deobfuscateIrealMusic(body), '${mirrorIrealBlock(block)}AB');
    });
  });

  group('round trip', () {
    test('scrambling and descrambling returns the notation, at every block boundary', () {
      // Digits only: the property below holds for notation that contains none of the three
      // substitution tokens, and digits cannot. A decoded chart never contains them either,
      // which is what makes this the operation an exporter performs.
      for (final int length in <int>[
        0,
        1,
        49,
        50,
        51,
        52,
        99,
        100,
        101,
        150,
        199,
        200,
        269,
      ]) {
        final String notation = String.fromCharCodes(
          List<int>.generate(length, (int i) => 0x30 + (i % 10)),
        );
        expect(
          deobfuscateIrealMusic(obfuscateIrealMusic(notation)),
          notation,
          reason: 'length $length',
        );
      }
    });

    test('the docstring constraint is real: notation containing a token does not round trip', () {
      // Stated as a test rather than left as prose, because it is a genuine limitation of the
      // format rather than of this implementation: 'LZ' is a token, so a chart that literally
      // contained it would be read back as a barline. Documented so a later reader does not
      // treat the round trip above as unconditional.
      expect(deobfuscateIrealMusic(obfuscateIrealMusic('LZ')), ' |');
      expect(deobfuscateIrealMusic(obfuscateIrealMusic('LZ')), isNot('LZ'));
    });
  });

  group('a real export', () {
    // The only case that proves the implementation against the format rather than against itself.
    // It is guarded by an environment variable because the file is a third-party chart and the
    // repository is public; run it locally with
    //
    //   IREAL_FIXTURE=<path to an iReal .html export> dart test
    //
    // Substitutions and a correct permutation consume every obfuscation token. The residual
    // check is what a swap implementation fails: with the groups exchanged instead of mirrored
    // the decoded text still contains `LZ` and `XyQ`, because characters never reach the
    // positions the substitutions expect.
    final String? fixture = Platform.environment['IREAL_FIXTURE'];

    test(
      'decodes without leaving any obfuscation token behind',
      () {
        final File file = File(fixture!);
        final RegExpMatch? url = RegExp('irealb://([^"]*)')
            .firstMatch(file.readAsStringSync());
        expect(url, isNotNull, reason: 'no irealb:// link found in $fixture');

        final List<String> fields = Uri.decodeFull(url!.group(1)!).split('=');
        final String? musicField = fields
            .where((String f) => f.startsWith(irealMusicPrefix))
            .firstOrNull;
        expect(musicField, isNotNull, reason: 'no music field found');
        expect(
          musicField!.substring(0, irealMusicPrefix.length),
          irealMusicPrefix,
          reason: 'the magic prefix is exactly ten characters',
        );

        final String decoded = deobfuscateIrealMusic(
          musicField.substring(irealMusicPrefix.length),
        );

        expect(decoded, isNot(contains('Kcl')));
        expect(decoded, isNot(contains('LZ')));
        expect(decoded, isNot(contains('XyQ')));
        // A decoded chart is chart notation, so it must contain barlines and at least one section
        // or repeat marker. A permutation that produced plausible garbage would still satisfy the
        // residual check, and this is what rules that out.
        expect(decoded, contains('|'));
        expect(RegExp(r'[*{}\[\]]').hasMatch(decoded), isTrue);

        // And the decoded body must tokenise without leftovers. This is the end-to-end claim: a
        // permutation that produced plausible garbage would survive the residual check above only
        // if the garbage happened to be valid notation, and the tokenizer is what rules that out.
        final List<IRealToken> tokens = tokenizeIReal(decoded);
        expect(tokens, isNotEmpty);
        final List<UnknownToken> unknown = tokens
            .whereType<UnknownToken>()
            .toList();
        expect(
          unknown,
          isEmpty,
          reason: unknown
              .map(
                (UnknownToken t) =>
                    '`${t.character}` at ${t.offset}, in context: '
                    '...${decoded.substring(t.offset < 12 ? 0 : t.offset - 12, (t.offset + 12).clamp(0, decoded.length))}...',
              )
              .join('\n'),
        );

        // Every chord must also parse, so a symbol the model cannot hold is reported rather than
        // quietly becoming an empty bar.
        final List<String> unparsable = <String>[];
        for (final IRealToken token in tokens) {
          if (token is ChordToken && parseIRealChord(token.text) == null) {
            unparsable.add(token.text);
          }
        }
        expect(
          unparsable,
          isEmpty,
          reason: 'chords the model cannot hold: $unparsable',
        );
      },
      skip: fixture == null
          ? 'set IREAL_FIXTURE to an iReal .html export'
          : null,
    );
  });
}
