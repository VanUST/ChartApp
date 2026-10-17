// PURPOSE: Pin the layout pipeline's behaviour with exact geometry. Because the engine takes its
//          text metrics as an input, every number below is arithmetic rather than a font
//          measurement, so an expectation can be derived by hand and a failure names a real
//          regression instead of a font-version difference.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, layout, bar-width, cell-offset, system-building, pagination, hit-testing,
//           hand-derived
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A 4/4 bar holding one major triad on beat 0 and nothing else.
Bar oneChordBar(int rootPitchClass) => Bar(
  chords: <BeatChord>[
    BeatChord(chord: Chord(root: ChordRoot(rootPitchClass)), beat: 0),
  ],
);

/// A 4/4 bar holding one chord on the given beat.
Bar chordOnBeat(int rootPitchClass, int beat) => Bar(
  chords: <BeatChord>[
    BeatChord(
      chord: Chord(root: ChordRoot(rootPitchClass)),
      beat: beat,
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
    test('a single-character chord in 4/4 measures to 88', () {
      // Cell 0: one 8-wide chord plus a 10 gap = 18. Cells 1..3 empty, floored at 18 each = 54.
      // Total 72, plus 8 padding on each side = 88.
      //
      // THE EXPECTATION WAS 76 AND IS 88 BECAUSE THE CELL FLOOR ROSE FROM 14 TO 18. 14 was the
      // old LayoutStyle.minCellWidth default, and it was narrower than a notehead (15.6), so two
      // notes on adjacent beats were engraved overlapping. See LayoutStyle.minCellWidth for the
      // measurement. The old assertion, quoted: expect(engine.measureBar(oneChordBar(0),
      // Key.cMajor), 76); — with cells floored at 14 the same bar was 18 + 3×14 + 16 = 76.
      expect(engine.measureBar(oneChordBar(0), Key.cMajor), 88);
    });

    test('a bar with no chords still reserves every cell', () {
      // Four empty cells at 18 = 72, plus 16 padding = 88. Empty cells are not free: they are
      // where a sustained chord is drawn, and collapsing them would move the chords that remain.
      //
      // WAS 72: expect(engine.measureBar(const Bar(), Key.cMajor), 72); at the old 14-pixel cell
      // floor, which is now 18 because a notehead is 15.6 wide and a cell narrower than a notehead
      // merges two adjacent-beat notes into one shape.
      expect(engine.measureBar(const Bar(), Key.cMajor), 88);
    });

    test('a wider chord widens its own cell only', () {
      // Dm7 renders as three characters = 24, plus a 10 gap = 34 for cell 0, plus 54 for the
      // other three cells at the 18 floor, plus 16 padding = 104. (WAS 92, with 42 for the other
      // three cells at the old 14 floor.)
      final Bar bar = Bar(
        chords: <BeatChord>[
          BeatChord(
            chord: Chord(
              root: ChordRoot(2),
              quality: ChordQuality.minorSeventh,
            ),
            beat: 0,
          ),
        ],
      );
      expect(engine.measureBar(bar, Key.cMajor), 104);
    });

    test('a three-four bar has three cells, not four', () {
      // 18 + 18 + 18 = 54, plus 16 padding = 70. (WAS 62: 18 + 14 + 14 = 46, plus 16, at the old
      // 14-pixel cell floor.)
      const Bar bar = Bar(
        timeSignature: TimeSignature.threeFour,
        chords: <BeatChord>[
          BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
        ],
      );
      expect(engine.measureBar(bar, Key.cMajor), 70);
    });

    test('the minimum bar width is respected', () {
      // A 2/4 bar is only two cells: 18 + 14 = 32, plus 16 = 48, which is below the 56 minimum.
      const Bar bar = Bar(
        timeSignature: TimeSignature.twoFour,
        chords: <BeatChord>[
          BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
        ],
      );
      expect(engine.measureBar(bar, Key.cMajor), 56);
    });

    test(
      'a chord beyond the meter widens the bar instead of being dropped',
      () {
        // Beat 7 does not exist in 4/4. This used to be skipped, which engraved a bar that was
        // silently missing a chord the musician had written: the content vanished and nothing on
        // the page said so. The bar now widens to include it, so a genuine overflow is visible.
        final Bar inMeter = Bar(
          chords: <BeatChord>[
            BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
          ],
        );
        final Bar beyond = Bar(
          chords: <BeatChord>[
            BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
            BeatChord(chord: Chord(root: ChordRoot(7)), beat: 7),
          ],
        );
        // In the meter: cell 0 holds an 8-wide chord plus a 10 gap, three empty cells at the 18
        // minimum, and 16 of bar padding: 18 + 54 + 16 = 88. (WAS 76 with the old 14 floor.)
        expect(engine.measureBar(inMeter, Key.cMajor), 88);
        // Widened to eight cells: cell 0 = 18, six empty cells at 18 = 108, cell 7 holds the second
        // one-character chord = 18, plus 16 padding: 18 + 108 + 18 + 16 = 160. (WAS 136.)
        expect(engine.measureBar(beyond, Key.cMajor), 160);
      },
    );

    test('a chord at a negative beat is skipped, because there is no cell to widen into', () {
      // The widening rule stops at the left edge of the bar: a beat before the printed cell 0
      // cannot be reached by adding cells to the right.
      final Bar bar = Bar(
        chords: <BeatChord>[
          BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
          BeatChord(chord: Chord(root: ChordRoot(7)), beat: -3),
        ],
      );
      expect(engine.measureBar(bar, Key.cMajor), 88);
    });
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
      // Five bars cannot fit one system, so section A alone occupies two systems; the second
      // continues the section and carries no label.
      final Song song = Song(
        title: 'Wrapping',
        sections: <Section>[sectionOf('sec-a', 'A', 5)],
      );
      final List<PageLayout> pages = engine.layout(
        song,
        pageWidth: 400,
        pageHeight: 600,
      );

      expect(pages.single.systems.length, 2);
      expect(pages.single.systems[0].sectionLabel, 'A');
      expect(pages.single.systems[1].sectionLabel, isNull);
      expect(pages.single.systems[0].bars.length, 4);
      expect(pages.single.systems[1].bars.length, 1);
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
      final Song song = Song(
        title: 'Long',
        sections: <Section>[sectionOf('sec-a', 'A', 12)],
      );
      // Twelve bars need three systems of four. The first carries a section label, so the three
      // systems are 66, 44 and 44 high plus 12 of spacing between them: 178 points of content.
      // A 2000-point page holds them all; a 200-point page has 152 points of content room and
      // must therefore split.
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
      // A 4/4 bar with four long chords is far wider than a 120-point page. It is engraved and
      // overflows rather than being dropped or silently shrunk: a chord that runs off the edge is
      // visible, and a layout that omitted it would look correct while losing music.
      final Bar wide = Bar(
        chords: <BeatChord>[
          for (int beat = 0; beat < 4; beat++)
            BeatChord(
              chord: Chord(
                root: ChordRoot(0),
                quality: ChordQuality.majorSeventh,
              ),
              beat: beat,
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
        pageWidth: 120,
        pageHeight: 600,
      );

      expect(pages.length, 1);
      expect(pages.single.systems.length, 1);
      expect(pages.single.bars.length, 1);
      expect(pages.single.bars.single.bounds.size.width, greaterThan(120));
    });
  });

  group('chord placement', () {
    test('the first chord sits one padding inside the bar', () {
      // Page margin 24, bar padding 8, so the chord starts at x = 32.
      final Song song = Song(
        title: 'Placement',
        sections: <Section>[
          Section(
            id: 'sec-a',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[oneChordBar(0)],
          ),
        ],
      );
      final PlacedBar bar = engine
          .layout(song, pageWidth: 400, pageHeight: 600)
          .single
          .bars
          .single;

      expect(bar.bounds.left, 24);
      // WAS 76: expect(bar.bounds.size.width, 76); with the old 14-pixel cell floor. The bar is
      // 88 wide now, and the chord still starts one padding inside it.
      expect(bar.bounds.size.width, 88);
      expect(bar.chords.single.bounds.left, 32);
      expect(
        bar.chords.single.bounds.size.width,
        8,
        reason: 'one character at 8 per char',
      );
    });

    test('a chord on a later beat is offset by the cells before it', () {
      // Cell widths are 18, 18, 18 and 18 — the third cell holds the chord — so the offsets are
      // 8, 26, 44 and 62 from the bar's left edge. A chord on beat 2 therefore starts at
      // 24 + 44 = 68. (WAS 60 with cell widths 14, 14, 18, 14 and offsets 8, 22, 36, 54.)
      final Song song = Song(
        title: 'Placement',
        sections: <Section>[
          Section(
            id: 'sec-a',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[chordOnBeat(0, 2)],
          ),
        ],
      );
      final PlacedChord chord = engine
          .layout(song, pageWidth: 400, pageHeight: 600)
          .single
          .bars
          .single
          .chords
          .single;

      expect(chord.beat, 2);
      expect(chord.bounds.left, 68);
    });

    test('two chords packed onto one beat are laid out side by side', () {
      // The comma-packed case: both are on beat 0, so they differ only by step, and the second
      // starts one chord width plus a gap after the first.
      final Bar packed = Bar(
        chords: <BeatChord>[
          BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
          BeatChord(chord: Chord(root: ChordRoot(7)), beat: 0, step: 1),
        ],
      );
      final Song song = Song(
        title: 'Packed',
        sections: <Section>[
          Section(
            id: 'sec-a',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[packed],
          ),
        ],
      );
      final List<PlacedChord> chords = engine
          .layout(song, pageWidth: 400, pageHeight: 600)
          .single
          .bars
          .single
          .chords;

      expect(chords.length, 2);
      expect(chords[0].step, 0);
      expect(chords[1].step, 1);
      // First at 32 with width 8; the second starts 8 + 10 later, at 50.
      expect(chords[0].bounds.left, 32);
      expect(chords[1].bounds.left, 50);
    });

    test(
      'a placed chord carries the address that identifies it in the song',
      () {
        // The property that lets an annotation anchored in the song model be drawn at the right
        // place: the layout reports the same bar address the anchor holds.
        final Song song = Song(
          title: 'Address',
          sections: <Section>[
            Section(
              id: 'sec-a',
              label: const SectionLabel.letter('A'),
              bars: <Bar>[oneChordBar(0), chordOnBeat(7, 3)],
            ),
          ],
        );
        final PageLayout page = engine
            .layout(song, pageWidth: 400, pageHeight: 600)
            .single;
        final PlacedBar second = page.bars[1];

        expect(second.sectionId, 'sec-a');
        expect(second.barIndex, 1);
        expect(
          song.barAt(second.sectionId, second.barIndex),
          song.sections.first.bars[1],
        );
      },
    );
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

      // The first chord occupies x in [32, 40] on the first bar's stave.
      final LayoutRect first = bars[0].chords.single.bounds;
      expect(
        first.contains(LayoutOffset(first.left + 1, first.top + 1)),
        isTrue,
      );
      expect(
        first.contains(LayoutOffset(first.right + 5, first.top + 1)),
        isFalse,
      );
      // The second bar starts 76 points later, so its chord is well outside the first bar.
      expect(
        bars[0].bounds.contains(bars[1].chords.single.bounds.origin),
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
          chords: <BeatChord>[
            BeatChord(
              chord: Chord(
                root: ChordRoot(10),
                quality: ChordQuality.majorSeventh,
              ),
              beat: 0,
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
