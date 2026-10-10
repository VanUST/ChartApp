// PURPOSE: Measure the two claims the eraser rests on that a count cannot settle: WHICH of two
//          nearly-coincident strokes a touch removes, with the distances that decided it, and
//          WHETHER an erased stroke comes back from undo EXACTLY — same id, same points, same
//          anchor — rather than as a stroke that merely looks the same. It is a probe and not a
//          test: it prints the numbers and the canonical JSON it compared, so the answer can be
//          read rather than trusted, and it asserts nothing.
// INPUTS: None. The chart, the page and the strokes are built here, so this runs on a machine with
//         no device and no font.
// OUTPUTS: Lines on stdout: the layout used, the near-miss distances for three aim points, and the
//          comparison of the erased stroke with the one undo put back. Exit code 0 unless a case it
//          needs cannot be set up, which exits 2 rather than printing a misleading zero.
// KEYWORDS: probe, eraser, ink, near-miss, tie-rule, undo-exactness, render-order, diagnostic,
//           not-part-of-the-library
import 'dart:io';

import 'package:chart_core/chart_core.dart';

/// A four-bar one-section chart, laid out deterministically by the package's default metrics.
Song probeChart() => Song(
  id: 'probe-ink-erase',
  title: 'Probe ink erase',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: 'A',
      label: SectionLabel.letter('A'),
      bars: <Bar>[
        for (int index = 0; index < 4; index++)
          Bar(
            chords: <BeatChord>[
              BeatChord(
                chord: Chord(
                  root: ChordRoot(index),
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

/// One straight pen stroke anchored to [anchor], drawn in anchor-local coordinates.
InkStroke straightStroke({
  required String id,
  required EventAnchor anchor,
  required double y,
  double x0 = 10,
  double x1 = 40,
  double size = 3,
}) => InkStroke(
  id: id,
  tool: StrokeTool.pen,
  color: '#102a43',
  size: size,
  anchor: anchor,
  points: <InkPoint>[
    InkPoint(x: x0, y: y, w: 0.5, t: 0),
    InkPoint(x: (x0 + x1) / 2, y: y, w: 0.5, t: 10),
    InkPoint(x: x1, y: y, w: 0.5, t: 20),
  ],
);

void main() {
  final Song song = probeChart();
  const LayoutEngine engine = LayoutEngine();
  final List<PageLayout> pages = engine.layout(
    song,
    pageWidth: 900,
    pageHeight: 1000,
  );
  if (pages.isEmpty || pages.first.bars.isEmpty) {
    stderr.writeln('could not lay out the probe chart');
    exit(2);
  }
  final PageLayout page = pages.first;
  final PlacedBar bar = page.bars.first;
  final PlacedCell cell = bar.cells.first;
  final EventAnchor anchor = EventAnchor(
    sectionId: bar.sectionId,
    bar: bar.barIndex,
    beat: cell.beat,
  );
  final InkPlacement placement = resolveEventAnchor(page, anchor)!;

  // The surface point under an anchor-local point: engraved = origin + local, surface = engraved *
  // scale, which is exactly the transform InkPainter applies.
  LayoutOffset surfaceOf(double localX, double localY) => LayoutOffset(
    (placement.origin.x + localX) * page.scale,
    (placement.origin.y + localY) * page.scale,
  );

  stdout.writeln(
    'PROBE layout page=${page.index} scale=${page.scale} '
    'anchor=$anchor cell_rect=(${cell.bounds.left},${cell.bounds.top},'
    '${cell.bounds.size.width},${cell.bounds.size.height})',
  );

  // --- The near-miss: two parallel strokes six anchor-local pixels apart, aimed between. --------
  // Six pixels is chosen because it is inside the eraser's band for a pen (nib 3 gives a 7.5-pixel
  // radius at scale 1) and comfortably outside the painted line itself, which is the case the
  // musician cannot resolve by eye.
  final InkStroke upper = straightStroke(
    id: 'ink-upper',
    anchor: anchor,
    y: 10,
  );
  final InkStroke lower = straightStroke(
    id: 'ink-lower',
    anchor: anchor,
    y: 16,
  );
  final List<InkStroke> pair = <InkStroke>[upper, lower];
  stdout.writeln(
    'PROBE strokes upper=(${upper.points.first.x},${upper.points.first.y})-'
    '(${upper.points.last.x},${upper.points.last.y}) '
    'lower=(${lower.points.first.x},${lower.points.first.y})-'
    '(${lower.points.last.x},${lower.points.last.y}) '
    'gap=${16 - 10} '
    'band_px=${inkStrokeNibWidth(upper) * page.scale / 2 + InkEraseAim.tolerancePx}',
  );
  for (final double aimY in <double>[11, 13, 15, 30]) {
    final LayoutOffset surface = surfaceOf(25, aimY);
    final LayoutOffset engraved = page.pagePointOf(surface);
    final double toUpper = inkStrokeDistanceToPagePoint(
      stroke: upper,
      origin: placement.origin,
      pagePoint: engraved,
    );
    final double toLower = inkStrokeDistanceToPagePoint(
      stroke: lower,
      origin: placement.origin,
      pagePoint: engraved,
    );
    final InkEraseHit? hit = hitTestInkErase(
      page: page,
      strokes: pair,
      surfacePoint: surface,
    );
    stdout.writeln(
      'PROBE aim_local_y=$aimY surface=(${surface.x.toStringAsFixed(2)},'
      '${surface.y.toStringAsFixed(2)}) '
      'dist_upper_px=${toUpper.toStringAsFixed(3)} '
      'dist_lower_px=${toLower.toStringAsFixed(3)} '
      'chose=${hit == null ? '(none)' : hit.stroke.id} '
      'chosen_distance_px=${hit?.surfaceDistance.toStringAsFixed(3) ?? '-'}',
    );
  }

  // --- Undo: remove the middle of three strokes and put it back. --------------------------------
  final EditSession session = EditSession(
    document: DocumentState(song: song),
    docId: song.id,
  );
  final List<InkStroke> originals = <InkStroke>[
    straightStroke(id: 'ink-A', anchor: anchor, y: 10),
    straightStroke(id: 'ink-B', anchor: anchor, y: 20),
    straightStroke(id: 'ink-C', anchor: anchor, y: 30),
  ];
  for (int index = 0; index < originals.length; index++) {
    session.apply(
      InkStrokeAddEvent(
        docId: session.docId,
        seq: session.seq,
        index: index,
        stroke: originals[index],
      ),
    );
  }
  final DocumentState before = session.document;
  stdout.writeln(
    'PROBE document_before ids=${before.strokes.map((InkStroke s) => s.id).toList()} '
    'undo_depth=${session.undoDepth}',
  );

  final InkStroke removed = originals[1];
  final bool erased = session.eraseStroke(removed.id);
  stdout.writeln(
    'PROBE erased id=${removed.id} applied=$erased '
    'ids_after=${session.document.strokes.map((InkStroke s) => s.id).toList()} '
    'undo_depth=${session.undoDepth} redo_depth=${session.redoDepth}',
  );

  final bool undone = session.undo();
  final DocumentState after = session.document;
  final int restoredIndex = after.strokes.indexWhere(
    (InkStroke s) => s.id == removed.id,
  );
  final InkStroke? restoredStroke = restoredIndex < 0
      ? null
      : after.strokes[restoredIndex];
  final bool sameId = restoredStroke?.id == removed.id;
  final bool sameAnchor = restoredStroke?.anchor == removed.anchor;
  final bool sameTool = restoredStroke?.tool == removed.tool;
  final bool sameColor = restoredStroke?.color == removed.color;
  final bool sameSize = restoredStroke?.size == removed.size;
  final bool samePointCount =
      restoredStroke?.points.length == removed.points.length;
  bool samePoints = samePointCount;
  if (restoredStroke != null && samePointCount) {
    for (int index = 0; index < removed.points.length; index++) {
      if (restoredStroke.points[index] != removed.points[index]) {
        samePoints = false;
      }
    }
  }
  stdout.writeln(
    'PROBE undone=$undone ids_after_undo='
    '${after.strokes.map((InkStroke s) => s.id).toList()} '
    'document_equal=${after == before}',
  );
  stdout.writeln(
    'PROBE compare same_id=$sameId same_anchor=$sameAnchor same_tool=$sameTool '
    'same_color=$sameColor same_size=$sameSize same_point_count=$samePointCount '
    'same_points=$samePoints stroke_equal=${restoredStroke == removed}',
  );
  stdout.writeln('PROBE removed_json=${removed.toJson()}');
  stdout.writeln('PROBE restored_json=${restoredStroke?.toJson()}');
  stdout.writeln(
    'PROBE anchor_removed=${removed.anchor.toJson()} '
    'anchor_restored=${restoredStroke?.anchor.toJson()}',
  );
}
