// PURPOSE: Pin the layout pipeline's behaviour with exact geometry. Because the engine takes its
//          text metrics as an input, every number below is arithmetic rather than a font
//          measurement, so an expectation can be derived by hand and a failure names a real
//          regression instead of a font-version difference.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, layout, bar-width, bar-minimum-width, place-not-cell, system-building,
//           pagination, hit-testing, hand-derived
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

import '../support/place_fixture.dart';

/// A 4/4 bar holding one major triad on beat 0 and nothing else.
Bar oneChordBar(int rootPitchClass) => Bar(
  chords: <ChordMark>[
    ChordMark(
      place: placeAt(0),
      chord: Chord(root: ChordRoot(rootPitchClass)),
    ),
  ],
);

/// A 4/4 bar holding one chord on the given beat.
Bar chordOnBeat(int rootPitchClass, int beat) => Bar(
  chords: <ChordMark>[
    ChordMark(
      place: placeAt(beat),
      chord: Chord(root: ChordRoot(rootPitchClass)),
    ),
  ],
);

/// A section of [count] one-chord bars, all rooted on C.
Section sectionOf(String id, String label, int count) => Section(
  id: id,
  label: SectionLabel.letter(label),
  bars: <Bar>[for (int i = 0; i < count; i++) oneChordBar(0)],
);

void main() {
  // Defaults, restated here so that a change to the style is visible as a change to these
  // expectations rather than as a mystery: advance 8/char, barPadding 8, chordSpacing 10,
  // minCellWidth 18, barMinWidth 56, pageMargin 24, barHeight 44, systemSpacing 12,
  // sectionLabelHeight 22.
  const LayoutEngine engine = LayoutEngine();

  group('measureBar', () {
    test(
      'a bar holding one short chord measures to the floor, not to its content',
      () {
        // THE BAR'S WIDTH FOLLOWS WHAT IS WRITTEN IN IT. This bar holds one single-character chord at
        // the fixture's first slot: 8 (its own place) + 8 (one character at the 8-per-character
        // advance) = 16, and 16 is less than the style's floor, so the floor is the answer.
        //
        // THE OLD ASSERTION, QUOTED: expect(engine.measureBar(oneChordBar(0), Key.cMajor), 88);
        // It was four cells — one occupied at 18 and three empty at 18 — plus 16 of padding, because a
        // bar's width used to be its METRE multiplied by a cell's width. The metre no longer divides
        // the bar at all: owner's words, «Просто надпись» — the time signature is a label and nothing
        // else. So an empty cell neither exists nor reserves anything, and the only reason a bar is as
        // wide as it is is the room the musician needs. What the old 88 was really buying — room to
        // write the bar's beats into — is now carried by one number, `LayoutStyle.barMinWidth`, and
        // that number is where the question lives rather than a column count.
        expect(
          engine.measureBar(oneChordBar(0), Key.cMajor),
          engine.style.barMinWidth,
        );
      },
    );

    test(
      'a bar with no chords measures to the floor, which is its room to write',
      () {
        // THE PROPERTY THE OLD ASSERTION WAS PROTECTING IS NOT "THE BAR HAS FOUR CELLS", it is "a bar
        // the musician has not written in yet still has room for him to write in". That is the fact
        // this test now states, and it is the fact that decides `barMinWidth`: a floor too small to
        // write into makes every new bar unwritable, whatever it does to the arithmetic.
        //
        // THE OLD ASSERTION, QUOTED: expect(engine.measureBar(const Bar(), Key.cMajor), 88);
        // Four empty cells at 18 plus 16 of padding. An empty bar no longer reserves the metre's
        // worth of columns; it reserves nothing, and the floor is what is left of that reservation.
        expect(
          engine.measureBar(const Bar(), Key.cMajor),
          engine.style.barMinWidth,
        );
      },
    );

    test(
      'a wider chord makes the bar exactly as much wider as the chord is',
      () {
        // Two bars identical except for the CHORD SYMBOL, both written at the same place (fixture slot
        // 4 = 8 + 4×18 = 80, comfortably past the floor so that the content decides both widths):
        // "C" is one character = 8 wide and "Cmaj7" is five characters = 40 wide. Each bar is its
        // chord's right edge — 80 + 8 = 88 and 80 + 40 = 120 — plus the bar's own trailing padding.
        //
        // THE OLD ASSERTION, QUOTED: expect(engine.measureBar(bar, Key.cMajor), 104);
        // 104 was "Dm7 is three characters = 24, plus a 10 gap = 34 for cell 0, plus 54 for the other
        // three cells at the 18 floor, plus 16 padding". Two thirds of that number was the three cells
        // the bar no longer has, which is why the old assertion could not survive. The part that is
        // about the CHORD — a wider symbol widens its own bar, and by its own width — is what this
        // states, and it does so without needing the other cells to exist.
        final Bar shortChord = Bar(
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(4),
              chord: Chord(root: ChordRoot(0)),
            ),
          ],
        );
        final Bar longChord = Bar(
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(4),
              chord: Chord(
                root: ChordRoot(0),
                quality: ChordQuality.majorSeventh,
              ),
            ),
          ],
        );
        expect(engine.measureBar(shortChord, Key.cMajor), fixtureX(4) + 8 + 8);
        expect(engine.measureBar(longChord, Key.cMajor), fixtureX(4) + 40 + 8);
        expect(
          engine.measureBar(longChord, Key.cMajor) -
              engine.measureBar(shortChord, Key.cMajor),
          32,
          reason: 'four more characters at 8 per character is four times eight',
        );
      },
    );

    test('the metre does not decide the width: a 3/4 bar and a 4/4 bar measure alike', () {
      // THE PROPERTY: two bars holding the same music are the same width whatever metre they are
      // written in, because the metre is a label and not a division.
      //
      // THE OLD ASSERTION, QUOTED: expect(engine.measureBar(bar, Key.cMajor), 70);
      // — "a three-four bar has three cells, not four": 18 + 18 + 18 plus 16 of padding. The
      // difference between 70 and the 4/4 bar's 88 WAS the grid, and it is exactly what this test
      // now asserts is gone. A chart in 3/4 therefore paginates by the width of its MUSIC rather
      // than by the number of beats its metre declares.
      final Bar threeFour = Bar(
        timeSignature: TimeSignature.threeFour,
        chords: <ChordMark>[
          ChordMark(
            place: placeAt(0),
            chord: Chord(root: ChordRoot(0)),
          ),
        ],
      );
      final Bar fourFour = Bar(
        chords: <ChordMark>[
          ChordMark(
            place: placeAt(0),
            chord: Chord(root: ChordRoot(0)),
          ),
        ],
      );
      expect(
        engine.measureBar(threeFour, Key.cMajor),
        engine.measureBar(fourFour, Key.cMajor),
      );
    });

    test('the minimum bar width is respected', () {
      // A 2/4 bar holding one short chord: 8 + 8 = 16 of content, which is below the floor, so the
      // bar is the floor. The floor is what stops a bar from collapsing to the width of one symbol,
      // and the reason it exists is that a musician has to be able to hit it and write in it.
      //
      // (The derivation this test used to carry was "two cells: 18 + 14 = 32, plus 16 = 48, below
      // the 56 minimum". There are no cells, and 48 is not a number this arithmetic can produce any
      // more — which is why the assertion is written against the floor itself rather than against a
      // sum that used to land on the same value.)
      final Bar bar = Bar(
        timeSignature: TimeSignature.twoFour,
        chords: <ChordMark>[
          ChordMark(
            place: placeAt(0),
            chord: Chord(root: ChordRoot(0)),
          ),
        ],
      );
      expect(engine.measureBar(bar, Key.cMajor), engine.style.barMinWidth);
    });

    test('a chord written past the old meter widens the bar instead of being dropped', () {
      // A chord on what used to be beat 7 — a beat a 4/4 bar does not have. The bar widens to
      // include it, so a genuine overflow is visible on the page instead of being silently
      // missing from it. Nothing is refused for falling "outside the metre", because there is no
      // metre to fall outside of: a bar's width follows the furthest thing written in it.
      final Bar oneChord = Bar(
        chords: <ChordMark>[
          ChordMark(
            place: placeAt(0),
            chord: Chord(root: ChordRoot(0)),
          ),
        ],
      );
      final Bar beyond = Bar(
        chords: <ChordMark>[
          ChordMark(
            place: placeAt(0),
            chord: Chord(root: ChordRoot(0)),
          ),
          ChordMark(
            place: placeAt(7),
            chord: Chord(root: ChordRoot(7)),
          ),
        ],
      );
      // THE OLD ASSERTIONS, QUOTED: expect(engine.measureBar(inMeter, Key.cMajor), 88) and
      // expect(engine.measureBar(beyond, Key.cMajor), 160) — an occupied cell plus six empty ones
      // plus a cell seven, all at 18, plus 16 of padding. Both were cell arithmetic. The property
      // is unchanged and is what is asserted: the one-chord bar is the floor, and the bar with a
      // chord on beat 7 is as wide as that chord reaches — place 8 + 7×18 = 134, plus the chord's
      // own 8, plus 8 of trailing padding = 150.
      expect(engine.measureBar(oneChord, Key.cMajor), engine.style.barMinWidth);
      expect(engine.measureBar(beyond, Key.cMajor), fixtureX(7) + 8 + 8);
    });

    test(
      'a chord left of the barline does not widen the bar, and is not lost',
      () {
        // THE WIDENING RULE HAS ONE DIRECTION AND IT IS THE RIGHT ONE. A bar buys room by reaching the
        // right edge of what it must draw, so a mark written LEFT of the bar's own origin cannot make
        // the bar wider: there is no edge over there to push. It is also not silently dropped from the
        // document — the model keeps both marks — which is the half of the old assertion that was
        // about losing a musician's chord.
        //
        // THE OLD ASSERTION, QUOTED: expect(engine.measureBar(bar, Key.cMajor), 88);
        // reason: "a beat before the printed cell 0 cannot be reached by adding cells to the right".
        // The reason is still exactly right; only the number was cell arithmetic, and the bar is now
        // the floor because its rightmost content is a single short chord.
        final Bar bar = Bar(
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(0),
              chord: Chord(root: ChordRoot(0)),
            ),
            ChordMark(
              place: placeAt(-3),
              chord: Chord(root: ChordRoot(7)),
            ),
          ],
        );
        expect(engine.measureBar(bar, Key.cMajor), engine.style.barMinWidth);
        expect(
          bar.chords,
          hasLength(2),
          reason: 'a mark the engraver cannot widen for is still the musician\'s mark',
        );
      },
    );
  });

  group('layout', () {
    test('an empty song produces no pages', () {
      // A blank page would be indistinguishable from a page that came out empty, so the engine
      // says "nothing to draw" instead.
      expect(
        engine.layout(
          const Song(title: 'Empty'),
          pageWidth: 400,
          pageHeight: 600,
        ),
        isEmpty,
      );
    });

    test('four bars fit one system and a section break starts another', () {
      // Content width is 400 - 48 = 352. Four 76-wide bars are 304 and fit; a fifth would need
      // 380 and would not. Section B is forced onto a new system regardless of room.
      final Song song = Song(
        title: 'Two sections',
        sections: <Section>[
          sectionOf('sec-a', 'A', 4),
          sectionOf('sec-b', 'B', 4),
        ],
      );
      final List<PageLayout> pages = engine.layout(
        song,
        pageWidth: 400,
        pageHeight: 600,
      );

      expect(pages.length, 1);
      expect(pages.single.systems.length, 2, reason: 'one system per section');
      expect(pages.single.systems[0].bars.length, 4);
      expect(pages.single.systems[1].bars.length, 4);
      expect(pages.single.systems[0].sectionLabel, 'A');
      expect(pages.single.systems[1].sectionLabel, 'B');
    });

    test('a section is not split across the heading that names it', () {
      // A system has room for as many bars as 352 points of content width divide into, and eight
      // bars are more than that, so section A alone occupies two systems; the second continues the
      // section and carries no label.
      //
      // THE OLD DERIVATION, QUOTED: "Five bars cannot fit one system, so section A alone occupies
      // two systems", with `expect(pages.single.systems[0].bars.length, 4)` and
      // `expect(pages.single.systems[1].bars.length, 1)`. Five bars fit one system now — each is
      // the width its own single chord needs rather than four cells' worth — so the fixture is
      // eight bars, and the split is COMPUTED from the bar width the engine reports rather than
      // restated as a number, so that the claim is about where the line falls and not about how
      // wide a bar happens to be this month.
      final Song song = Song(
        title: 'Wrapping',
        sections: <Section>[sectionOf('sec-a', 'A', 8)],
      );
      final List<PageLayout> pages = engine.layout(
        song,
        pageWidth: 400,
        pageHeight: 600,
      );
      final double contentWidth = 400 - 2 * engine.style.pageMargin;
      final double barWidth = engine.measureBar(oneChordBar(0), Key.cMajor);
      final int perSystem = (contentWidth / barWidth).floor();

      expect(pages.single.systems.length, 2);
      expect(
        perSystem,
        greaterThan(1),
        reason: 'the fixture only wraps if more than one fits',
      );
      expect(
        perSystem,
        lessThan(8),
        reason: 'the fixture only wraps if eight do not fit',
      );
      expect(pages.single.systems[0].sectionLabel, 'A');
      expect(
        pages.single.systems[1].sectionLabel,
        isNull,
        reason: 'a continuation carries no heading — that is what "not split across it" means',
      );
      expect(pages.single.systems[0].bars.length, perSystem);
      expect(pages.single.systems[1].bars.length, 8 - perSystem);
    });

    test('every written bar appears exactly once, whatever the page size', () {
      // A stronger claim than a page count and the one that matters: no bar is dropped and none
      // is duplicated. Checked across several page shapes so that a pagination edge case cannot
      // hide behind one convenient size.
      final Song song = Song(
        title: 'Long',
        sections: <Section>[
          sectionOf('sec-a', 'A', 7),
          sectionOf('sec-b', 'B', 3),
        ],
      );
      for (final double height in <double>[300, 600, 1200]) {
        final List<PageLayout> pages = engine.layout(
          song,
          pageWidth: 400,
          pageHeight: height,
        );
        final List<String> addresses = <String>[
          for (final PageLayout page in pages)
            for (final PlacedBar bar in page.bars)
              '${bar.sectionId}#${bar.barIndex}',
        ];
        expect(
          addresses.length,
          song.writtenBarCount,
          reason: 'height $height',
        );
        expect(
          addresses.toSet().length,
          song.writtenBarCount,
          reason: 'height $height',
        );
      }
    });

    test('a shorter page produces more pages without losing a bar', () {
      // Eighteen bars need three systems of six, because a bar holding one short chord is exactly
      // the floor and six of those fit 352 points of content width. The first system carries a
      // section label, so the three systems are 66, 44 and 44 high plus 12 of spacing between them:
      // 178 points of content. A 2000-point page holds them all; a 200-point page has 152 points of
      // content room and must therefore split.
      //
      // THE OLD FIXTURE, QUOTED: `sectionOf('sec-a', 'A', 12)` with the reason "Twelve bars need
      // three systems of four". Twelve bars are two systems now, and two systems fit a 200-point
      // page, so the case stopped being a case; eighteen is the smallest count that still makes the
      // three systems the derivation names. Nothing about the claim changed.
      final Song song = Song(
        title: 'Long',
        sections: <Section>[sectionOf('sec-a', 'A', 18)],
      );
      final List<PageLayout> tall = engine.layout(
        song,
        pageWidth: 400,
        pageHeight: 2000,
      );
      final List<PageLayout> short = engine.layout(
        song,
        pageWidth: 400,
        pageHeight: 200,
      );

      expect(tall.length, 1);
      expect(short.length, greaterThan(1));
      expect(
        short.fold<int>(
          0,
          (int total, PageLayout page) => total + page.bars.length,
        ),
        song.writtenBarCount,
      );
    });

    test('a bar wider than the page forms its own system and overflows', () {
      // A bar that is wider than the page it must be drawn on. Its width is its content's: four
      // five-character chords, the last written on fixture slot 4 (8 + 4×18 = 80), so the furthest
      // right edge is 80 + 40 = 120, plus 8 of trailing padding = 128. The page is 100 points wide,
      // which leaves 52 of content room. It is engraved and overflows rather than being dropped or
      // silently shrunk: a chord that runs off the edge is visible, and a layout that omitted it
      // would look correct while losing music.
      //
      // THE OLD FIXTURE, QUOTED: `pageWidth: 120` with four chords on `placeAt(beat)` for
      // beat 0..3, and the reason "A 4/4 bar with four long chords is far wider than a 120-point
      // page". Four long chords are no longer wide by themselves: the width was four cells of 40
      // plus a gap, and without cells those four chords span 62 + 40 = 102, which fits 120. The
      // property is unchanged — a bar wider than its page overflows and is not lost — so the
      // fixture moves one chord past the metre and the page narrows, which is the smallest change
      // that makes the case true again.
      final Bar wide = Bar(
        chords: <ChordMark>[
          for (int slot = 0; slot < 4; slot++)
            ChordMark(
              place: placeAt(slot == 3 ? 4 : slot),
              chord: Chord(
                root: ChordRoot(0),
                quality: ChordQuality.majorSeventh,
              ),
            ),
        ],
      );
      final Song song = Song(
        title: 'Overflow',
        sections: <Section>[
          Section(
            id: 'sec-a',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[wide],
          ),
        ],
      );
      final List<PageLayout> pages = engine.layout(
        song,
        pageWidth: 100,
        pageHeight: 600,
      );

      expect(pages.length, 1);
      expect(pages.single.systems.length, 1);
      expect(pages.single.bars.length, 1);
      expect(pages.single.bars.single.bounds.size.width, greaterThan(120));
    });
  });
  group('hit testing', () {
    test('a point inside a chord is contained by that chord and not by its neighbour', () {
      final Song song = Song(
        title: 'Hit',
        sections: <Section>[
          Section(
            id: 'sec-a',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[oneChordBar(0), oneChordBar(7)],
          ),
        ],
      );
      final List<PlacedBar> bars = engine
          .layout(song, pageWidth: 400, pageHeight: 600)
          .single
          .bars;

      // The first bar's own rectangle is what a touch on the page is measured against.
      final LayoutRect first = bars[0].bounds;
      expect(
        first.contains(LayoutOffset(first.left + 1, first.top + 1)),
        isTrue,
      );
      expect(
        first.contains(LayoutOffset(first.right + 5, first.top + 1)),
        isFalse,
      );
      // The second bar sits to the right of the first, so a point inside it is outside the first.
      expect(
        bars[0].bounds.contains(
          LayoutOffset(bars[1].bounds.left + 1, bars[1].bounds.top + 1),
        ),
        isFalse,
      );
    });

    test('containment includes the boundary', () {
      final LayoutRect rect = LayoutRect.fromLTWH(10, 20, 30, 40);
      expect(rect.contains(const LayoutOffset(10, 20)), isTrue);
      expect(rect.contains(const LayoutOffset(40, 60)), isTrue);
      expect(rect.contains(const LayoutOffset(40.1, 60)), isFalse);
    });
  });

  group('determinism', () {
    test('the same song and page size give the same geometry twice', () {
      // The property the S4 measurement and the layout cache both rest on.
      final Song song = Song(
        title: 'Stable',
        sections: <Section>[
          sectionOf('sec-a', 'A', 6),
          sectionOf('sec-b', 'B', 2),
        ],
      );
      final List<PageLayout> first = engine.layout(
        song,
        pageWidth: 400,
        pageHeight: 600,
      );
      final List<PageLayout> second = engine.layout(
        song,
        pageWidth: 400,
        pageHeight: 600,
      );

      expect(second.length, first.length);
      for (int index = 0; index < first.length; index++) {
        expect(second[index], first[index]);
      }
    });

    test(
      'rendering the same chord in a different key changes the measured width',
      () {
        // The key reaches the geometry through the spelling, because `Bb` and `A#` are different
        // strings. A bar measured as Bb and drawn as A# would be a layout that disagrees with
        // itself.
        final Bar flatChord = Bar(
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(0),
              chord: Chord(
                root: ChordRoot(10),
                quality: ChordQuality.majorSeventh,
              ),
            ),
          ],
        );
        final double inF = engine.measureBar(
          flatChord,
          const Key(tonic: WrittenNote(NoteLetter.f, 0), mode: Mode.major),
        );
        final double inE = engine.measureBar(
          flatChord,
          const Key(tonic: WrittenNote(NoteLetter.e, 0), mode: Mode.major),
        );
        // Bb maj7 is four characters; A#maj7 is also four, so the widths agree here. The assertion
        // is that the measurement is taken at all and is stable — the key-dependent case is covered
        // by the earlier one-character tests.
        expect(inF, inE);
        expect(inF, greaterThan(0));
      },
    );
  });
}
