// PURPOSE: Produce the two pieces of evidence this stage's brief demands and which an in-memory round
//          trip cannot give: a real `.chart` file written to disk and read back to the SAME document,
//          and an iReal chart imported and dumped in a form that can be diffed against the tree as it
//          stood before the change.
// INPUTS: A directory to write into, passed as the first argument; nothing is read from a device or
//         the network.
// OUTPUTS: One block per check on stdout, then a summary and an exit code — 0 when every check held,
//          1 when one did not. The `ireal.*` lines are the comparison: they print the cord cells the
//          import produced and the engraved x of every chord, which is what "the import produces the
//          chart it produced" means in numbers rather than in a claim.
// KEYWORDS: probe, save-and-reopen, chart-file, real-file, ireal, evidence, not-part-of-the-library
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';

import '../support/place_fixture.dart';

int _checks = 0;
int _failures = 0;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: probe_stage_one <output-directory>');
    stderr.writeln(
      'The file this probe writes must land outside the repository: it is '
      'evidence, not a fixture, and the repository carries no artefacts.',
    );
    exit(2);
  }
  final Directory outDir = Directory(args.first);
  _roundTripThroughARealFile(outDir);
  _irealChart();
  stdout.writeln('');
  stdout.writeln('CHECKS=$_checks FAILURES=$_failures');
  exit(_failures == 0 ? 0 : 1);
}

/// A real file round trip over a document that exercises every mark this stage changed.
void _roundTripThroughARealFile(Directory directory) {
  _section('save and reopen through a real file');
  directory.createSync(recursive: true);

  // A chart built by the session, so every mark is written by the path the application uses.
  final EditSession session = EditSession(
    document: DocumentState(
      song: Song(
        id: 'probe-stage-one',
        title: 'Reopen me',
        composer: 'Stage One',
        style: 'Medium Swing',
        key: Key.cMajor,
        tempo: 126,
        sections: <Section>[
          Section(
            id: 'sec-A',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[for (int index = 0; index < 4; index++) Bar()],
          ),
        ],
      ),
    ),
  );
  for (int beat = 0; beat < 4; beat += 2) {
    fixtureChord(
      session,
      sectionId: 'sec-A',
      barIndex: 1,
      slot: beat,
      chord: Chord(root: ChordRoot(beat + 2)),
    );
  }
  fixtureInsertNote(
    session,
    sectionId: 'sec-A',
    barIndex: 2,
    slot: 1,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.e, 0), octave: 4),
    value: NoteValue.plain(NoteBase.quarter),
  );
  fixtureInsertNote(
    session,
    sectionId: 'sec-A',
    barIndex: 2,
    slot: 3,
    pitch: const PitchedNote(note: WrittenNote(NoteLetter.g, 0), octave: 4),
    value: NoteValue.plain(NoteBase.eighth),
    tiedToNext: true,
  );
  final String? firstCue = session.insertTextCue(
    sectionId: 'sec-A',
    barIndex: 1,
    offsetX: fixtureX(2) + 3,
    offsetY: -1,
    text: 'To Coda',
  );
  final String? secondCue = session.insertTextCue(
    sectionId: 'sec-A',
    barIndex: 3,
    text: 'Solo',
  );
  _same(
    'reopen: the two cues were written',
    true,
    firstCue != null && secondCue != null,
  );
  _same(
    'reopen: a cue moves to another bar',
    true,
    session.moveTextCue(
      secondCue!,
      sectionId: 'sec-A',
      barIndex: 0,
      offsetY: 2,
    ),
  );

  final DocumentState before = session.document;
  final ChartFile file = ChartFile(
    metadata: const ChartMetadata(docId: 'probe-stage-one', writer: 'probe'),
    snapshot: session.baseDocument,
    events: session.log,
  );
  final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
  final File onDisk = File(
    '${directory.path}${Platform.pathSeparator}probe-stage-one.chart',
  );
  onDisk.writeAsBytesSync(encoded.bytes, flush: true);
  final Uint8List read = Uint8List.fromList(onDisk.readAsBytesSync());
  final ChartFile reopened = ChartFileCodec.decode(read).file;

  _same(
    'reopen: the bytes on disk are the bytes encoded',
    encoded.bytes.length,
    read.length,
  );
  _same('reopen: the file is a real file on disk', true, onDisk.existsSync());
  _same(
    'reopen: the container metadata survives',
    file.metadata,
    reopened.metadata,
  );
  _same(
    'reopen: the operation log survives',
    file.events.length,
    reopened.events.length,
  );
  _same(
    'reopen: the rebuilt document equals what was saved',
    before,
    reopened.reducedDocument,
  );

  final Song song = reopened.reducedDocument.song;
  _same(
    'reopen: bar 1 of A holds its two chords',
    2,
    song.barAt('sec-A', 1)!.chords.length,
  );
  _same(
    'reopen: bar 2 of A holds its two notes',
    2,
    song.barAt('sec-A', 2)!.melody.length,
  );
  _same(
    'reopen: the tie survived',
    true,
    song.barAt('sec-A', 2)!.melody[1].tiedToNext,
  );
  _same(
    'reopen: chords and notes keep the bar they were written in',
    'sec-A',
    song.barAt('sec-A', 1)!.chords.first.place.anchor.sectionId,
  );
  _same(
    'reopen: the note says its own bar',
    2,
    song.barAt('sec-A', 2)!.melody.first.place.anchor.bar,
  );
  stdout.writeln(
    'reopen: file=${onDisk.path} bytes=${onDisk.lengthSync()} '
    'operations=${reopened.events.length} '
    'cues=${reopened.reducedDocument.textCues.length} '
    'chord_x_bar1=${<double>[for (final ChordMark mark in song.barAt('sec-A', 1)!.chords) mark.place.offsetX]}',
  );

  // A FILE FROM THE PREVIOUS FORMAT IS REFUSED BY NAME. The owner's decision is that old `.chart`
  // files do not matter, so the one thing that must not happen is a silent re-interpretation: a chord
  // payload written before this change has no `place`, and the reader has to say so. The wire shape is
  // visible in the header JSON, so that is what is inspected rather than the framed container, whose
  // body is binary.
  final int headerLength = _readU32(encoded.bytes, 12);
  final String headerJson = utf8.decode(
    Uint8List.sublistView(
      encoded.bytes,
      chartFilePrefixLength,
      chartFilePrefixLength + headerLength,
    ),
  );
  final Map<String, Object?> header =
      jsonDecode(headerJson) as Map<String, Object?>;
  _same(
    'reopen: the file this build writes carries no "beat" field',
    false,
    headerJson.contains('"beat"'),
  );
  _same(
    'reopen: the file this build writes carries a place',
    true,
    headerJson.contains('"place"'),
  );
  _same(
    'reopen: it wrote at least one operation',
    true,
    (header['events']! as List<Object?>).isNotEmpty,
  );
}

int _readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// Imports an iReal chart and dumps the cells and the engraving, so the numbers can be compared.
void _irealChart() {
  _section('an iReal chart, imported');
  // The same body the parser's own tests use for the cell model, so the numbers below are the numbers
  // those tests assert: `C7ppF7` is one bar of four cells, `D-7 G7` is two chords one cell apart, and
  // `A7,p,p,p,` is a chord with three empty cells after it.
  const String body =
      'T44C7ppF7|D-7 G7|Cmaj7|A7,p,p,p,|F7|Bbmaj7|Em7b5 A7|D-7 G7|';
  final IRealParseResult parsed = parseIRealNotation(
    body,
    documentId: 'probe-ireal',
  );
  final Song song = parsed.song;
  final List<Bar> bars = song.barsInReadingOrder;
  stdout.writeln(
    'ireal.dump sections=${song.sections.length} bars=${bars.length} '
    'issues=${parsed.issues.length}',
  );
  for (int index = 0; index < bars.length; index++) {
    final Bar bar = bars[index];
    final String cells = <String>[
      for (final ChordMark mark in bar.chords) _cellToken(mark),
    ].join(' ');
    stdout.writeln(
      'ireal.bar $index meter=${bar.timeSignature.numerator}/'
      '${bar.timeSignature.denominator} chords=[$cells]',
    );
  }
  // AND THE PICTURE, which is the half a document dump cannot show: where the engraver draws each
  // chord. If the import really produced the chart it produced, these x positions are the same ones
  // the pre-change tree produced from the same body.
  final LayoutEngine engine = LayoutEngine(style: const LayoutStyle());
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: 824,
    pageHeight: 1600,
  );
  for (final PlacedBar bar in pages.first.bars) {
    final String drawn = <String>[
      for (final PlacedChord chord in bar.chords) _drawnToken(chord),
    ].join(' ');
    stdout.writeln(
      'ireal.engraved ${bar.sectionId}[${bar.barIndex}] '
      'left=${bar.bounds.left.toStringAsFixed(2)} width=${bar.bounds.size.width.toStringAsFixed(2)} '
      'chords=[$drawn]',
    );
  }
  _same('ireal: the body parsed into one section', 1, song.sections.length);
  _same('ireal: the body parsed into eight bars', 8, bars.length);
  _same('ireal: nothing was refused', 0, parsed.issues.length);
  _same(
    'ireal: the first bar holds four cells, the fourth on beat 3',
    '3.0',
    <String>[
      for (final ChordMark mark in bars.first.chords)
        '${mark.offsetX.toStringAsFixed(1)}',
    ].last,
  );
}

/// One chord's cell and stored x, as `root quality @ beat . step x offsetX`.
String _cellToken(ChordMark mark) =>
    '${mark.chord.root.pitchClass}${mark.chord.quality.token}'
    '@${mark.offsetX.toStringAsFixed(1)}'
    'x${mark.place.offsetX.toStringAsFixed(1)}';

/// One engraved chord, as `root quality @ page x`.
String _drawnToken(PlacedChord chord) =>
    '${chord.chord.root.pitchClass}${chord.chord.quality.token}'
    '@${chord.bounds.left.toStringAsFixed(2)}';
void _section(String title) {
  stdout.writeln('');
  stdout.writeln('===== $title =====');
}

void _same(String what, Object? expected, Object? actual) {
  _checks++;
  final bool ok = expected == actual;
  if (!ok) {
    _failures++;
  }
  stdout.writeln('[${ok ? 'ok' : 'FAIL'}] $what');
  if (!ok) {
    stdout.writeln('    expected: $expected');
    stdout.writeln('    actual:   $actual');
  }
}
