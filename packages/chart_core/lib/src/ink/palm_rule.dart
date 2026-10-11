// PURPOSE: Decide whether an input contact may lay down ink, from the numbers alone, so that the
//          web ink mode reads a finger's tap as a SELECTION while a stylus draws, and so a palm
//          resting on the glass while the pen writes does not leave a smear across a chart. It is a
//          pure predicate because the alternative — deciding inside the pointer handler that also
//          mutates the document and repaints — makes the rule impossible to check without a browser,
//          a tablet and a hand.
//
//          THE RULE USES EXACTLY TWO SIGNALS, and each rejection says WHICH signal fired. The two
//          are the pointer's own KIND (a stylus is not a finger; the browser tells us) and the
//          CONTACT WIDTH (a palm is far wider than a fingertip). The second is only consulted while
//          a stylus is in play, because touch parity outranks palm rejection: with no pen near the
//          glass a wide contact is a finger and draws, and a tap selects.
// INPUTS: The contact's [InkCaptureKind], its measured width in logical pixels, whether a stylus
//         has been seen inside the proximity window, and whether the ink mode is on.
// OUTPUTS: An [InkContactDecision] carrying `mayInk`, the stable reason token, and the inputs that
//          decided it. No input combination throws: a width that is negative, infinite or NaN is
//          never palm-like, because a number that was not measured must not reject a contact.
// KEYWORDS: ink, palm-rejection, contact-width, stylus-proximity, touch-parity, pure-predicate,
//           admission, instrumented-decision
//
// WHY THE WIDTH THRESHOLD IS 40 LOGICAL PIXELS AND WHERE IT COMES FROM.
//
// It is not a physical size and this file does not claim one. The only separation ever measured for
// the browser was recorded in the web pen spike on the owner's tablet: admitted finger contacts
// measured 1 to 8 of the browser's `width` field, while the two palm-like contacts in the run with
// no pen measured 71 and 87. Forty sits between the two populations with a factor of five of
// headroom above the widest finger. The unit is CSS pixels, which is Flutter's logical pixel here
// because the engine converts a pointer's position to logical pixels at the same point it reads the
// width, so the two are in one space. A DIFFERENT PANEL NEEDS ITS OWN SEPARATION MEASURED before
// this number is reused; the constant is stated rather than tuned.
//
// WHY THE PROXIMITY WINDOW IS ONE SECOND, AND WHAT IT ASSUMES.
//
// The stylus stream is not continuous: it stops between strokes and between hover reports, and a
// palm that lands in one of those gaps is exactly what the window is for. One second is a judgement,
// not a measurement: far longer than any gap between consecutive pen reports, long enough to span a
// pen lift and a hand reposition, and short enough that putting the pen down and deliberately
// drawing with a finger works within a second. It matches the window the Android palm rule uses, so
// the two platforms answer the same way to the same gesture.
/// Which physical pointer produced an input sample, as the capture layer classified it.
///
/// Deliberately NOT the engine's `PointerDeviceKind`: that type lives in `dart:ui` and this file is
/// pure Dart so the rule can be checked with `dart test`. The capture layer's job is to map the
/// platform's kind onto this one, and the mapping is a switch of four cases.
enum InkCaptureKind {
  /// A stylus in writing mode.
  stylus('stylus'),

  /// A stylus whose other end is down, i.e. the eraser.
  stylusEraser('stylusEraser'),

  /// A finger, or a palm the platform classified as a finger.
  finger('finger'),

  /// A mouse or trackpad pointer.
  mouse('mouse'),

  /// A pointer whose kind is none of the above.
  unknown('unknown');

  const InkCaptureKind(this.token);

  /// Stable spelling used in a log line and in a decision record.
  final String token;

  /// Whether this kind is a stylus in either orientation.
  ///
  /// A getter rather than a comparison at each call site, because the two stylus kinds are one
  /// concept everywhere the rule and the capture layer use it, and the eraser differs only in the
  /// tool the stroke is committed with.
  bool get isStylus =>
      this == InkCaptureKind.stylus || this == InkCaptureKind.stylusEraser;
}

// PURPOSE: Decide, from the numbers alone, whether a contact may lay down ink, and name the input
//          that decided it, so a log line can be audited against the rule instead of restating a
//          bare boolean.
// INPUTS: See [decide]; the width and the stylus fact are supplied by the caller rather than read
//         from a device, so the same arithmetic runs on synthetic widths in a test.
// OUTPUTS: An [InkContactDecision]. No input combination throws.
// KEYWORDS: palm-rule, threshold, provenance, admission-reason, stylus-gate, ink-mode-gate
/// The two-signal rule that decides whether a contact may ink or must select.
class InkPalmRule {
  const InkPalmRule._();

  /// Version of this rule. A change to the threshold, the comparison, the gates or the reason
  /// tokens bumps it, so a stored record can be read against the rule that produced it.
  static const int version = 1;

  /// The width at or above which a non-stylus contact is palm-like, in logical pixels.
  ///
  /// See the file header for where the number comes from and what it does NOT claim.
  static const double palmWidthThreshold = 40.0;

  /// How long a stylus counts as in play after it was last seen, in milliseconds.
  static const int stylusProximityWindowMs = 1000;

  /// Stable reason token: the ink mode is off, so nothing draws.
  static const String reasonInkModeOff = 'ink-mode-off';

  /// Stable reason token: a stylus contact, to which the width rule never applies.
  static const String reasonStylus = 'stylus-tool';

  /// Stable reason token: a mouse pointer, which never draws ink in this increment.
  static const String reasonMouse = 'mouse-tool';

  /// Stable reason token: a contact below the palm width threshold.
  static const String reasonWidthBelowThreshold = 'width-below-threshold';

  /// Stable reason token: a non-stylus contact whose width the platform never reported.
  ///
  /// **ADMITTED, AND THE SENTENCE THAT USED TO STAND HERE SAID THE OPPOSITE. It is corrected rather
  /// than deleted, because the reasoning is the interesting part and it was wrong on a real device.**
  /// What it said: an unmeasured width "cannot support the conclusion 'this may draw'", the cost of
  /// admitting is "a smear across the chart", and the cost of refusing is merely "a finger taps and
  /// selects, which is a feature and destroys nothing".
  ///
  /// **THE OWNER'S TABLET FALSIFIED THAT, and it falsified the whole trade.** His S Pen's touches
  /// arrive as `PointerDeviceKind.finger` with `width == 0`, so EVERY PEN CONTACT ON EVERY SCREEN
  /// LANDED HERE AND WAS REFUSED — silently. He reported it as "рисует сейчас через раз" and then as
  /// "на всём экране", and the app's own log named the reason while saying nothing to him:
  /// `ink.contact.down ... no-ink reason=width-not-reported kind=finger width=0.0`.
  ///
  /// The trade was priced wrongly, and that is the lesson worth keeping. A wrong stroke is VISIBLE,
  /// ATTRIBUTABLE and ERASABLE — the musician sees it, knows he did not write it, and removes it. A
  /// refused stroke is INVISIBLE: nothing appears, nothing is said, and the tool reads as broken. The
  /// cost of refusing was written down as "destroys nothing", and in fact it destroys the only
  /// question that matters, which is whether the pen works at all. **Fail open, because a failure
  /// nobody can see cannot be diagnosed by the person suffering it.**
  ///
  /// The palm protection this token sat behind is NOT weakened: a contact whose width IS measured and
  /// is palm-like while a stylus is in play is still refused, and that is where a real palm lands —
  /// the spike on this tablet measured palms at 71 and 87 logical pixels.
  static const String reasonWidthNotReported = 'width-not-reported';

  /// Stable reason token: a palm-like contact refused while a stylus was in play.
  static const String reasonPalmLikeWidth = 'palm-like-width';

  /// Stable reason token: a palm-like contact admitted because no stylus was in play.
  ///
  /// A separate token from [reasonWidthBelowThreshold] on purpose: a wide finger that drew with the
  /// pen put away is the touch-parity case made visible, and a reader of the log must be able to
  /// tell it from an ordinary narrow finger without re-deriving the comparison.
  static const String reasonPalmLikeWidthNoStylus = 'palm-like-width-no-stylus';

  /// Whether [width] is palm-like against [palmWidthThreshold].
  ///
  /// The comparison is inclusive, so a contact exactly at the threshold is palm-like and the
  /// boundary itself is decided rather than left to rounding. A non-finite width is never palm-like.
  static bool isPalmLikeWidth(double width) =>
      width.isFinite && width >= palmWidthThreshold;

  // PURPOSE: Answer whether one contact may lay down ink, and why.
  // INPUTS: kind — the pointer's kind. width — the contact's width in logical pixels, or 0 when the
  //         platform reported none. stylusInPlay — whether a stylus was seen inside the proximity
  //         window. inkModeOn — whether the musician has turned ink on.
  // OUTPUTS: A decision. The order of the tests is the order of the reasons: the mode gate first,
  //          because with ink off a stylus selects like a finger; then the stylus, which is never
  //          subject to the width rule; then the mouse; then the unmeasured width, refused; then the
  //          palm-like width, refused only while a stylus is in play. A contact with a measured width
  //          below the threshold draws, and a palm-like one with no pen in play draws too, each with
  //          the reason that names which of the two it was.
  // KEYWORDS: admission, reason-order, stylus-gate, touch-parity, unmeasured-width, no-throw
  /// Returns the decision for one contact.
  static InkContactDecision decide({
    required InkCaptureKind kind,
    required double width,
    required bool stylusInPlay,
    required bool inkModeOn,
  }) {
    final bool palmLike = isPalmLikeWidth(width);
    final bool widthMeasured = width.isFinite && width > 0;
    InkContactDecision build({required bool mayInk, required String reason}) =>
        InkContactDecision(
          mayInk: mayInk,
          reason: reason,
          kind: kind,
          decidingWidth: width,
          palmLikeWidth: palmLike,
          stylusInPlay: stylusInPlay,
          inkModeOn: inkModeOn,
        );

    if (!inkModeOn) {
      return build(mayInk: false, reason: reasonInkModeOff);
    }
    if (kind.isStylus) {
      return build(mayInk: true, reason: reasonStylus);
    }
    if (kind == InkCaptureKind.mouse) {
      return build(mayInk: false, reason: reasonMouse);
    }
    // What is left is a finger, a palm the platform called a finger, or a kind this build does not
    // know. All three are subject to the same two signals.
    //
    // AN UNMEASURED WIDTH ADMITS. It used to refuse, and on the owner's tablet that refused EVERY
    // PEN CONTACT he made, because his S Pen arrives as a pointer kind of `finger` with no width. He
    // reported it first as "рисует сейчас через раз" and then as "на всём экране", while the app's
    // log named the reason and said nothing to him. Refusing is the one failure a musician cannot
    // see, cannot attribute and cannot report as anything but "the pen is broken", so the doubt
    // resolves toward drawing. `reasonWidthNotReported` carries the full correction, and the PALM
    // half below is untouched: a measured, palm-like contact while a stylus is in play is still
    // refused, and that is where a real palm lands.
    if (!widthMeasured) {
      return build(mayInk: true, reason: reasonWidthNotReported);
    }
    if (palmLike && stylusInPlay) {
      return build(mayInk: false, reason: reasonPalmLikeWidth);
    }
    return build(
      mayInk: true,
      reason: palmLike
          ? reasonPalmLikeWidthNoStylus
          : reasonWidthBelowThreshold,
    );
  }
}

/// What the rule decided about one contact, with the inputs that decided it.
///
/// The inputs travel with the verdict because a bare `mayInk` boolean cannot be checked: it says
/// what happened and not which number caused it, so a wide contact that drew could only be found by
/// digging through a width list afterwards. Carrying them makes the log line and the rule one
/// record.
class InkContactDecision {
  /// Creates a decision from already-computed values.
  const InkContactDecision({
    required this.mayInk,
    required this.reason,
    required this.kind,
    required this.decidingWidth,
    required this.palmLikeWidth,
    required this.stylusInPlay,
    required this.inkModeOn,
  });

  /// Whether the contact may lay down ink. False means it selects, pans or is ignored.
  final bool mayInk;

  /// Stable token naming why, one of the `InkPalmRule.reason*` constants or the kind tokens.
  final String reason;

  /// The kind the contact was classified as.
  final InkCaptureKind kind;

  /// The width that was compared against the threshold, in logical pixels.
  final double decidingWidth;

  /// Whether [decidingWidth] was at or above the threshold, independent of the gate.
  ///
  /// True together with `mayInk` for a wide finger admitted with no pen in play, which is what makes
  /// the touch-parity case visible in the record rather than indistinguishable from a narrow finger.
  final bool palmLikeWidth;

  /// Whether a stylus was in play when the contact arrived.
  final bool stylusInPlay;

  /// Whether the ink mode was on when the contact arrived.
  final bool inkModeOn;

  /// The decision as one key-value line, for a log that can be parsed and diffed.
  @override
  String toString() =>
      '${mayInk ? 'ink' : 'no-ink'} reason=$reason kind=${kind.token} '
      'width=${decidingWidth.toStringAsFixed(1)} '
      'palm_like=$palmLikeWidth stylus_in_play=$stylusInPlay ink_on=$inkModeOn';
}
