// PURPOSE: Check the two pure decisions the web ink mode rests on — whether a contact may draw, and
//          where a stroke's anchor landed on a page — on synthetic numbers, so that a rule which
//          only works when a hand is holding a pen is caught here instead of on a tablet.
//
//          The assertions are chosen to fail if the behaviour changes: the palm rule is exercised at
//          its threshold from both sides and with the stylus gate open and shut, and the anchor
//          arithmetic is exercised against a page whose scale is NOT 1, because that is the case a
//          transform that assumed 1 would still pass everywhere else.
// INPUTS: None. The layout is built here, so the test needs no device and no fixture.
// OUTPUTS: Pass/fail per behaviour, and one printed line naming the anchor and the page point it
//          resolves to so the arithmetic can be read rather than only trusted.
// KEYWORDS: test, ink, palm-rule, touch-parity, stylus-proximity, anchor-local, page-scale,
//           transposition-survival
import 'dart:io';
import 'dart:math' as math;

import 'package:chart_core/chart_core.dart';
import 'package:test/test.dart';

/// A synthetic 16-bar song in one section, laid out wide enough that FIT must shrink it.
Song twoSectionChart() => Song(
  id: 'ink-test',
  title: 'Ink anchor',
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
          for (int index = 0; index < 8; index++)
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

/// The engine the test lays charts out with.
///
/// The default style, which uses the package's own deterministic [FixedAdvanceTextMetrics]: the
/// layout is then reproducible on any machine and the test asserts arithmetic rather than glyph
/// shapes.
const LayoutEngine engine = LayoutEngine();

/// The Euclidean length of the vector ([dx], [dy]), so a distance assertion reads as one number.
double _length(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

void main() {
  group('InkPalmRule', () {
    test('ink mode off refuses every contact, whatever it is', () {
      for (final InkCaptureKind kind in InkCaptureKind.values) {
        final InkContactDecision decision = InkPalmRule.decide(
          kind: kind,
          width: 5,
          stylusInPlay: false,
          inkModeOn: false,
        );
        expect(decision.mayInk, isFalse, reason: 'kind ${kind.token}');
        expect(decision.reason, InkPalmRule.reasonInkModeOff);
      }
    });

    test('a stylus draws with ink on, and its width is never consulted', () {
      final InkContactDecision decision = InkPalmRule.decide(
        kind: InkCaptureKind.stylus,
        width: 900,
        stylusInPlay: true,
        inkModeOn: true,
      );
      expect(decision.mayInk, isTrue);
      expect(decision.reason, InkPalmRule.reasonStylus);
      expect(decision.palmLikeWidth, isTrue);
    });

    test('a finger draws when no stylus is in play, however wide it is', () {
      final InkContactDecision decision = InkPalmRule.decide(
        kind: InkCaptureKind.finger,
        width: 87,
        stylusInPlay: false,
        inkModeOn: true,
      );
      expect(decision.mayInk, isTrue);
      expect(decision.reason, InkPalmRule.reasonPalmLikeWidthNoStylus);
      expect(
        decision.palmLikeWidth,
        isTrue,
        reason: 'the touch-parity case must be visible in the record',
      );
    });

    // THE ASSERTION BELOW WAS THE DEFECT, AND IT IS KEPT VISIBLE RATHER THAN DELETED, the way the
    // scale-squared anchor test keeps its own. It read:
    //
    //     test('an unmeasured width is refused rather than treated as a fingertip', () {
    //       for (final double width in <double>[0, -1, double.nan, ...]) {
    //         expect(decision.mayInk, isFalse, reason: 'width $width');
    //         expect(decision.reason, InkPalmRule.reasonWidthNotReported);
    //
    // and `width == 0` IS THE OWNER'S S PEN. Every pen contact on his tablet carries no width, so
    // this test asserted exactly the behaviour that made drawing work "через раз" and then not at
    // all, while the app's log named the reason and told him nothing. A test that passes because it
    // was written to match the code cannot tell a contract from a defect.
    //
    // The contract is inverted here: an unmeasured width DRAWS, and the token survives so a
    // diagnosis can still name the doubt. The NaN and infinite cases are kept deliberately — they
    // are the shapes a platform sends when it has no number, and all of them must draw.
    test('an unmeasured width DRAWS, because a refusal nobody can see is the worse failure', () {
      for (final double width in <double>[
        0,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final InkContactDecision decision = InkPalmRule.decide(
          kind: InkCaptureKind.finger,
          width: width,
          stylusInPlay: false,
          inkModeOn: true,
        );
        expect(decision.mayInk, isTrue, reason: 'width $width');
        expect(decision.reason, InkPalmRule.reasonWidthNotReported);
      }
    });

    test('a measured width below the threshold draws', () {
      final InkContactDecision decision = InkPalmRule.decide(
        kind: InkCaptureKind.finger,
        width: 4,
        stylusInPlay: false,
        inkModeOn: true,
      );
      expect(decision.mayInk, isTrue);
      expect(decision.reason, InkPalmRule.reasonWidthBelowThreshold);
    });

    test('a palm-like contact is refused while a stylus is in play', () {
      final InkContactDecision decision = InkPalmRule.decide(
        kind: InkCaptureKind.finger,
        width: 71,
        stylusInPlay: true,
        inkModeOn: true,
      );
      expect(decision.mayInk, isFalse);
      expect(decision.reason, InkPalmRule.reasonPalmLikeWidth);
    });

    test('the threshold is inclusive, and one unit below it draws', () {
      expect(
        InkPalmRule.isPalmLikeWidth(InkPalmRule.palmWidthThreshold),
        isTrue,
      );
      expect(
        InkPalmRule.isPalmLikeWidth(InkPalmRule.palmWidthThreshold - 0.0001),
        isFalse,
      );
    });

    test('a width that was not measured never rejects a contact', () {
      for (final double width in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1,
        0,
      ]) {
        expect(
          InkPalmRule.isPalmLikeWidth(width),
          isFalse,
          reason: 'width $width',
        );
      }
    });

    test('a mouse never draws ink in this increment', () {
      final InkContactDecision decision = InkPalmRule.decide(
        kind: InkCaptureKind.mouse,
        width: 0,
        stylusInPlay: false,
        inkModeOn: true,
      );
      expect(decision.mayInk, isFalse);
      expect(decision.reason, InkPalmRule.reasonMouse);
    });
  });

  group('anchor placement', () {
    test('a cell anchor resolves to the cell rectangle, and a bar anchor to the bar', () {
      final List<PageLayout> pages = engine.layout(
        twoSectionChart(),
        pageWidth: 824,
        pageHeight: 600,
      );
      final PageLayout page = pages.first;
      final PlacedBar bar = page.bars[2];
      final PlacedCell cell = bar.cells[1];

      final InkPlacement? cellPlacement = resolveEventAnchor(
        page,
        EventAnchor(
          sectionId: bar.sectionId,
          bar: bar.barIndex,
          beat: cell.beat,
        ),
      );
      expect(cellPlacement, isNotNull);
      expect(cellPlacement!.bounds, cell.bounds);
      expect(cellPlacement.origin, cell.bounds.origin);

      final InkPlacement? barPlacement = resolveEventAnchor(
        page,
        EventAnchor(sectionId: bar.sectionId, bar: bar.barIndex),
      );
      expect(barPlacement, isNotNull);
      expect(barPlacement!.bounds, bar.bounds);
    });

    test(
      'an address the page does not hold resolves to null, not to a guess',
      () {
        final PageLayout page = engine
            .layout(twoSectionChart(), pageWidth: 824, pageHeight: 600)
            .first;
        expect(
          resolveEventAnchor(
            page,
            const EventAnchor(sectionId: 'Z', bar: 0, beat: 0),
          ),
          isNull,
        );
        expect(
          resolveEventAnchor(
            page,
            const EventAnchor(sectionId: 'A', bar: 999, beat: 0),
          ),
          isNull,
        );
      },
    );

    test('a stored point translated by the anchor lands on the page', () {
      const LayoutOffset origin = LayoutOffset(120, 40);
      const InkPoint point = InkPoint(x: 3.5, y: -2.5, w: 0.7, t: 12);
      expect(inkPointToPage(point, origin), const LayoutOffset(123.5, 37.5));
      expect(
        pagePointToAnchorLocal(const LayoutOffset(123.5, 37.5), origin),
        const LayoutOffset(3.5, -2.5),
        reason: 'the two directions must be exact inverses',
      );
    });

    test(
      'a fitted page keeps a stroke on the same PAGE point as an ordinary page',
      () {
        final Song song = twoSectionChart();
        // The reference point: the centre of the anchor cell on an ordinary page, and a stored point
        // that sits 5 by 5 logical pixels from that cell's own corner.
        final PageLayout plain = engine
            .layout(song, pageWidth: 824, pageHeight: 600)
            .first;
        final PlacedBar plainBar = plain.bars[4];
        final PlacedCell plainCell = plainBar.cells.first;
        final InkPlacement plainPlacement = resolveEventAnchor(
          plain,
          EventAnchor(
            sectionId: plainBar.sectionId,
            bar: plainBar.barIndex,
            beat: plainCell.beat,
          ),
        )!;
        const InkPoint stored = InkPoint(x: 5, y: 5, w: 0.5, t: 0);
        final LayoutOffset plainPoint = inkPointToPage(
          stored,
          plainPlacement.origin,
        );

        // The same stroke on a fitted page. The page is engraved at a LARGER virtual size and drawn
        // smaller, so the engraved point is a different number and the SURFACE point is the same —
        // which is the property that makes ink stay where the musician put it.
        final FitOutcome fit = engine.fitToPage(
          song,
          pageWidth: 400,
          pageHeight: 300,
        );
        final PageLayout fitted = fit.page!;
        expect(fitted.scale, lessThan(1));
        final PlacedBar fittedBar = fitted.bars[4];
        final PlacedCell fittedCell = fittedBar.cells.first;
        final InkPlacement fittedPlacement = resolveEventAnchor(
          fitted,
          EventAnchor(
            sectionId: fittedBar.sectionId,
            bar: fittedBar.barIndex,
            beat: fittedCell.beat,
          ),
        )!;
        final LayoutOffset fittedPoint = inkPointToPage(
          stored,
          fittedPlacement.origin,
        );

        // In engraved coordinates the two pages place the cell in different places — that is what a
        // different scale means — so the engraved points differ.
        expect(fittedPoint, isNot(plainPoint));
        // On their own surfaces they agree to the scale, because the cell moved with the music.
        stdout.writeln(
          'ink.fit_proof scale=${fitted.scale.toStringAsFixed(4)} '
          'plain_engraved=(${plainPoint.x.toStringAsFixed(2)},'
          '${plainPoint.y.toStringAsFixed(2)}) '
          'fitted_engraved=(${fittedPoint.x.toStringAsFixed(2)},'
          '${fittedPoint.y.toStringAsFixed(2)}) '
          'plain_cell=(${plainCell.bounds.left.toStringAsFixed(2)},'
          '${plainCell.bounds.top.toStringAsFixed(2)}) '
          'fitted_cell=(${fittedCell.bounds.left.toStringAsFixed(2)},'
          '${fittedCell.bounds.top.toStringAsFixed(2)})',
        );
        // The stored offset from the cell's own corner is the same on both pages, which is the whole
        // claim: the ink describes a place IN the music, not a place on the glass.
        expect(plainPoint.x - plainCell.bounds.left, closeTo(5, 1e-9));
        expect(plainPoint.y - plainCell.bounds.top, closeTo(5, 1e-9));
        expect(fittedPoint.x - fittedCell.bounds.left, closeTo(5, 1e-9));
        expect(fittedPoint.y - fittedCell.bounds.top, closeTo(5, 1e-9));
      },
    );

    // THIS IS THE CASE THE OLD FIT PROOF MISSED. The test above draws a stored point and asks where
    // it renders; it therefore exercises the RENDER direction, and it passes on a fitted page even
    // while capture is broken, because a stored point never goes through the capture transform at
    // all. The case that breaks is a stroke drawn while the page is ALREADY fitted: the page point
    // is derived from the surface point at the moment the pen lands, and there two rules for one
    // transform disagreed by a factor of the scale. A stroke drawn at the centre of the cell under
    // the pen was anchored to the cell at `surface * scale²` — about ten engraved pixels away on the
    // fixture below — and then drawn at that wrong place, which is the visible offset from the nib.
    //
    // The assertions are chosen to fail if the transform changes direction again: [hit] names the
    // bar and cell the pen actually touched, and the stroke's own anchor must be that same address.
    test('a stroke drawn on an ALREADY-fitted page is anchored to the cell under the pen', () {
      // The point the fitted arm stores, kept so the ordinary arm can be compared against it.
      InkPoint? storedFirst;
      void expectCaptureOnFittedPage(double fitScaleCeiling) {
        final Song song = twoSectionChart();
        final FitOutcome fit = engine.fitToPage(
          song,
          pageWidth: 824 * fitScaleCeiling,
          pageHeight: 600 * fitScaleCeiling,
        );
        final PageLayout page = fit.page!;
        if (fitScaleCeiling < 1) {
          expect(page.scale, lessThan(1));
        } else {
          expect(page.scale, 1, reason: 'this arm is the ordinary page');
        }

        // The cell the pen will land in — the last of the last bar, the furthest engraved point
        // from the origin and so the one a scale error moves the most.
        final PlacedBar bar = page.bars.last;
        final PlacedCell cell = bar.cells.last;
        final LayoutOffset centre = LayoutOffset(
          cell.bounds.left + cell.bounds.size.width / 2,
          cell.bounds.top + cell.bounds.size.height / 2,
        );
        // A small engraved offset from the cell's centre, so the nib is visibly inside the cell
        // and the stored point is not the centre by accident. It is scaled onto the surface, which
        // is the direction the painter goes.
        const LayoutOffset engravedNudge = LayoutOffset(4, 3);
        final LayoutOffset nudge = LayoutOffset(
          engravedNudge.x * page.scale,
          engravedNudge.y * page.scale,
        );
        final LayoutOffset surface = LayoutOffset(
          centre.x * page.scale + nudge.x,
          centre.y * page.scale + nudge.y,
        );

        // What the pen is over, read through the SAME entry the capture path used.
        final ChartHit? hit = hitTestPage(page, page.pagePointOf(surface));
        expect(hit, isNotNull, reason: 'the fixture must offer a cell here');
        expect(hit!.barIndex, bar.barIndex);
        expect(hit.sectionId, bar.sectionId);
        expect(hit.beat, cell.beat);

        // The whole capture path — begin, one move, end — with real surface coordinates.
        final InkStrokeAssembler assembler = InkStrokeAssembler(
          tool: StrokeTool.pen,
          color: '#102a43',
          size: 3,
        );
        expect(
          assembler.begin(
            page: page,
            surfacePoint: surface,
            pressure: 0.6,
            time: 1000,
          ),
          isTrue,
        );
        assembler.add(
          surfacePoint: LayoutOffset(surface.x + 2, surface.y + 1),
          pressure: 0.6,
          time: 1016,
        );
        final InkStroke stroke = assembler.end(page: page, id: 'fitted')!;

        final EventAnchor anchor = stroke.anchor;
        final int recordedBeat = anchor.beat ?? -1;
        final int aimedBeat = cell.beat;
        // How far the recorded anchor's cell is from the one under the pen, in engraved pixels.
        final InkPlacement? recorded = resolveEventAnchor(page, anchor);
        final LayoutOffset recordedOrigin =
            recorded?.origin ?? LayoutOffset.zero;
        final double dx = recordedOrigin.x - cell.bounds.left;
        final double dy = recordedOrigin.y - cell.bounds.top;

        stdout.writeln(
          'ink.capture_fit scale=${page.scale.toStringAsFixed(4)} '
          'surface=(${surface.x.toStringAsFixed(2)},'
          '${surface.y.toStringAsFixed(2)}) '
          'pagePoint=(${page.pagePointOf(surface).x.toStringAsFixed(2)},'
          '${page.pagePointOf(surface).y.toStringAsFixed(2)}) '
          'aimed=${anchor.sectionId}-${bar.barIndex} beat $aimedBeat '
          'anchored=${anchor.sectionId}-${anchor.bar} '
          'beat $recordedBeat '
          'cell_error_px=${_length(dx, dy).toStringAsFixed(4)}',
        );

        // The defect, stated as the assertion that catches it: the recorded anchor must name the
        // bar and the cell under the pen, not the bar at `surface * scale`.
        expect(
          anchor.bar,
          bar.barIndex,
          reason: 'the anchor bar must be the bar under the pen',
        );
        expect(anchor.sectionId, bar.sectionId);
        expect(
          recordedBeat,
          aimedBeat,
          reason: 'the anchor cell must be the cell under the pen',
        );
        expect(
          _length(dx, dy),
          lessThan(1e-9),
          reason: 'the recorded anchor rect must be the aimed cell rect',
        );

        // And the stored points must put the ink back on the surface point that was drawn, which
        // is the property the eye checks: `InkPainter` scales the anchor by `canvas.scale`, then
        // adds the local points. If capture and render disagree, this round trip is off by scale².
        final LayoutOffset rendered = inkPointToPage(
          stroke.points.first,
          recordedOrigin,
        );
        final double roundTrip = _length(
          rendered.x - page.pagePointOf(surface).x,
          rendered.y - page.pagePointOf(surface).y,
        );
        expect(
          roundTrip,
          lessThan(1e-9),
          reason: 'the stored point must render back onto the engraved pen position',
        );
        // In engraved pixels the nudge of (4, 3) shrinks to the surface; the same claim measured
        // on the glass, which is what the musician sees.
        final LayoutOffset renderedSurface = LayoutOffset(
          rendered.x * page.scale,
          rendered.y * page.scale,
        );
        expect(
          _length(renderedSurface.x - surface.x, renderedSurface.y - surface.y),
          lessThan(1e-9),
          reason: 'the ink must be under the nib on the surface',
        );
        expect(stroke.points.first.w, 0.6);
        // The stored offset is measured from the anchor's own corner, so it is the pen's distance
        // from the cell's left edge — not the small nudge by itself, because the pen was aimed at
        // the cell's centre and a bar's last cell is often narrow. This is the number the whole
        // file is about: it is measured in the carved page's own pixels and is therefore the same
        // on a fitted page and an ordinary one.
        expect(
          stroke.points.first.x,
          closeTo((centre.x + engravedNudge.x) - cell.bounds.left, 1e-9),
          reason: 'the stored offset from the anchor corner is the pen, not its nudge',
        );
        expect(
          stroke.points.first.y,
          closeTo((centre.y + engravedNudge.y) - cell.bounds.top, 1e-9),
        );
        expect(
          stroke.points.first.x,
          inInclusiveRange(0, cell.bounds.size.width),
          reason: 'the stored point must lie inside the cell the pen landed in',
        );
        stdout.writeln(
          'ink.capture_fit.local scale=${page.scale.toStringAsFixed(4)} '
          'first_local=(${stroke.points.first.x},${stroke.points.first.y}) '
          'anchor_origin=(${recordedOrigin.x},${recordedOrigin.y}) '
          'cell=(${cell.bounds.left},${cell.bounds.top},'
          '${cell.bounds.size.width},${cell.bounds.size.height}) '
          'engraved_point=(${page.pagePointOf(surface).x},'
          '${page.pagePointOf(surface).y}) '
          'rendered_surface=(${renderedSurface.x},${renderedSurface.y}) '
          'drawn_surface=(${surface.x},${surface.y})',
        );
        storedFirst = stroke.points.first;
      }

      // The strongest statement available, and the one the whole anchor-local design exists to
      // make: the SAME pen position, written on a page shrunk by FIT and on an ordinary page,
      // stores the SAME anchor-local point. Capture that multiplied instead of divided stored
      // `surface * scale² - origin` and this comparison was off by tens of engraved pixels.
      // Fitted: the case that was broken, and the reason this test exists.
      expectCaptureOnFittedPage(0.5);
      final InkPoint? fittedStored = storedFirst;
      // Ordinary: the control that was never broken, so a fix aimed only at FIT is visible.
      expectCaptureOnFittedPage(1);
      expect(fittedStored, isNotNull);
      expect(
        fittedStored,
        storedFirst,
        reason:
            'the stored anchor-local point must not depend on the page scale',
      );
    });

    // CORRECTED ASSERTION. This test previously read
    //   `final LayoutOffset page = inkSurfaceToPage(surface, 0.4);`
    //   `expect(page.x, closeTo(13.2, 1e-9));`
    //   `expect(page.y, closeTo(30.8, 1e-9));`
    // and it encoded the defect rather than guarding against it. `inkSurfaceToPage` multiplied by
    // the page scale, but `PageLayout.pagePointOf` — the one transform the renderer's inverse, the
    // hit test and the eraser all use — DIVIDES by it. With the two rules disagreeing by a factor of
    // the scale, a stroke drawn while a page was already fitted was anchored to the cell at
    // `surface * scale²` and drawn about ten engraved pixels from the nib. `13.2` is therefore the
    // value the bug produces, not the value the surface point maps to; the correct engraved position
    // of surface (33, 77) at scale 0.4 is (82.5, 192.5). The transform now lives in exactly one
    // place — `pagePointOf`, which divides — and `inkSurfaceToPage` no longer exists.
    test(
      'the page transform DIVIDES by the fit scale, and inverts the painter',
      () {
        const LayoutOffset surface = LayoutOffset(33, 77);
        const double scale = 0.4;
        final PageLayout fitted = PageLayout(
          index: 0,
          size: const LayoutSize(100, 100),
          systems: const <PlacedSystem>[],
          scale: scale,
        );

        // The engraved page is LARGER than the surface (FIT engraves at `size / scale` and shrinks the
        // result), so the surface point must travel UP the scale, i.e. be divided by it.
        final LayoutOffset page = fitted.pagePointOf(surface);
        expect(page.x, closeTo(82.5, 1e-9));
        expect(page.y, closeTo(192.5, 1e-9));

        // What the OLD test asserted, kept as an explicit refutation: the multiplying rule lands
        // 175.9 engraved pixels away, which is a different bar on any real page, not a rounding
        // difference.
        expect(page.x, isNot(closeTo(13.2, 0.5)));
        expect(page.y, isNot(closeTo(30.8, 0.5)));

        // And it is the exact inverse of what the painter does: `InkPainter` scales the engraved
        // geometry onto the surface by `canvas.scale(scale, scale)`, so scaling an engraved point DOWN
        // by [scale] and reading it back through `pagePointOf` must return that engraved point.
        const LayoutOffset engraved = LayoutOffset(100, 50);
        expect(
          fitted.pagePointOf(
            LayoutOffset(engraved.x * scale, engraved.y * scale),
          ),
          engraved,
        );

        // Scale 1 is the ordinary page and pays nothing in either direction.
        const PageLayout ordinary = PageLayout(
          index: 0,
          size: LayoutSize(100, 100),
          systems: <PlacedSystem>[],
        );
        expect(ordinary.pagePointOf(surface), surface);
      },
    );
  });
}
