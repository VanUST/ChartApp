// PURPOSE: Write a `.chart` file that carries a melody, using the container's own encoder, so the
//          document can be opened on the owner's tablet through the application's own file chooser.
//          The chart is a fixture for a visual check — "do the notes come back, and are they drawn"
//          — and building it here rather than by tapping keeps the check about the ROUND TRIP rather
//          than about the driver's aim.
// INPUTS: One argument: the path to write. Defaults to `note-fixture.chart` in the current directory.
// OUTPUTS: The file, and one line on stdout naming its path, its byte count and every note in it.
// KEYWORDS: tool, chart-file, melody, fixture, device-verification, not-part-of-the-library
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';

import '../support/place_fixture.dart';

/// The melody of bar 1: a stacked pair on one beat and an eighth note tied forward.
List<NoteMark> _barOne() => <NoteMark>[
  NoteMark(
    place: placeAt(0),
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.c, 0), octave: 5),
    value: const NoteValue.plain(NoteBase.half),
  ),
  NoteMark(
    place: placeAt(0, 1),
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.e, 0), octave: 4),
    value: const NoteValue.plain(NoteBase.quarter),
  ),
  NoteMark(
    place: placeAt(2),
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.g, 0), octave: 5),
    value: const NoteValue.plain(NoteBase.eighth),
    tiedToNext: true,
  ),
];

/// The melody of bar 2: a sharp, a flat and a note high enough to need ledger lines.
List<NoteMark> _barTwo() => <NoteMark>[
  NoteMark(
    place: placeAt(0),
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.f, 1), octave: 4),
    value: const NoteValue.plain(NoteBase.quarter),
  ),
  NoteMark(
    place: placeAt(1),
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.b, -1), octave: 4),
    value: const NoteValue.plain(NoteBase.quarter),
  ),
  NoteMark(
    place: placeAt(2),
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.a, 0), octave: 5),
    value: const NoteValue.plain(NoteBase.half),
  ),
];

/// A one-section chart of [bars] bars, whose FIRST TWO bars carry the melody above.
///
/// The two bars are separate lists and each is handed to the bar it belongs to. An earlier version of
/// this file built one list and passed it to bar 1 alone, so all six notes sat in bar 1 while the
/// notes meant for the second bar stayed in it — which the engraved page then drew exactly as
/// written, and which took a printed geometry dump to tell from an engraving defect.
Song _song(int bars) => Song(
  id: 'note-fixture',
  title: 'Noty - proba',
  key: Key.cMajor,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < bars; index++)
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: placeAt(0),
                chord: Chord(
                  root: ChordRoot(<int>[0, 7, 9, 5][index % 4]),
                  quality: ChordQuality.majorTriad,
                ),
              ),
            ],
            melody: switch (index) {
              0 => _barOne(),
              1 => _barTwo(),
              _ => const <NoteMark>[],
            },
          ),
      ],
    ),
  ],
);

void main(List<String> args) {
  final String path = args.isEmpty ? 'note-fixture.chart' : args.first;
  final Song song = _song(8);
  // The container's own shape: a snapshot plus the operations after it. This fixture has no history
  // to replay, so the snapshot is the whole chart and the tail is empty — which is exactly what the
  // application's own `chartFileFor` writes for a document with no edits since it was opened.
  final ChartFile file = ChartFile(
    metadata: const ChartMetadata(docId: 'note-fixture', writer: 'chartapp'),
    snapshot: DocumentState(song: song),
  );
  final Uint8List bytes = ChartFileCodec.encode(file).bytes;
  File(path).writeAsBytesSync(bytes);
  stdout.writeln('fixture path=$path bytes=${bytes.length} bars=8');
  final ChartFileDecodeResult back = ChartFileCodec.decode(bytes);
  for (final Section section in back.file.reducedDocument.song.sections) {
    for (int index = 0; index < section.bars.length; index++) {
      for (final NoteMark note in section.bars[index].melody) {
        stdout.writeln(
          'fixture note bar=${index + 1} beat=${note.offsetX.toStringAsFixed(1)} '
          'pitch=${note.pitch} value=${note.value}'
          '${note.tiedToNext ? ' tied' : ''}',
        );
      }
    }
  }
}
