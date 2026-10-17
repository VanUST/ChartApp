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

import '../support/place_fixture.dart';

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
  final LayoutRect cell = bar.bounds;
  final EventAnchor anchor = EventAnchor(
    sectionId: bar.sectionId,
    bar: bar.barIndex,
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
    'anchor=$anchor cell_rect=(${cell.left},${cell.top},'
    '${cell.size.width},${cell.size.height})',
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

  // --- The DRAG: one path through four strokes, in the order it reaches them, once each. ----------
  // This is the gesture the eraser is now driven by (the owner's "надо попасть сразу, неудобно"), and
  // the two numbers a report must carry are HOW MANY strokes one gesture crosses and WHAT PUTTING
  // THEM BACK COSTS. The path is fed the way a pointer feeds one: sample after sample, a pixel
  // apart, so the trail's own resampling is exercised rather than bypassed.
  final EditSession dragSession = EditSession(
    document: DocumentState(song: song),
    docId: song.id,
  );
  final List<InkStroke> four = <InkStroke>[
    for (int row = 0; row < 4; row++)
      straightStroke(id: 'drag-${row + 1}', anchor: anchor, y: 10 + row * 10),
  ];
  for (int index = 0; index < four.length; index++) {
    dragSession.apply(
      InkStrokeAddEvent(
        docId: dragSession.docId,
        seq: dragSession.seq,
        index: index,
        stroke: four[index],
      ),
    );
  }
  final DocumentState dragBefore = dragSession.document;
  stdout.writeln(
    'PROBE drag_document_before ids='
    '${dragBefore.strokes.map((InkStroke s) => s.id).toList()} '
    'undo_depth=${dragSession.undoDepth}',
  );
  final InkEraseTrail trail = InkEraseTrail(
    page: page,
    strokes: dragSession.document.strokes,
  );
  const double pathLocalX = 25;
  int dragSamples = 0;
  for (double localY = 2; localY <= 48; localY += 1) {
    trail.addSample(surfaceOf(pathLocalX, localY));
    dragSamples++;
  }
  stdout.writeln(
    'PROBE drag_path samples=$dragSamples '
    'from_local=($pathLocalX,2) to_local=($pathLocalX,48) '
    'crossed=${trail.crossed.length} '
    'ids_in_order=${trail.crossed.map((InkEraseHit h) => h.stroke.id).toList()} '
    'distances=${trail.crossed.map((InkEraseHit h) => h.surfaceDistance.toStringAsFixed(2)).toList()}',
  );
  // THE SAME PATH AGAIN MUST CROSS NOTHING: a stroke is named once, and a hand that rubs back and
  // forth over the same ink must not append a second deletion of it.
  final InkEraseTrail repeat = InkEraseTrail(
    page: page,
    strokes: dragSession.document.strokes,
  );
  for (double localY = 2; localY <= 48; localY += 1) {
    repeat.addSample(surfaceOf(pathLocalX, localY));
  }
  final int firstPass = repeat.crossed.length;
  for (double localY = 48; localY >= 2; localY -= 1) {
    repeat.addSample(surfaceOf(pathLocalX, localY));
  }
  stdout.writeln(
    'PROBE drag_repeat first_pass=$firstPass after_paths=2 '
    'crossed=${repeat.crossed.length} '
    'ids=${repeat.crossed.map((InkEraseHit h) => h.stroke.id).toList()}',
  );
  // Apply the deletions in the order crossed, then put them back one undo at a time and count.
  final int undoBeforeDrag = dragSession.undoDepth;
  for (final InkEraseHit hit in trail.crossed) {
    dragSession.eraseStroke(hit.stroke.id);
  }
  stdout.writeln(
    'PROBE drag_applied crossed=${trail.crossed.length} '
    'strokes_after=${dragSession.document.strokes.length} '
    'ids_after=${dragSession.document.strokes.map((InkStroke s) => s.id).toList()} '
    'undo_steps_added=${dragSession.undoDepth - undoBeforeDrag}',
  );
  int undos = 0;
  while (dragSession.canUndo && dragSession.document != dragBefore) {
    dragSession.undo();
    undos++;
    stdout.writeln(
      'PROBE drag_undo n=$undos ids=${dragSession.document.strokes.map((InkStroke s) => s.id).toList()}',
    );
  }
  stdout.writeln(
    'PROBE drag_undo_total undos=$undos '
    'document_equal=${dragSession.document == dragBefore} '
    'ids_after_undo=${dragSession.document.strokes.map((InkStroke s) => s.id).toList()}',
  );

  // --- The COST of the trail on a page that is as inked as this application allows. ---------------
  // The eraser runs on the thread that reads the pen, so the price of a screen-wide drag is a number
  // this project must be able to read rather than assume. The stroke count and point count come from
  // A61's measured full page (about five thousand accumulated points); the path is a screen wide.
  final List<InkStroke> dense = <InkStroke>[
    for (int row = 0; row < 40; row++)
      InkStroke(
        id: 'dense-$row',
        tool: StrokeTool.pen,
        color: '#102a43',
        size: 3,
        anchor: anchor,
        points: <InkPoint>[
          for (int point = 0; point < 120; point++)
            InkPoint(
              x: 4 + point * 1.2,
              y: 4 + row * 2.2 + (point.isEven ? 0 : 0.8),
              w: 0.5,
              t: point * 4,
            ),
        ],
      ),
  ];
  final Stopwatch stopwatch = Stopwatch()..start();
  final InkEraseTrail denseTrail = InkEraseTrail(page: page, strokes: dense);
  final int buildMicros = stopwatch.elapsedMicroseconds;
  stopwatch.reset();
  int denseSamples = 0;
  for (double localX = 2; localX <= 60; localX += 0.5) {
    denseTrail.addSample(surfaceOf(localX, 45));
    denseSamples++;
  }
  final int walkMicros = stopwatch.elapsedMicroseconds;
  stdout.writeln(
    'PROBE cost strokes=${dense.length} '
    'points=${dense.length * dense[0].points.length} '
    'path_samples=$denseSamples build_ms=${(buildMicros / 1000).toStringAsFixed(3)} '
    'walk_ms=${(walkMicros / 1000).toStringAsFixed(3)} '
    'us_per_sample=${denseSamples == 0 ? '-' : (walkMicros / denseSamples).toStringAsFixed(1)} '
    'crossed=${denseTrail.crossed.length}',
  );
}
