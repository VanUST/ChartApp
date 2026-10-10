// PURPOSE: Print the performance order that `derivePlayOrder` produces for a set of hand-made
//          charts, one line per played bar, so that the reading of every ambiguous repeat shape can
//          be read off rather than inferred from a pass/fail. A derivation and its own unit test
//          agree by construction; this probe prints the played written bars, the sounding bars and
//          the pass numbers so a musician can check them against what the chart says.
// INPUTS: None. Every fixture is built here from chords and barlines; one of them is assembled by
//         the real iReal parser so that the derivation is exercised on a chart nobody hand-built.
// OUTPUTS: One block per song: its written bars labelled by their chord, every played position with
//          its written bar, sounding bar and pass, then the repeat passages and the issues. Prints
//          a property line per song — how often each written bar sounds — and exits 1 when a
//          fixture's played count does not match the count this file states for it.
// KEYWORDS: probe, play-order, repeat, volta, percent, trace, evidence, not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// Semitone names for the chord roots this probe uses.
const List<String> _rootNames = <String>[
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

int _failures = 0;

void main() {
  _trace(
    'no repeats at all',
    _song(<Bar>[_bar(0), _bar(5), _bar(7), _bar(0)]),
    expectedPlayed: 4,
  );
  _trace(
    'plain repeat',
    _song(<Bar>[
      _bar(0, opening: Barline.repeatStart),
      _bar(5, closing: Barline.repeatEnd),
      _bar(7),
      _bar(0),
    ]),
    expectedPlayed: 6,
  );
  _trace(
    'voltas, assembled by the iReal parser from T44{C |A- |N1D- |G7 } |N2D- G7 |C6 Z',
    _parsed('*AT44{C |A- |N1D- |G7 } |N2D- G7 |C6 Z'),
    expectedPlayed: 8,
  );
  _trace(
    'percent bars: x after a chord, then r after x',
    _song(<Bar>[
      _bar(0),
      _bar(5),
      _bar(7),
      _percent(RepeatPrevious.oneBar),
      _bar(9),
      _percent(RepeatPrevious.twoBars),
    ]),
    expectedPlayed: 7,
  );

  stdout.writeln('');
  stdout.writeln('--- ambiguous cases ---');
  stdout.writeln('');
  _trace(
    'a percent bar as the first bar of the song',
    _song(<Bar>[_percent(RepeatPrevious.oneBar), _bar(5)]),
    expectedPlayed: 2,
  );
  _trace(
    'a percent bar chained onto another percent bar',
    _song(<Bar>[
      _bar(0),
      _bar(5),
      _percent(RepeatPrevious.oneBar),
      _percent(RepeatPrevious.oneBar),
    ]),
    expectedPlayed: 4,
  );
  _trace(
    'a repeat start with no repeat end',
    _song(<Bar>[_bar(0, opening: Barline.repeatStart), _bar(5)]),
    expectedPlayed: 2,
  );
  _trace(
    'a repeat end with no repeat start',
    _song(<Bar>[_bar(0), _bar(5, closing: Barline.repeatEnd)]),
    expectedPlayed: 2,
  );
  _trace(
    'nested repeats: outer { A { B C } D }',
    _song(<Bar>[
      _bar(0, opening: Barline.repeatStart),
      _bar(5, opening: Barline.repeatStart),
      _bar(7, closing: Barline.repeatEnd),
      _bar(9, closing: Barline.repeatEnd),
    ]),
    // The inner passage is played in full on each of the outer's two passes, so its three bars
    // sound four times and the outer's two remaining bars twice: 4 + 4 + 4 = 12.
    expectedPlayed: 12,
  );
  _trace(
    'an unnumbered bracket under a repeat',
    _song(<Bar>[
      _bar(0, opening: Barline.repeatStart, volta: const Volta(0)),
      _bar(5, closing: Barline.repeatEnd, volta: const Volta(0)),
    ]),
    expectedPlayed: 4,
  );
  _trace(
    'a bracket that no repeat contains',
    _song(<Bar>[_bar(0), _bar(5, volta: const Volta(1)), _bar(7)]),
    expectedPlayed: 3,
  );
  _trace(
    'a lone first-ending bracket over the whole passage',
    _song(<Bar>[
      _bar(0, opening: Barline.repeatStart, volta: const Volta(1)),
      _bar(5, closing: Barline.repeatEnd, volta: const Volta(1)),
      _bar(7),
    ]),
    expectedPlayed: 3,
  );
  _trace(
    'three passes from brackets 2 and 3',
    _song(<Bar>[
      _bar(0, opening: Barline.repeatStart),
      _bar(5, closing: Barline.repeatEnd),
      _bar(7, volta: const Volta(2)),
      _bar(9, volta: const Volta(3)),
    ]),
    expectedPlayed: 8,
  );
  _trace(
    'a repeat that crosses a section boundary',
    _twoSectionSong(),
    expectedPlayed: 5,
  );
  _trace('a song of no bars', const Song(title: 'empty'), expectedPlayed: 0);
  _trace(
    'a song with an empty section beside a non-empty one',
    const Song(
      title: 'empty section',
      sections: <Section>[
        Section(id: 'sec-A-0', label: SectionLabel.letter('A')),
        Section(
          id: 'sec-B-0',
          label: SectionLabel.letter('B'),
          bars: <Bar>[
            Bar(
              chords: <BeatChord>[
                BeatChord(chord: Chord(root: ChordRoot(0)), beat: 0),
              ],
            ),
          ],
        ),
      ],
    ),
    expectedPlayed: 1,
  );

  stdout.writeln('');
  stdout.writeln('FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

// ---------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------

/// A one-chord bar on the given [root], with the structure the caller asks for.
Bar _bar(
  int root, {
  Barline opening = Barline.single,
  Barline closing = Barline.single,
  Volta? volta,
}) => Bar(
  openingBarline: opening,
  closingBarline: closing,
  volta: volta,
  chords: <BeatChord>[BeatChord(chord: Chord(root: ChordRoot(root)), beat: 0)],
);

/// A bar that writes no chord and carries only a repeat-previous symbol, as a `%` bar does.
Bar _percent(RepeatPrevious previous) => Bar(repeatPrevious: previous);

/// A one-section song holding [bars].
Song _song(List<Bar> bars) => Song(
  title: 'probe',
  sections: <Section>[
    Section(id: 'sec-A-0', label: const SectionLabel.letter('A'), bars: bars),
  ],
);

/// A song whose repeat starts in A and ends in B, so the passage crosses a section boundary.
Song _twoSectionSong() => Song(
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

/// The song the real iReal assembler builds from [notation].
Song _parsed(String notation) => parseIRealNotation(notation).song;

// ---------------------------------------------------------------------------------------------
// Printing
// ---------------------------------------------------------------------------------------------

/// Prints the written bars of [song], every played position, the passages and the issues.
void _trace(String title, Song song, {required int expectedPlayed}) {
  stdout.writeln('=== $title');
  stdout.writeln('written : ${_writtenTrace(song)}');
  final PlayOrder order = derivePlayOrder(song);
  stdout.writeln('played  : ${order.length} position(s)');
  for (final PlayedBar bar in order.played) {
    final String chain = bar.passes
        .map(
          (PlayedPass pass) =>
              '${pass.repeatStart}=${pass.pass}/${pass.passCount}',
        )
        .join(' in ');
    stdout.writeln(
      '  ${bar.position.toString().padLeft(2)}'
      '  written=${_label(song, bar.written).padRight(2)}'
      '  source=${_label(song, bar.source).padRight(2)}'
      '  pass=${bar.pass}/${bar.passCount}'
      '${chain.isEmpty ? '' : '  passages=$chain'}',
    );
  }
  stdout.writeln('sounding: ${_soundTrace(song, order)}');
  for (final RepeatPassage passage in order.passages) {
    stdout.writeln('passage : $passage');
  }
  for (final PlayOrderIssue issue in order.issues) {
    stdout.writeln('issue   : ${issue.message}');
  }
  if (order.length != expectedPlayed) {
    _failures++;
    stdout.writeln(
      'MISMATCH: expected $expectedPlayed played position(s), got ${order.length}',
    );
  }
  stdout.writeln('');
}

/// The written bars as `<address>=<label>`, in reading order.
String _writtenTrace(Song song) => song.sections
    .expand(
      (Section section) => section.bars.indexed.map(
        ((int, Bar) pair) => '${section.id}[${pair.$1}]=${_barLabel(pair.$2)}',
      ),
    )
    .join(' ');

/// The sounding written bar of every played position, as a space-separated label list.
String _soundTrace(Song song, PlayOrder order) => order.sources
    .map((WrittenBarAddress address) => _label(song, address))
    .join(' ');

/// How often each sounding written bar appears, so a lost or extra pass is visible.
String _label(Song song, WrittenBarAddress address) {
  final Bar? bar = song.barAt(address.sectionId, address.barIndex);
  return bar == null ? '?' : _barLabel(bar);
}

/// A bar's label: the root of its first chord, or a dash when it writes none.
String _barLabel(Bar bar) {
  if (bar.chords.isEmpty) {
    return '-';
  }
  return _rootNames[bar.chords.first.chord.root.pitchClass];
}
