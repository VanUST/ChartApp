// PURPOSE: Prove on the RENDERED PAGE that the chart's key and meter are drawn where the layout
//          reserved them — and nowhere else. The layout side is pinned in `chart_core`; what this
//          file adds is the half only pixels answer: that the row is really inked, that it is inked
//          in the notation's dark ink rather than in a heading's blue, that nothing is drawn in the
//          gap between it and the section letter, and that a second page carries no header at all.
// INPUTS: None. The chart is built here and rendered in memory; no font is loaded, because the case
//         is about WHERE ink is and WHAT INK it is, and the framework's box glyphs answer both.
// OUTPUTS: Pass/fail per claim, plus `probe.header` lines on stdout naming each band sampled, the
//          pixels found in it and the darkest ink in it — so a failure quotes the measurement rather
//          than the adjective.
// KEYWORDS: test, chart-header, key, meter, pixels, ink-detector, negative-control, page-two,
//           notation-ink, d27
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The logical page this file engraves, matching the render probes' surface.
const double pageWidth = 824;

/// The page height, matching the render probes' surface.
const double pageHeight = 1318;

/// The metrics the page is measured with, in the production sizes but with no font family: the boxes
/// the framework draws for a missing font still have a width, a colour and a position, which is
/// everything this file asks about.
const FlutterTextMetrics metrics = FlutterTextMetrics(
  chordStyle: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Color(0xFF102A43),
  ),
  smallChordStyle: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Color(0xFF102A43),
  ),
  sectionLabelStyle: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Color(0xFF2E5D8A),
  ),
  staffTextStyle: TextStyle(fontSize: 10, color: Color(0xFF486581)),
  textCueStyle: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Color(0xFF102A43),
  ),
);

/// The style every case is laid out with: the application's proportions, the metrics above, and the
/// engine's own defaults for everything this case does not depend on.
LayoutStyle styleWith(TextMetrics textMetrics) => LayoutStyle(
  textMetrics: textMetrics,
  pageMargin: 20,
  barMinWidth: 64,
  barPadding: 8,
  chordSpacing: 12,
  minCellWidth: 18,
  barHeight: 52,
  systemSpacing: 18,
  sectionLabelHeight: 26,
);

/// A chart of [bars] bars in [key] and [meter], the first of which carries a chord on its first beat.
///
/// The chord in the first cell is deliberate and is the case the owner named: a chart's first bar may
/// hold a chord, so the header may not be drawn as one or over one.
Song chartOf({
  Key key = Key.cMajor,
  TimeSignature meter = TimeSignature.fourFour,
  int bars = 1,
}) => Song(
  title: 'Header',
  key: key,
  sections: <Section>[
    Section(
      id: 'A',
      label: const SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < bars; index++)
          Bar(
            timeSignature: meter,
            chords: <ChordMark>[
              ChordMark(
                place: placeAt(0),
                chord: Chord(root: ChordRoot(0)),
              ),
            ],
          ),
      ],
    ),
  ],
);

/// Paints [page] and reads its pixels back.
///
/// Returns the raw RGBA bytes with the width that addresses them. The caller disposes nothing: the
/// image and the picture are disposed here, because both hold engine-side memory.
Future<({Uint8List pixels, int width})> paintPage(
  Song song,
  PageLayout page,
) async {
  final int width = pageWidth.round();
  final int height = pageHeight.round();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  ChartPainter(
    song: song,
    page: page,
    metrics: metrics,
  ).paint(canvas, ui.Size(pageWidth, pageHeight));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData? raw = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  expect(raw, isNotNull, reason: 'the renderer must produce pixels to read');
  image.dispose();
  picture.dispose();
  return (pixels: raw!.buffer.asUint8List(), width: width);
}

/// Counts the inked pixels in a box, and reports the darkest one's channel sum and the extent the
/// ink covers.
///
/// The sum is how this file tells the two inks apart on one page: the chart's notation is drawn in
/// near-black navy and a section letter in a lighter blue, and the claim is that the header is the
/// former, because it is notation and not a heading. The extent is how it tells a LINE of words from
/// a single letter, which is what the second page's case needs.
({int ink, int darkest, int minX, int maxX, int minY, int maxY}) scan(
  Uint8List pixels,
  int width,
  LayoutRect box,
) {
  int ink = 0;
  int darkest = 255 * 3;
  int minX = 1 << 30;
  int maxX = -(1 << 30);
  int minY = 1 << 30;
  int maxY = -(1 << 30);
  // A HALF-OPEN BOX: `[left, right) x [top, bottom)`. A rectangle that ends exactly where another
  // begins must not sample the other's first row — the gap between the header and the section letter
  // is exactly that case, and a closed interval there reads the letter's own top row as ink in the
  // gap.
  for (int y = box.top.floor(); y < box.bottom; y++) {
    for (int x = box.left.floor(); x < box.right; x++) {
      final int at = 4 * (y * width + x);
      final int sum = pixels[at] + pixels[at + 1] + pixels[at + 2];
      if (sum < 250 * 3) {
        ink++;
        if (sum < darkest) {
          darkest = sum;
        }
        if (x < minX) {
          minX = x;
        }
        if (x > maxX) {
          maxX = x;
        }
        if (y < minY) {
          minY = y;
        }
        if (y > maxY) {
          maxY = y;
        }
      }
    }
  }
  return (
    ink: ink,
    darkest: darkest,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the header is inked in its band, in the notation ink, clear of the section letter', () async {
    final Song song = chartOf();
    final PageLayout page = LayoutEngine(style: styleWith(metrics))
        .layout(song, pageWidth: pageWidth, pageHeight: pageHeight)
        .single;
    final PlacedChartHeader header = page.header!;
    final PlacedSystem system = page.systems.first;
    final LayoutRect labelBand = system.labelBand!;
    final PlacedBar bar = system.bars.first;
    final ChartPainter painter = ChartPainter(
      song: song,
      page: page,
      metrics: metrics,
    );
    expect(painter.page.header, isNotNull);
    final ({Uint8List pixels, int width}) rendered = await paintPage(
      song,
      page,
    );

    final ({int ink, int darkest, int minX, int maxX, int minY, int maxY})
    inHeader = scan(rendered.pixels, rendered.width, header.bounds);
    // The GAP: from the bottom of the header's band to the top of the section letter's band.
    final ({int ink, int darkest, int minX, int maxX, int minY, int maxY})
    inGap = scan(
      rendered.pixels,
      rendered.width,
      LayoutRect.fromLTWH(
        header.bounds.left,
        header.bounds.bottom,
        header.bounds.size.width,
        labelBand.top - header.bounds.bottom,
      ),
    );
    final ({int ink, int darkest, int minX, int maxX, int minY, int maxY})
    inLabel = scan(rendered.pixels, rendered.width, labelBand);
    final ({int ink, int darkest, int minX, int maxX, int minY, int maxY})
    inChordRow = scan(rendered.pixels, rendered.width, bar.bounds);
    // A CONTROL BOX of the same size as the header's band, over the paper to the right of the last
    // bar: it must hold nothing, which is what proves the detector is not counting white as ink.
    final ({int ink, int darkest, int minX, int maxX, int minY, int maxY})
    control = scan(
      rendered.pixels,
      rendered.width,
      LayoutRect.fromLTWH(
        header.bounds.left + header.bounds.size.width / 2,
        header.bounds.top + header.bounds.size.height * 3,
        header.bounds.size.width / 2,
        header.bounds.size.height,
      ),
    );
    stdout.writeln(
      'probe.header text="${header.text}" band=${header.bounds} '
      'header_ink=${inHeader.ink} header_darkest=${inHeader.darkest} '
      'header_x=${inHeader.minX}..${inHeader.maxX} '
      'header_y=${inHeader.minY}..${inHeader.maxY} '
      'gap_ink=${inGap.ink} gap_y=${inGap.minY}..${inGap.maxY} '
      'label_top=${labelBand.top} label_bottom=${labelBand.bottom} '
      'label_ink=${inLabel.ink} label_darkest=${inLabel.darkest} '
      'chord_row_ink=${inChordRow.ink} control_ink=${control.ink}',
    );

    expect(inHeader.ink, greaterThan(0), reason: 'the header is drawn at all');
    // THE COLLISION CLAIM, made on pixels rather than on rectangles: the header's ink ends above the
    // letter's ink, with visible paper between them. The exact-zero row count is not asserted because
    // a box glyph — the framework's stand-in for a missing font — bleeds one row past its line box,
    // and a product decision must not be tuned to a test font.
    expect(
      inHeader.maxY,
      lessThan(inLabel.minY),
      reason:
          'the header ink ends at y=${inHeader.maxY} and the section letter begins at '
          'y=${inLabel.minY}',
    );
    expect(
      inLabel.minY - inHeader.maxY,
      greaterThanOrEqualTo(3),
      reason: 'the two lines must be separated, not touching',
    );
    expect(
      inGap.maxY,
      lessThan(inLabel.minY),
      reason: 'whatever bleeds into the gap stops before the letter',
    );
    expect(
      inLabel.ink,
      greaterThan(0),
      reason: 'the section letter is still drawn',
    );
    expect(
      inChordRow.ink,
      greaterThan(0),
      reason: 'the first bar still draws its chord, which the header does not cover',
    );
    expect(control.ink, 0, reason: 'the detector sees no ink on blank paper');
    // The header is set in the CHORD's ink, not in the section label's: the key and the meter are
    // notation and the letter is a heading, and on a page where both stand in the same left column
    // the ink is what tells the reader which is which.
    expect(
      inHeader.darkest,
      lessThan(inLabel.darkest),
      reason:
          'the header must be drawn in the darker, notation ink: '
          '${inHeader.darkest} against the letter\'s ${inLabel.darkest}',
    );
  });

  test('the second page carries no header, and its first bar starts at the margin', () async {
    // A chart long enough to need two pages, so the claim "page one only" is measured rather than
    // implied by a page count.
    //
    // WHY THIS CLAIM IS STRUCTURAL AND NOT A PIXEL BOX, which is the one difference from the case
    // above. On page two the first system continues its section, so it carries no section letter and
    // no band: its chord row begins AT the page margin, in exactly the rows a header would have
    // used. A pixel sample of that band on page two therefore finds the music, and "no header here"
    // is not something a picture can say. What a picture does not have to say is this: the painter
    // draws a header from `page.header` and nowhere else, so a page whose value is null has nothing
    // to draw — and the two values below are that null and its consequence, the margin.
    final Song song = chartOf(bars: 96);
    final List<PageLayout> pages = LayoutEngine(style: styleWith(metrics))
        .layout(song, pageWidth: pageWidth, pageHeight: 300);
    expect(pages.length, greaterThan(1));
    expect(pages.first.header, isNotNull);
    expect(pages[1].header, isNull);
    final PlacedSystem secondSystem = pages[1].systems.first;
    stdout.writeln(
      'probe.header.page2 header=${pages[1].header} '
      'second_page_label=${secondSystem.sectionLabel} '
      'page2_first_system_top=${secondSystem.bounds.top} '
      'page2_first_bar_top=${secondSystem.bars.first.bounds.top}',
    );
    expect(
      secondSystem.bounds.top,
      styleWith(metrics).pageMargin,
      reason:
          'the first system on page two starts at the margin, not below a band',
    );
    expect(
      secondSystem.bars.first.bounds.top - secondSystem.bounds.top,
      0,
      reason:
          'the first system of page two carries no section label, so its chord row begins at '
          'the system top: page one pays the header and the letter, page two pays nothing',
    );
  });
}
