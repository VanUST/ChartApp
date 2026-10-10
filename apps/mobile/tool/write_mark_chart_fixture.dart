// PURPOSE: Put a real `.chart` file on disk for a headless BROWSER to be driven with, because a
//          browser can only be handed a file that already exists and the file has to be one whose
//          bars a driver can name: the container is built by the same `chartFileFor` and
//          `ChartFileCodec` the Save button uses, and the song is four bars in one section with a
//          different chord on each, so a sign a browser press writes can be seen to have landed on
//          the bar the driver selected rather than on a neighbour.
//
//          It carries NO mark, deliberately: the run that drives a mark button through its semantic
//          node is evidence that the button PUTS a sign on the bar, and a bar that already carried
//          one could not show that. Imports no Flutter, which is why plain `dart run` can execute it.
// INPUTS: An optional output directory as the first argument, defaulting to `build/chart_fixtures`
//         under the current directory. The directory is created when it does not exist.
// OUTPUTS: One file, `marks.chart`, and one line with its absolute path and byte count, so a
//          browser-driving tool can be given the path without a second lookup.
// KEYWORDS: fixtures, chart-file, browser-verification, bar-mark, dart-run, headless
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';
import 'package:chartapp/chart_document.dart';

void main(List<String> arguments) {
  final Directory directory = Directory(
    arguments.isNotEmpty ? arguments.first : 'build/chart_fixtures',
  );
  directory.createSync(recursive: true);

  final Song song = Song(
    id: 'chartapp-mark-fixture',
    title: 'Mark Fixture',
    composer: 'ChartApp',
    style: 'Medium Swing',
    key: Key.cMajor,
    tempo: 120,
    sections: <Section>[
      Section(
        id: 'A',
        label: const SectionLabel.letter('A'),
        bars: <Bar>[
          for (int index = 0; index < 4; index++)
            Bar(
              chords: <BeatChord>[
                BeatChord(
                  chord: Chord(
                    root: ChordRoot(index * 2),
                    quality: ChordQuality.majorSeventh,
                  ),
                  beat: 0,
                ),
              ],
            ),
        ],
      ),
    ],
  );

  final ChartFile file = chartFileFor(
    DocumentState(song: song),
    modifiedAt: DateTime.utc(2026, 11, 1, 12),
  );
  final Uint8List bytes = ChartFileCodec.encode(file).bytes;
  final File written = File(
    '${directory.path}${Platform.pathSeparator}marks.chart',
  );
  written.writeAsBytesSync(bytes, flush: true);
  if (written.lengthSync() != bytes.length) {
    throw FileSystemException(
      'the fixture was written short: expected ${bytes.length} bytes.',
      written.path,
    );
  }
  stdout.writeln(
    'file=${written.absolute.path} bytes=${written.lengthSync()} '
    'song="${song.title}" bars=${song.writtenBarCount} '
    'marks=${song.sections.first.bars.where((Bar bar) => bar.marks.isNotEmpty).length}',
  );
}
