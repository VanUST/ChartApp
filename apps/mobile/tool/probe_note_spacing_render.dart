// PURPOSE: Produce the ONE picture and the exact numbers that decide whether two notes on adjacent
//          beats can be told apart on the page. `LayoutStyle.minCellWidth` decides how far apart
//          they are engraved and a notehead is a fixed 1.2 staff spaces, so the margin between two
//          noteheads is `minCellWidth − noteheadWidth` — and until this change the engine's DEFAULT
//          made that number NEGATIVE. This instrument draws the same bar twice, at the old 14 and
//          at the 18 the application passes and the default now is, and prints for each:
//
//            * where every notehead actually landed, from the engraver's own glyph boxes;
//            * the CLEAR GAP between two adjacent-beat noteheads, which is the number the reader of
//              handwritten notes depends on;
//            * how many notes a geometry reader recovers from that bar, which turns "they look
//              merged" into a count.
//
//          WHY A PICTURE IS PART OF THE EVIDENCE. "The notes overlap" is a claim about what a
//          musician sees, and the only instrument that settles it is the page. The PNGs are written
//          OUTSIDE the repository — it is public, and a rendered image is evidence for one
//          inspection rather than an artefact to commit — and both are opened and described in the
//          record for this change.
// INPUTS: STAFF_PROBE_OUT names the directory the PNGs are written to, defaulting to a path outside
//         the repository.
// OUTPUTS: `probe.spacing.*` lines on stdout, and two PNGs at 6x: `spacing-14@6x.png` and
//          `spacing-18@6x.png`, each a crop around the first bar's melody staff.
// KEYWORDS: probe, spacing, cell-width, notehead, overlap, minCellWidth, render, d37, evidence,
//           not-part-of-the-suite
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the probe's PNGs are written when `STAFF_PROBE_OUT` says nothing.
const String spacingProbeDirectory =
    r'C:\projects\ChartApp-acl-reports\note-reader\spacing';

/// The family name the loaded font is registered under.
const String _fontFamily = 'ChartSpacingProbeFont';

/// Font files tried in order, so a readable PNG can be produced on Windows, Linux and macOS.
const List<String> _fontCandidates = <String>[
  r'C:\Windows\Fonts\segoeui.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
];

/// The surface every case is engraved on, matching the other render instruments' page.
const double _pageWidth = 824;

/// The page height, matching the other render instruments' surface.
const double _pageHeight = 1318;

/// One decimal place, so a printed column stays readable.
String f(double value) => value.toStringAsFixed(1);

// PURPOSE: The layout constants the application uses, with the cell width under test.
// INPUTS: cell — the `minCellWidth` to engrave at.
// OUTPUTS: The style.
// KEYWORDS: layout-style, cell-width-under-test, application-geometry
LayoutStyle _style(double cell, FlutterTextMetrics metrics) => LayoutStyle(
  textMetrics: metrics,
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: cell,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

// PURPOSE: The metrics the probe draws the clef and the section letter with.
// INPUTS: family — the loaded font family.
// OUTPUTS: The metrics.
// KEYWORDS: text-metrics, probe-font
FlutterTextMetrics _metricsFor(String family) => FlutterTextMetrics(
  chordStyle: TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
  smallChordStyle: TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
  sectionLabelStyle: TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: const Color(0xFF2E5D8A),
  ),
  staffTextStyle: TextStyle(
    fontFamily: family,
    fontSize: 10,
    color: const Color(0xFF486581),
  ),
  textCueStyle: TextStyle(
    fontFamily: family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF102A43),
  ),
);

// PURPOSE: Register a real font with the test engine, because the default test font draws every
//          glyph as a filled box and a page of boxes shows nothing about a staff.
// INPUTS: None. The first existing candidate in [_fontCandidates] is used.
// OUTPUTS: The registered family name, or null when no candidate exists.
// KEYWORDS: font, font-loader, readable-text
Future<String?> _loadFont() async {
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

// PURPOSE: The bar the two renders are compared on: four notes on ADJACENT beats, the hardest
//          spacing the application engraves and the case the whole question is about.
// INPUTS: None.
// OUTPUTS: A one-bar song in C major whose melody is E4 F4 G4 A4 — four different heights, so a
//          merged pair cannot be excused as "the same note drawn twice".
// KEYWORDS: fixture, adjacent-beats, four-notes, treble
Song _fixture() => Song(
  id: 'chartapp-spacing-probe',
  title: 'Adjacent beats',
  composer: '',
  style: '',
  key: Key.cMajor,
  tempo: 120,
  staffSet: const StaffSet(pitched: StaffSpec.pitched()),
  sections: <Section>[
    Section(
      id: 'sec-1',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        Bar(
          melody: <BeatNote>[
            for (final (int, int, int) written in <(int, int, int)>[
              (0, 4, 2), // E4, the staff's bottom line
              (1, 4, 3), // F4
              (2, 4, 4), // G4
              (3, 4, 5), // A4
            ])
              BeatNote(
                pitch: PitchedNote(
                  note: WrittenNote(NoteLetter.values[written.$3], 0),
                  octave: written.$2,
                ),
                value: const NoteValue.plain(NoteBase.quarter),
                beat: written.$1,
              ),
          ],
        ),
      ],
    ),
  ],
);

// PURPOSE: Paint one region of a laid-out page at a magnification, so a margin of two logical pixels
//          becomes something an eye can see and a reader can judge.
// INPUTS: page, song and metrics — what to draw. out — the file. region — the part of the page to
//         show, in page coordinates. zoom — surface pixels per page pixel.
// OUTPUTS: The bytes written.
//
//          IT PAINTS THE WHOLE PAGE AND THEN CROPS, rather than handing the painter a smaller
//          surface: the painter fills its background and clips in the PAGE's own coordinates, so a
//          caller that passed the region as the size would get the page's top-left corner instead
//          and a blank file. Measured by the staff probe before this one, and the reason the
//          magnification and the offset are a canvas transform and the crop is a clip in SURFACE
//          coordinates laid down before the painter draws anything.
// KEYWORDS: probe, crop, magnification, png, notehead, margin, clip-in-surface-space
Future<List<int>> _renderCrop(
  PageLayout page,
  Song song,
  FlutterTextMetrics metrics,
  File out, {
  required LayoutRect region,
  required double zoom,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.clipRect(
    ui.Rect.fromLTWH(0, 0, region.size.width * zoom, region.size.height * zoom),
  );
  canvas.scale(zoom);
  canvas.translate(-region.left, -region.top);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
  ).paint(canvas, ui.Size(page.size.width, page.size.height));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    (region.size.width * zoom).round(),
    (region.size.height * zoom).round(),
  );
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    throw StateError('the engine produced no PNG bytes for ${out.path}');
  }
  image.dispose();
  picture.dispose();
  out.parent.createSync(recursive: true);
  final List<int> bytes = png.buffer.asUint8List();
  out.writeAsBytesSync(bytes);
  return bytes;
}

// PURPOSE: Trace the engraved noteheads of one bar into the ink a reader is given, so the count
//          printed beside the picture comes from the SAME page the picture shows.
// INPUTS: bar — the placed bar, whose `melody.glyphs` carry one notehead per note.
// OUTPUTS: One closed ring per notehead, in page coordinates, at a fine pen's nib. Only the
//          noteheads are traced: the question here is whether two heads can be told apart, and the
//          stems and the ledger line are the reader's other business, measured by
//          `probe_note_reader.dart`.
// KEYWORDS: ink, notehead-ring, page-coordinates, reader-input
List<PageInkStroke> _headInk(PlacedBar bar, {double nib = 2.2}) {
  final List<PageInkStroke> ink = <PageInkStroke>[];
  int index = 0;
  for (final MelodyGlyph glyph in bar.melody.glyphs) {
    if (glyph.kind != MelodyGlyphKind.notehead) {
      continue;
    }
    final LayoutRect box = glyph.bounds;
    final double cx = box.left + box.size.width / 2;
    final double cy = box.top + box.size.height / 2;
    final double rx = math.max(0.5, (box.size.width - nib) / 2);
    final double ry = math.max(0.5, (box.size.height - nib) / 2);
    ink.add(
      PageInkStroke(
        id: 'head-${index++}',
        nib: nib,
        points: <LayoutOffset>[
          for (int i = 0; i <= 24; i++)
            LayoutOffset(
              cx + rx * math.cos(i * math.pi / 12),
              cy + ry * math.sin(i * math.pi / 12),
            ),
        ],
      ),
    );
  }
  return ink;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'the same four notes at the old cell width and at the new one',
    () async {
      final String? family = await _loadFont();
      expect(family, isNotNull, reason: 'a page of filled boxes shows nothing');
      final FlutterTextMetrics metrics = _metricsFor(family!);
      final Song song = _fixture();
      final String outDir =
          Platform.environment['STAFF_PROBE_OUT'] ?? spacingProbeDirectory;
      Directory(outDir).createSync(recursive: true);
      const double headWidth = 1.2 * 13;
      stdout.writeln(
        'probe.spacing notehead=${f(headWidth)} '
        'margin_at_14=${f(14 - headWidth)} margin_at_18=${f(18 - headWidth)}',
      );
      for (final double cell in <double>[14, 18]) {
        final PageLayout page = LayoutEngine(style: _style(cell, metrics))
            .layout(song, pageWidth: _pageWidth, pageHeight: _pageHeight)
            .first;
        final PlacedBar bar = page.bars.first;
        final List<double> centres = <double>[];
        for (final MelodyGlyph glyph in bar.melody.glyphs) {
          if (glyph.kind == MelodyGlyphKind.notehead) {
            centres.add(glyph.bounds.left + glyph.bounds.size.width / 2);
          }
        }
        double smallestGap = double.infinity;
        for (int i = 1; i < centres.length; i++) {
          final double gap = centres[i] - centres[i - 1] - headWidth;
          if (gap < smallestGap) {
            smallestGap = gap;
          }
        }
        final MelodyStaffFrame? frame = melodyFramesOfPage(
          page,
        )['${bar.sectionId}\u0000${bar.barIndex}'];
        final MelodyNoteReading reading = const MelodyNoteReader().read(
          sectionId: bar.sectionId,
          barIndex: bar.barIndex,
          ink: _headInk(bar),
          frame: frame!,
        );
        stdout.writeln(
          'probe.spacing cell=${f(cell)} heads_written=${centres.length} '
          'head_x=${centres.map(f).join(",")} '
          'smallest_clear_gap=${f(smallestGap)} '
          'heads_read=${reading.heads.length} '
          'refused=${reading.refusals.length}',
        );
        final LayoutRect region = LayoutRect.fromLTWH(
          bar.bounds.left - 6,
          bar.melody.bounds.top - 20,
          bar.bounds.size.width + 12,
          bar.melody.bounds.size.height + 40,
        );
        final File out = File(
          '$outDir${Platform.pathSeparator}spacing-${cell.round()}@6x.png',
        );
        final List<int> bytes = await _renderCrop(
          page,
          song,
          metrics,
          out,
          region: region,
          zoom: 6,
        );
        stdout.writeln(
          'probe.spacing.crop cell=${f(cell)} file=${out.path} '
          'bytes=${bytes.length} zoom=6 '
          'region=[${f(region.left)},${f(region.top)} '
          '${f(region.size.width)}x${f(region.size.height)}]',
        );
      }
    },
  );
}
