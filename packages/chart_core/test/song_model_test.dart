// PURPOSE: Pin the song model's addressing and structural vocabulary — that a bar is found by
//          its section id and its index, that two chords packed onto one beat are still two
//          distinguishable places, and that the marks a chart draws around a bar survive on the
//          bar rather than being flattened away. These are the properties the annotation
//          anchors, the layout engine and the iReal codec all stand on.
// INPUTS: None.
// OUTPUTS: Pass/fail per expectation.
// KEYWORDS: test, song-model, bar, section, anchor, volta, repeat, time-signature, hand-derived
import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A bar in 4/4 with a Dm7 on beat one and a G7 on beat one, one step later.
///
/// Two chords sharing a beat is what a comma packs into one cell, and it is the case an anchor
/// has to keep apart.
const Bar _packedBeat = Bar(
  chords: <BeatChord>[
    BeatChord(
      chord: Chord(root: ChordRoot(2), quality: ChordQuality.minorSeventh),
      beat: 0,
    ),
    BeatChord(
      chord: Chord(root: ChordRoot(7), quality: ChordQuality.dominantSeventh),
      beat: 0,
      step: 1,
    ),
  ],
);

/// A bar that carries no chords, which means the previous chord sustains.
const Bar _sustainingBar = Bar();

/// A two-bar repeated passage with a first and a second ending.
const List<Bar> _repeatedPassage = <Bar>[
  Bar(
    openingBarline: Barline.repeatStart,
    volta: Volta(1),
    chords: <BeatChord>[BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0)],
  ),
  Bar(closingBarline: Barline.repeatEnd, volta: Volta(1)),
  Bar(volta: Volta(2), marks: <BarMark>{BarMark.fermata}),
  Bar(closingBarline: Barline.finalBar),
];

void main() {
  group('TimeSignature', () {
    test('gives a simple meter one cell per beat', () {
      expect(TimeSignature.fourFour.cellsPerBar, 4);
      expect(TimeSignature.threeFour.cellsPerBar, 3);
      expect(TimeSignature.twoFour.cellsPerBar, 2);
    });

    test('gives a compound meter one cell per dotted beat', () {
      // 6/8 is two dotted-quarter beats, not six eighth-note cells.
      expect(TimeSignature.sixEight.cellsPerBar, 2);
      expect(const TimeSignature(numerator: 12, denominator: 8).cellsPerBar, 4);
      expect(const TimeSignature(numerator: 9, denominator: 8).cellsPerBar, 3);
    });

    test(
      'counts an irregular meter plainly rather than pretending it is compound',
      () {
        // 7/8 is genuinely seven uneven beats; dividing by three would invent a beat structure.
        expect(
          const TimeSignature(numerator: 7, denominator: 8).cellsPerBar,
          7,
        );
        expect(
          const TimeSignature(numerator: 5, denominator: 4).cellsPerBar,
          5,
        );
        expect(
          const TimeSignature(numerator: 2, denominator: 2).cellsPerBar,
          2,
        );
      },
    );
  });

  group('BeatChord addressing', () {
    test('two chords packed onto one beat differ by their step', () {
      const BeatChord first = BeatChord(
        chord: Chord(root: ChordRoot(2)),
        beat: 0,
      );
      const BeatChord second = BeatChord(
        chord: Chord(root: ChordRoot(2)),
        beat: 0,
        step: 1,
      );
      // Same chord, same beat, different place in the bar.
      expect(first.chord, second.chord);
      expect(first.beat, second.beat);
      expect(first == second, isFalse);
    });

    test('the default step is zero and the default size is normal', () {
      const BeatChord chord = BeatChord(
        chord: Chord(root: ChordRoot(0)),
        beat: 2,
      );
      expect(chord.step, 0);
      expect(chord.size, ChordSize.normal);
    });

    test('size is part of equality', () {
      const BeatChord normal = BeatChord(
        chord: Chord(root: ChordRoot(0)),
        beat: 0,
      );
      const BeatChord small = BeatChord(
        chord: Chord(root: ChordRoot(0)),
        beat: 0,
        size: ChordSize.small,
      );
      expect(normal == small, isFalse);
    });
  });

  group('Bar', () {
    test('defaults to an empty bar in 4/4 bounded by single barlines', () {
      expect(_sustainingBar.chords, isEmpty);
      expect(_sustainingBar.timeSignature, TimeSignature.fourFour);
      expect(_sustainingBar.openingBarline, Barline.single);
      expect(_sustainingBar.closingBarline, Barline.single);
      expect(_sustainingBar.volta, isNull);
      expect(_sustainingBar.repeatPrevious, RepeatPrevious.none);
      expect(_sustainingBar.slashRepeat, isFalse);
      expect(_sustainingBar.noChord, isFalse);
      expect(_sustainingBar.marks, isEmpty);
      expect(_sustainingBar.staffText, isEmpty);
    });

    test('a bar with no chords is valid and means the chord sustains', () {
      expect(_sustainingBar.chords, isEmpty);
      expect(_sustainingBar.noChord, isFalse);
    });

    test('recognises the barlines that open and close a repeat', () {
      expect(_repeatedPassage[0].startsRepeat, isTrue);
      expect(_repeatedPassage[0].endsRepeat, isFalse);
      expect(_repeatedPassage[1].endsRepeat, isTrue);
      expect(_repeatedPassage[1].startsRepeat, isFalse);
    });

    test('carries its own meter, so a mid-song change is not lost', () {
      const Bar inThree = Bar(timeSignature: TimeSignature.threeFour);
      expect(inThree.timeSignature, TimeSignature.threeFour);
      expect(inThree == _sustainingBar, isFalse);
    });

    test('preserves a stateful repeat-previous marker', () {
      const Bar repeatsTwo = Bar(repeatPrevious: RepeatPrevious.twoBars);
      expect(repeatsTwo.repeatPrevious, RepeatPrevious.twoBars);
      expect(repeatsTwo == _sustainingBar, isFalse);
    });

    test('preserves marks and staff text verbatim', () {
      const Bar marked = Bar(
        marks: <BarMark>{BarMark.segno, BarMark.coda},
        staffText: <String>['D.C. al Coda'],
      );
      expect(marked.marks, contains(BarMark.segno));
      expect(marked.marks, contains(BarMark.coda));
      expect(marked.staffText, <String>['D.C. al Coda']);
      expect(marked == _sustainingBar, isFalse);
    });

    test('keeps two chords on one beat in order under equality', () {
      expect(_packedBeat.chords.length, 2);
      expect(_packedBeat.chords[0].step, 0);
      expect(_packedBeat.chords[1].step, 1);
      // Built the other way round, the same bar is a different bar.
      const Bar reversed = Bar(
        chords: <BeatChord>[
          BeatChord(
            chord: Chord(
              root: ChordRoot(7),
              quality: ChordQuality.dominantSeventh,
            ),
            beat: 0,
            step: 1,
          ),
          BeatChord(
            chord: Chord(
              root: ChordRoot(2),
              quality: ChordQuality.minorSeventh,
            ),
            beat: 0,
          ),
        ],
      );
      expect(reversed == _packedBeat, isFalse);
    });

    test(
      'a bar with an unnumbered bracket differs from one with no bracket',
      () {
        const Bar numbered = Bar(volta: Volta(1));
        const Bar unnumbered = Bar(volta: Volta(0));
        expect(numbered == unnumbered, isFalse);
        expect(unnumbered.volta, isNotNull);
        expect(unnumbered.volta! == Volta(0), isTrue);
      },
    );
  });

  group('Section', () {
    test('labels a rehearsal letter without reading meaning into it', () {
      const SectionLabel label = SectionLabel.letter('B');
      expect(label.kind, SectionKind.letter);
      expect(label.text, 'B');
      // B is a name here, not a bridge.
      expect(label.toString(), 'B');
    });

    test('carries a stable id that is not its position', () {
      const Section first = Section(
        id: 'sec-a',
        label: SectionLabel.letter('A'),
      );
      const Section second = Section(
        id: 'sec-b',
        label: SectionLabel.letter('A'),
      );
      // Same label, different identity: the label is what is printed, the id is what an anchor
      // holds, and a tune can contain two sections labelled A.
      expect(first.label, second.label);
      expect(first == second, isFalse);
    });

    test('compares its bars in order', () {
      const Section one = Section(
        id: 's',
        label: SectionLabel.letter('A'),
        bars: <Bar>[_packedBeat, _sustainingBar],
      );
      const Section other = Section(
        id: 's',
        label: SectionLabel.letter('A'),
        bars: <Bar>[_sustainingBar, _packedBeat],
      );
      expect(one == other, isFalse);
    });
  });

  group('Song', () {
    const Song song = Song(
      id: 'doc-1',
      title: 'Probe',
      composer: 'LastName FirstName',
      style: 'Medium Swing',
      key: Key.cMajor,
      tempo: 140,
      sections: <Section>[
        Section(
          id: 'sec-a',
          label: SectionLabel.letter('A'),
          bars: <Bar>[_packedBeat, _sustainingBar],
        ),
        Section(
          id: 'sec-b',
          label: SectionLabel.letter('B'),
          bars: _repeatedPassage,
        ),
      ],
    );

    test('counts the bars it was given and lists them in reading order', () {
      expect(song.writtenBarCount, 6);
      expect(song.barsInReadingOrder.length, 6);
      // Reading order is section A's bars, then section B's.
      expect(song.barsInReadingOrder[0], _packedBeat);
      expect(song.barsInReadingOrder[1], _sustainingBar);
      expect(song.barsInReadingOrder[2], _repeatedPassage[0]);
    });

    test('resolves a section by id, not by position', () {
      expect(song.sectionById('sec-b')?.label.text, 'B');
      expect(song.sectionById('missing'), isNull);
    });

    test('resolves an anchor to the bar it names', () {
      expect(song.barAt('sec-a', 0), _packedBeat);
      expect(song.barAt('sec-b', 1), _repeatedPassage[1]);
    });

    test(
      'answers null for an anchor that names nothing, rather than throwing',
      () {
        // A dangling anchor is ordinary during an import or a partial merge; the caller decides
        // whether it is worth reporting.
        expect(
          song.barAt('sec-a', 2),
          isNull,
          reason: 'past the end of the section',
        );
        expect(song.barAt('sec-a', -1), isNull, reason: 'before the start');
        expect(song.barAt('nope', 0), isNull, reason: 'unknown section');
      },
    );

    test(
      'an empty tempo means unset and is distinguishable from a real one',
      () {
        const Song untimed = Song(title: 'Untimed');
        expect(untimed.tempo, 0);
        expect(song.tempo, 140);
        expect(untimed == song, isFalse);
      },
    );

    test('equality covers every part including the key', () {
      const Song sameKeyDifferentTitle = Song(title: 'Other', key: Key.cMajor);
      const Song sameTitleDifferentKey = Song(
        title: 'Untimed',
        key: Key(tonic: WrittenNote(NoteLetter.g, 0), mode: Mode.major),
      );
      expect(sameKeyDifferentTitle == sameTitleDifferentKey, isFalse);
      expect(const Song(title: 'X') == const Song(title: 'X'), isTrue);
    });
  });
}
