// PURPOSE: Pin the performance order `derivePlayOrder` produces for each shape of written repeat,
//          so that the reading of a repeat, an alternative ending and a `%` bar is a checkable
//          claim rather than a property of the code. Every expectation below is derived from the
//          chart by hand and written into a comment, not read off a run of the function: a test
//          written from the implementation agrees with it by construction and proves nothing.
// INPUTS: None. The fixtures are hand-built chords and barlines; one of them is assembled by the
//         real iReal parser so the derivation is also exercised on notation nobody hand-wrote.
// OUTPUTS: Pass/fail per expectation, plus the multiset property that no written bar is lost and
//          none sounds on a pass its bracket excludes.
// KEYWORDS: test, play-order, repeat, volta, percent, nested, hand-derived, multiset-property
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// The address of bar [index] in the single section every hand-built fixture here uses.
WrittenBarAddress _a(int index) =>
    WrittenBarAddress(sectionId: 'sec-A-0', barIndex: index);

/// A one-chord bar on [root], with the structure the caller asks for.
Bar _bar(
  int root, {
  Barline opening = Barline.single,
  Barline closing = Barline.single,
  Volta? volta,
}) => Bar(
  openingBarline: opening,
  closingBarline: closing,
  volta: volta,
  chords: <ChordMark>[
    ChordMark(
      place: cellAt(0),
      chord: Chord(root: ChordRoot(root)),
    ),
  ],
);

/// A bar that writes no chord and carries only a repeat-previous symbol, as a `%` bar does.
Bar _percent(RepeatPrevious previous) => Bar(repeatPrevious: previous);

/// A one-section song holding [bars].
Song _song(List<Bar> bars) => Song(
  title: 'fixture',
  sections: <Section>[
    Section(id: 'sec-A-0', label: const SectionLabel.letter('A'), bars: bars),
  ],
);

/// The written bar every played position sounds, by bar index.
List<int> _sources(PlayOrder order) => <int>[
  for (final WrittenBarAddress address in order.sources) address.barIndex,
];

/// The written bar every played position is reached through, by bar index.
List<int> _written(PlayOrder order) => <int>[
  for (final WrittenBarAddress address in order.writtenBars) address.barIndex,
];

/// How often each written bar sounds across the whole performance.
Map<int, int> _sourceCounts(PlayOrder order) {
  final Map<int, int> counts = <int, int>{};
  for (final PlayedBar bar in order.played) {
    counts.update(
      bar.source.barIndex,
      (int value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  return counts;
}

/// The pass through the INNERMOST passage of every played position.
List<int> _passes(PlayOrder order) => <int>[
  for (final PlayedBar bar in order.played) bar.pass,
];

void main() {
  group('no repeats at all', () {
    // Derivation: four bars with no repeat barlines. Each is played once, in reading order, and
    // each sounds itself.
    final Song song = _song(<Bar>[_bar(0), _bar(5), _bar(7), _bar(0)]);
    final PlayOrder order = derivePlayOrder(song);

    test('plays every written bar once, in reading order', () {
      expect(order.length, 4);
      expect(_sources(order), <int>[0, 1, 2, 3]);
      expect(_written(order), <int>[0, 1, 2, 3]);
    });

    test('reports no passage, no issue, and no pass above the first', () {
      expect(order.passages, isEmpty);
      expect(order.issues, isEmpty);
      expect(_passes(order), <int>[1, 1, 1, 1]);
      expect(
        order.played.map((PlayedBar bar) => bar.passCount),
        everyElement(1),
      );
      expect(
        order.played.map((PlayedBar bar) => bar.isInRepeat),
        everyElement(isFalse),
      );
    });
  });

  group('a plain repeat', () {
    // Derivation: `{ C | F :| G | C`. The passage is bars 0 and 1; it is played twice because the
    // model stores no count, and the repeat sign alone can only mean "again": C F, C F. Then the
    // written order continues with bars 2 and 3.
    final Song song = _song(<Bar>[
      _bar(0, opening: Barline.repeatStart),
      _bar(5, closing: Barline.repeatEnd),
      _bar(7),
      _bar(0),
    ]);
    final PlayOrder order = derivePlayOrder(song);

    test('plays the passage twice and then continues after it', () {
      expect(order.length, 6);
      expect(_sources(order), <int>[0, 1, 0, 1, 2, 3]);
    });

    test('names the pass of every position inside the passage', () {
      expect(_passes(order), <int>[1, 1, 2, 2, 1, 1]);
      expect(order.played[0].repeatStart, _a(0));
      expect(order.played[1].repeatStart, _a(0));
      expect(order.played[4].repeatStart, isNull);
      expect(
        order.played[0].passes.single,
        const PlayedPass(
          repeatStart: WrittenBarAddress(sectionId: 'sec-A-0', barIndex: 0),
          pass: 1,
          passCount: 2,
        ),
      );
    });

    test('reports the passage and that its count was assumed', () {
      expect(order.passages, <RepeatPassage>[
        RepeatPassage(
          start: _a(0),
          end: _a(1),
          passCount: 2,
          passCountBasis: PassCountBasis.assumedTwoPasses,
          crossesSection: false,
        ),
      ]);
      expect(order.issues, isEmpty);
    });
  });

  group('alternative endings', () {
    // Derivation, from the real iReal body `T44{C |A- |N1D- |G7 } |N2D- G7 |C6 Z`, which the
    // parser turns into bars
    //   0 = C, repeat start; 1 = A-; 2 = D- with bracket 1; 3 = G7, repeat end;
    //   4 = D- G7 with bracket 2; 5 = C6, final.
    // The bracket written at bar 2 is inherited by bar 3, because bar 3 has no bracket of its own
    // and still lies before the closing barline; that is what makes "D- | G7" the first ending
    // rather than leaving G7 in the body on every pass. So pass 1 is C A- D- G7, pass 2 is
    // C A- (skipping both bracketed bars) followed by the second ending, bar 4.
    final Song song = parseIRealNotation(
      '*AT44{C |A- |N1D- |G7 } |N2D- G7 |C6 Z',
    ).song;
    final PlayOrder order = derivePlayOrder(song);

    test('reads the brackets as first and second endings', () {
      expect(song.writtenBarCount, 6);
      expect(_sources(order), <int>[0, 1, 2, 3, 0, 1, 4, 5]);
    });

    test(
      'skips the first ending on the second pass and takes the second ending',
      () {
        expect(_passes(order), <int>[1, 1, 1, 1, 2, 2, 2, 1]);
        expect(
          order.played[3].source,
          _a(3),
          reason: 'the first ending sounds on pass 1',
        );
        expect(
          order.played[6].source,
          _a(4),
          reason: 'the second ending sounds on pass 2',
        );
      },
    );

    test('says the second bracket required the second pass', () {
      expect(order.passages.single.passCount, 2);
      expect(
        order.passages.single.passCountBasis,
        PassCountBasis.voltaRequired,
      );
      expect(order.issues, isEmpty);
    });
  });

  group('percent bars', () {
    // Derivation: C | F | G | x | A | r.
    //   bars 0..2 write their own chords, so they sound themselves;
    //   bar 3 is `x`, one bar back: it sounds bar 2;
    //   bar 4 sounds itself;
    //   bar 5 is `r`, two bars back. `r` is TWO bars of music, so it yields two played positions:
    //   first the bar two back (bar 3, which is itself `x` and so sounds bar 2), then the bar one
    //   back (bar 4, which sounds itself). Written bars 3 and 5 therefore never sound themselves.
    final Song song = _song(<Bar>[
      _bar(0),
      _bar(5),
      _bar(7),
      _percent(RepeatPrevious.oneBar),
      _bar(9),
      _percent(RepeatPrevious.twoBars),
    ]);
    final PlayOrder order = derivePlayOrder(song);

    test('follows x back to the bar before it', () {
      expect(_sources(order), <int>[0, 1, 2, 2, 4, 2, 4]);
    });

    test('turns one written r bar into two played positions', () {
      expect(
        order.length,
        7,
        reason: 'six written bars, with r standing for two',
      );
      expect(_written(order), <int>[0, 1, 2, 3, 4, 5, 5]);
      expect(order.played[5].written, order.played[6].written);
      expect(
        order.played[5].source,
        _a(2),
        reason: 'two back is the x bar, which sounds bar 2',
      );
      expect(order.played[6].source, _a(4), reason: 'one back is bar 4');
    });

    test('marks exactly the percent bars as repeating another written bar', () {
      expect(
        order.played.map((PlayedBar bar) => bar.repeatsPreviousBar),
        <bool>[false, false, false, true, false, true, true],
      );
    });

    test(
      'a percent chained onto a percent follows the chain to the concrete bar',
      () {
        // Derivation: C | F | x | x. Bar 2 is one back = bar 1 = F. Bar 3 is one back = bar 2,
        // which is itself `x` and so goes back to F. Both sound F, not each other.
        final PlayOrder chained = derivePlayOrder(
          _song(<Bar>[
            _bar(0),
            _bar(5),
            _percent(RepeatPrevious.oneBar),
            _percent(RepeatPrevious.oneBar),
          ]),
        );
        expect(_sources(chained), <int>[0, 1, 1, 1]);
        expect(chained.issues, isEmpty);
      },
    );

    test(
      'a percent as the first bar of the song keeps its position and reports',
      () {
        // There is no bar before the first one, so there is no music to repeat. Dropping the
        // position would silently shorten the performance, so it is kept, it sounds itself, and the
        // anomaly is reported.
        final PlayOrder first = derivePlayOrder(
          _song(<Bar>[_percent(RepeatPrevious.oneBar), _bar(5)]),
        );
        expect(first.length, 2);
        expect(_sources(first), <int>[0, 1]);
        expect(first.played[0].source, first.played[0].written);
        expect(
          first.issues.single.kind,
          PlayOrderIssueKind.percentWithoutPreviousBar,
        );
        expect(first.issues.single.at, _a(0));
      },
    );

    test('a two-bar percent with nothing before it is still two bars and one problem', () {
      // `r` asks for the previous TWO bars. At the first bar of the song neither exists, but the
      // symbol still stands for two bars of music, so two positions are kept; both references run
      // off the start, and they name one problem at one bar rather than two.
      final PlayOrder order = derivePlayOrder(
        _song(<Bar>[_percent(RepeatPrevious.twoBars), _bar(5)]),
      );
      expect(
        order.length,
        3,
        reason: 'the r bar is two played positions, plus bar 1',
      );
      expect(_sources(order), <int>[0, 0, 1]);
      expect(_written(order), <int>[0, 0, 1]);
      expect(order.issues, hasLength(1));
      expect(
        order.issues.single.kind,
        PlayOrderIssueKind.percentWithoutPreviousBar,
      );
      expect(order.issues.single.at, _a(0));
    });
  });

  group('the ambiguous structural cases', () {
    test(
      'a repeat end with no start plays as an ordinary barline and reports',
      () {
        final PlayOrder order = derivePlayOrder(
          _song(<Bar>[_bar(0), _bar(5, closing: Barline.repeatEnd)]),
        );
        expect(_sources(order), <int>[0, 1]);
        expect(order.passages, isEmpty);
        expect(
          order.issues.single.kind,
          PlayOrderIssueKind.repeatEndWithoutStart,
        );
        expect(order.issues.single.at, _a(1));
      },
    );

    test('a repeat start with no end plays the passage once and reports', () {
      final PlayOrder order = derivePlayOrder(
        _song(<Bar>[_bar(0, opening: Barline.repeatStart), _bar(5)]),
      );
      expect(_sources(order), <int>[0, 1]);
      expect(order.passages, isEmpty);
      expect(
        order.issues.single.kind,
        PlayOrderIssueKind.repeatStartWithoutEnd,
      );
      expect(order.issues.single.at, _a(0));
    });

    test(
      'a nested passage is played in full on each pass of the outer one',
      () {
        // Derivation: outer { A { B C } D }. The inner passage is bars 1..2 and repeats twice per
        // outer pass; the outer repeats twice. So A and D sound twice each, B and C four times each,
        // and the order is C F G F G A | C F G F G A.
        final PlayOrder order = derivePlayOrder(
          _song(<Bar>[
            _bar(0, opening: Barline.repeatStart),
            _bar(5, opening: Barline.repeatStart),
            _bar(7, closing: Barline.repeatEnd),
            _bar(9, closing: Barline.repeatEnd),
          ]),
        );
        expect(_sources(order), <int>[0, 1, 2, 1, 2, 3, 0, 1, 2, 1, 2, 3]);
        expect(order.passages.length, 2);
        expect(_sourceCounts(order), <int, int>{0: 2, 1: 4, 2: 4, 3: 2});
      },
    );

    test('a played bar inside nested passages records both passes', () {
      final PlayOrder order = derivePlayOrder(
        _song(<Bar>[
          _bar(0, opening: Barline.repeatStart),
          _bar(5, opening: Barline.repeatStart),
          _bar(7, closing: Barline.repeatEnd),
          _bar(9, closing: Barline.repeatEnd),
        ]),
      );
      expect(order.played[3].passes.length, 2, reason: 'inside both passages');
      expect(order.played[3].passes[0].repeatStart, _a(0));
      expect(
        order.played[3].passes[0].pass,
        1,
        reason: 'outer still on pass 1',
      );
      expect(order.played[3].passes[1].repeatStart, _a(1));
      expect(order.played[3].passes[1].pass, 2, reason: 'inner on pass 2');
      expect(
        order.played[3].pass,
        2,
        reason: 'the innermost pass is the reported one',
      );
      expect(
        order.played[5].passes.length,
        1,
        reason: 'outside the inner passage',
      );
    });

    test(
      'an unnumbered bracket selects no pass and so plays on every pass',
      () {
        // Volta(0) carries no figure, so it cannot be compared with a pass number. The alternative
        // — treating it as "no pass" — would delete the bar from the performance, which is worse
        // than playing it.
        final PlayOrder order = derivePlayOrder(
          _song(<Bar>[
            _bar(0, opening: Barline.repeatStart, volta: const Volta(0)),
            _bar(5, closing: Barline.repeatEnd, volta: const Volta(0)),
          ]),
        );
        expect(_sources(order), <int>[0, 1, 0, 1]);
        expect(order.issues, isEmpty);
      },
    );

    test('a third-ending bracket makes a three-pass passage', () {
      // Derivation: `{ A | B :| C (N2) | D (N3)`. The highest bracket is 3, so the body is played
      // three times: pass 1 A B, pass 2 A B then the N2 bar, pass 3 A B then the N3 bar.
      final PlayOrder order = derivePlayOrder(
        _song(<Bar>[
          _bar(0, opening: Barline.repeatStart),
          _bar(5, closing: Barline.repeatEnd),
          _bar(7, volta: const Volta(2)),
          _bar(9, volta: const Volta(3)),
        ]),
      );
      expect(_sources(order), <int>[0, 1, 0, 1, 2, 0, 1, 3]);
      expect(order.passages.single.passCount, 3);
      expect(
        order.passages.single.passCountBasis,
        PassCountBasis.voltaRequired,
      );
      expect(_sourceCounts(order), <int, int>{0: 3, 1: 3, 2: 1, 3: 1});
    });

    test('a bracket no repeat contains is ignored and reported', () {
      final PlayOrder order = derivePlayOrder(
        _song(<Bar>[_bar(0), _bar(5, volta: const Volta(1)), _bar(7)]),
      );
      expect(_sources(order), <int>[0, 1, 2]);
      expect(order.issues.single.kind, PlayOrderIssueKind.voltaOutsideRepeat);
      expect(order.issues.single.at, _a(1));
    });

    test('a lone first-ending bracket over the whole passage makes the second pass silent', () {
      // Derivation: `{ A (1.) B (1.) :| C`. The bracket says both bars are the first time only,
      // so the second pass the repeat sign demands selects no bar: it plays nothing. The decision
      // is that the repeat is honoured rather than dropped, and that a pass with nothing in it is
      // reported instead of vanishing.
      final PlayOrder order = derivePlayOrder(
        _song(<Bar>[
          _bar(0, opening: Barline.repeatStart, volta: const Volta(1)),
          _bar(5, closing: Barline.repeatEnd, volta: const Volta(1)),
          _bar(7),
        ]),
      );
      expect(_sources(order), <int>[0, 1, 2]);
      expect(order.played.map((PlayedBar bar) => bar.pass), <int>[1, 1, 1]);
      expect(order.passages.single.passCount, 2);
      expect(
        order.passages.single.passCountBasis,
        PassCountBasis.assumedTwoPasses,
        reason: 'the only bracket is number 1, which asks for no more than the floor of two',
      );
      expect(order.issues.single.kind, PlayOrderIssueKind.passPlaysNothing);
      expect(order.issues.single.at, _a(0));
    });

    test(
      'a passage that crosses a section boundary is expanded and flagged',
      () {
        final Song song = Song(
          title: 'crossing',
          sections: <Section>[
            Section(
              id: 'sec-A-0',
              label: const SectionLabel.letter('A'),
              bars: <Bar>[_bar(0, opening: Barline.repeatStart)],
            ),
            Section(
              id: 'sec-B-0',
              label: const SectionLabel.letter('B'),
              bars: <Bar>[
                _bar(5, closing: Barline.repeatEnd),
                _bar(7),
              ],
            ),
          ],
        );
        final PlayOrder order = derivePlayOrder(song);
        expect(_sources(order), <int>[0, 0, 0, 0, 1]);
        expect(
          order.played.map((PlayedBar bar) => bar.source.sectionId),
          <String>['sec-A-0', 'sec-B-0', 'sec-A-0', 'sec-B-0', 'sec-B-0'],
        );
        expect(order.passages.single.crossesSection, isTrue);
      },
    );

    test('a song of no bars plays nothing and reports nothing', () {
      final PlayOrder order = derivePlayOrder(const Song(title: 'empty'));
      expect(order.isEmpty, isTrue);
      expect(order.length, 0);
      expect(order.sources, isEmpty);
      expect(order.passages, isEmpty);
      expect(order.issues, isEmpty);
    });

    test('a section of no bars contributes nothing and is not a defect', () {
      final Song song = Song(
        title: 'empty section',
        sections: <Section>[
          const Section(id: 'sec-A-0', label: SectionLabel.letter('A')),
          Section(
            id: 'sec-B-0',
            label: const SectionLabel.letter('B'),
            bars: <Bar>[_bar(0)],
          ),
        ],
      );
      final PlayOrder order = derivePlayOrder(song);
      expect(_sources(order), <int>[0]);
      expect(order.played.single.source.sectionId, 'sec-B-0');
      expect(order.issues, isEmpty);
    });
  });

  group('the property that would be false if the derivation were wrong', () {
    // Every written bar must sound exactly as often as its bracket and its enclosing passages
    // allow, and never otherwise: a bar outside every bracket sounds once per enclosing pass; a
    // bar in a numbered bracket sounds once in all, on its pass; a `%` bar never sounds itself.
    // A derivation that dropped the first ending on the final pass would read {2: 0}; one that
    // replayed the whole body on every pass would read {3: 2} instead of {3: 1}.
    test('no written bar is lost and none sounds on a pass its bracket excludes', () {
      expect(
        _sourceCounts(
          derivePlayOrder(_song(<Bar>[_bar(0), _bar(5), _bar(7), _bar(0)])),
        ),
        <int, int>{0: 1, 1: 1, 2: 1, 3: 1},
      );
      expect(
        _sourceCounts(
          derivePlayOrder(
            _song(<Bar>[
              _bar(0, opening: Barline.repeatStart),
              _bar(5, closing: Barline.repeatEnd),
              _bar(7),
              _bar(0),
            ]),
          ),
        ),
        <int, int>{0: 2, 1: 2, 2: 1, 3: 1},
      );
      expect(
        _sourceCounts(
          derivePlayOrder(
            parseIRealNotation('*AT44{C |A- |N1D- |G7 } |N2D- G7 |C6 Z').song,
          ),
        ),
        <int, int>{0: 2, 1: 2, 2: 1, 3: 1, 4: 1, 5: 1},
      );
      expect(
        _sourceCounts(
          derivePlayOrder(
            _song(<Bar>[
              _bar(0),
              _bar(5),
              _bar(7),
              _percent(RepeatPrevious.oneBar),
              _bar(9),
              _percent(RepeatPrevious.twoBars),
            ]),
          ),
        ),
        // Bars 3 and 5 are `%` bars: they are written positions, never sources.
        <int, int>{0: 1, 1: 1, 2: 3, 4: 2},
      );
    });

    test(
      'a derivation is a pure function of the song: twice gives the same order',
      () {
        final Song song = _song(<Bar>[
          _bar(0, opening: Barline.repeatStart),
          _bar(5, closing: Barline.repeatEnd),
          _bar(7),
        ]);
        final PlayOrder first = derivePlayOrder(song);
        final PlayOrder second = derivePlayOrder(song);
        expect(second.played, first.played);
        expect(second.passages, first.passages);
        expect(second.issues, first.issues);
        // The song itself is untouched: its written bars are still the three it was built with.
        expect(song.writtenBarCount, 3);
        expect(song.barsInReadingOrder.length, 3);
      },
    );

    test(
      'every played position is numbered in order and every pass is in range',
      () {
        final PlayOrder order = derivePlayOrder(
          _song(<Bar>[
            _bar(0, opening: Barline.repeatStart),
            _bar(5, opening: Barline.repeatStart),
            _bar(7, closing: Barline.repeatEnd),
            _bar(9, closing: Barline.repeatEnd),
            _bar(0),
          ]),
        );
        for (int index = 0; index < order.length; index++) {
          expect(order.played[index].position, index);
          for (final PlayedPass pass in order.played[index].passes) {
            expect(pass.pass, greaterThanOrEqualTo(1));
            expect(pass.passCount, greaterThanOrEqualTo(pass.pass));
          }
        }
      },
    );
  });
}
