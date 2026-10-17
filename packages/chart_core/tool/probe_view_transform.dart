// PURPOSE: Measure, for a chart under the musician's own zoom and pan, the four claims owner
//          decision D34 rests on and that no count can settle: that a surface point maps to exactly
//          one page point and back, that a pen sample written at any zoom is anchored to the cell
//          under the nib, that a chord hit test names the same cell at every zoom and offset, and
//          that a stored stroke's position relative to its bar does not change as the view does. It
//          is a probe and not a test: it prints the numbers and asserts nothing, so the answer can
//          be read rather than trusted.
// INPUTS: None. The chart, the page and the strokes are built here, so this runs on a machine with
//         no device, no font and no widget binding.
// OUTPUTS: Lines on stdout. For each view: the page-to-surface mapping of one cell centre and back,
//          the anchor the assembler chose for a pen sample aimed at that centre and the stored
//          anchor-local point it produced, the cell the same surface point names under hit testing,
//          and the surface position the painter would draw the stored stroke at — compared with the
//          point the pen was put at. Exit code 0 unless the probe cannot set up its page, which
//          exits 2 rather than printing a misleading zero.
// KEYWORDS: probe, view-transform, zoom, pan, single-inverse, pen-anchor, chord-hit-test,
//           ink-does-not-move, d33, d34, diagnostic, not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

import '../support/place_fixture.dart';

/// A twelve-bar two-section chart, laid out deterministically by the package's default metrics.
Song probeChart() => Song(
  id: 'probe-view-transform',
  title: 'Probe view transform',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    for (final String label in <String>['A', 'B'])
      Section(
        id: label,
        label: SectionLabel.letter(label),
        bars: <Bar>[
          for (int index = 0; index < 6; index++)
            Bar(
              chords: <ChordMark>[
                ChordMark(
                  place: placeAt(0),
                  chord: Chord(
                    root: ChordRoot(index),
                    quality: ChordQuality.majorSeventh,
                  ),
                ),
              ],
            ),
        ],
      ),
  ],
);

/// The pane this probe engraves for, and the surface the views are expressed in.
const double paneWidth = 900;
const double paneHeight = 1000;

void main() {
  final Song song = probeChart();
  const LayoutEngine engine = LayoutEngine();
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: paneWidth,
    pageHeight: paneHeight,
  );
  if (pages.isEmpty || pages.first.bars.isEmpty) {
    stderr.writeln('could not lay out the probe chart');
    exit(2);
  }
  final PageLayout engraved = pages.first;
  final PlacedBar bar = engraved.bars[3];
  final LayoutRect cell = bar.bounds;
  final EventAnchor aimed = EventAnchor(
    sectionId: bar.sectionId,
    bar: bar.barIndex,
  );

  stdout.writeln(
    'PROBE page pane=${paneWidth}x$paneHeight scale=${engraved.scale} '
    'systems=${engraved.systems.length} bars=${engraved.bars.length} '
    'aimed_cell=$aimed '
    'cell_rect=(${cell.left},${cell.top},'
    '${cell.size.width},${cell.size.height})',
  );

  // The centre of the aimed cell, in the page's own engraved coordinates. Every view below puts the
  // nib on the point of the SURFACE that this cell centre maps to, which is the whole of "the pen
  // writes where it is put".
  final LayoutOffset cellCentre = LayoutOffset(
    cell.left + cell.size.width / 2,
    cell.top + cell.size.height / 2,
  );

  // Each view is (zoom, pan in surface pixels). The pans are chosen to be the CLAMPED extremes for
  // their zoom — the corners a musician can actually reach by dragging — rather than numbers that a
  // gesture could never produce.
  for (final (double, LayoutOffset) request in <(double, LayoutOffset)>[
    (1, LayoutOffset.zero),
    (1.5, LayoutOffset(0, 0)),
    (2, LayoutOffset(-400, -300)),
    (2, LayoutOffset(-900, -1000)),
    (4, LayoutOffset(-2000, -2500)),
  ]) {
    final double requestedZoom = request.$1;
    final LayoutOffset requestedPan = request.$2;
    final PageLayout page = engraved.withView(
      zoom: requestedZoom,
      pan: requestedPan,
    );

    // --- 1. ONE INVERSE: surface -> page -> surface is the identity. -----------------------------
    final LayoutOffset surfaceOfCell = page.surfacePointOf(cellCentre);
    final LayoutOffset backAgain = page.pagePointOf(surfaceOfCell);
    final double roundTripError =
        (backAgain.x - cellCentre.x).abs() + (backAgain.y - cellCentre.y).abs();

    // --- 2. THE PEN IS PUT AT THAT SURFACE POINT AND MUST LAND ON THE CELL. ----------------------
    final InkStrokeAssembler assembler = InkStrokeAssembler(
      tool: StrokeTool.pen,
      color: '#102a43',
      size: 3,
    );
    final bool opened = assembler.begin(
      page: page,
      surfacePoint: surfaceOfCell,
      pressure: 0.5,
      time: 1000,
    );
    final InkStroke? stroke = opened
        ? assembler.end(page: page, id: 'probe-stroke')
        : null;
    final InkAnchorChoice? choice = opened
        ? resolveInkAnchor(page, page.pagePointOf(surfaceOfCell))
        : null;

    // --- 3. THE CHORD HIT TEST AT THE SAME SURFACE POINT. ----------------------------------------
    final ChartHit? hit = hitTestPage(page, page.pagePointOf(surfaceOfCell));
    final String hitAddress = hit == null
        ? '(none)'
        : '${hit.sectionId}#${hit.barIndex} beat=${hit.local.x}';

    // --- 4. WHERE THE PAINTER WOULD DRAW THE STORED STROKE. --------------------------------------
    // The painter resolves the anchor on the page, adds the stored anchor-local point, and applies
    // the page's own transform. This is that arithmetic, so the number below is where the ink is
    // DRAWN and not where it is stored.
    final InkPlacement? placement = stroke == null
        ? null
        : resolveEventAnchor(page, stroke.anchor);
    final LayoutOffset? drawn = (stroke == null || placement == null)
        ? null
        : page.surfacePointOf(
            LayoutOffset(
              placement.origin.x + stroke.points.first.x,
              placement.origin.y + stroke.points.first.y,
            ),
          );
    final double inkError = drawn == null
        ? double.nan
        : (drawn.x - surfaceOfCell.x).abs() + (drawn.y - surfaceOfCell.y).abs();

    stdout.writeln(
      'PROBE view zoom=${page.zoom} '
      'pan=(${page.pan.x.toStringAsFixed(1)},${page.pan.y.toStringAsFixed(1)}) '
      'drawn_scale=${page.drawnScale.toStringAsFixed(6)} '
      'cell_surface=(${surfaceOfCell.x.toStringAsFixed(2)},'
      '${surfaceOfCell.y.toStringAsFixed(2)}) '
      'page_point=(${backAgain.x.toStringAsFixed(2)},'
      '${backAgain.y.toStringAsFixed(2)}) '
      'round_trip_err_px=${roundTripError.toStringAsFixed(9)}',
    );
    stdout.writeln(
      'PROBE pen zoom=${page.zoom} opened=$opened '
      'anchor=${stroke?.anchor ?? '(none)'} '
      'basis=${choice?.basis.token ?? '(none)'} '
      'aimed=$aimed anchor_matches=${stroke?.anchor == aimed} '
      'first_local=(${stroke?.points.first.x.toStringAsFixed(6) ?? '-'},'
      '${stroke?.points.first.y.toStringAsFixed(6) ?? '-'}) '
      'expected_local=(${(cellCentre.x - (choice?.origin.x ?? 0)).toStringAsFixed(6)},'
      '${(cellCentre.y - (choice?.origin.y ?? 0)).toStringAsFixed(6)}) '
      'drawn_surface=(${drawn?.x.toStringAsFixed(2) ?? '-'},'
      '${drawn?.y.toStringAsFixed(2) ?? '-'}) '
      'draw_err_px=${inkError.toStringAsFixed(9)}',
    );
    stdout.writeln(
      'PROBE hit zoom=${page.zoom} '
      'hit=$hitAddress '
      // The hit test still names a CELL, because the layout still divides a bar into columns; the
      // stroke is anchored to the BAR, so what is compared here is the bar the touch landed on.
      'same_bar=${hit != null && hit.sectionId == aimed.sectionId && hit.barIndex == aimed.bar}',
    );
  }

  // --- THE HANDWRITING DOES NOT MOVE: one stroke, five views, one stored form. -------------------
  // The stroke is written ONCE at zoom 1 and then read back at every other view: what changes is
  // where it is drawn (a surface position), and what must not change is the anchor-local point and
  // the offset from its own anchor's corner.
  final PageLayout identity = engraved.withView(
    zoom: 1,
    pan: LayoutOffset.zero,
  );
  final InkStrokeAssembler writer = InkStrokeAssembler(
    tool: StrokeTool.pen,
    color: '#102a43',
    size: 3,
  );
  writer.begin(
    page: identity,
    surfacePoint: identity.surfacePointOf(
      LayoutOffset(cellCentre.x - 6, cellCentre.y - 3),
    ),
    pressure: 0.5,
    time: 0,
  );
  final InkStroke written = writer.end(page: identity, id: 'probe-fixed')!;
  stdout.writeln(
    'PROBE fixed anchor=${written.anchor} '
    'stored=(${written.points.first.x.toStringAsFixed(6)},'
    '${written.points.first.y.toStringAsFixed(6)})',
  );
  for (final (double, LayoutOffset) view in <(double, LayoutOffset)>[
    (1, LayoutOffset.zero),
    (2, LayoutOffset(-400, -300)),
    (3, LayoutOffset(-1200, -1500)),
    (4, LayoutOffset(-2400, -2900)),
  ]) {
    final PageLayout page = engraved.withView(zoom: view.$1, pan: view.$2);
    final InkPlacement? placement = resolveEventAnchor(page, written.anchor);
    if (placement == null) {
      stdout.writeln('PROBE fixed zoom=${view.$1} anchor_unresolved');
      continue;
    }
    final LayoutOffset drawn = page.surfacePointOf(
      LayoutOffset(
        placement.origin.x + written.points.first.x,
        placement.origin.y + written.points.first.y,
      ),
    );
    // The bar's own corner, drawn, so "the ink moved with its bar" can be checked as the difference
    // between two surface points rather than as one absolute number.
    final LayoutOffset barOrigin = page.surfacePointOf(placement.origin);
    stdout.writeln(
      'PROBE fixed zoom=${page.zoom} '
      'pan=(${page.pan.x.toStringAsFixed(1)},${page.pan.y.toStringAsFixed(1)}) '
      'anchor=${placement.anchor} '
      'drawn_ink=(${drawn.x.toStringAsFixed(2)},${drawn.y.toStringAsFixed(2)}) '
      'drawn_bar_origin=(${barOrigin.x.toStringAsFixed(2)},'
      '${barOrigin.y.toStringAsFixed(2)}) '
      'ink_minus_bar=(${(drawn.x - barOrigin.x).toStringAsFixed(6)},'
      '${(drawn.y - barOrigin.y).toStringAsFixed(6)})',
    );
  }
}
