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

    test(
      'an unmeasured width is refused rather than treated as a fingertip',
      () {
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
          expect(decision.mayInk, isFalse, reason: 'width $width');
          expect(decision.reason, InkPalmRule.reasonWidthNotReported);
        }
      },
    );

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

    test('the surface-to-page conversion is the inverse of the page scale', () {
      const LayoutOffset surface = LayoutOffset(33, 77);
      expect(inkSurfaceToPage(surface, 1), surface);
      const double scale = 0.4;
      final LayoutOffset page = inkSurfaceToPage(surface, scale);
      expect(page.x, closeTo(13.2, 1e-9));
      expect(page.y, closeTo(30.8, 1e-9));
      final PageLayout synthetic = PageLayout(
        index: 0,
        size: const LayoutSize(100, 100),
        systems: const <PlacedSystem>[],
        scale: scale,
      );
      expect(synthetic.pagePointOf(page), surface);
    });
  });
}
