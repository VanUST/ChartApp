// PURPOSE: Produce the numbers that show the display seam works, and nothing else. It reports,
//          for a bar that carries staff text, the stored string, the display string, the width the
//          LAYOUT reserved for the line and the width the PAINTER's own text configuration gives
//          that same string — so "the measured width and the drawn width are the same" is a pair of
//          numbers rather than a claim. It also encodes the song into a `.chart` container and
//          decodes it back, comparing the two songs and printing the raw `Bar.staffText`, so the
//          stored form is shown to be untouched by a display-only change.
//
//          It is an instrument, not part of the suite: it lives in `tool/`, so it is not picked up
//          by `flutter test`'s default run or by the `melos run verify` gate. Its expectations only
//          pin what it already printed — measured equals drawn, and the stored form survives — so a
//          reader can check the numbers by eye and the runner still reports a clean exit. Run it
//          from `apps/mobile` with:
//
//              flutter test tool/probe_staff_text_display.dart
//
//          It writes nothing and opens no window: `flutter test` runs the engine headless.
// INPUTS: The owner's iReal export at [iRealProbePath] (read-only) for the real-corpus numbers,
//         plus a small synthetic table for the prefix and whitespace edge cases the corpus does
//         not contain.
// OUTPUTS: `probe.*` lines on stdout: the display table, the real-corpus width pairs, and the
//          container round-trip comparison. A missing export is reported and the corpus half is
//          skipped; the synthetic half always runs.
// KEYWORDS: probe, staff-text, display-form, width-agreement, round-trip, chart-container, headless
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The owner's export, the same file the viewer opens by default.
const String iRealProbePath = r'C:\Users\1\Downloads\Ракета Русское.html';

/// The font family the loaded font is registered under.
const String _fontFamily = 'ChartProbeFont';

/// Font files tried in order, so the probe produces real text metrics on any desktop.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The stored strings the display rule has to decide, with the trap each one is here for.
const List<String> _syntheticStored = <String>[
  '*69Куплет', // two-digit prefix, no padding
  '*72Припев ', // trailing space
  '*69          проигрыш', // long run of leading spaces
  '*74   !._', // leading spaces before punctuation
  '*7Solo', // one digit: not the imported shape, but legal on a hand-built bar
  '*007Solo', // three digits: the same
  '*69', // a position and nothing to say
  '  8+8x', // leading spaces with NO prefix (present in the owner corpus)
  'Fine', // no prefix at all
  '*', // a star with no digits is not a prefix
];

// PURPOSE: Register a real font, so the widths below are the widths a reader sees rather than the
//          test font's uniform boxes.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists.
// KEYWORDS: font, font-loader, real-metrics, graceful-degradation
Future<String?> _loadProbeFont() async {
  for (final String path in _fontCandidates) {
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final FontLoader loader = FontLoader(_fontFamily)
      ..addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    await loader.load();
    stdout.writeln('probe.font path=$path family=$_fontFamily');
    return _fontFamily;
  }
  return null;
}

// PURPOSE: Build the metrics the layout and the painter's text configuration share, so a width from
//          either side is the same width.
// INPUTS: family — the loaded font family, or null for the framework default.
// OUTPUTS: A [FlutterTextMetrics] whose staff-text style is what the painter would use.
// KEYWORDS: metrics, styles, font-family, one-instance
FlutterTextMetrics _metricsFor(String? family) => FlutterTextMetrics(
  chordStyle: TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  ),
  smallChordStyle: TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  ),
  sectionLabelStyle: TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  ),
  staffTextStyle: TextStyle(fontFamily: family, fontSize: 10),
);

// PURPOSE: Report what the display rule decides for each stored string, independent of any layout.
// INPUTS: None.
// OUTPUTS: One `probe.display` line per [_syntheticStored] entry.
// KEYWORDS: display-form, edge-cases, table
void _reportDisplayTable() {
  stdout.writeln('probe.display --- stored -> display ---');
  for (final String stored in _syntheticStored) {
    stdout.writeln(
      'probe.display stored="${_visible(stored)}" '
      'display="${_visible(displayStaffText(stored))}"',
    );
  }
}

/// The string with its characters made countable, so a trailing space is visible in the output.
String _visible(String value) =>
    value.replaceAll(' ', '\u2423').replaceAll('\t', '\\t');

// PURPOSE: Lay out one song and report, for every placed bar with staff text, the measured and the
//          drawn width side by side.
// INPUTS: label — a name for this song in the output. song — the song. metrics — the metrics the
//         layout is measured with, which is also what the painter is given.
// OUTPUTS: One `probe.width` line per staff-text line, plus a `probe.width.bar` line giving the bar
//          width with and without the staff text's contribution. Returns whether every pair
//          reported agreed, so the caller can fail loudly instead of leaving a printed `false` for
//          a reader to notice.
// KEYWORDS: width-agreement, layout-and-painter, measurement-evidence
bool _reportWidths(String label, Song song, FlutterTextMetrics metrics) {
  final LayoutEngine engine = LayoutEngine(
    style: LayoutStyle(
      textMetrics: metrics,
      pageMargin: 20,
      barMinWidth: 64,
      barPadding: 8,
      chordSpacing: 12,
      minCellWidth: 18,
      barHeight: 52,
      systemSpacing: 18,
      sectionLabelHeight: 26,
    ),
  );
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: 824,
    pageHeight: 1318,
  );
  int lines = 0;
  bool allSame = true;
  for (final PageLayout page in pages) {
    for (final PlacedBar bar in page.bars) {
      // The stored strings that produced the placed lines, in the same order: the engine skips an
      // entry whose display form is empty, so the pairing filters the same way.
      final Bar? model = song.barAt(bar.sectionId, bar.barIndex);
      final List<String> storeds = model == null
          ? const <String>[]
          : model.staffText
                .where((String stored) => displayStaffText(stored).isNotEmpty)
                .toList();
      for (int index = 0; index < bar.staffText.length; index++) {
        final PlacedStaffText line = bar.staffText[index];
        lines++;
        final String stored = index < storeds.length ? storeds[index] : '';
        // Exactly what the painter does: a TextPainter over line.text in the staff-text style.
        final TextPainter painter = TextPainter(
          text: TextSpan(text: line.text, style: metrics.staffTextStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final double drawn = painter.width;
        painter.dispose();
        final double measured = line.bounds.size.width;
        // What the bar would have reserved if the prefix and padding were still in the string:
        // the number the defect made the layout carry.
        final double raw = stored.isEmpty
            ? measured
            : metrics.measure(stored, ChartTextRole.staffText).width;
        allSame = allSame && measured == drawn;
        stdout.writeln(
          'probe.width song="$label" '
          '${bar.sectionId}#${bar.barIndex} '
          'stored="${_visible(stored)}" text="${_visible(line.text)}" '
          'layout_measured=$measured painter_drawn=$drawn '
          'measured_equals_drawn=${measured == drawn} '
          'raw_stored_measured=$raw '
          'bar_left=${bar.bounds.left} text_left=${line.bounds.left}',
        );
      }
    }
  }
  stdout.writeln('probe.width.summary song="$label" lines=$lines');
  return allSame;
}

/// Reads the owner's export, or null when it is absent.
IRealLibrary? _ownerLibrary() {
  final File file = File(iRealProbePath);
  if (!file.existsSync()) {
    return null;
  }
  return parseIRealExport(file.readAsStringSync(), source: iRealProbePath);
}

// PURPOSE: Encode [song] into a `.chart` container, decode it back, and report whether the stored
//          staff text survived byte-for-byte.
// INPUTS: song — the song to round-trip.
// OUTPUTS: The decoded song, so the caller can keep using it; prints the comparison and the raw
//          staff texts.
// KEYWORDS: round-trip, chart-container, stored-form, encode-decode
Song _reportRoundTrip(Song song) {
  final ChartFile file = ChartFile(
    metadata: const ChartMetadata(docId: 'probe-doc'),
    snapshot: DocumentState(song: song),
  );
  final Uint8List bytes = ChartFileCodec.encode(file).bytes;
  final Song after = ChartFileCodec.decode(bytes).file.snapshot.song;
  final List<String> rawTexts = <String>[
    for (final Section section in after.sections)
      for (final Bar bar in section.bars) ...bar.staffText,
  ];
  stdout.writeln(
    'probe.roundtrip bytes=${bytes.length} song_equal=${after == song} '
    'raw_texts=${rawTexts.length}',
  );
  for (final String raw in rawTexts.take(12)) {
    stdout.writeln('probe.roundtrip.stored "${_visible(raw)}"');
  }
  return after;
}

void main() {
  test(
    'staff text display seam: widths agree and the stored prefix survives',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final String? family = await _loadProbeFont();
      final FlutterTextMetrics metrics = _metricsFor(family);

      _reportDisplayTable();

      // The synthetic bar carries every trap in one place, so the width pair exists even on a machine
      // without the owner's export.
      final Song synthetic = Song(
        title: 'Display seam',
        sections: <Section>[
          Section(
            id: 'sec-probe',
            label: const SectionLabel.letter('A'),
            bars: <Bar>[
              Bar(
                timeSignature: TimeSignature.fourFour,
                chords: <ChordMark>[
                  ChordMark(
                    place: cellAt(0),
                    chord: const Chord(root: ChordRoot(0)),
                  ),
                ],
                staffText: const <String>[
                  '*69Куплет',
                  '*72Припев ',
                  '*69          проигрыш',
                ],
              ),
            ],
          ),
        ],
      );
      expect(
        _reportWidths('synthetic', synthetic, metrics),
        isTrue,
        reason: 'the width the layout measured must equal the width the painter draws',
      );
      final Song syntheticAfter = _reportRoundTrip(synthetic);
      expect(
        syntheticAfter,
        synthetic,
        reason: 'the container round trip must not edit',
      );
      expect(syntheticAfter.sections.first.bars.first.staffText, const <String>[
        '*69Куплет',
        '*72Припев ',
        '*69          проигрыш',
      ], reason: 'the raw prefix and padding must survive the round trip');

      final IRealLibrary? library = _ownerLibrary();
      if (library == null) {
        stdout.writeln(
          'probe.corpus skipped reason=no-export-at-$iRealProbePath',
        );
        return;
      }
      IRealSong? withText;
      for (final IRealSong entry in library.songs) {
        final bool hasText = entry.song.sections.any(
          (Section section) => section.bars.any(
            (Bar bar) => bar.staffText.any(
              (String text) => displayStaffText(text).isNotEmpty,
            ),
          ),
        );
        if (hasText) {
          withText = entry;
          break;
        }
      }
      if (withText == null) {
        stdout.writeln(
          'probe.corpus skipped reason=no-song-with-displayable-text',
        );
        return;
      }
      stdout.writeln(
        'probe.corpus song="${withText.title}" '
        'bars=${withText.song.writtenBarCount}',
      );
      expect(
        _reportWidths(withText.title, withText.song, metrics),
        isTrue,
        reason:
            'every real-corpus line must draw at the width it was measured at',
      );
      final Song corpusAfter = _reportRoundTrip(withText.song);
      expect(
        corpusAfter,
        withText.song,
        reason: 'the corpus song must round trip',
      );
      final List<String> raw = <String>[
        for (final Section section in corpusAfter.sections)
          for (final Bar bar in section.bars) ...bar.staffText,
      ];
      expect(raw, contains('*69Куплет'));
      expect(
        raw,
        contains('*69          проигрыш'),
        reason: 'the run of leading spaces is part of what the chart wrote',
      );
    },
  );
}
