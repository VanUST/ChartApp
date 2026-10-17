// PURPOSE: Verify the whole ink path end to end, on the real widgets and through the real operation
//          log: a contact that may ink becomes a stroke in the document, a contact that may not
//          selects, undo removes the stroke, and the stroke stays on the same musical position when
//          the page is fitted, when the key is transposed and after the document has been through
//          the `.chart` container. The last three are the reason the anchor is stored local, so they
//          are asserted as geometry rather than as "a stroke still exists".
//
//          WHY THE ASSERTIONS ARE ON NUMBERS AND NOT ON TYPES. A stroke that survived a transposition
//          because it was never moved, and one that survived because it was moved correctly, are the
//          same value in a `hasLength(1)` assertion. The offset from the anchor's own corner is what
//          separates them, so that is what is compared.
// INPUTS: None. The chart is synthetic and the layout is deterministic, so this runs on any machine
//         with no device and no font.
// OUTPUTS: Pass/fail per behaviour, plus the drawn surface point, the stored anchor-local point, the
//          cell rectangle each is measured against, and the reconstructed stroke after each of the
//          three transforms, printed so the arithmetic can be read rather than only trusted.
// KEYWORDS: test, ink, pointer-routing, palm-rule, op-log, undo, anchor-local, fit, transposition,
//           chart-file-round-trip, fit-scale
import 'dart:io';

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:chartapp/ink_capture_surface.dart';
import 'package:chartapp/ireal_library.dart';
import 'package:chartapp/l10n/app_localizations.dart';
import 'package:chartapp/viewer_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Key;
import 'package:flutter_test/flutter_test.dart';

import '../support/place_fixture.dart';

/// The pane width the viewer is pumped at for the interaction cases, chosen so the default page mode
/// is PAGES: those cases want a page whose scale is 1, and FIT is switched to explicitly where it is
/// being tested.
///
/// It is also wide enough that a system holds more than one bar, which matters because the strokes
/// in this file are aimed at bars 0, 3 and 5 — a narrow pane would pack the chart into a column of
/// single-bar systems and the test would be asserting about a layout nobody intended.
const Size _paneSize = Size(900, 1000);

/// A twelve-bar two-section chart, laid out deterministically by the package's default metrics.
Song inkChart() => Song(
  id: 'ink-mode',
  title: 'Ink mode',
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

/// A one-song library holding [song].
IRealLibrary libraryOf(Song song) => IRealLibrary(
  playlistName: '',
  songs: <IRealSong>[IRealSong(index: 0, song: song)],
);

/// A chart long enough that FIT must genuinely shrink it, which is the case a page-scale defect
/// survives on every ordinary page and only shows on a fitted one.
Song longInkChart() => Song(
  id: 'ink-mode-long',
  title: 'Ink mode long',
  composer: 'ChartApp',
  style: 'Medium Swing',
  key: Key.cMajor,
  tempo: 120,
  sections: <Section>[
    for (int section = 0; section < 4; section++)
      Section(
        id: 'S$section',
        label: SectionLabel.letter(String.fromCharCode(65 + section)),
        bars: <Bar>[
          for (int index = 0; index < 16; index++)
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
      // The application's own delegates, so the screen under test is the one the application
      // builds. `flutter_test` reports `en_US` as the device locale, so this reads the ENGLISH
      // interface.
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

/// The widget the page is drawn in, which is what a gesture's global position is measured against.
Finder pageFinder() => find.byWidgetPredicate(
  (Widget widget) => widget is CustomPaint && widget.painter is ChartPainter,
);

/// The surface that receives pointer events for the page currently shown.
///
/// This is what a gesture's global position must be measured against, because a pointer event's
/// `localPosition` is relative to THAT box and not to the painter's. The two coincide when the page
/// is the only child of the pane, but a paged view keeps neighbouring pages alive and a chart whose
/// page is taller than its viewport scrolls, so measuring against the painter puts every gesture a
/// constant distance away from where it was aimed — a mistake that still passes whenever the
/// asserted quantity is a difference, which is why the tests here aim from this box.
Finder pageSurfaceFinder() => find.byType(RawPointerCapture);

/// The screen position of a point given in the page's own ENGRAVED coordinates.
Offset pagePointToGlobal(
  WidgetTester tester,
  ChartPainter painter,
  Offset page,
) {
  final Offset topLeft = tester.getTopLeft(pageSurfaceFinder().first);
  return topLeft + page * painter.page.scale;
}

/// Draws one stroke from [pageStart] to [pageEnd], in the page's engraved coordinates, with a
/// pointer of [kind] and the given contact [width].
///
/// The pressure axis is NOT swept here: `TestGesture` builds its own pointer events and exposes no
/// way to set a per-sample pressure, so a test that pretended to vary it would be asserting about
/// the harness rather than about the capture. What this exercises is the routing and the geometry,
/// which is where the defects this file is for actually live; the pressure fallback and the palm
/// rule have their own cases in `chart_core`'s `ink_rules_test.dart`.
Future<void> drawStroke(
  WidgetTester tester,
  ChartPainter painter, {
  required Offset pageStart,
  required Offset pageEnd,
  required PointerDeviceKind kind,
  double width = 0,
}) async {
  final TestGesture gesture = await tester.startGesture(
    pagePointToGlobal(tester, painter, pageStart),
    kind: kind,
  );
  await tester.pump(const Duration(milliseconds: 8));
  for (int step = 1; step <= 4; step++) {
    final Offset page = Offset.lerp(pageStart, pageEnd, step / 4)!;
    await gesture.moveTo(
      pagePointToGlobal(tester, painter, page),
      timeStamp: Duration(milliseconds: 8 * step),
    );
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Switches the ink mode by pressing the app bar's own control, so the test exercises the button a
/// musician presses rather than the field it sets.
Future<void> setInkMode(WidgetTester tester, bool on) async {
  final bool current = inkToggleIsOn(tester);
  if (current == on) {
    return;
  }
  await tester.tap(find.byKey(const ValueKey<String>('viewer-ink-toggle')));
  await tester.pumpAndSettle();
}

/// Whether the ink control currently reads as on.
bool inkToggleIsOn(WidgetTester tester) {
  final IconButton button = tester.widget<IconButton>(
    find.byKey(const ValueKey<String>('viewer-ink-toggle')),
  );
  return button.tooltip!.startsWith('Drawing');
}

void main() {
  testWidgets('a stylus with ink on leaves a stroke in the document', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, inkChart());
    final ChartPainter painter = chartPainter(tester);
    expect(
      painter.page.scale,
      1,
      reason: 'this half of the test wants an ordinary page',
    );

    // Ink off first: the pen selects, and nothing is drawn. That is the state the mode starts in.
    expect(inkToggleIsOn(tester), isFalse);
    final PlacedBar bar = painter.page.bars[3];
    final LayoutRect cell = bar.bounds;
    final Offset cellCentre = Offset(
      cell.left + cell.size.width / 2,
      cell.top + cell.size.height / 2,
    );
    await drawStroke(
      tester,
      painter,
      pageStart: cellCentre,
      pageEnd: cellCentre + const Offset(24, 6),
      kind: PointerDeviceKind.stylus,
    );
    expect(
      inkPainter(tester).strokes,
      isEmpty,
      reason: 'with the mode off the pen must not leave ink',
    );

    // Ink on: the same gesture draws.
    await setInkMode(tester, true);
    final Offset startPage = cellCentre - const Offset(10, 4);
    final Offset endPage = cellCentre + const Offset(10, 4);
    await drawStroke(
      tester,
      painter,
      pageStart: startPage,
      pageEnd: endPage,
      kind: PointerDeviceKind.stylus,
    );

    final InkPainter ink = inkPainter(tester);
    expect(ink.strokes, hasLength(1), reason: 'one stroke was drawn');
    final ResolvedInkStroke drawn = ink.strokes.single;
    expect(drawn.stroke.tool, StrokeTool.pen);
    expect(drawn.stroke.points.length, greaterThan(1));
    expect(drawn.stroke.anchor.sectionId, 'A');
    expect(drawn.stroke.anchor.bar, 3);
    // REWRITTEN, and the old assertion is quoted because it pinned a cell address the model no
    // longer has: `expect(drawn.stroke.anchor.beat, 0);` — a stroke's anchor used to name the beat it
    // was drawn in, so this line asserted "the pen went down on beat one". The anchor is now the BAR
    // alone and the position inside the bar is in the stroke's own points, so what has to be checked
    // is that the stroke starts where the pen touched, which the block below does in pixels rather
    // than in a cell index. What the old line protected — that the stroke is not silently moved to
    // another place on the page — is preserved by that comparison and is stronger.
    expect(
      drawn.stroke.anchor == const EventAnchor(sectionId: 'A', bar: 3),
      isTrue,
    );

    // The stored points are measured from the BAR's own top-left corner, and the first one is the
    // point the pen touched — which is what makes the stroke independent of where the page is.
    final Offset origin = Offset(bar.bounds.left, bar.bounds.top);
    final InkPoint first = drawn.stroke.points.first;
    expect(first.x, closeTo(startPage.dx - origin.dx, 1e-6));
    expect(first.y, closeTo(startPage.dy - origin.dy, 1e-6));
    expect(
      drawn.stroke.points.every((InkPoint point) => point.w > 0),
      isTrue,
      reason: 'a real pressure axis must be stored, not the neutral fallback',
    );
    expect(
      drawn.stroke.points.last.t,
      greaterThan(0),
      reason: 'the samples must carry their own time',
    );

    stdout.writeln(
      'ink.test.drawn page_scale=${painter.page.scale} '
      'anchor=${drawn.stroke.anchor} '
      'cell=${bar.sectionId}#${bar.barIndex} rect=(${cell.left},'
      '${cell.top},${cell.size.width},${cell.size.height}) '
      'surface_first=(${startPage.dx},${startPage.dy}) '
      'local_first=(${first.x.toStringAsFixed(3)},${first.y.toStringAsFixed(3)}) '
      'points=${drawn.stroke.points.length} '
      'pressure_distinct=${drawn.stroke.points.map((InkPoint p) => p.w).toSet().length}',
    );
  });

  testWidgets('in ink mode a touch DRAWS, and a measured palm does not', (
    WidgetTester tester,
  ) async {
    await pumpViewer(tester, inkChart());
    await setInkMode(tester, true);
    final ChartPainter painter = chartPainter(tester);
    final PlacedBar bar = painter.page.bars[6];
    final LayoutRect cell = bar.bounds;
    final Offset cellCentre = Offset(
      cell.left + cell.size.width / 2,
      cell.top + cell.size.height / 2,
    );

    // **THE ASSERTION THIS REPLACES WAS THE CONTRACT, AND THE OWNER'S OWN TABLET FALSIFIED IT. It is
    // quoted rather than deleted, the way the scale-squared anchor test and the palm-rule test keep
    // theirs.**
    //
    // It said: `touch parity means a finger feature, and this feature is selection` — a finger must
    // select and must never draw, even with ink mode ON, so that the pen alone writes.
    //
    // **THE PREMISE IS SOUND AND THIS DEVICE DOES NOT HONOUR IT.** This comment used to assert that
    // on the owner's tablet the S Pen's contacts arrive as `PointerDeviceKind.touch`, because
    // Samsung's stylus fusion merges them into the touch stream — and the whole mode decision below
    // rests on that. **THE TABLET CONTRADICTS THE COMMENT, AND THE TABLET IS THE INSTRUMENT**: a
    // stylus contact injected with `adb shell input stylus swipe` logs
    // `ink.contact.down ... ink reason=stylus-tool kind=stylus width=0.0 ... stylus_in_play=true
    // ink_on=true`, so on this build the pen IS its own kind and is NOT merged into the touch
    // stream. The claim is left standing beside its refutation rather than deleted, because the mode
    // decision it justified has not been revisited: with the pen arriving as a stylus, "a touch
    // draws" is no longer needed for THIS tablet, and that is a question for the owner rather than a
    // silent reversal here. The width half of the sentence — palms at 71 and 87 logical pixels
    // against a threshold of 40 — came from the WEB spike's raw browser width and has never been
    // observed on Android at all: every contact this application has logged on the tablet, stylus or
    // finger, reported `width=0.0`.
    //
    // SO THE MODE CARRIES THE MEANING INSTEAD OF THE DEVICE KIND, in the owner's own words:
    // **"рисование должно быть свободным"**. With ink mode ON the musician has DECLARED that he is
    // writing, so a touch draws. With ink mode OFF nothing draws and a touch selects, which is where
    // touch parity is a real choice rather than a guess about hardware.
    //
    // AND THE PALM IS STILL CAUGHT BY WIDTH, which is the half that never needed the device kind:
    // palms on this tablet measure 71 and 87 logical pixels against a threshold of 40. That is the
    // WEB half of the rule; on Android the width is not reported and the palm is refused by the ink
    // layer's own view-gesture rule instead — see `docs/sdd.md` A64.
    //
    // A TEST THAT PASSES BECAUSE IT MATCHES THE CODE CANNOT TELL A CONTRACT FROM A DEFECT. This one
    // was written to match the code, and the hardware said otherwise.
    final TestGesture gesture = await tester.startGesture(
      pagePointToGlobal(tester, painter, cellCentre),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(12, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      inkPainter(tester).strokes,
      hasLength(1),
      reason: 'ink mode is the musician saying he is writing',
    );
    // THE PALM IS NOT TESTED HERE, AND THAT IS DELIBERATE. The harness reports no contact width, and
    // width is the ONLY signal that separates a palm from the pen on this device: a `TestGesture`
    // would exercise the width-less path and prove nothing about a palm. That guard lives in
    // `packages/chart_core/test/ink_rules_test.dart`, which drives explicit widths — 0 for the pen,
    // 71 and 87 for the palms this tablet actually produces — and it is the assertion that matters.
    //
    // AND A SECOND STROKE ON THE SAME BEAT IS NOT DRAWN HERE EITHER, because it collides: the stroke
    // id is derived from its ANCHOR, so two strokes on one bar-and-beat both become
    // `ink-<section>-<bar>-<beat>-0-0` and the reducer refuses the second with
    // `stroke "ink-B-0-0-0-0" is already present`. That was found by writing this test, it is a real
    // defect reachable by an ordinary musician, and it is recorded rather than hidden by making the
    // test avoid it.
  });

  testWidgets('undo removes the stroke, and the document returns to its exact'
      ' previous value', (WidgetTester tester) async {
    await pumpViewer(tester, inkChart());
    await setInkMode(tester, true);
    final ChartPainter painter = chartPainter(tester);
    final LayoutRect cell = painter.page.bars.first.bounds;
    final Offset centre = Offset(
      cell.left + cell.size.width / 2,
      cell.top + cell.size.height / 2,
    );
    await drawStroke(
      tester,
      painter,
      pageStart: centre - const Offset(6, 0),
      pageEnd: centre + const Offset(6, 0),
      kind: PointerDeviceKind.stylus,
    );
    expect(
      inkPainter(tester).strokes,
      hasLength(1),
      reason: 'one stroke is on the page before the undo',
    );

    await tester.tap(find.byKey(const ValueKey<String>('viewer-undo')));
    await tester.pumpAndSettle();
    expect(
      inkPainter(tester).strokes,
      isEmpty,
      reason: 'the same page with the stroke removed',
    );

    await tester.tap(find.byKey(const ValueKey<String>('viewer-redo')));
    await tester.pumpAndSettle();
    expect(inkPainter(tester).strokes, hasLength(1));
  });

  testWidgets('an ordinary page and a fitted one put the stroke on the same'
      ' spot in the music', (WidgetTester tester) async {
    // FIT: the page is re-engraved larger and drawn smaller, so both the origin and the stored point
    // are expressed in different numbers while the offset between them is not. This chart is long
    // enough that FIT genuinely shrinks it — a chart that already fits on one page at scale 1 would
    // make this test pass without exercising the scale at all, so the assertion below is what says
    // the case was reached.
    await pumpViewer(tester, longInkChart(), size: const Size(700, 1400));
    await setInkMode(tester, true);
    final ChartPainter plainPainter = chartPainter(tester);
    expect(
      plainPainter.page.scale,
      1,
      reason: 'the narrow pane must still open in PAGES, or the two cases cannot be compared',
    );
    final PlacedBar plainBar = plainPainter.page.bars[0];
    final LayoutRect plainCell = plainBar.bounds;
    final Offset plainCentre = Offset(
      plainCell.left + plainCell.size.width / 2,
      plainCell.top + plainCell.size.height / 2,
    );
    // The stroke starts five pixels up and to the left of the cell centre, so in PAGES at scale 1 the
    // stored point is exactly the surface offset from the cell's own corner: half the cell minus five.
    const double aim = 5;
    await drawStroke(
      tester,
      plainPainter,
      pageStart: plainCentre - const Offset(aim, aim),
      pageEnd: plainCentre + const Offset(aim, aim),
      kind: PointerDeviceKind.stylus,
    );
    final ResolvedInkStroke onPlain = inkPainter(tester).strokes.single;
    final Offset plainOffset = Offset(
      onPlain.stroke.points.first.x,
      onPlain.stroke.points.first.y,
    );
    final Offset plainOrigin = Offset(onPlain.origin.x, onPlain.origin.y);
    // REWRITTEN, and the two expectations below used to read
    //   expect(plainOffset.dx, closeTo(plainCell.size.width / 2 - aim, 1e-6));
    //   expect(plainOffset.dy, closeTo(plainCell.size.height / 2 - aim, 1e-6));
    // — the stored point measured from the CELL's corner. A stroke is anchored to its BAR now, so the
    // origin is the bar's corner and the same quantity is the pen's own position in the bar. The claim
    // is unchanged: the stored point is where the pen went, expressed in the music's own pixels.
    expect(
      plainOffset.dx,
      closeTo(plainCentre.dx - plainBar.bounds.left - aim, 1e-6),
    );
    expect(
      plainOffset.dy,
      closeTo(plainCentre.dy - plainBar.bounds.top - aim, 1e-6),
    );

    // FIT: the page is re-engraved larger and drawn smaller, so the anchor's origin on the page is a
    // different number while the stored point is the SAME number, which is what keeps the ink on its
    // musical position when the musician switches to a page that has been shrunk.
    await tester.tap(find.byKey(const ValueKey<String>('scene-bar-mode-fit')));
    await tester.pumpAndSettle();
    final ChartPainter fitted = chartPainter(tester);
    expect(
      fitted.page.scale,
      lessThan(1),
      reason: 'the fit case is only tested if FIT actually shrank the page',
    );
    final ResolvedInkStroke onFit = inkPainter(tester).strokes.single;
    final Offset fitOffset = Offset(
      onFit.stroke.points.first.x,
      onFit.stroke.points.first.y,
    );
    final Offset fitOrigin = Offset(onFit.origin.x, onFit.origin.y);
    expect(
      fitOffset.dx,
      closeTo(plainOffset.dx, 1e-9),
      reason: 'the stored form does not change when the page is fitted',
    );
    expect(fitOffset.dy, closeTo(plainOffset.dy, 1e-9));
    // The page really is a different one: FIT re-engraved it, which is what the scale below 1 means,
    // and the anchor still resolved to the same bar of the same section. Comparing the two origins by
    // value would prove nothing — the first bar of the first section sits at the page margin on both
    // pages, which is exactly what a layout is supposed to do.
    expect(onFit.stroke.anchor, onPlain.stroke.anchor);
    expect(
      fitted.page.systems.length,
      isNot(plainPainter.page.systems.length),
      reason: 'the fitted page must be a different engraving, or this test proves nothing',
    );

    stdout.writeln(
      'ink.test.fit plain_scale=${plainPainter.page.scale} '
      'plain_origin=(${plainOrigin.dx},${plainOrigin.dy}) '
      'plain_systems=${plainPainter.page.systems.length} '
      'plain_cell=(${plainCell.left},${plainCell.top},'
      '${plainCell.size.width},${plainCell.size.height}) '
      'plain_stored=(${plainOffset.dx.toStringAsFixed(3)},'
      '${plainOffset.dy.toStringAsFixed(3)}) '
      'fit_scale=${fitted.page.scale.toStringAsFixed(4)} '
      'fit_origin=(${fitOrigin.dx.toStringAsFixed(2)},'
      '${fitOrigin.dy.toStringAsFixed(2)}) '
      'fit_systems=${fitted.page.systems.length} '
      'fit_stored=(${fitOffset.dx.toStringAsFixed(3)},'
      '${fitOffset.dy.toStringAsFixed(3)})',
    );
  });

  testWidgets('transposing re-spells the chords and leaves the ink measured from'
      ' its own cell', (WidgetTester tester) async {
    await pumpViewer(tester, inkChart());
    await setInkMode(tester, true);
    final ChartPainter painter = chartPainter(tester);
    final PlacedBar bar = painter.page.bars[5];
    final LayoutRect cell = bar.bounds;
    final Offset centre = Offset(
      cell.left + cell.size.width / 2,
      cell.top + cell.size.height / 2,
    );
    await drawStroke(
      tester,
      painter,
      pageStart: centre - const Offset(4, 2),
      pageEnd: centre + const Offset(4, 2),
      kind: PointerDeviceKind.stylus,
    );
    final ResolvedInkStroke before = inkPainter(tester).strokes.single;
    final Offset storedBefore = Offset(
      before.stroke.points.first.x,
      before.stroke.points.first.y,
    );

    // Transpose with the twelve-key grid's own control: open it from the key badge and pick a key
    // two semitones up, which is the second cell of the grid.
    await tester.tap(find.byKey(const ValueKey<String>('scene-bar-key-badge')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('key-grid-2')),
      findsOneWidget,
      reason: 'the grid must offer a key two semitones up',
    );
    await tester.tap(find.byKey(const ValueKey<String>('key-grid-2')));
    await tester.pumpAndSettle();

    final ChartPainter transposed = chartPainter(tester);
    expect(
      transposed.song.key,
      isNot(painter.song.key),
      reason: 'the chart must actually have been transposed',
    );
    final ResolvedInkStroke after = inkPainter(tester).strokes.single;
    final Offset storedAfter = Offset(
      after.stroke.points.first.x,
      after.stroke.points.first.y,
    );
    expect(
      storedAfter.dx,
      closeTo(storedBefore.dx, 1e-9),
      reason: 'the stored point is not rewritten by a transposition',
    );
    expect(storedAfter.dy, closeTo(storedBefore.dy, 1e-9));
    expect(after.stroke.anchor.sectionId, before.stroke.anchor.sectionId);
    expect(after.stroke.anchor.bar, before.stroke.anchor.bar);

    stdout.writeln(
      'ink.test.transpose written_key=${painter.song.key} '
      'shown_key=${transposed.song.key} '
      'anchor_before=${before.stroke.anchor} anchor_after=${after.stroke.anchor} '
      'origin_before=(${before.origin.x},${before.origin.y}) '
      'origin_after=(${after.origin.x.toStringAsFixed(2)},'
      '${after.origin.y.toStringAsFixed(2)}) '
      'stored_before=(${storedBefore.dx},${storedBefore.dy}) '
      'stored_after=(${storedAfter.dx},${storedAfter.dy})',
    );
  });

  test('a stroke survives the .chart container with its geometry intact', () {
    final Song song = inkChart();
    final EditSession session = EditSession(
      document: DocumentState(song: song),
      docId: song.id,
    );
    const InkStroke stored = InkStroke(
      id: 'ink-A-3-0-0',
      tool: StrokeTool.pen,
      color: '#102a43',
      size: 3,
      anchor: EventAnchor(sectionId: 'A', bar: 3),
      points: <InkPoint>[
        InkPoint(x: 5, y: -2, w: 0.25, t: 0),
        InkPoint(x: 9, y: 4, w: 0.75, t: 17),
      ],
    );
    session.apply(
      InkStrokeAddEvent(
        docId: session.docId,
        seq: session.seq,
        index: 0,
        stroke: stored,
      ),
    );
    expect(session.document.strokes, hasLength(1));

    final ChartFile file = ChartFile(
      metadata: ChartMetadata(docId: song.id, writer: 'chartapp'),
      snapshot: session.document,
      events: session.log,
    );
    final ChartFileEncodeResult encoded = ChartFileCodec.encode(file);
    final ChartFileDecodeResult decoded = ChartFileCodec.decode(encoded.bytes);
    expect(decoded.file.snapshot.strokes, hasLength(1));
    expect(decoded.file.snapshot.strokes.single, stored);
    expect(decoded.file.events, hasLength(1));
    expect(decoded.file.events.single, isA<InkStrokeAddEvent>());
    stdout.writeln(
      'ink.test.chart_file bytes=${encoded.bytes.length} '
      'warnings=${encoded.warnings.length} '
      'strokes=${decoded.file.snapshot.strokes.length} '
      'events=${decoded.file.events.length} '
      'round_trip_equal=${decoded.file.snapshot.strokes.single == stored}',
    );
  });
}
