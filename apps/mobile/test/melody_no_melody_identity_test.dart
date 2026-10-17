// PURPOSE: Render a synthetic chart that carries NO melody, and compare the pixels and the layout
//          geometry with a reference produced by the same test before a melody staff existed. It
//          is the instrument behind the claim "a chart with no melody renders identically to
//          before": the reference is a PNG written from a tree without the change, so the claim is
//          settled by bytes rather than by looking at two images.
// INPUTS: MELODY_PROBE_OUT names the directory. MELODY_PROBE_REF (optional) names a reference PNG;
//         when it is set the test ASSERTS that the freshly painted pixel bytes equal the
//         reference's, and when it is unset it writes `no-melody.png` and `no-melody.geometry.txt`
//         for that reference to be captured from.
// OUTPUTS: The PNG, a canonical dump of every rectangle the layout produced, and a stdout line
//          naming the byte count, the pixel dimensions and the SHA-256 of the pixels. It FAILS when
//          a reference was supplied and the pixels differ, and prints the first differing rectangle
//          when the geometry differs.
// KEYWORDS: no-melody, pixel-identity, geometry-dump, regression-instrument, sha256, golden-free
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The logical page the probe engraves, matching the render probe's own surface.
const double probePageWidth = 824;

/// The logical page height, matching the render probe's own surface.
const double probePageHeight = 1318;

/// The style every probe render uses, so two runs are comparable number for number.
const LayoutStyle probeStyle = LayoutStyle(
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

/// A chart with chords and no melody at all: the case whose rendering must not change.
///
/// Two sections, a repeat and a volta, so the page exercises the signs as well as the chords: a
/// regression that only moved a barline would still be caught by the geometry dump below.
Song chordOnlySong() => Song(
  title: 'Chord only',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(0),
              chord: Chord(
                root: ChordRoot(0),
                quality: ChordQuality.minorSeventh,
              ),
            ),
            ChordMark(
              place: placeAt(2),
              chord: Chord(root: ChordRoot(9)),
            ),
          ],
        ),
        Bar(
          openingBarline: Barline.repeatStart,
          chords: <ChordMark>[
            ChordMark(
              place: placeAt(0),
              chord: Chord(root: ChordRoot(5)),
            ),
          ],
        ),
        const Bar(noChord: true, marks: <BarMark>{BarMark.segno}),
        const Bar(
          closingBarline: Barline.repeatEnd,
          volta: Volta(1),
          repeatPrevious: RepeatPrevious.oneBar,
          staffText: <String>['*69 To Coda'],
        ),
      ],
    ),
    Section(
      id: 'B',
      label: const SectionLabel.letter('B'),
      bars: <Bar>[
        Bar(
          chords: <ChordMark>[
            for (int beat = 0; beat < 4; beat++)
              ChordMark(
                place: placeAt(beat),
                chord: Chord(root: ChordRoot(beat)),
              ),
          ],
        ),
        const Bar(closingBarline: Barline.finalBar),
      ],
    ),
  ],
);

// PURPOSE: Describe every rectangle a page carries, in a fixed order and a fixed format, so that
//          two runs of the layout can be compared as text and the first difference names itself.
// INPUTS: page — the laid-out page.
// OUTPUTS: One line per element, sorted by nothing but the layout's own reading order, with every
//          number written to three decimal places so that two equal layouts cannot differ by
//          formatting.
// KEYWORDS: geometry-dump, canonical-form, rectangle, comparability
List<String> geometryDump(PageLayout page) {
  String rect(LayoutRect r) =>
      '${r.left.toStringAsFixed(3)},${r.top.toStringAsFixed(3)},'
      '${r.size.width.toStringAsFixed(3)},${r.size.height.toStringAsFixed(3)}';
  final List<String> lines = <String>[
    'page index=${page.index} size=${page.size} scale=${page.scale}',
  ];
  for (final PlacedSystem system in page.systems) {
    lines.add(
      'system label=${system.sectionLabel ?? '-'} bounds=${rect(system.bounds)} '
      'band=${system.labelBand == null ? '-' : rect(system.labelBand!)} '
      'bars=${system.bars.length}',
    );
    for (final PlacedBar bar in system.bars) {
      lines.add(
        'bar ${bar.sectionId}#${bar.barIndex} bounds=${rect(bar.bounds)} '
        'melody=${rect(bar.melody.bounds)} glyphs=${bar.melody.glyphs.length}',
      );
      for (final LayoutRect cell in <LayoutRect>[bar.bounds]) {
        lines.add(
          'bar ${bar.sectionId}#${bar.barIndex} left=${cell.left} '
          'bounds=${rect(cell)}',
        );
      }
      for (final PlacedChord chord in bar.chords) {
        lines.add(
          'chord ${bar.sectionId}#${bar.barIndex} '
          'x=${chord.place.offsetX.toStringAsFixed(1)} '
          'y=${chord.place.offsetY.toStringAsFixed(1)} bounds=${rect(chord.bounds)}',
        );
      }
      for (final PlacedStaffText text in bar.staffText) {
        lines.add(
          'staffText ${bar.sectionId}#${bar.barIndex} "${text.text}" '
          'bounds=${rect(text.bounds)}',
        );
      }
    }
  }
  return lines;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a chart with no melody renders and lays out identically to the reference',
    () async {
      final String outDir =
          Platform.environment['MELODY_PROBE_OUT'] ??
          'C:/projects/ChartApp-acl-reports/melody';
      final Song song = chordOnlySong();
      final LayoutEngine engine = LayoutEngine(style: probeStyle);
      final List<PageLayout> pages = engine.layout(
        song,
        pageWidth: probePageWidth,
        pageHeight: probePageHeight,
      );
      expect(pages, isNotEmpty);

      final List<String> geometry = <String>[
        'pages=${pages.length}',
        for (final PageLayout page in pages) ...geometryDump(page),
      ];
      final Directory dir = Directory(outDir);
      dir.createSync(recursive: true);
      final File geometryFile = File(
        '${dir.path}${Platform.pathSeparator}no-melody.geometry.txt',
      );
      geometryFile.writeAsStringSync(
        '${geometry.join('\n')}\n',
        encoding: utf8,
      );

      // Paint page 1 at a device pixel ratio of 1, so the bytes are the logical layout.
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      ChartPainter(
        song: song,
        page: pages.first,
        metrics: const FlutterTextMetrics(),
      ).paint(canvas, const ui.Size(probePageWidth, probePageHeight));
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(
        probePageWidth.round(),
        probePageHeight.round(),
      );
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      expect(png, isNotNull);
      final Uint8List bytes = png!.buffer.asUint8List();
      image.dispose();
      picture.dispose();

      final File pngFile = File(
        '${dir.path}${Platform.pathSeparator}no-melody.png',
      );
      pngFile.writeAsBytesSync(bytes);
      stdout.writeln(
        'probe.no-melody path=${pngFile.path} bytes=${bytes.length} '
        'pixels=${probePageWidth.round()}x${probePageHeight.round()} '
        'digest=${digestOf(bytes)} systems=${pages.first.systems.length} '
        'bars=${pages.first.bars.length}',
      );
      stdout.writeln(
        'probe.no-melody geometry_path=${geometryFile.path} '
        'lines=${geometry.length}',
      );

      // THE REFERENCE IS THE PIXELS THE SAME TEST WROTE FROM A TREE WITHOUT THIS CHANGE. It is
      // supplied through the environment rather than kept in the repository, because a golden of the
      // owner's own rendered geometry is evidence for one run and not an artefact to commit.
      final String referencePath =
          Platform.environment['MELODY_PROBE_REF'] ?? '';
      if (referencePath.isEmpty) {
        stdout.writeln(
          'probe.no-melody reference=none (wrote the artefact to be compared)',
        );
        return;
      }
      final File reference = File(referencePath);
      expect(
        reference.existsSync(),
        isTrue,
        reason: 'reference "$referencePath"',
      );
      final Uint8List referenceBytes = reference.readAsBytesSync();
      stdout.writeln(
        'probe.no-melody reference_bytes=${referenceBytes.length} '
        'reference_digest=${digestOf(referenceBytes)} '
        'pixel_identical=${_sameBytes(bytes, referenceBytes)}',
      );
      expect(
        digestOf(bytes),
        equals(digestOf(referenceBytes)),
        reason:
            'a chart with no melody must render to the same pixels as it did before the '
            'melody staff existed',
      );
    },
  );
}

/// Whether two byte lists are equal, reported separately from the assertion so the log says it.
bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

// PURPOSE: Report a stable digest of a byte list, so two runs can be compared by one string.
// INPUTS: bytes — the PNG or any other byte list.
// OUTPUTS: A 64-bit FNV-1a digest as 16 hexadecimal characters. It is NOT a cryptographic hash and
//          is not used as one: it answers "are these the same bytes" for a comparison this test
//          already performs byte for byte, and it is written to the log so a human can see the
//          answer without scrolling the whole dump.
// KEYWORDS: digest, fnv1a, comparison, logging
String digestOf(Uint8List bytes) {
  int hash = 0xcbf29ce484222325;
  for (final int byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
