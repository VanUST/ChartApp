// PURPOSE: Count the chord pairs the ENGRAVING would draw on top of each other, and count the same
//          pairs at the positions the DOCUMENT stores, so that "two symbols read as one word" is a
//          number a change can be measured by instead of a remark about a photograph. It exists
//          because the defect it measures was invisible for as long as it lasted: the importer writes
//          an x per cell and the width of a symbol is the font's business, so `Db` beside `Bb/D` was
//          two chords in the model and one word on the page.
// INPUTS: argv[0] — a path to an `.html` file holding an `irealb://` link. Optionally argv[1] — a
//         case-insensitive title substring, so one song can be measured on its own.
// OUTPUTS: One line per bar that carries a pair drawn closer than the style's minimum gap, naming the
//          two symbols and the two x values, and a summary line:
//            SUMMARY songs=N bars=N pairs=N stored_overlaps=N drawn_overlaps=N exit=0
//          `stored_overlaps` counts pairs whose STORED boxes intersect — the number the document
//          itself carries, which is what the previous census of the owner's book reported.
//          `drawn_overlaps` counts the same pairs in the boxes the layout draws. The exit code is 1
//          when the drawn count is not zero, because the engraving promises it never draws two
//          symbols on top of each other.
//
//          THE MEASUREMENT IS A LOWER BOUND AND SAYS SO. The widths come from
//          `FixedAdvanceTextMetrics`, which advances 8 points per character, while the application
//          draws chords with a real font at 15 points where `Db` is about 19 wide. So this probe
//          UNDER-counts what a reader would see, and it is still the right instrument for what it is
//          used for: the two counts below are taken with the SAME metric on the SAME bars, so the
//          difference between them is the engraving's rule and not the ruler's. The tablet screenshot
//          is the instrument for the real font.
// KEYWORDS: probe, chord-row, minimum-gap, overlap, lower-bound, before-and-after, not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// Runs the probe and reports the exit code the measurement earned.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: probe_chord_gap <file.html> [title-substring]');
    exit(2);
  }
  final File file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('no such file: ${args[0]}');
    exit(2);
  }
  final RegExpMatch? link = RegExp('irealb://([^"]*)')
      .firstMatch(file.readAsStringSync());
  if (link == null) {
    stderr.writeln('no irealb:// link found in ${args[0]}');
    exit(2);
  }
  final String decoded = Uri.decodeFull(link.group(1)!);
  final String? filter = args.length > 1 ? args[1].toLowerCase() : null;
  final List<String> segments = decoded.split('===');
  final List<String> songs = segments.length > 1
      ? segments.sublist(0, segments.length - 1)
      : segments;

  const LayoutStyle style = LayoutStyle(
    pageMargin: 20,
    barMinWidth: 64,
    barPadding: 8,
    chordSpacing: 12,
    minCellWidth: 18,
    barHeight: 52,
    systemSpacing: 18,
    sectionLabelHeight: 26,
  );
  const LayoutEngine engine = LayoutEngine(style: style);
  const SpellingTable table = SpellingTable();

  int songsShown = 0;
  int barsSeen = 0;
  int pairs = 0;
  int storedOverlaps = 0;
  int drawnOverlaps = 0;
  int meterSigns = 0;
  int signsSeen = 0;

  for (int index = 0; index < songs.length; index++) {
    final IRealPayload payload = IRealPayload.parse(songs[index]);
    if (filter != null && !payload.title.toLowerCase().contains(filter)) {
      continue;
    }
    final Song song = parseIRealPayload(
      songs[index],
      documentId: 'gap-$index',
    ).song;
    songsShown++;
    final List<PageLayout> pages = engine.layout(
      song,
      pageWidth: 824,
      pageHeight: 1318,
    );
    for (final PageLayout page in pages) {
      for (final PlacedBar placed in page.bars) {
        for (final PlacedBarSign sign in placed.signs) {
          signsSeen++;
          if (sign.kind == BarSignKind.meterChange) {
            meterSigns++;
            stdout.writeln(
              '    METRE "${sign.text}" song="${song.title}" '
              'at ${placed.sectionId}[${placed.barIndex}] '
              'box=${sign.bounds.left.toStringAsFixed(1)},'
              '${sign.bounds.top.toStringAsFixed(1)} '
              '${sign.bounds.size.width.toStringAsFixed(1)}x'
              '${sign.bounds.size.height.toStringAsFixed(1)} '
              'bar=${placed.bounds.left.toStringAsFixed(1)},'
              '${placed.bounds.top.toStringAsFixed(1)} '
              '${placed.bounds.size.width.toStringAsFixed(1)}x'
              '${placed.bounds.size.height.toStringAsFixed(1)}',
            );
          }
        }
        final Bar? bar = song.barAt(placed.sectionId, placed.barIndex);
        if (bar == null || bar.chords.length < 2) {
          continue;
        }
        barsSeen++;
        for (int mark = 1; mark < bar.chords.length; mark++) {
          pairs++;
          final ChordMark previous = bar.chords[mark - 1];
          final ChordMark next = bar.chords[mark];
          final String previousText = previous.chord.render(song.key, table);
          final String nextText = next.chord.render(song.key, table);
          final double previousStoredRight =
              previous.offsetX +
              style.textMetrics
                  .measure(previousText, ChartTextRole.chord)
                  .width;
          if (previousStoredRight > next.offsetX) {
            storedOverlaps++;
          }
          final double previousDrawnRight =
              placed.chords[mark - 1].bounds.right;
          if (previousDrawnRight > placed.chords[mark].bounds.left) {
            drawnOverlaps++;
            stdout.writeln(
              '    TOUCHING ${placed.sectionId}[${placed.barIndex}] '
              '"$previousText" at '
              '${placed.chords[mark - 1].bounds.left.toStringAsFixed(1)} '
              '(right ${previousDrawnRight.toStringAsFixed(1)}) and '
              '"$nextText" at '
              '${placed.chords[mark].bounds.left.toStringAsFixed(1)}',
            );
          }
        }
      }
    }
  }

  final int exitCode = drawnOverlaps == 0 ? 0 : 1;
  stdout.writeln(
    'SUMMARY songs=$songsShown bars=$barsSeen pairs=$pairs '
    'stored_overlaps=$storedOverlaps drawn_overlaps=$drawnOverlaps '
    'signs=$signsSeen metre_signs=$meterSigns exit=$exitCode',
  );
  exit(exitCode);
}
