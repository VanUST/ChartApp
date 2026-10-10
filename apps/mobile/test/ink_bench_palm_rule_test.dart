// PURPOSE: Pin the palm predicate's arithmetic on synthetic contact values, so the rule a device
//          run is judged by is fixed even though only the device can confirm it against a real
//          palm. Two properties matter here and are tested separately: the width separation the
//          owner's run measured (13-15 admitted fingers against 86 and 91 palm-like contacts), and
//          the stylus gate that keeps the rule from refusing a finger when no pen is in play.
// INPUTS: None; every case is constructed.
// OUTPUTS: Pass/fail per case. A failure names the value, the threshold, the gate state and the
//          decision expected.
// KEYWORDS: palm-rule, predicate, threshold, synthetic-values, boundary, stylus-gate, touch-parity
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_native/ink_native.dart';

/// The threshold the cases are evaluated against, taken from the rule itself rather than repeated.
const double threshold = PalmWidthRule.thresholdTouchMajor;

/// Decides one contact with the pen in play.
PalmContactDecision withPen(double touchMajor, {InkPointerKind? kind}) =>
    PalmWidthRule.decide(
      kind: kind ?? InkPointerKind.finger,
      touchMajor: touchMajor,
      thresholdTouchMajor: threshold,
      stylusInPlay: true,
    );

/// Decides one contact with no pen in play.
PalmContactDecision withoutPen(double touchMajor, {InkPointerKind? kind}) =>
    PalmWidthRule.decide(
      kind: kind ?? InkPointerKind.finger,
      touchMajor: touchMajor,
      thresholdTouchMajor: threshold,
      stylusInPlay: false,
    );

void main() {
  group('the threshold carries no density conversion', () {
    test('the rule takes no display density at all', () {
      // The predicate's signature is the enforcement: version 1 multiplied by density, which is
      // impossible now because no density is available to it. This test exists so re-introducing a
      // density parameter is a deliberate act rather than a refactor.
      expect(PalmWidthRule.version, 2);
      expect(PalmWidthRule.thresholdTouchMajor, 40.0);
      expect(PalmWidthRule.stylusProximityWindowMs, 1000);
    });

    test(
      'the threshold is not the density-scaled value version 1 computed',
      () {
        // 2.125 is the reference tablet's real density (`wm density` reports 340). Version 1 of the
        // rule multiplied 20 dp by it and got 42.5; the rule must not carry that arithmetic any more,
        // and this assertion fails if someone reinstates it with the same numbers.
        const double referenceDensity = 2.125;
        expect(
          PalmWidthRule.thresholdTouchMajor,
          isNot(closeTo(20 * referenceDensity, 0.0001)),
        );
        expect(PalmWidthRule.thresholdTouchMajor, 40.0);
      },
    );

    test('the unit is declared and is not claimed to be a physical length', () {
      expect(PalmWidthRule.thresholdUnit, contains('AXIS_TOUCH_MAJOR'));
      expect(PalmWidthRule.thresholdUnitEvidence, contains('255'));
      expect(PalmWidthRule.thresholdUnitEvidence, contains('3302.954'));
      expect(
        PalmWidthRule.thresholdUnitEvidence,
        contains('validated for the reference device'),
      );
      expect(
        PalmWidthRule.thresholdUnitEvidence,
        contains('No density conversion is applied'),
      );
    });
  });

  group('isPalmLikeWidth', () {
    test('the boundary is inclusive, so the threshold itself is palm-like', () {
      expect(
        PalmWidthRule.isPalmLikeWidth(
          touchMajor: threshold,
          thresholdTouchMajor: threshold,
        ),
        isTrue,
      );
      expect(
        PalmWidthRule.isPalmLikeWidth(
          touchMajor: threshold - 0.001,
          thresholdTouchMajor: threshold,
        ),
        isFalse,
      );
    });

    test('a value that was not measured is never palm-like', () {
      for (final double value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1,
      ]) {
        expect(
          PalmWidthRule.isPalmLikeWidth(
            touchMajor: value,
            thresholdTouchMajor: threshold,
          ),
          isFalse,
          reason: 'value $value',
        );
      }
    });
  });

  group('with the pen in play, the owner run separation is respected', () {
    for (final double value in <double>[13.0, 15.0]) {
      test('a $value contact is admitted', () {
        final PalmContactDecision decision = withPen(value);
        expect(decision.admitted, isTrue);
        expect(decision.palmLikeWidth, isFalse);
        expect(decision.reason, PalmWidthRule.reasonWidthBelowThreshold);
        expect(decision.decidingTouchMajor, value);
        expect(decision.thresholdTouchMajor, threshold);
        expect(decision.stylusInPlay, isTrue);
      });
    }
    for (final double value in <double>[86.0, 91.0]) {
      test('a $value contact is rejected', () {
        final PalmContactDecision decision = withPen(value);
        expect(decision.admitted, isFalse);
        expect(decision.palmLikeWidth, isTrue);
        expect(decision.reason, PalmWidthRule.reasonPalmLikeWidth);
        expect(decision.decidingTouchMajor, value);
        expect(decision.thresholdTouchMajor, threshold);
        expect(decision.stylusInPlay, isTrue);
      });
    }
  });

  group('with NO pen in play, touch parity wins', () {
    test('a 91 contact is ADMITTED as a finger, not rejected as a palm', () {
      final PalmContactDecision decision = withoutPen(91);
      expect(
        decision.admitted,
        isTrue,
        reason: 'a finger must draw with no stylus present',
      );
      expect(
        decision.palmLikeWidth,
        isTrue,
        reason: 'the width test still reports the truth',
      );
      expect(decision.reason, PalmWidthRule.reasonPalmLikeWidthNoStylus);
      expect(decision.stylusInPlay, isFalse);
    });

    test('a 500 contact is admitted with no pen in play', () {
      expect(withoutPen(500).admitted, isTrue);
    });

    test('the same value is rejected with the pen and admitted without it', () {
      // The whole point of the gate, in one assertion: the pen's presence, not the width alone,
      // decides. Without this the rule would be a touch-parity regression.
      expect(withPen(91).admitted, isFalse);
      expect(withoutPen(91).admitted, isTrue);
    });
  });

  group(
    'the rule never subjects a tool it was not written for to the width test',
    () {
      for (final InkPointerKind kind in <InkPointerKind>[
        InkPointerKind.sPen,
        InkPointerKind.sPenEraser,
      ]) {
        test('${kind.wireName} is admitted at 500, with and without a pen', () {
          for (final bool pen in <bool>[true, false]) {
            final PalmContactDecision decision = PalmWidthRule.decide(
              kind: kind,
              touchMajor: 500,
              thresholdTouchMajor: threshold,
              stylusInPlay: pen,
            );
            expect(decision.admitted, isTrue, reason: 'stylusInPlay=$pen');
            expect(decision.reason, PalmWidthRule.reasonStylus);
            expect(decision.palmLikeWidth, isFalse);
          }
        });
      }

      test('a mouse is admitted at 500, with and without a pen', () {
        for (final bool pen in <bool>[true, false]) {
          final PalmContactDecision decision = PalmWidthRule.decide(
            kind: InkPointerKind.mouse,
            touchMajor: 500,
            thresholdTouchMajor: threshold,
            stylusInPlay: pen,
          );
          expect(decision.admitted, isTrue);
          expect(decision.reason, PalmWidthRule.reasonMouse);
        }
      });

      test(
        'a platform-classified palm is rejected whatever its width or the gate',
        () {
          for (final double value in <double>[0, 13, 91]) {
            for (final bool pen in <bool>[true, false]) {
              final PalmContactDecision decision = PalmWidthRule.decide(
                kind: InkPointerKind.palm,
                touchMajor: value,
                thresholdTouchMajor: threshold,
                stylusInPlay: pen,
              );
              expect(
                decision.admitted,
                isFalse,
                reason: 'value $value pen $pen',
              );
              expect(decision.reason, PalmWidthRule.reasonPlatformPalm);
            }
          }
        },
      );

      test(
        'an unrecognised tool type is judged by value and gate, like a finger',
        () {
          expect(withPen(13).reason, PalmWidthRule.reasonWidthBelowThreshold);
          expect(
            withPen(91, kind: InkPointerKind.unknown).reason,
            PalmWidthRule.reasonPalmLikeWidth,
          );
          expect(
            withoutPen(91, kind: InkPointerKind.unknown).reason,
            PalmWidthRule.reasonPalmLikeWidthNoStylus,
          );
        },
      );
    },
  );

  test('the decision renders every input it decided on', () {
    expect(
      withPen(91).toString(),
      'rejected (palm-like-width, touchMajor=91.0, threshold=40.0, stylusInPlay=true)',
    );
    expect(
      withoutPen(91).toString(),
      'admitted (palm-like-width-no-stylus, touchMajor=91.0, threshold=40.0, '
      'stylusInPlay=false)',
    );
  });

  test('the rule publishes a threshold, a window and a provenance for the artifact', () {
    expect(PalmWidthRule.version, greaterThan(0));
    expect(PalmWidthRule.thresholdTouchMajor, greaterThan(0));
    expect(PalmWidthRule.stylusProximityWindowMs, greaterThan(0));
    expect(PalmWidthRule.provenance, contains('bench-20261010T143629'));
    expect(
      PalmWidthRule.provenance,
      contains('Validated for that device only'),
    );
  });
}
