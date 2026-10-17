// PURPOSE: Print where every note of a `.chart` file lands on the engraved page, using the SAME
//          layout engine and the same style the application uses, so a claim about what the screen
//          shows is a measurement rather than an impression. It exists because a screenshot of the
//          owner's tablet showed notes in some bars and not others and the difference had to be
//          decided by numbers.
// INPUTS: One argument: a path to a `.chart` file. A second, optional argument is the page width in
//         logical pixels (default 1056, the width the viewer measured on the tablet).
// OUTPUTS: One line per bar naming the bar, the note count and each note's (beat, step, pitch) with
//         the page x of its notehead; then a line per bar saying how many glyphs were drawn.
// KEYWORDS: probe, melody, layout, geometry, measurement, chart-file, not-part-of-the-library
import 'dart:io';
import 'dart:typed_data';

import 'package:chart_core/chart_core.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/probe_note_placement.dart <file.chart> [pageWidth]',
    );
    exit(2);
  }
  final Uint8List bytes = File(args.first).readAsBytesSync();
  final ChartFileDecodeResult decoded = ChartFileCodec.decode(bytes);
  final Song song = decoded.file.reducedDocument.song;
  stdout.writeln(
    'probe song="${song.title}" key=${song.key} '
    'bars=${song.writtenBarCount} pageWidth=${args.length > 1 ? args[1] : '1056'}',
  );

  final double width = args.length > 1 ? double.parse(args[1]) : 1056;
  // A tall page, so one system holds all eight bars and the horizontal placement is what the
  // measurement is about: pagination would otherwise move bars onto a second page and hide the
  // question behind a line break.
  final LayoutEngine engine = const LayoutEngine();
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: width,
    pageHeight: 20000,
  );
  stdout.writeln(
    'probe pages=${pages.length} scale=${pages.first.scale} '
    'systems=${pages.first.systems.length}',
  );

  for (final PageLayout page in pages) {
    for (final PlacedBar bar in page.bars) {
      final StringBuffer notes = StringBuffer();
      // The pages carry no per-note geometry hook in `PlacedBar`, so the noteheads are read from the
      // melody staff the bar carries, which is what the painter draws.
      for (final MelodyGlyph glyph in bar.melody.glyphs) {
        if (glyph.kind != MelodyGlyphKind.notehead) {
          continue;
        }
        notes.write(
          ' head@(${glyph.bounds.left.toStringAsFixed(0)},'
          '${glyph.bounds.top.toStringAsFixed(0)})',
        );
      }
      stdout.writeln(
        'probe bar=${bar.sectionId}#${bar.barIndex} '
        'bounds=(${bar.bounds.left.toStringAsFixed(0)},'
        '${bar.bounds.top.toStringAsFixed(0)},'
        '${bar.bounds.size.width.toStringAsFixed(0)}) '
        'cells=${bar.cells.length} '
        'model_notes=${_notesOf(song, bar.sectionId, bar.barIndex)} '
        'glyph_noteheads=${bar.melody.glyphs.where((MelodyGlyph g) => g.kind == MelodyGlyphKind.notehead).length}'
        '$notes',
      );
    }
  }
}

/// Every note of one bar of [song], as `beat.step:pitch`, so a missing glyph can be told from a
/// missing model note.
String _notesOf(Song song, String sectionId, int barIndex) {
  final Bar? bar = song.barAt(sectionId, barIndex);
  if (bar == null || bar.melody.isEmpty) {
    return 'none';
  }
  return <String>[
    for (final NoteMark note in bar.melody)
      '${note.pseudoBeat}.${note.pseudoStep}:${note.pitch}',
  ].join(',');
}
