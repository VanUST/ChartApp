// PURPOSE: Verify owner decision D34 end to end on the real widgets: two fingers together move the
//          chart and a pinch magnifies it, ONE finger does neither, the zoom control in the scene
//          bar moves the view and takes it back to the whole page, a chord tap names the same cell
//          at every zoom, and — the acceptance test — THE PEN STILL WRITES when the page is
//          magnified, landing on the cell under the nib with the same stored anchor-local point it
//          would have produced on an unmagnified page.
//
//          WHY TWO SYNTHETIC POINTERS AND NOT A DEVICE. `adb shell input` drives ONE pointer: it has
//          a single pointer id and no way to hold two contacts down at once, so a genuine two-finger
//          gesture cannot be injected over adb at all. This file is therefore the instrument for the
//          GESTURE, and the device run recorded in `docs/sdd.md` A63 is the instrument for the PEN.
//          Saying which instrument produced which claim is the point; a screenshot of a pan no adb
//          run produced would have been worth less than this sentence.
//
//          WHY EVERY AIM IS THE PAGE'S OWN CENTRE. A zoom made by the scene bar's control keeps the
//          page point under the middle of the pane still, so the page's centre is a point that stays
//          in view at every zoom and at every pan the clamp allows. Aiming there makes the same cell
//          reachable at 1x, 2x and 4x, which is exactly what the three claims need: a hit test that
//          names the same cell, a pen that lands on that cell, and a stored point that is the same
//          number at every magnification.
//
//          WHY THE ASSERTIONS ARE NUMBERS. "The zoom changed" is satisfied by a zoom that changed to
//          the wrong value, and "the pen wrote" is satisfied by a stroke anchored to the wrong bar.
//          The claims here are the anchor's address, the stored anchor-local point (which must be
//          the SAME value at every zoom), and the page's own view fields.
//
//          AND ONE CLAIM ABOUT THE OWNER'S SCALE LOCK (A66), measured here because no other
//          instrument could: a lock held across a pane change that ALTERS THE PAGE'S OWN `scale`.
//          A66 §2 records that its own window engraved at 1:1, so its case proves "the lock survives
//          a re-engraving" but not "the lock compensates a different scale", and A68 §8 records that
//          the device run never took that measurement either. That case is the pair.
// INPUTS: None. The chart is synthetic and the layout is deterministic, so this runs on any machine
//         with no device and no font. The scale-lock case pumps a long chart in a window narrow
//         enough that hiding and showing the chrome change the page's own scale.
// OUTPUTS: Pass/fail per behaviour, plus the numbers each one rests on — the view before and after
//          each gesture, the cell the pen aimed at, the anchor it received, the stored point, the
//          same stored point on an unmagnified page, and the page's own scale on both sides of the
//          pane change — printed so the arithmetic can be read rather than only trusted.
// KEYWORDS: test, widget, two-finger, pan, pinch, view-transform, zoom, pen-at-zoom, hit-test,
//           synthetic-pointers, d33, d34, view-lock, pane-change, a66
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ink_capture_surface.dart';
import 'package:chartapp/ink_layer.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The pane the viewer is pumped at for the view cases.
///
/// It is the size `ink_mode_test.dart` already uses for the interaction cases, so the page mode, the
/// engraving and the cells are the same ones that file asserts about: a regression here cannot
/// quietly be a regression in the fixture.
const Size _paneSize = Size(900, 1000);

/// A two-section chart, laid out deterministically by the package's default metrics.
///
/// SIXTY BARS AND NOT TWELVE, AND THE REASON IS THE FOUR-TIMES ZOOM CASE. THE OLD FIXTURE, QUOTED:
/// `for (int index = 0; index < 6; index++)` — twelve bars in all, which used to fill the page
/// because a bar was four cells wide. A bar is as wide as its content now (one 5-character chord is
/// 91 points), so twelve bars were two systems in the top seventh of an 824×1318 page: the pen case
/// zooms to 4×, and at that zoom the glass looks at the MIDDLE of the page, which was blank paper.
/// Sixty bars fill the page with systems, so every zoom looks at music — which is what a fixture for
/// a view transform is for.
Song viewChart() => Song(
  id: 'view-transform',
  title: 'View transform',
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
          for (int index = 0; index < 30; index++)
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

/// A one-song library holding [song].
IRealLibrary libraryOf(Song song) => IRealLibrary(
  playlistName: '',
  songs: <IRealSong>[IRealSong(index: 0, song: song)],
);

/// A chart long enough that FIT must engrave it BELOW 1:1 in the window the pane cases use.
///
/// [viewChart] is short enough to fit a tablet pane at full size, which is right for the gesture
/// cases and useless for the lock: A66 §2 records that its own window engraved at 1:1, so a scale
/// held there could not be told apart from a scale that never changed. This chart is the fixture
/// that makes the page's own scale a number the lock has to compensate.
Song longViewChart(int bars) => Song(
  id: 'view-transform-long',
  title: 'Long view transform',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    Section(
      id: 'L',
      label: const SectionLabel.letter('L'),
      bars: <Bar>[
        for (int index = 0; index < bars; index++)
          Bar(
            chords: <ChordMark>[
              ChordMark(
                place: placeAt(0),
                chord: Chord(
                  root: ChordRoot(index % 12),
                  quality: ChordQuality.majorSeventh,
                ),
              ),
            ],
          ),
      ],
    ),
  ],
);

/// Pumps the viewer with [song] loaded through an injected loader.
Future<void> pumpViewer(
  WidgetTester tester,
  Song song, {
  Size size = _paneSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: IRealViewerScreen(
        loader: (String path) async => libraryOf(song),
        initialPath: 'synthetic',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The chart painter currently on screen.
ChartPainter chartPainter(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
  );
  return tester.widget<CustomPaint>(finder).painter! as ChartPainter;
}

/// The ink painter currently on screen.
InkPainter inkPainter(WidgetTester tester) {
  final Finder finder = find.byWidgetPredicate(
    (Widget widget) => widget is CustomPaint && widget.painter is InkPainter,
  );
  return tester.widget<CustomPaint>(finder).painter! as InkPainter;
}

/// The surface that receives pointer events for the page currently shown.
Finder pageSurfaceFinder() => find.byType(RawPointerCapture).first;

/// Switches the ink mode by pressing the app bar's own control.
Future<void> setInkMode(WidgetTester tester, bool on) async {
  final IconButton button = tester.widget<IconButton>(
    find.byKey(const ValueKey<String>('viewer-ink-toggle')),
  );
  if (button.tooltip!.startsWith('Drawing') == on) {
    return;
  }
  await tester.tap(find.byKey(const ValueKey<String>('viewer-ink-toggle')));
  await tester.pumpAndSettle();
}

/// The surface position of a point given in the page's engraved coordinates, at the page's view.
///
/// It is the page's own forward transform — the one `pagePointOf` inverts — rather than a copy of
/// the arithmetic, so a gesture aimed through this helper is aimed through the same transform the
/// pen is routed by.
Offset surfaceOf(WidgetTester tester, PageLayout page, Offset pagePoint) {
  final LayoutOffset surface = page.surfacePointOf(
    LayoutOffset(pagePoint.dx, pagePoint.dy),
  );
  return Offset(surface.x, surface.y);
}

/// The global position of a point given in the page's engraved coordinates.
Offset pagePointToGlobal(
  WidgetTester tester,
  PageLayout page,
  Offset pagePoint,
) =>
    tester.getTopLeft(pageSurfaceFinder()) + surfaceOf(tester, page, pagePoint);

/// Draws one stroke from [pageStart] to [pageEnd], in the page's engraved coordinates, with a pen.
///
/// [startMs] is the timestamp the contact begins at, and it is REQUIRED rather than defaulting to
/// zero: a stroke's identity is derived from its anchor AND the millisecond it began (see
/// `InkCaptureLayer._nextStrokeId`), so two strokes a test draws on one cell with the default
/// timestamp would share an id and the document would refuse the second. Naming the start time is
/// what lets this file draw three strokes on the same cell — which is what makes their stored points
/// comparable — without depending on the undo path to clear the id in between.
Future<void> drawStroke(
  WidgetTester tester,
  PageLayout page, {
  required Offset pageStart,
  required Offset pageEnd,
  required int startMs,
}) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.stylus,
  );
  await gesture.down(
    pagePointToGlobal(tester, page, pageStart),
    timeStamp: Duration(milliseconds: startMs),
  );
  await tester.pump(const Duration(milliseconds: 8));
  for (int step = 1; step <= 4; step++) {
    await gesture.moveTo(
      pagePointToGlobal(
        tester,
        page,
        Offset.lerp(pageStart, pageEnd, step / 4)!,
      ),
      timeStamp: Duration(milliseconds: startMs + 8 * step),
    );
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up(timeStamp: Duration(milliseconds: startMs + 8 * 5));
  await tester.pumpAndSettle();
}

/// The point at the middle of the page, in the page's own engraved coordinates.
///
/// This is the point a zoom made from the scene bar holds still, so it stays in view at every
/// magnification and every legal pan; see the file header.
Offset pageCentreOf(PageLayout page) =>
    Offset(page.size.width / 2, page.size.height / 2);

/// The ink layer the page currently on screen routes its contacts into.
///
/// Read from the widget rather than from a private field of the screen: the widget already carries
/// the layer as its own public contract, and a test that could only see it through the screen would
/// have to be told about a copy of the state that the screen does not own.
InkCaptureLayer inkLayerOf(WidgetTester tester) =>
    tester.widget<RawPointerCapture>(pageSurfaceFinder()).layer;

/// Sends one raw touch-down with an EXPLICIT contact radius, through the binding's own hit test.
///
/// WHY THE HAND-BUILT EVENT RATHER THAN `TestGesture`. `TestGesture` builds its own
/// `PointerDownEvent` and exposes no way to set `radiusMajor`; the palm rule compares the contact's
/// WIDTH — measured on this panel at 71 and 87 logical pixels against a threshold of 40 — so a
/// gesture built by the harness would exercise the width-less path and prove nothing about a palm.
/// Dispatching the event by hand is the only way this file can put a palm on the glass.
///
/// The radius is half the width the rule compares, because `InkInputMapper.contactWidthOf` doubles
/// `radiusMajor` before the comparison: a real palm that reports 71 logical pixels of width is sent
/// here as `radiusMajor: 35.5`.
void sendTouchDown(
  WidgetTester tester, {
  required int pointer,
  required Offset at,
  required double radiusMajor,
  required int timeMs,
}) {
  tester.binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      kind: PointerDeviceKind.touch,
      position: at,
      radiusMajor: radiusMajor,
      radiusMinor: radiusMajor,
      buttons: kPrimaryButton,
      device: 1,
      timeStamp: Duration(milliseconds: timeMs),
    ),
  );
}

/// Sends one raw touch-move for a contact already down; see [sendTouchDown].
void sendTouchMove(
  WidgetTester tester, {
  required int pointer,
  required Offset at,
  required double radiusMajor,
  required int timeMs,
}) {
  tester.binding.handlePointerEvent(
    PointerMoveEvent(
      pointer: pointer,
      kind: PointerDeviceKind.touch,
      position: at,
      radiusMajor: radiusMajor,
      radiusMinor: radiusMajor,
      buttons: kPrimaryButton,
      device: 1,
      timeStamp: Duration(milliseconds: timeMs),
    ),
  );
}

/// Sends one raw touch-up for a contact already down; see [sendTouchDown].
void sendTouchUp(
  WidgetTester tester, {
  required int pointer,
  required Offset at,
  required int timeMs,
}) {
  tester.binding.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      kind: PointerDeviceKind.touch,
      position: at,
      buttons: kPrimaryButton,
      device: 1,
      timeStamp: Duration(milliseconds: timeMs),
    ),
  );
}

/// One text line describing the view, for the numbers each test prints.
String viewOf(PageLayout page) =>
    'zoom=${page.zoom.toStringAsFixed(4)} '
    'pan=(${page.pan.x.toStringAsFixed(2)},${page.pan.y.toStringAsFixed(2)}) '
    'drawn_scale=${page.drawnScale.toStringAsFixed(4)}';

void main() {
  testWidgets('two fingers pan and pinch; one finger does neither', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, viewChart());
    final ChartPainter plain = chartPainter(tester);
    expect(plain.page.zoom, 1, reason: 'a chart opens at the identity view');

    // The pane's own rectangle, so the two touches land inside the chart rather than on the bars
    // around it.
    final Offset centre = tester.getRect(pageSurfaceFinder()).center;
    const double apart = 60;
    const double spread = 140;

    // --- ONE FINGER DOES NOTHING TO THE VIEW ----------------------------------------------------
    final TestGesture single = await tester.startGesture(centre, pointer: 11);
    await tester.pump();
    await single.moveBy(const Offset(30, 25));
    await tester.pump();
    await single.up();
    await tester.pumpAndSettle();
    final PageLayout afterOne = chartPainter(tester).page;
    expect(
      afterOne.zoom,
      1,
      reason: 'one finger is not the view gesture (owner decision D34)',
    );
    expect(afterOne.pan, LayoutOffset.zero);
    stdout.writeln(
      'view.test.one_finger pointer_count=1 ${viewOf(afterOne)} unchanged=true',
    );

    // --- TWO FINGERS: A PINCH OUT MAGNIFIES -----------------------------------------------------
    final TestGesture first = await tester.startGesture(
      centre - const Offset(apart, 0),
      pointer: 21,
    );
    final TestGesture second = await tester.startGesture(
      centre + const Offset(apart, 0),
      pointer: 22,
    );
    await tester.pump();
    // Move them apart in equal steps, so the focal point stays where it started and the sample is a
    // pinch rather than a pinch with a pan in it.
    for (int step = 0; step < 4; step++) {
      await first.moveBy(const Offset(-20, 0));
      await second.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final PageLayout pinched = chartPainter(tester).page;
    // The span went from 60 to 140, a factor of 7/3.
    expect(
      pinched.zoom,
      closeTo(spread / apart, 0.05),
      reason: 'the pinch factor must be the ratio of the two spans',
    );
    stdout.writeln(
      'view.test.pinch pointers=2 span_from=$apart span_to=$spread '
      '${viewOf(pinched)}',
    );

    // --- AND WHILE STILL DOWN, THE SAME TWO FINGERS PAN ------------------------------------------
    const Offset pan = Offset(-50, -30);
    await first.moveBy(pan);
    await second.moveBy(pan);
    await tester.pump(const Duration(milliseconds: 16));
    final PageLayout panned = chartPainter(tester).page;
    expect(
      panned.zoom,
      closeTo(pinched.zoom, 1e-9),
      reason: 'a translation of the fingers must not change the scale',
    );
    expect(
      panned.pan.x,
      lessThan(pinched.pan.x - 1),
      reason: 'moving both fingers left must move the chart left',
    );
    expect(panned.pan.y, lessThan(pinched.pan.y - 1));
    stdout.writeln(
      'view.test.pan pointers=2 focal_delta=(${pan.dx},${pan.dy}) '
      '${viewOf(panned)}',
    );

    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    // --- THE SCENE BAR'S CONTROL IS THE WAY BACK ------------------------------------------------
    await tester.tap(
      find.byKey(const ValueKey<String>('scene-bar-zoom-reset')),
    );
    await tester.pumpAndSettle();
    final PageLayout reset = chartPainter(tester).page;
    expect(reset.zoom, 1);
    expect(reset.pan, LayoutOffset.zero);
    stdout.writeln('view.test.reset ${viewOf(reset)}');
  });

  testWidgets('the zoom buttons step the view and the reset returns it', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, viewChart());
    await tester.tap(find.byKey(const ValueKey<String>('scene-bar-zoom-in')));
    await tester.pumpAndSettle();
    final PageLayout once = chartPainter(tester).page;
    expect(once.zoom, greaterThan(1));
    await tester.tap(find.byKey(const ValueKey<String>('scene-bar-zoom-in')));
    await tester.pumpAndSettle();
    final PageLayout twice = chartPainter(tester).page;
    expect(twice.zoom, greaterThan(once.zoom));
    await tester.tap(find.byKey(const ValueKey<String>('scene-bar-zoom-out')));
    await tester.pumpAndSettle();
    final PageLayout onceAgain = chartPainter(tester).page;
    expect(onceAgain.zoom, closeTo(once.zoom, 1e-9));
    await tester.tap(
      find.byKey(const ValueKey<String>('scene-bar-zoom-reset')),
    );
    await tester.pumpAndSettle();
    final PageLayout reset = chartPainter(tester).page;
    expect(reset.zoom, 1);
    expect(reset.pan, LayoutOffset.zero);
    stdout.writeln(
      'view.test.buttons once=${once.zoom.toStringAsFixed(4)} '
      'twice=${twice.zoom.toStringAsFixed(4)} '
      'back=${onceAgain.zoom.toStringAsFixed(4)} ${viewOf(reset)}',
    );
  });

  testWidgets('the pen writes at every zoom, at the place under the nib', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, viewChart());
    await setInkMode(tester, true);

    // THE AIM IS CHOSEN INSIDE THE VISIBLE WINDOW OF EACH ZOOM, FROM THE APP'S OWN TRANSFORM. THE OLD
    // FIXTURE, QUOTED: the target was `pageCentreOf(plain)` — the middle of the PAGE, chosen once and
    // reused at every zoom — together with `Offset(target.dx - cell.left, target.dy - cell.top)`
    // measured from the CELL's corner, because a stroke was anchored to the column it was drawn in.
    //
    // TWO THINGS STOPPED BEING TRUE. A stroke is anchored to its BAR, so the origin every stored point
    // is measured from is the bar's corner. And a bar is as wide as what is written in it, so this
    // chart's bars no longer fill the page: the middle of the page is blank paper (that is the null
    // the old fixture dereferenced), and at 4× the glass shows a quarter of the page's middle, so a
    // page point that was comfortably visible at 1× can be off the surface entirely.
    //
    // So each zoom aims at the bar nearest the middle of the GLASS at that zoom, asking [PageLayout.
    // pagePointOf] where the middle of the glass is in the page. That is the same transform the pen
    // uses, which is the point: the case then measures whether the stored point is the nib's own
    // place in the bar, at every zoom, which is what "the pen writes where it looks" means.
    final Rect pane = tester.getRect(pageSurfaceFinder());
    int level = 0;
    for (final double requested in <double>[1, 2, 4]) {
      level++;
      // Put the view at (at least) the requested zoom through the scene bar's own controls, which is
      // the interface path D33 asks for; the pinch is exercised by the first test.
      while (chartPainter(tester).page.zoom < requested - 1e-6) {
        await tester.tap(
          find.byKey(const ValueKey<String>('scene-bar-zoom-in')),
        );
        await tester.pumpAndSettle();
      }
      final PageLayout page = chartPainter(tester).page;
      expect(
        page.zoom,
        greaterThanOrEqualTo(requested - 1e-6),
        reason: 'the view must have reached the zoom the loop asked for',
      );
      // THE VISIBLE WINDOW IN PAGE COORDINATES, from the app's own inverse transform, and the aim is
      // the middle of the part of a bar that the glass actually shows. A stroke can only be drawn
      // where the page is on screen, and at 4× that is a quarter of the page's middle — a bar whose
      // CENTRE is above the window may still have half its height showing, and that is where the
      // pen has to be asked to write.
      final LayoutOffset windowTopLeft = page.pagePointOf(LayoutOffset.zero);
      final LayoutOffset windowBottomRight = page.pagePointOf(
        LayoutOffset(pane.width, pane.height),
      );
      PlacedBar? aimedAt;
      double bestArea = 0;
      LayoutRect bestPart = LayoutRect.fromLTWH(0, 0, 0, 0);
      for (final PlacedBar candidate in page.bars) {
        final double left = candidate.bounds.left > windowTopLeft.x
            ? candidate.bounds.left
            : windowTopLeft.x;
        final double top = candidate.bounds.top > windowTopLeft.y
            ? candidate.bounds.top
            : windowTopLeft.y;
        final double right =
            candidate.bounds.left + candidate.bounds.size.width <
                windowBottomRight.x
            ? candidate.bounds.left + candidate.bounds.size.width
            : windowBottomRight.x;
        final double bottom =
            candidate.bounds.top + candidate.bounds.size.height <
                windowBottomRight.y
            ? candidate.bounds.top + candidate.bounds.size.height
            : windowBottomRight.y;
        if (right <= left + 24 || bottom <= top + 16) {
          continue;
        }
        final double area = (right - left) * (bottom - top);
        if (area > bestArea) {
          bestArea = area;
          aimedAt = candidate;
          bestPart = LayoutRect.fromLTWH(left, top, right - left, bottom - top);
        }
      }
      expect(
        aimedAt,
        isNotNull,
        reason:
            'no part of any bar big enough to aim at is inside the window the glass shows at '
            'zoom ${page.zoom} (window=(${windowTopLeft.x.toStringAsFixed(1)},'
            '${windowTopLeft.y.toStringAsFixed(1)})..(${windowBottomRight.x.toStringAsFixed(1)},'
            '${windowBottomRight.y.toStringAsFixed(1)}) bars=${page.bars.length} '
            'first=(${page.bars.first.bounds.left.toStringAsFixed(1)},'
            '${page.bars.first.bounds.top.toStringAsFixed(1)},'
            '${page.bars.first.bounds.size.width.toStringAsFixed(1)}x'
            '${page.bars.first.bounds.size.height.toStringAsFixed(1)})): the fixture cannot '
            'measure the pen at this zoom',
      );
      final LayoutRect cell = aimedAt!.bounds;
      final Offset target = Offset(
        bestPart.left + bestPart.size.width / 2,
        bestPart.top + bestPart.size.height / 2,
      );
      final ChartHit aimed = hitTestPage(
        page,
        LayoutOffset(target.dx, target.dy),
      )!;
      final PlacedBar bar = aimed.bar;
      // REWRITTEN, and this offset used to be measured from the CELL's corner. A stroke is anchored
      // to its BAR now, so the origin every stored point is measured from is the bar's corner and the
      // pen's own position in the music is that much further along.
      final Offset fromCorner = Offset(
        target.dx - bar.bounds.left,
        target.dy - bar.bounds.top,
      );
      await drawStroke(
        tester,
        page,
        pageStart: target,
        pageEnd: target + const Offset(14, 5),
        startMs: level * 1000,
      );
      final List<ResolvedInkStroke> strokes = inkPainter(tester).strokes;
      expect(
        strokes,
        hasLength(level),
        reason: 'a stroke must reach the document at zoom ${page.zoom}',
      );
      final ResolvedInkStroke drawn = strokes.last;
      final InkStroke stroke = drawn.stroke;
      final Offset stored = Offset(
        stroke.points.first.x,
        stroke.points.first.y,
      );
      final Offset surface = surfaceOf(tester, page, target);
      final LayoutOffset pagePoint = page.pagePointOf(
        LayoutOffset(surface.dx, surface.dy),
      );
      expect(
        stroke.anchor.sectionId,
        bar.sectionId,
        reason: 'the stroke must be anchored to the bar under the pen',
      );
      expect(stroke.anchor.bar, bar.barIndex);
      // REWRITTEN. The old assertion was
      //   expect(stroke.anchor.beat, cell.left,
      //       reason: 'the stroke began inside the cell, so it is anchored to it');
      // and it pinned the CELL a stroke was anchored to. An anchor names the bar now — the position
      // inside the bar is in the stroke's own points — so the same fact is checked as the one that
      // still exists: the stroke hangs on the bar under the pen and its first point is where the pen
      // touched, which the comparisons below do in pixels. That is a stronger statement than the
      // cell index was: it would catch a stroke moved by any distance at all, where the index only
      // caught a move to another column.
      expect(
        stroke.anchor,
        EventAnchor(sectionId: bar.sectionId, bar: bar.barIndex),
      );
      // THE STORED POINT IS THE NIB'S OWN PLACE IN ITS BAR, AT EVERY ZOOM. The old pair of
      // expectations here compared the stored point with the one a different zoom produced
      // (`storedAtIdentity`), which was a way of saying the same thing while the aim was fixed; with
      // the aim moving to stay visible, the claim is stated about the bar the pen actually landed in
      // and its two halves are the transform and the geometry.
      expect(
        pagePoint.x - drawn.origin.x,
        closeTo(stored.dx, 1e-6),
        reason: 'the stored point is the page point relative to its anchor',
      );
      expect(pagePoint.y - drawn.origin.y, closeTo(stored.dy, 1e-6));
      expect(stored.dx, closeTo(fromCorner.dx, 1e-6));
      expect(stored.dy, closeTo(fromCorner.dy, 1e-6));
      stdout.writeln(
        'view.test.pen ${viewOf(page)} '
        'aimed=${bar.sectionId}#${bar.barIndex} bar_x=${cell.left} '
        'anchor=${stroke.anchor} '
        'surface=(${surface.dx.toStringAsFixed(2)},'
        '${surface.dy.toStringAsFixed(2)}) '
        'page_point=(${pagePoint.x.toStringAsFixed(2)},'
        '${pagePoint.y.toStringAsFixed(2)}) '
        'anchor_origin=(${drawn.origin.x.toStringAsFixed(2)},'
        '${drawn.origin.y.toStringAsFixed(2)}) '
        'stored=(${stored.dx.toStringAsFixed(6)},'
        '${stored.dy.toStringAsFixed(6)}) points=${stroke.points.length}',
      );
    }
  });

  testWidgets('a chord tap names the same place in the bar at every zoom', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, viewChart());
    final PageLayout plain = chartPainter(tester).page;
    // A BAR'S OWN CENTRE, not the page's. THE OLD FIXTURE, QUOTED: `final Offset target =
    // pageCentreOf(plain);` with `hitTestPage(...)!`. The middle of the page is blank paper on this
    // chart now — its twelve content-width bars fit one system at the top — so the fixture aims at a
    // bar that exists and the property under test is unchanged: the same surface aim names the same
    // place in the same bar at every zoom.
    final PlacedBar aimedAt = plain.bars[plain.bars.length ~/ 2];
    final LayoutRect aimedRect = aimedAt.bounds;
    final Offset target = Offset(
      aimedRect.left + aimedRect.size.width / 2,
      aimedRect.top + aimedRect.size.height / 2,
    );
    final ChartHit aimed = hitTestPage(
      plain,
      LayoutOffset(target.dx, target.dy),
    )!;
    String? named;
    for (final double requested in <double>[1, 2, 4]) {
      while (chartPainter(tester).page.zoom < requested - 1e-6) {
        await tester.tap(
          find.byKey(const ValueKey<String>('scene-bar-zoom-in')),
        );
        await tester.pumpAndSettle();
      }
      final PageLayout page = chartPainter(tester).page;
      await tester.tapAt(pagePointToGlobal(tester, page, target));
      await tester.pumpAndSettle();
      final ChartHit? hit = chartPainter(tester).selection;
      expect(hit, isNotNull, reason: 'a tap on a bar must select it');
      expect(hit!.sectionId, aimed.bar.sectionId);
      expect(hit.barIndex, aimed.bar.barIndex);
      // THE OLD ASSERTIONS, QUOTED: expect(hit.local.x, aimed.local.x) and the recorded name
      // `'... beat=${hit.local.x}'`, with the reason "the same surface aim must name the same cell at
      // every zoom". There is no cell; `local.x` is the distance from the bar's left edge, and it is
      // the same number at every zoom for the same reason it was before — it is a PAGE coordinate,
      // so the zoom it was drawn at cannot enter it.
      expect(hit.local.x, aimed.local.x);
      named ??= '${hit.sectionId}#${hit.barIndex} x=${hit.local.x}';
      expect(
        '${hit.sectionId}#${hit.barIndex} x=${hit.local.x}',
        named,
        reason: 'the same surface aim must name the same place at every zoom',
      );
      stdout.writeln(
        'view.test.hit ${viewOf(page)} '
        'aimed=${aimed.bar.sectionId}#${aimed.bar.barIndex} x=${aimed.local.x} '
        'named=${hit.sectionId}#${hit.barIndex} x=${hit.local.x}',
      );
    }
  });

  // --- THE PALM ----------------------------------------------------------------------------------
  //
  // WHY THESE CASES ARE HERE AND WHAT THEY ARE WORTH. The owner reported that resting his palm on
  // the glass while writing was read as a two-finger movement, so the chart panned under his hand.
  // A genuine two-finger contact CANNOT be injected by `adb shell input`, which carries one pointer
  // id and cannot hold two contacts down at once, so the GESTURE half of the rule is measured here,
  // with two synthetic pointers, and the PEN half is measured on the tablet. Which instrument
  // produced which claim is the point of saying so.

  testWidgets('a palm-like contact does not start the view gesture', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, viewChart());
    // Ink OFF, so this case is about the palm alone and cannot pass because of the pen's gate: the
    // width signal is the only reason the gesture may be refused here.
    final Offset centre = tester.getRect(pageSurfaceFinder()).center;
    final InkCaptureLayer layer = inkLayerOf(tester);
    const double palmWidth = 71;
    final int before = layer.viewGestureRefusalCount;

    // Two contacts, 120 apart, exactly as an honest two-finger pinch: one an ordinary finger, the
    // other the palm the spike measured. The palm is the second, so a gesture that counted it would
    // be holding two touches.
    sendTouchDown(
      tester,
      pointer: 41,
      at: centre - const Offset(60, 0),
      radiusMajor: 0,
      timeMs: 0,
    );
    await tester.pump();
    sendTouchDown(
      tester,
      pointer: 42,
      at: centre + const Offset(60, 0),
      radiusMajor: palmWidth / 2,
      timeMs: 16,
    );
    await tester.pump();
    for (int step = 0; step < 4; step++) {
      sendTouchMove(
        tester,
        pointer: 41,
        at: centre - Offset(60 + 20.0 * step, 0),
        radiusMajor: 0,
        timeMs: 32 + 16 * step,
      );
      sendTouchMove(
        tester,
        pointer: 42,
        at: centre + Offset(60 + 20.0 * step, 0),
        radiusMajor: palmWidth / 2,
        timeMs: 32 + 16 * step,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    sendTouchUp(tester, pointer: 41, at: centre, timeMs: 200);
    sendTouchUp(tester, pointer: 42, at: centre, timeMs: 216);
    await tester.pumpAndSettle();

    final PageLayout page = chartPainter(tester).page;
    expect(
      layer.viewGestureRefusalCount,
      greaterThan(before),
      reason: 'the palm-like contact must be refused a place in the gesture',
    );
    expect(page.zoom, 1, reason: 'a palm is not a finger of the view gesture');
    expect(
      page.pan,
      LayoutOffset.zero,
      reason: 'the chart must not move under a palm-like contact',
    );
    stdout.writeln(
      'view.test.palm width_sent=$palmWidth refused=${layer.viewGestureRefusalCount - before} '
      '${viewOf(page)}',
    );
  });

  testWidgets('no touch joins the view gesture while a stroke is open', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, viewChart());
    await setInkMode(tester, true);
    final Offset centre = tester.getRect(pageSurfaceFinder()).center;
    final InkCaptureLayer layer = inkLayerOf(tester);

    // The pen goes down and moves, and is NOT lifted: that is what "a pen contact is active" means
    // here, and it is the definition the gate uses because it is observable without trusting the
    // platform to name the pointer's kind or to report its width.
    final TestGesture pen = await tester.startGesture(
      centre - const Offset(40, 30),
      kind: PointerDeviceKind.stylus,
      pointer: 51,
    );
    await tester.pump(const Duration(milliseconds: 8));
    await pen.moveTo(centre - const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 8));
    expect(
      layer.isDrawingInk,
      isTrue,
      reason: 'the pen is down and the case is only tested while it is',
    );
    final int before = layer.viewGestureRefusalCount;

    // Two ordinary fingers — no palm-like width at all — try to pinch while the pen is writing.
    sendTouchDown(
      tester,
      pointer: 61,
      at: centre - const Offset(60, 0),
      radiusMajor: 0,
      timeMs: 100,
    );
    await tester.pump();
    sendTouchDown(
      tester,
      pointer: 62,
      at: centre + const Offset(60, 0),
      radiusMajor: 0,
      timeMs: 116,
    );
    await tester.pump();
    for (int step = 0; step < 4; step++) {
      sendTouchMove(
        tester,
        pointer: 61,
        at: centre - Offset(60 + 20.0 * step, 0),
        radiusMajor: 0,
        timeMs: 132 + 16 * step,
      );
      sendTouchMove(
        tester,
        pointer: 62,
        at: centre + Offset(60 + 20.0 * step, 0),
        radiusMajor: 0,
        timeMs: 132 + 16 * step,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    sendTouchUp(tester, pointer: 61, at: centre, timeMs: 220);
    sendTouchUp(tester, pointer: 62, at: centre, timeMs: 236);
    await tester.pumpAndSettle();

    final PageLayout page = chartPainter(tester).page;
    expect(
      layer.viewGestureRefusalCount,
      greaterThan(before),
      reason: 'a touch while a pen is in play must be refused the gesture',
    );
    expect(
      page.zoom,
      1,
      reason: 'the page must not zoom while a pen writes on it',
    );
    expect(
      page.pan,
      LayoutOffset.zero,
      reason:
          'THE DEFECT: the chart moved under a writing hand. It must not move at all while a pen '
          'contact is active, whatever the platform calls that contact',
    );
    expect(layer.isDrawingInk, isTrue, reason: 'the pen is still down');

    // The pen is unaffected by the refusal: the stroke it was drawing when the touches arrived is
    // still committed when it lifts. What is compared is the DOCUMENT's own list before the lift and
    // after it, not the painter's, because the painter also carries the stroke still being drawn and
    // a count of it would count the pen's own open work as if it had already been committed.
    final int committedBeforeLift = layer.documentStrokes.length;
    await pen.moveTo(centre - const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 8));
    await pen.up();
    await tester.pumpAndSettle();
    expect(
      layer.documentStrokes.length,
      committedBeforeLift + 1,
      reason:
          'the pen keeps writing, which is the half that must never regress',
    );
    stdout.writeln(
      'view.test.pen_in_play refused=${layer.viewGestureRefusalCount - before} '
      '${viewOf(page)} strokes=${layer.documentStrokes.length}',
    );
  });

  testWidgets('two ordinary touches still pan and pinch while ink is ON', (
    WidgetTester tester,
  ) async {
    // THE OVER-BLOCKING CASE, AND IT IS A REAL RISK. With the ink mode on a touch DRAWS (A61's
    // decision for this panel), so the first of the two fingers opens a stroke before the second
    // arrives, and a gate that refused whenever any stroke was open would forbid two-finger panning
    // in the one mode where a musician writing is most likely to want it. This test was written
    // because the first version of the gate did exactly that, and it failed here.
    //
    // What must survive: the gesture takes over from its OWN first finger, cancels its half-drawn
    // stroke, and moves the page.
    await pumpViewer(tester, viewChart());
    await setInkMode(tester, true);
    final Offset centre = tester.getRect(pageSurfaceFinder()).center;
    final InkCaptureLayer layer = inkLayerOf(tester);
    final int before = layer.viewGestureRefusalCount;

    sendTouchDown(
      tester,
      pointer: 71,
      at: centre - const Offset(60, 0),
      radiusMajor: 0,
      timeMs: 0,
    );
    await tester.pump();
    expect(
      layer.isDrawingInk,
      isTrue,
      reason: 'the first finger drew, which is the state this case is about',
    );
    sendTouchDown(
      tester,
      pointer: 72,
      at: centre + const Offset(60, 0),
      radiusMajor: 0,
      timeMs: 16,
    );
    await tester.pump();
    for (int step = 1; step <= 4; step++) {
      sendTouchMove(
        tester,
        pointer: 71,
        at: centre - Offset(60 + 20.0 * step, 0),
        radiusMajor: 0,
        timeMs: 16 + 16 * step,
      );
      sendTouchMove(
        tester,
        pointer: 72,
        at: centre + Offset(60 + 20.0 * step, 0),
        radiusMajor: 0,
        timeMs: 16 + 16 * step,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    sendTouchUp(tester, pointer: 71, at: centre, timeMs: 200);
    sendTouchUp(tester, pointer: 72, at: centre, timeMs: 216);
    await tester.pumpAndSettle();

    final PageLayout page = chartPainter(tester).page;
    expect(
      layer.viewGestureRefusalCount,
      before,
      reason: 'the gesture must take over from its own first finger',
    );
    expect(
      page.zoom,
      closeTo(140 / 60, 0.05),
      reason: 'two fingers must still pinch the chart with the pen mode on',
    );
    expect(
      inkPainter(tester).strokes,
      isEmpty,
      reason: 'the first finger was a finger of the gesture, not a mark',
    );
    stdout.writeln(
      'view.test.pen_free_ink_on pinch=${page.zoom.toStringAsFixed(4)} '
      'refused=${layer.viewGestureRefusalCount - before} strokes=0 ${viewOf(page)}',
    );
  });

  // PURPOSE: Measure the owner's «кнопка фиксирования масштаба» — that while it is on, NOTHING moves
  //          the drawn scale: not a pinch, not the three МАСШТАБ controls, not a change of page mode.
  //          It exists because "the scale is fixed" is a claim, and this project's rule is that a
  //          claim about a layout carries the number it rests on.
  // INPUTS: The viewer pumped at the size the first case uses.
  // OUTPUTS: `view.test.lock` lines on stdout with the drawn scale before and after each attempt, and
  //          pass/fail on the four claims: the pinch is refused, the buttons are disabled and their
  //          callbacks change nothing, a page-mode change cannot change the size, and releasing the
  //          lock does not move the chart.
  // KEYWORDS: test, view-lock, pinch, disabled, page-mode, drawn-scale, no-jump
  testWidgets(
    'the fixed scale resists a pinch, the buttons and a mode change',
    (WidgetTester tester) async {
      await pumpViewer(tester, viewChart());
      // Two steps in, through the interface, so the locked number is not the identity: a lock that is
      // only tested at ×1.0 cannot tell "fixed" from "the pinch never arrived".
      for (int step = 0; step < 2; step++) {
        await tester.tap(
          find.byKey(const ValueKey<String>('scene-bar-zoom-in')),
        );
        await tester.pumpAndSettle();
      }
      final PageLayout free = chartPainter(tester).page;
      stdout.writeln('view.test.lock before_locking ${viewOf(free)}');

      await tester.tap(find.byKey(const ValueKey<String>('viewer-view-lock')));
      await tester.pumpAndSettle();
      final PageLayout locked = chartPainter(tester).page;
      expect(
        locked.drawnScale,
        free.drawnScale,
        reason: 'locking is not a change of magnification in either direction',
      );
      expect(locked.pan, free.pan);

      // --- A PINCH IS REFUSED ------------------------------------------------------------------
      final Offset centre = tester.getRect(pageSurfaceFinder()).center;
      final TestGesture first = await tester.startGesture(
        centre - const Offset(60, 0),
        pointer: 31,
      );
      final TestGesture second = await tester.startGesture(
        centre + const Offset(60, 0),
        pointer: 32,
      );
      await tester.pump();
      for (int step = 0; step < 4; step++) {
        await first.moveBy(const Offset(-20, 0));
        await second.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final PageLayout afterPinch = chartPainter(tester).page;
      expect(
        afterPinch.drawnScale,
        closeTo(locked.drawnScale, 1e-9),
        reason: 'a fixed scale does not pinch',
      );
      expect(
        afterPinch.pan,
        locked.pan,
        reason: 'a fixed view does not pan either',
      );
      stdout.writeln(
        'view.test.lock pinch span_from=60 span_to=140 ${viewOf(afterPinch)} '
        'drawn_scale_from=${locked.drawnScale.toStringAsFixed(4)} '
        'drawn_scale_to=${afterPinch.drawnScale.toStringAsFixed(4)}',
      );

      // --- THE THREE BUTTONS ARE DISABLED AND CHANGE NOTHING ------------------------------------
      for (final String key in <String>[
        'scene-bar-zoom-in',
        'scene-bar-zoom-out',
        'scene-bar-zoom-reset',
      ]) {
        final Finder button = find.byKey(ValueKey<String>(key));
        expect(
          button,
          findsOneWidget,
          reason: '$key stays on the bar when locked',
        );
        await tester.tap(button, warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      final PageLayout afterButtons = chartPainter(tester).page;
      expect(
        afterButtons.drawnScale,
        closeTo(locked.drawnScale, 1e-9),
        reason: 'the scale controls cannot move a fixed scale',
      );
      expect(afterButtons.pan, locked.pan);
      stdout.writeln(
        'view.test.lock buttons in_out_reset=3 ${viewOf(afterButtons)} '
        'drawn_scale=${afterButtons.drawnScale.toStringAsFixed(4)} moved=false',
      );

      // --- A PAGE-MODE CHANGE RE-ENGRAVES BUT CANNOT RE-SCALE -----------------------------------
      await tester.tap(
        find.byKey(const ValueKey<String>('scene-bar-mode-pages')),
      );
      await tester.pumpAndSettle();
      final PageLayout afterMode = chartPainter(tester).page;
      expect(
        afterMode.drawnScale,
        closeTo(locked.drawnScale, 1e-6),
        reason:
            'a locked scale is held against a re-engraving too, which is the whole point of holding '
            'the drawn scale rather than the zoom',
      );
      stdout.writeln(
        'view.test.lock mode_change to=pages ${viewOf(afterMode)} '
        'scale=${afterMode.scale.toStringAsFixed(4)} '
        'drawn_scale=${afterMode.drawnScale.toStringAsFixed(4)} held=true',
      );

      // --- AND A PANE CHANGE, WHICH IS THE ONE IT CANNOT REFUSE ---------------------------------
      //
      // Hiding the chrome gives the chart a bigger pane, so the page mode re-engraves at a NEW scale.
      // No control can refuse that — the window is not the application's to hold — which is why the
      // lock holds the DRAWN scale and re-derives the zoom from whatever the new engraving produced.
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
      );
      await tester.pumpAndSettle();
      final PageLayout afterPane = chartPainter(tester).page;
      expect(
        afterPane.drawnScale,
        closeTo(locked.drawnScale, 1e-6),
        reason: 'a bigger pane must not re-scale a fixed chart',
      );
      stdout.writeln(
        'view.test.lock pane_change chrome=hidden ${viewOf(afterPane)} '
        'scale=${afterPane.scale.toStringAsFixed(4)} '
        'drawn_scale=${afterPane.drawnScale.toStringAsFixed(4)} held=true',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
      );
      await tester.pumpAndSettle();

      // --- RELEASING THE LOCK IS NOT A JUMP -----------------------------------------------------
      await tester.tap(find.byKey(const ValueKey<String>('viewer-view-lock')));
      await tester.pumpAndSettle();
      final PageLayout released = chartPainter(tester).page;
      expect(
        released.drawnScale,
        closeTo(afterMode.drawnScale, 1e-6),
        reason: 'a lock whose release moves the chart is a control a musician learns not to touch',
      );
      stdout.writeln(
        'view.test.lock released ${viewOf(released)} '
        'drawn_scale=${released.drawnScale.toStringAsFixed(4)}',
      );
    },
  );

  // PURPOSE: Measure the HALF OF THE LOCK THE DEVICE COULD NOT PROVE. A66 §2 says it plainly about
  //          its own case: in a 900x1000 window FIT already engraves at 1:1, so the case proves "the
  //          lock survives a re-engraving" but NOT "the lock compensates a DIFFERENT scale" — the
  //          second half was left to the tablet, and A68 §8 records that the tablet run never took
  //          that measurement either ("компенсация масштаба при смене панели на устройстве не
  //          предъявлена"). So the pair — a lock held across a pane change that ALTERS the page's own
  //          `scale` — had not been shown by any instrument. This case shows it headlessly.
  // INPUTS: A chart long enough to force FIT below 1:1, pumped in a window small enough that hiding
  //         the chrome and showing it again change the pane measurably.
  // OUTPUTS: `view.test.lock-pane` lines with the page's own scale, the derived zoom and the drawn
  //          scale on both sides of the pane change, and pass/fail on: the fixture forces a scale
  //          below 1, the pane change really moves that scale, the drawn scale is unchanged, the zoom
  //          is the ratio the engraving implies, and releasing changes nothing.
  // KEYWORDS: test, view-lock, pane-change, re-engraving, derived-zoom, compensation, a66
  testWidgets(
    'a lock holds the drawn scale across a pane change that re-engraves the page',
    (WidgetTester tester) async {
      // The chrome is hidden FIRST so that showing it again SHRINKS the pane — and the window is wide
      // enough that the pane stays above `sceneBarTabletWidth` either way, so the page mode stays FIT
      // and what the pane change moves is the page's own `scale` rather than the mode. (A pane that
      // drops below that width re-engraves in PAGES at 1:1, which grows the scale and lands on the
      // clamp instead: that is the other, already-measured direction.)
      //
      // THE DIRECTION MATTERS. `PageLayout.withView` refuses a zoom below 1, so a pane that GROWS can
      // only make the music bigger and the lock reports itself clamped (A66 §1 says so and names the
      // log line). The shrinking direction is where the lock has room to compensate, and that is the
      // measurement A66 §2 and A68 §8 both record as missing.
      await pumpViewer(tester, longViewChart(72), size: const Size(1000, 1000));
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
      );
      await tester.pumpAndSettle();
      final PageLayout wide = chartPainter(tester).page;
      stdout.writeln(
        'view.test.lock-pane chrome=hidden scale=${wide.scale.toStringAsFixed(6)} '
        '${viewOf(wide)}',
      );

      await tester.tap(find.byKey(const ValueKey<String>('viewer-view-lock')));
      await tester.pumpAndSettle();
      final PageLayout locked = chartPainter(tester).page;
      expect(
        locked.drawnScale,
        wide.drawnScale,
        reason: 'locking is not a change of magnification in either direction',
      );

      // --- THE PANE CHANGE: SHOWING THE CHROME SHRINKS THE PANE AND RE-ENGRAVES SMALLER ---------
      await tester.tap(
        find.byKey(const ValueKey<String>('viewer-chrome-toggle')),
      );
      await tester.pumpAndSettle();
      final PageLayout narrow = chartPainter(tester).page;
      stdout.writeln(
        'view.test.lock-pane chrome=shown scale=${narrow.scale.toStringAsFixed(6)} '
        '${viewOf(narrow)} '
        'scale_from=${wide.scale.toStringAsFixed(6)} '
        'locked_drawn_scale=${locked.drawnScale.toStringAsFixed(6)} '
        'unity_divided_by_scale=${(1 / narrow.scale).toStringAsFixed(6)}',
      );
      expect(
        narrow.scale,
        lessThan(wide.scale),
        reason:
            'the pane change must really alter the page’s own scale — that is the pair this case '
            'exists for, and without it the case is the one A66 already had',
      );
      expect(
        narrow.drawnScale,
        closeTo(locked.drawnScale, 1e-6),
        reason:
            'THE LOCK HOLDS THE DRAWN SCALE: a re-engraving at a smaller scale must be compensated '
            'by a larger zoom, or the music changes size under the musician’s hand the moment a bar '
            'of interface appears',
      );
      expect(
        narrow.zoom,
        closeTo(locked.drawnScale / narrow.scale, 1e-6),
        reason:
            'the zoom is DERIVED from the engraving while the lock is on, so there is no second '
            'place a size could come from',
      );
      expect(
        narrow.zoom,
        greaterThan(1),
        reason:
            'compensating a smaller engraving is the one thing that needs a zoom above the identity, '
            'and a compensation that never left 1 did not compensate anything',
      );

      // --- AND RELEASING HANDS BACK THE ZOOM THAT WAS DRAWN -------------------------------------
      //
      // WHAT IS ASSERTED HERE IS THE MECHANISM A66 PROMISES, NOT THE DRAWN SCALE, and the difference
      // is measured rather than assumed. The sentence that says the scale is fixed occupies a line of
      // the status bar, and when the lock is released that line goes: the pane is 739x622 while the
      // lock is on and 739x638 immediately after, so the page is re-engraved from a TALLER pane — a
      // pane change like any other, which after the release is the chart's to follow. The drawn scale
      // therefore moves by the ratio of those two panes (printed below, 2.5 per cent in this run),
      // and asserting it unchanged would be asserting that a pane change does nothing. What MUST hold
      // is that the zoom handed back is the one that was on the glass: a release that restored a
      // stored zoom would jump the chart by a number the musician never saw.
      await tester.tap(find.byKey(const ValueKey<String>('viewer-view-lock')));
      await tester.pumpAndSettle();
      final PageLayout released = chartPainter(tester).page;
      stdout.writeln(
        'view.test.lock-pane chrome=shown released ${viewOf(released)} '
        'drawn_scale=${released.drawnScale.toStringAsFixed(6)} '
        'zoom_while_locked=${narrow.zoom.toStringAsFixed(6)}',
      );
      expect(
        released.zoom,
        closeTo(narrow.zoom, 1e-6),
        reason:
            'releasing the lock stores the zoom that was on the glass, so the chart does not jump '
            'by a stored number nobody saw',
      );
    },
  );

  // --- THE GATE THAT NEVER OPENED, AND ITS SHIPPED FORM AS A TEST -------------------------------
  //
  // WHY THIS CASE EXISTS, IN THE OWNER'S TERMS. His tablet report was "перемещение с помощью одного
  // пальца вообще пропало — никак не переместится по листу", and the cause was not the pan (that
  // needs two fingers by owner decision D34 and is measured above) but the ADMISSION GATE in front
  // of it: `InkCaptureLayer.refuseViewGestureTouch` refused every touch with `stylus-in-play` for one
  // second after any pen contact OR hover while the ink mode was on. He holds the pen for the whole
  // session, so the window was effectively always open and the gesture was refused for the whole
  // session. **A safety gate that depends on a condition the user never stops satisfying is an
  // outage, and this case is the form of that lesson that runs in the gate.**
  //
  // WHAT IT MEASURES, AND WHY IT WOULD HAVE FAILED BEFORE THE FIX. The pen writes a stroke and LIFTS
  // — nothing is drawing, so the strongest refusal (`ink-contact-open`) has nothing to fire on — and
  // the two fingers arrive in the very next frame, deep inside the one-second proximity window. Under
  // the old rule both touches were refused; under the rule as it stands the gesture is admitted and
  // the pinch magnifies the page. The assertion is deliberately on the OUTCOME (the zoom) and not on
  // the token, because the token is what the fix removed: a test that asserted a string would have
  // kept the outage and passed.
  //
  // AND IT CARRIES ITS OWN COUNTER-ASSERTION, ONE CASE ABOVE. A pen contact that is still OPEN must
  // still refuse — that is A64's defect, and `no touch joins the view gesture while a stroke is open`
  // pins it — so this file fails if the whole gate were removed rather than the staleness window
  // alone.
  testWidgets('a pen that has lifted does not refuse the two-finger pan', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, viewChart());
    await setInkMode(tester, true);
    final Offset centre = tester.getRect(pageSurfaceFinder()).center;
    final InkCaptureLayer layer = inkLayerOf(tester);

    // The pen writes and lifts: the state a musician is in for a whole session, and the state in
    // which the old window refused everything for a second after every stroke.
    final TestGesture pen = await tester.startGesture(
      centre - const Offset(40, 30),
      kind: PointerDeviceKind.stylus,
      pointer: 71,
    );
    await tester.pump(const Duration(milliseconds: 8));
    await pen.moveTo(centre - const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 8));
    await pen.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      layer.isDrawingInk,
      isFalse,
      reason: 'the pen has lifted, which is the whole point of the case',
    );
    final int before = layer.viewGestureRefusalCount;

    // Two ordinary fingers, immediately — inside the one-second window the old rule measured.
    sendTouchDown(
      tester,
      pointer: 81,
      at: centre - const Offset(60, 0),
      radiusMajor: 0,
      timeMs: 40,
    );
    await tester.pump();
    sendTouchDown(
      tester,
      pointer: 82,
      at: centre + const Offset(60, 0),
      radiusMajor: 0,
      timeMs: 56,
    );
    await tester.pump();
    // A pinch out, so the evidence is a scale that changed rather than a pan the clamp could eat.
    for (int step = 0; step < 4; step++) {
      sendTouchMove(
        tester,
        pointer: 81,
        at: centre - Offset(60 + 20.0 * step, 0),
        radiusMajor: 0,
        timeMs: 72 + 16 * step,
      );
      sendTouchMove(
        tester,
        pointer: 82,
        at: centre + Offset(60 + 20.0 * step, 0),
        radiusMajor: 0,
        timeMs: 72 + 16 * step,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    sendTouchUp(tester, pointer: 81, at: centre, timeMs: 160);
    sendTouchUp(tester, pointer: 82, at: centre, timeMs: 176);
    await tester.pumpAndSettle();

    final PageLayout page = chartPainter(tester).page;
    expect(
      layer.viewGestureRefusalCount,
      before,
      reason:
          'a pen that has LIFTED is not a pen on the glass: no touch may be refused on the '
          'proximity window, because on this musician’s tablet that window never closes',
    );
    expect(
      page.zoom,
      greaterThan(1.2),
      reason:
          'THE DEFECT: the two-finger gesture was refused for the whole session and the document '
          'could not be moved. A pinch after a lifted pen must magnify the page',
    );
    stdout.writeln(
      'view.test.pen_lifted refused=${layer.viewGestureRefusalCount - before} '
      '${viewOf(page)}',
    );
  });

  // --- THE ONE-CONTACT PAN, WHICH IS THE GESTURE THAT CAN BE PROVED ON THE GLASS ---------------
  //
  // WHY IT IS MEASURED HERE AND ON THE TABLET BOTH. Owner decision D34 gives the view a TWO-finger
  // pan and that decision stands, but a gesture no instrument can inject — `adb shell input` carries
  // one pointer, and two simultaneous injections are cancelled by the dispatcher — is a gesture
  // nobody has ever seen work on the glass. So the SELECT tool, in which nothing lays ink and a drag
  // is therefore free by construction, owns a one-contact pan: the one `adb` can inject and the one
  // the owner can perform with the pen in his hand.
  //
  // WHAT THIS CASE PINS, INCLUDING THE HALF THAT MUST NOT REGRESS. In the Select tool a drag moves
  // the sheet. In the PEN tool the same drag still draws, because the pan's own admission gate says
  // `tool-writes` and the stroke keeps the contact — the pen must keep writing, and a pan that stole
  // one stroke of every session would be a worse defect than the one it fixed.
  testWidgets(
    'the select tool moves the sheet with one contact; the pen still writes',
    (WidgetTester tester) async {
      await pumpViewer(tester, viewChart());
      // Two steps in, through the interface: at zoom 1 the page exactly fills the pane and the clamp
      // makes every pan zero, so a pan could not be measured there even if it were admitted.
      await tester.tap(find.byKey(const ValueKey<String>('scene-bar-zoom-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('scene-bar-zoom-in')));
      await tester.pumpAndSettle();
      final PageLayout zoomed = chartPainter(tester).page;
      expect(
        zoomed.zoom,
        greaterThan(1),
        reason: 'the view has somewhere to move',
      );
      final Offset centre = tester.getRect(pageSurfaceFinder()).center;

      // --- THE SELECT TOOL (ink off, which is the state the screen opens in) --------------------
      final TestGesture drag = await tester.startGesture(centre, pointer: 91);
      await tester.pump();
      // Two samples after the slop, so the recogniser accepts on the first and follows the rest.
      await drag.moveBy(const Offset(-30, -20));
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveBy(const Offset(-30, -20));
      await tester.pump(const Duration(milliseconds: 16));
      await drag.up();
      await tester.pumpAndSettle();
      final PageLayout panned = chartPainter(tester).page;
      expect(
        panned.pan.x,
        lessThan(zoomed.pan.x - 1),
        reason: 'dragging left must move the sheet left in the Select tool',
      );
      expect(
        panned.pan.y,
        lessThan(zoomed.pan.y - 1),
        reason: 'dragging up must move the sheet up in the Select tool',
      );
      expect(
        panned.zoom,
        closeTo(zoomed.zoom, 1e-9),
        reason:
            'a one-contact pan is a translation and must not change the scale',
      );
      stdout.writeln(
        'view.test.select_pan pointers=1 travel=(-60,-40) '
        'from=${viewOf(zoomed)} to=${viewOf(panned)}',
      );

      // --- THE PEN TOOL: THE SAME DRAG IS A STROKE ----------------------------------------------
      await setInkMode(tester, true);
      final InkCaptureLayer layer = inkLayerOf(tester);
      final int strokesBefore = layer.documentStrokes.length;
      final PageLayout beforeInk = chartPainter(tester).page;
      final TestGesture write = await tester.startGesture(centre, pointer: 92);
      await tester.pump(const Duration(milliseconds: 8));
      await write.moveBy(const Offset(-30, -20));
      await tester.pump(const Duration(milliseconds: 8));
      await write.moveBy(const Offset(-30, -20));
      await tester.pump(const Duration(milliseconds: 8));
      await write.up();
      await tester.pumpAndSettle();
      expect(
        layer.documentStrokes.length,
        strokesBefore + 1,
        reason:
            'THE PEN MUST KEEP WRITING: in the pen tool a one-contact drag is a stroke, and the pan '
            'recogniser declines by name (`tool-writes`) rather than taking it',
      );
      expect(
        chartPainter(tester).page.pan,
        beforeInk.pan,
        reason: 'a stroke must not move the sheet',
      );
      stdout.writeln(
        'view.test.pen_still_writes strokes=${layer.documentStrokes.length} '
        '${viewOf(chartPainter(tester).page)}',
      );
    },
  );
}
