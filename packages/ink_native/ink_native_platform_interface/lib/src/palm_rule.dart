// PURPOSE: Define the one predicate that decides whether a contact is palm-like, in the contract
//          every platform implementation and the bench share, so the rule is visible, testable on
//          synthetic widths and identical in the arithmetic the native surfaces apply. Before this
//          file the only palm test in the system was `MotionEvent.TOOL_TYPE_PALM`, an invisible
//          platform constant: a 91-unit-wide contact the platform called a finger was admitted and
//          drawn as ink, and nothing in the artifact said why.
//
//          THE RULE HAS TWO CONDITIONS, NOT ONE. A contact of palm-like width is only a palm
//          candidate while a stylus is in play — hovering, touching, or seen within
//          [PalmWidthRule.stylusProximityWindowMs]. With no pen in play a finger draws however
//          wide it is, because touch parity (everything works without a stylus) outranks rejecting
//          a palm.
// INPUTS: A contact's pointer kind, its measured touch-major value, the threshold in the same
//         units, and whether a stylus was in play when the contact arrived.
// OUTPUTS: A [PalmContactDecision] naming the outcome, the reason and the inputs that decided it.
//          Never throws: a negative, infinite or NaN width is treated as not palm-like, because a
//          number that was not measured must not reject a contact.
// KEYWORDS: palm-rejection, touch-major, threshold, predicate, inspectable, cross-check,
//           contact-classification, stylus-proximity, touch-parity
library;

import 'ink_types.dart';

// PURPOSE: Decide, from the numbers alone, whether one contact is palm-like and whether it may
//          draw, and say why, so the bench can print the deciding values instead of a bare
//          `drawAdmitted` boolean.
// INPUTS: See [decide]; the threshold and the stylus-proximity fact are supplied by the caller
//         rather than read from the device, so the same arithmetic can be evaluated on synthetic
//         widths in a test with no hardware.
// OUTPUTS: A [PalmContactDecision]. No input combination throws.
// KEYWORDS: palm-rule, threshold, provenance, admission-reason, stylus-gate, testable
/// The width rule that decides whether a contact is treated as a palm.
///
/// The rule is deliberately a pure function of (kind, width, threshold, stylusInPlay): the native
/// surface applies it to decide whether to draw, and the Dart bench applies it again to the
/// reported numbers to check that the native decision and the documented rule agree. A disagreement
/// is reported as a finding, which is what keeps two implementations of one rule from drifting.
class PalmWidthRule {
  const PalmWidthRule._();

  /// Version of this rule; a change to the threshold, the comparison, the gate or the reasons
  /// bumps it.
  ///
  /// Carried into the run's info file so an artifact can be read against the rule that produced it.
  /// Version 2 added the stylus gate and dropped the density conversion of version 1.
  static const int version = 2;

  /// The width at or above which a non-stylus contact is palm-like, in `AXIS_TOUCH_MAJOR` units.
  ///
  /// PROVENANCE — the number comes from the only separation ever measured here, the owner's run
  /// `bench-20261010T143629` on the reference device (SM-X806B): contacts the platform called
  /// fingers and that were admitted measured 13.0-15.0 of this unit, while the two palm-like
  /// contacts measured 86.0 and 91.0. 40 sits between the two populations with a factor of 2.7 of
  /// headroom above the widest admitted finger and 2.15 below the narrowest palm-like contact.
  ///
  /// NO DENSITY CONVERSION. Version 1 of this rule multiplied the threshold by the display density
  /// and called the result pixels, which asserted a physical meaning the number does not have. See
  /// [thresholdUnitEvidence]. This value is a device-calibrated axis value and is comparable only
  /// within one digitizer family; a different panel needs its own separation measured before this
  /// number is reused. That limitation is stated in every run's info file.
  static const double thresholdTouchMajor = 40.0;

  /// How long a stylus counts as "in play" after it was last seen, in milliseconds.
  ///
  /// A touch of palm-like width is rejected only inside this window. The window exists because the
  /// pen's own event stream is not continuous: it stops while the pen is lifted between strokes and
  /// between hover reports, and a palm that lands in one of those gaps is exactly the case the rule
  /// is for. A thousand milliseconds is a judgement, not a measurement: it is far longer than any
  /// gap between consecutive pen reports at 120 Hz, long enough to span a pen lift and a hand
  /// reposition mid-writing, and short enough that putting the pen down and drawing with a finger
  /// works within a second. It is reported in the info file so a run can be read against it.
  static const int stylusProximityWindowMs = 1000;

  /// What the threshold's unit is, in one line, for the screen and the artifact.
  static const String thresholdUnit =
      'MotionEvent.AXIS_TOUCH_MAJOR as the app sees it';

  /// The evidence for [thresholdUnit], measured on the reference device rather than assumed.
  ///
  /// `getevent -pl` on SM-X806B reports `ABS_MT_TOUCH_MAJOR: min 0, max 255` for `sec_touchscreen`
  /// while its positions run 0-1751 and 0-2799, and `dumpsys input` reports the range the app sees
  /// as `TOUCH_MAJOR: min 0.000, max 3302.954`, which is the panel diagonal in pixels
  /// (hypot(1752, 2800)). So Android rescales the raw 8-bit axis into display pixels, and the value
  /// is formally pixels.
  ///
  /// It is nevertheless NOT a physical contact width: a fingertip measured 13-15 of it, about one
  /// millimetre at 340 dpi, and the raw slots in `dumpsys input` hold values of 1 to 189 for
  /// ordinary touches. The digitizer's `TOUCH_MAJOR` behaves like a signal strength, not a
  /// diameter, so converting it into dp would invent a physical meaning. The separation between
  /// fingers and palms is real and reproducible; the absolute size is not, and the threshold is
  /// therefore validated for this device's digitizer only.
  static const String thresholdUnitEvidence =
      'getevent -pl: ABS_MT_TOUCH_MAJOR min 0 max 255 (positions 0-1751/0-2799); dumpsys input: '
      'app-visible TOUCH_MAJOR min 0.000 max 3302.954 = panel diagonal in px. Formally pixels, but '
      'a fingertip measures 13-15 and a 1 mm contact is impossible, so the value is a vendor '
      'signal, not a physical width. No density conversion is applied, and the threshold is '
      'validated for the reference device only.';

  /// Reason recorded when the platform itself classified the contact as a palm.
  static const String reasonPlatformPalm = 'platform-palm-tool-type';

  /// Reason recorded for a stylus or eraser contact, to which the width rule is never applied.
  static const String reasonStylus = 'stylus-tool';

  /// Reason recorded for a mouse or trackpad pointer.
  static const String reasonMouse = 'mouse-tool';

  /// Reason recorded for a non-stylus contact below the threshold.
  static const String reasonWidthBelowThreshold = 'width-below-threshold';

  /// Reason recorded for a palm-like-width contact rejected while a stylus was in play.
  static const String reasonPalmLikeWidth = 'palm-like-width';

  /// Reason recorded for a palm-like-width contact ADMITTED because no stylus was in play.
  ///
  /// This reason is the touch-parity guarantee made visible: the same wide contact that is a palm
  /// next to the pen is a finger when the pen is away, and the record says which of the two
  /// happened rather than leaving a bare `drawAdmitted: true`.
  static const String reasonPalmLikeWidthNoStylus = 'palm-like-width-no-stylus';

  /// The provenance of [thresholdTouchMajor], published into every run's info file.
  ///
  /// Kept as a constant rather than prose at the call site so the number and its justification
  /// cannot be separated: a reader who sees the threshold in an artifact sees where it came from in
  /// the same map.
  static const String provenance =
      'Not a platform constant: Android publishes no palm-width threshold and the digitizer axis '
      'is vendor-scaled. Chosen from the only measurement available, the owner run '
      'bench-20261010T143629 on SM-X806B, where admitted finger contacts measured 13.0-15.0 units '
      'and the two palm-like contacts measured 86.0 and 91.0. 40.0 sits between the two '
      'populations. Validated for that device only.';

  /// Whether [touchMajor] is palm-like against [thresholdTouchMajor].
  ///
  /// The comparison is inclusive (`>=`): a contact exactly at the threshold is palm-like, so the
  /// boundary itself is decided rather than left to whichever side a floating-point rounding lands.
  /// A non-finite width is never palm-like.
  static bool isPalmLikeWidth({
    required double touchMajor,
    required double thresholdTouchMajor,
  }) => touchMajor.isFinite && touchMajor >= thresholdTouchMajor;

  /// Decides whether a contact may draw, and names the inputs that decided it.
  ///
  /// The order of the tests is the order of the reasons. The platform's own classification wins
  /// over everything; a stylus or mouse is never subject to the width rule; and a palm-like width
  /// is rejected ONLY while [stylusInPlay] is true. That last condition is the touch-parity
  /// guarantee: with no pen in play this returns an admission for any finger, however wide.
  static PalmContactDecision decide({
    required InkPointerKind kind,
    required double touchMajor,
    required double thresholdTouchMajor,
    required bool stylusInPlay,
  }) {
    final bool palmLike = isPalmLikeWidth(
      touchMajor: touchMajor,
      thresholdTouchMajor: thresholdTouchMajor,
    );
    if (kind == InkPointerKind.palm) {
      return PalmContactDecision(
        admitted: false,
        reason: reasonPlatformPalm,
        palmLikeWidth: palmLike,
        decidingTouchMajor: touchMajor,
        thresholdTouchMajor: thresholdTouchMajor,
        stylusInPlay: stylusInPlay,
      );
    }
    if (kind == InkPointerKind.sPen || kind == InkPointerKind.sPenEraser) {
      return PalmContactDecision(
        admitted: true,
        reason: reasonStylus,
        palmLikeWidth: false,
        decidingTouchMajor: touchMajor,
        thresholdTouchMajor: thresholdTouchMajor,
        stylusInPlay: stylusInPlay,
      );
    }
    if (kind == InkPointerKind.mouse) {
      return PalmContactDecision(
        admitted: true,
        reason: reasonMouse,
        palmLikeWidth: false,
        decidingTouchMajor: touchMajor,
        thresholdTouchMajor: thresholdTouchMajor,
        stylusInPlay: stylusInPlay,
      );
    }
    if (palmLike && stylusInPlay) {
      return PalmContactDecision(
        admitted: false,
        reason: reasonPalmLikeWidth,
        palmLikeWidth: true,
        decidingTouchMajor: touchMajor,
        thresholdTouchMajor: thresholdTouchMajor,
        stylusInPlay: stylusInPlay,
      );
    }
    return PalmContactDecision(
      admitted: true,
      reason: palmLike
          ? reasonPalmLikeWidthNoStylus
          : reasonWidthBelowThreshold,
      palmLikeWidth: palmLike,
      decidingTouchMajor: touchMajor,
      thresholdTouchMajor: thresholdTouchMajor,
      stylusInPlay: stylusInPlay,
    );
  }
}

// PURPOSE: Carry one contact's admission decision together with the inputs to it, so a stroke
//          record can be audited without re-deriving the rule from a separate list of numbers.
// INPUTS: Built by [PalmWidthRule.decide]; the constructor is public so a test can build one.
// OUTPUTS: An immutable 6-field record. Every field is a scalar or a boolean: the reason is the
//          stable wire spelling, never a localised sentence.
// KEYWORDS: admission, decision, reason, touch-major, stylus-gate, audit-record
/// One contact's admission decision and the inputs behind it.
class PalmContactDecision {
  /// Creates a decision from already-computed values.
  const PalmContactDecision({
    required this.admitted,
    required this.reason,
    required this.palmLikeWidth,
    required this.decidingTouchMajor,
    required this.thresholdTouchMajor,
    required this.stylusInPlay,
  });

  /// Whether the surface may draw this contact.
  final bool admitted;

  /// Stable wire spelling of why: one of `PalmWidthRule.reason*`.
  final String reason;

  /// Whether [decidingTouchMajor] was at or above [thresholdTouchMajor].
  ///
  /// This is the width test alone and is independent of the gate: a wide finger drawn with no pen
  /// in play reports `palmLikeWidth: true` and `admitted: true` together, which is what makes the
  /// touch-parity case visible in the record.
  final bool palmLikeWidth;

  /// The touch-major value that was compared against [thresholdTouchMajor], in axis units.
  final double decidingTouchMajor;

  /// The threshold that was in force, in the same axis units.
  final double thresholdTouchMajor;

  /// Whether a stylus was in play when this contact arrived.
  final bool stylusInPlay;

  /// Stable one-line rendering for logs and the screen.
  @override
  String toString() =>
      '${admitted ? 'admitted' : 'rejected'} ($reason, '
      'touchMajor=${decidingTouchMajor.toStringAsFixed(1)}, '
      'threshold=${thresholdTouchMajor.toStringAsFixed(1)}, '
      'stylusInPlay=$stylusInPlay)';
}
