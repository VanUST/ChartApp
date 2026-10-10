// PURPOSE: Pin the assembler's reading of decoded iReal notation: where a chord lands inside a
//          bar, that a comma removes an empty cell rather than stacking two chords, when a bar is
//          padding, how a section boundary claims the bar an opening barline just created, and —
//          the point of this file — that a symbol the model cannot represent becomes an issue
//          instead of an exception. Every expectation below is derived by hand and the derivation
//          is written next to it, so a failure names a rule rather than a number.
// INPUTS: None. The last group reads a real iReal export from the path in the IREAL_FIXTURE
//         environment variable and is skipped when it is unset.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, ireal, parser, assembler, cell-model, comma-separator, padding, diagnostics,
//           real-export, hand-derived
import 'dart:io';

import 'package:chart_core/src/chord.dart';
import 'package:chart_core/src/ireal/obfuscation.dart';
import 'package:chart_core/src/ireal/parser.dart';
import 'package:chart_core/src/song/bar.dart';
import 'package:chart_core/src/song/section.dart';
import 'package:chart_core/src/song/song.dart';
import 'package:chart_core/src/song/time_signature.dart';
import 'package:test/test.dart';

/// The chords of [bar] as `rootQuality[/bass]@beat.step[size]`, in stored order.
///
/// A chord is rendered from its pitch class and opaque quality token rather than through
/// `Chord.render`, because rendering consults a key and this file is about placement, not
/// spelling.
List<String> placementsOf(Bar bar) {
  final List<String> placements = <String>[];
  for (final BeatChord chord in bar.chords) {
    final String size = chord.size == ChordSize.small ? '[small]' : '';
    final ChordRoot? bass = chord.chord.bass;
    final String slash = bass == null ? '' : '/${bass.pitchClass}';
    placements.add(
      '${chord.chord.root.pitchClass}${chord.chord.quality.token}$slash'
      '@${chord.beat}.${chord.step}$size',
    );
  }
  return placements;
}

/// Every bar of [song] in reading order.
List<Bar> barsOf(Song song) => song.barsInReadingOrder;

void main() {
  group('a chord occupies a cell', () {
    test(
      'the protocol document\'s |C7ppF7| is one bar of exactly four cells',
      () {
        // Derivation: the leading `|` closes a bar that received no token, so it is padding and is
        // dropped. C7 is placed on cell 0 and the pointer moves to 1. Each `p` occupies a cell and
        // moves on, so the two slashes take cells 1 and 2. F7 then lands on cell 3. The trailing
        // `|` closes the bar. One bar, four cells — the document's own worked example.
        final IRealParseResult result = parseIRealNotation('|C7ppF7|');

        expect(result.issues, isEmpty);
        final List<Bar> bars = barsOf(result.song);
        expect(bars, hasLength(1));
        expect(placementsOf(bars.single), <String>['07@0.0', '57@3.0']);
        expect(bars.single.slashRepeat, isTrue);
      },
    );

    test('a space consumes a cell, so D- D-/C lands on cells 0 and 2', () {
      // Derivation: D- is placed on cell 0 and the pointer moves to 1; the space occupies cell 1
      // and moves to 2; D-/C is placed on cell 2. This is the document's second worked example
      // and it is what proves a space is not free.
      final IRealParseResult result = parseIRealNotation('|D- D-/C|');
      final Bar bar = barsOf(result.song).single;

      expect(placementsOf(bar), <String>['2-@0.0', '2-/0@2.0']);
    });

    test('a comma removes an empty cell rather than joining two chords', () {
      // Derivation taken from the reference implementation, NOT from the protocol prose. A comma
      // is dropped before it can become a token, so it consumes no cell and stacks nothing. `s`
      // turns on small size and persists. Eh is placed on cell 0, step 0, and the pointer moves to
      // 1. The comma does nothing at all. A7 therefore takes CELL 1, step 0. The trailing comma
      // has no chord after it. Both chords are small, because `s` persists until `l`.
      //
      // What this pins: two chords written with a comma between them are ONE CELL APART, not two
      // chords on a single beat. An earlier version of the parser read the comma the other way and
      // stacked both on cell 0. Every worked example in the protocol document is consistent with
      // BOTH readings, so only the reference parser settles it — which is why this expectation
      // comes from reading that parser rather than from reasoning about the examples.
      final IRealParseResult result = parseIRealNotation('|sEh,A7,|');
      final Bar bar = barsOf(result.song).single;

      expect(placementsOf(bar), <String>['4h@0.0[small]', '97@1.0[small]']);
    });

    test(
      'a comma between symbols that already consume cells changes nothing',
      () {
        // Derivation: A7 is placed on cell 0, pointer to 1. The comma does nothing. The first `p`
        // occupies cell 1, pointer to 2. The second comma does nothing. The second `p` occupies
        // cell 2, pointer to 3. The third comma does nothing. B7 — root B, pitch class 11 — is
        // placed on cell 3.
        //
        // This is the case where the two readings of the comma AGREE, which is precisely why the
        // rule could not be settled from examples that all have this shape. It is kept as the
        // regression pin for the cell consumption of `p`.
        final IRealParseResult result = parseIRealNotation('|A7,p,p,B7|');

        expect(placementsOf(barsOf(result.song).single), <String>[
          '97@0.0',
          '117@3.0',
        ]);
      },
    );

    test('p, x, r and n each consume one cell', () {
      // Derivation: the leading `|` closes a padding bar and is dropped. `x ` is x on cell 0 plus
      // a space on cell 1, then `|` closes the bar. `n `, `r ` and `p ` do the same in their own
      // bars. Four bars, and each token shows up as that bar's own flag rather than as a chord,
      // because none of the four is a chord.
      final IRealParseResult result = parseIRealNotation('|x |n |r |p |');
      final List<Bar> bars = barsOf(result.song);

      expect(bars, hasLength(4));
      expect(bars[0].repeatPrevious, RepeatPrevious.oneBar);
      expect(bars[1].noChord, isTrue);
      expect(bars[2].repeatPrevious, RepeatPrevious.twoBars);
      expect(bars[3].slashRepeat, isTrue);
    });
  });

  group('sections', () {
    test(
      '[*i starts a section without losing the bracket on its first bar',
      () {
        // Derivation: `[` creates an empty bar and sets its opening barline to double. `*i` starts
        // the intro; because the open bar is empty it belongs to the new section rather than to the
        // section that was current, so the bracket survives. B- and the space then fill cells 0
        // and 1, and `|` closes the bar. One section, one bar.
        final IRealParseResult result = parseIRealNotation('[*iB- |');
        final List<Section> sections = result.song.sections;

        expect(sections, hasLength(1));
        expect(sections.single.id, 'sec-i-0');
        expect(sections.single.label.kind, SectionKind.intro);
        expect(sections.single.bars.single.openingBarline, Barline.double);
        expect(placementsOf(sections.single.bars.single), <String>['11-@0.0']);
      },
    );

    test(
      'an earlier bar does not renumber a later section: sec-A-0 then sec-A-1',
      () {
        // Derivation: the first `*A` is occurrence 0 of key A, the second is occurrence 1. The ids
        // come from label plus occurrence, not from position, so inserting a bar into the first A
        // leaves both ids alone.
        final IRealParseResult result = parseIRealNotation('*AC7|*AD7|');

        expect(
          result.song.sections.map((Section section) => section.id).toList(),
          <String>['sec-A-0', 'sec-A-1'],
        );
        expect(
          result.song.sections
              .map((Section section) => section.label.kind)
              .toList(),
          <SectionKind>[SectionKind.letter, SectionKind.letter],
        );
        expect(
          result.song.sections
              .map((Section section) => section.label.text)
              .toList(),
          <String>['A', 'A'],
        );
      },
    );

    test('the section that a marker leaves with no bars is dropped', () {
      // Derivation: `*A` opens section A; `*B` closes it with no bars, so nothing is emitted for
      // it, and the body ends with section B also holding no bars. A section of no bars is not a
      // section a musician can read, and emitting it would put an empty label in the layout.
      final IRealParseResult result = parseIRealNotation('*A*B');

      expect(result.song.sections, isEmpty);
      expect(result.issues, isEmpty);
    });

    test('a body with no marker puts its bars in one implicit section', () {
      // Derivation: C7 and F7 are separated by `|`, and no `*` ever appears. The bars still need
      // a home, so the assembler creates `sec-implicit-0` rather than dropping them.
      final IRealParseResult result = parseIRealNotation('C7|F7|');

      expect(result.song.sections, hasLength(1));
      expect(result.song.sections.single.id, 'sec-implicit-0');
      expect(placementsOf(barsOf(result.song)[0]), <String>['07@0.0']);
      expect(placementsOf(barsOf(result.song)[1]), <String>['57@0.0']);
    });
  });

  group('signs that belong to the bar', () {
    test(
      'an opening barline, a volta, a fermata and a segno land on one bar',
      () {
        // Derivation: `*A` opens a bar (no content yet). `{` sets its opening barline to a repeat
        // start. C7 takes cell 0. N2 sets volta 2. `f` adds a fermata and `S` a segno; neither
        // consumes a cell, so they do not move C7. `|` closes the bar.
        final IRealParseResult result = parseIRealNotation('*A{C7N2fS|');
        final Bar bar = barsOf(result.song).single;

        expect(bar.openingBarline, Barline.repeatStart);
        expect(bar.closingBarline, Barline.single);
        expect(bar.volta, const Volta(2));
        expect(bar.marks, <BarMark>{BarMark.fermata, BarMark.segno});
        expect(placementsOf(bar), <String>['07@0.0']);
      },
    );

    test('a closing `]` is written on the bar it closes', () {
      // Derivation: C7 takes cell 0, then `]` both closes the bar and names the closing barline
      // as double. The opening barline was never set, so it stays single.
      final IRealParseResult result = parseIRealNotation('*AC7]');
      final Bar bar = barsOf(result.song).single;

      expect(bar.closingBarline, Barline.double);
      expect(bar.openingBarline, Barline.single);
    });

    test('staff text keeps a two-digit vertical-position prefix', () {
      // Derivation: the tokenizer separates `<*72Solo>` into text `Solo` and position 72, and
      // `<Fine>` into text `Fine` with no position. Reassembling the first as `*72Solo` restores
      // the written text exactly. `*07Solo` is padded back to two digits, because the prefix is
      // two characters in the notation and `*7Solo` would not be the same instruction.
      final IRealParseResult result = parseIRealNotation(
        '*A<*72Solo>C7|<Fine>D-|<*07Bass>E-|',
      );
      final List<Bar> bars = barsOf(result.song);

      expect(bars[0].staffText, <String>['*72Solo']);
      expect(bars[1].staffText, <String>['Fine']);
      expect(bars[2].staffText, <String>['*07Bass']);
    });
  });

  group('padding and finalisation', () {
    test('a bar that received only spaces is dropped, not emitted', () {
      // Derivation: C7 takes cell 0 and `|` closes the first bar. The four spaces occupy cells
      // 0..3 of a new bar and `|` closes it, but nothing was written in it, so it is the padding
      // iReal uses to fill a line and not a measure. F7 then makes the second real bar. Two
      // bars, not three.
      final IRealParseResult result = parseIRealNotation('C7|    |F7|');

      expect(barsOf(result.song), hasLength(2));
      expect(placementsOf(barsOf(result.song)[0]), <String>['07@0.0']);
      expect(placementsOf(barsOf(result.song)[1]), <String>['57@0.0']);
    });

    test('padding after the last barline does not add a bar', () {
      // Derivation: C7 makes a bar, `|` closes it, and the two trailing spaces begin a bar that
      // never receives content, so the end of input drops it.
      final IRealParseResult result = parseIRealNotation('C7|  ');

      expect(barsOf(result.song), hasLength(1));
    });

    test('a body of only spaces has no sections at all', () {
      // Derivation: every token is a cell advance, so the one bar never receives content, is
      // dropped, and the section that would have held it ends with no bars and is dropped too.
      final IRealParseResult result = parseIRealNotation('   ');

      expect(result.song.sections, isEmpty);
      expect(result.issues, isEmpty);
    });

    test('a final bar with no closing barline is still emitted', () {
      // Derivation: iReal omits the last barline. C7 takes cell 0 and the body ends, so the open
      // bar is closed by the parser with the model's default single barline.
      final IRealParseResult result = parseIRealNotation('*AC7');
      final Bar bar = barsOf(result.song).single;

      expect(placementsOf(bar), <String>['07@0.0']);
      expect(bar.closingBarline, Barline.single);
    });
  });

  group('persistent state', () {
    test('a meter set before any chord applies to that bar and the next', () {
      // Derivation: `*A` opens no bar. `T34` sets the meter to 3/4 before any bar exists, so the
      // bar C7 creates starts in 3/4; the meter persists, so the bar D- creates is 3/4 too.
      final IRealParseResult result = parseIRealNotation('*AT34C7|D-|');
      final List<Bar> bars = barsOf(result.song);

      expect(bars[0].timeSignature, TimeSignature.threeFour);
      expect(bars[1].timeSignature, TimeSignature.threeFour);
    });

    test(
      'a meter change after music starts takes effect from the next bar',
      () {
        // Derivation: C7 takes cell 0 and the space cell 1 of a 4/4 bar; T34 arrives with that bar
        // already holding music, and a bar carries one meter, so the bar keeps 4/4 rather than
        // misdating the chord. The change persists, so the next bar is 3/4.
        final IRealParseResult result = parseIRealNotation('*AC7 T34 |D-|');
        final List<Bar> bars = barsOf(result.song);

        expect(bars[0].timeSignature, TimeSignature.fourFour);
        expect(bars[1].timeSignature, TimeSignature.threeFour);
      },
    );

    test('chord size persists across bars and `l` restores it', () {
      // Derivation: `s` makes C7 small; the size persists across the barline, and `l` restores
      // normal before D- is placed.
      final IRealParseResult result = parseIRealNotation('*AsC7|lD-|');
      final List<Bar> bars = barsOf(result.song);

      expect(placementsOf(bars[0]), <String>['07@0.0[small]']);
      expect(placementsOf(bars[1]), <String>['2-@0.0']);
    });
  });

  group('problems become issues, never exceptions', () {
    test('an unrepresentable chord is reported and its bar survives', () {
      // Derivation: `W/A` has an invisible root the chord model cannot hold, so parseIRealChord
      // returns null and an issue is recorded at the offset of `W` (index 5: `*A` is 0-1, `C7` is
      // 2-3, `|` is 4). The chord token still consumed cell 0 and still marks the bar as content,
      // so the bar is emitted empty instead of vanishing and shifting F7's address. Three bars,
      // one issue.
      final IRealParseResult result = parseIRealNotation('*AC7|W/A|F7|');
      final List<Bar> bars = barsOf(result.song);

      expect(bars, hasLength(3));
      expect(bars[1].chords, isEmpty);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('W/A'));
      expect(result.issues.single.offset, 5);
    });

    test('an unrecognised character is reported and the rest of the chart survives', () {
      // Derivation: `@` is not part of the grammar, so the tokenizer emits UnknownToken at index
      // 5. The bar holding it is kept, so F7 keeps its place: three bars, one issue.
      final IRealParseResult result = parseIRealNotation('*AC7|@|F7|');

      expect(barsOf(result.song), hasLength(3));
      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('@'));
      expect(result.issues.single.offset, 5);
    });

    test(
      'a body that is nothing but bad characters still returns a result',
      () {
        // Derivation: three unknown tokens at offsets 0, 1 and 2. None is a grammar symbol, but the
        // contract is that nothing throws, so the call returns a song with an implicit section for
        // the one bar those characters were written into, and three issues.
        final IRealParseResult result = parseIRealNotation('@@@');

        expect(result.issues, hasLength(3));
        expect(
          result.issues.map((IRealParseIssue issue) => issue.offset).toList(),
          <int>[0, 1, 2],
        );
        expect(result.song.sections, hasLength(1));
        expect(result.song.sections.single.id, 'sec-implicit-0');
        expect(barsOf(result.song), hasLength(1));
      },
    );

    test('a system break is reported because the model cannot store it', () {
      // Derivation: `Y` asks for vertical space before a system, and Bar has no field for it. The
      // parser records an issue instead of dropping the written instruction silently. `Y` also
      // does not consume a cell and does not make a bar content, because it is a layout hint.
      final IRealParseResult result = parseIRealNotation('*YYYYC7|');

      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('System break'));
      expect(result.issues.single.offset, 2);
      expect(placementsOf(barsOf(result.song).single), <String>['07@0.0']);
    });

    test(
      'the document id is carried onto the song, and nothing else is invented',
      () {
        // Derivation: the music body holds no title, composer or key, so the parser must not
        // fabricate one from the notation. It carries the id the caller supplied and leaves the
        // metadata at the model's defaults.
        final IRealParseResult result = parseIRealNotation(
          '*AC7|',
          documentId: 'doc-1',
        );

        expect(result.song.id, 'doc-1');
        expect(result.song.title, '');
        expect(result.song.composer, '');
        expect(result.song.style, '');
        expect(result.song.tempo, 0);
      },
    );
  });

  group('a real export', () {
    // The only case that proves the assembler against a chart written by iReal Pro rather than by
    // this file's author. Guarded by an environment variable because the chart is a third party's
    // work and the repository is public. Run locally with
    //
    //   IREAL_FIXTURE=<path to an iReal .html export> dart test test/ireal_parser_test.dart
    //
    // Expected structure, derived by hand from the decoded body before the parser was run against
    // it. The body is (spaces shown as written):
    //
    //   [*iB- |x |E- |x |A |x |D,|F#/C# F#,|B- |B-,B,|E- |x |F# |x |B- |x ]{*AB- |...
    //
    // Section `*i` starts inside the `[` bar the opening barline just created, and the 16 bars it
    // owns are the 16 segments between `[*i` and the closing `]`. Section `*A` starts on the bar
    // `{` opened, and owns the 12 segments up to the `[` that opens the B section. Section `*B`
    // owns 21 bars: 17 segments before the `}` that ends the repeat, then the bar the 12-space run
    // forms is dropped as padding, then three segments and the unclosed final bar.
    //
    // NOTE, recorded rather than smoothed over: the task brief described a 13-bar intro. The
    // decoded fixture has 16 bars between `[*i` and `]` — the segment list is quoted above and the
    // count is a direct property of the input, not of this parser. The test asserts what the file
    // contains.
    final String? fixture = Platform.environment['IREAL_FIXTURE'];

    test('parses the export into an intro, an A section and a B section', () {
      final String html = File(fixture!).readAsStringSync();
      final RegExpMatch? url = RegExp('irealb://([^"]*)').firstMatch(html);
      expect(url, isNotNull, reason: 'no irealb:// link found in $fixture');

      final List<String> fields = Uri.decodeFull(url!.group(1)!).split('=');
      final String musicField = fields.firstWhere(
        (String field) => field.startsWith(irealMusicPrefix),
      );
      final String decoded = deobfuscateIrealMusic(
        musicField.substring(irealMusicPrefix.length),
      );

      // The parser is handed the music body alone, so a parser bug could not change these.
      // They pin which export this run used: title, composer, and the key field `B-`, which is
      // iReal's minor spelling — B minor. (The field list is measured from this export; the
      // field at index 3 is the style, "Russian Retro".)
      expect(fields[0], contains('Три белых коня'));
      expect(fields[1], 'кинофильмов из');
      expect(fields[3], 'Russian Retro');
      expect(fields[4], 'B-');

      final IRealParseResult result = parseIRealNotation(
        decoded,
        documentId: 'tri-belyh-konya',
      );

      // The house rule for this export: it tokenises with no unrecognised character, and every
      // chord symbol in it is representable, so a non-empty issue list is a defect.
      expect(result.issues, isEmpty);

      final List<Section> sections = result.song.sections;
      expect(sections.map((Section section) => section.id).toList(), <String>[
        'sec-i-0',
        'sec-A-0',
        'sec-B-0',
      ]);
      expect(
        sections.map((Section section) => section.label.kind).toList(),
        <SectionKind>[
          SectionKind.intro,
          SectionKind.letter,
          SectionKind.letter,
        ],
      );
      expect(
        sections.map((Section section) => section.bars.length).toList(),
        <int>[16, 12, 21],
      );
      expect(result.song.writtenBarCount, 49);

      // The intro's first bar keeps the `[` and its last bar takes the `]`. The A section starts
      // on the `{` bar and the B section's first bar keeps the `[` that opened it. The `}` closes
      // the bar before the padding run, not the section's last bar: the tail after it is one more
      // unclosed bar, which the parser closes with the model's default single barline.
      expect(sections[0].bars.first.openingBarline, Barline.double);
      expect(sections[0].bars.last.closingBarline, Barline.double);
      expect(sections[1].bars.first.openingBarline, Barline.repeatStart);
      expect(sections[2].bars.first.openingBarline, Barline.double);
      expect(
        sections[2].bars.any(
          (Bar bar) => bar.closingBarline == Barline.repeatEnd,
        ),
        isTrue,
      );
      expect(sections[2].bars.last.closingBarline, Barline.single);

      // The `x` symbols: the intro alternates a chord bar with a repeat-previous bar.
      expect(sections[0].bars[1].repeatPrevious, RepeatPrevious.oneBar);
      expect(sections[0].bars[1].chords, isEmpty);

      // `Q` is the coda mark and `f` the fermata; both are written in the B section.
      final Iterable<BarMark> marks = sections[2].bars.expand(
        (Bar bar) => bar.marks,
      );
      expect(marks, contains(BarMark.coda));
      expect(marks, contains(BarMark.fermata));

      // The two staff texts carry vertical positions, which the parser stores back as the `*NN`
      // prefix the chart wrote.
      final List<String> staffText = sections
          .expand((Section section) => section.bars)
          .expand((Bar bar) => bar.staffText)
          .toList();
      expect(staffText, contains('*72 /d.'));
      expect(staffText, contains('*74 x3'));

      // Slash chords are a property of the chord model, so an F#/C# in the chart must come back
      // as a chord with a bass note.
      final bool hasSlashChord = sections
          .expand((Section section) => section.bars)
          .expand((Bar bar) => bar.chords)
          .any((BeatChord chord) => chord.chord.bass != null);
      expect(hasSlashChord, isTrue);
    }, skip: fixture == null ? 'set IREAL_FIXTURE' : null);
  });
}
