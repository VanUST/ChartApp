// PURPOSE: Define the value types that cross the Dart/native boundary for ink, so that the
//          three platform implementations and the app agree on what a tool, a transform, a
//          stored stroke, a committed stroke, a latency measurement and a contact-admission
//          decision are, and a change to one of them is a compile error in all of them rather
//          than a silent mismatch at runtime.
// INPUTS: None; these are plain immutable values.
// OUTPUTS: Immutable objects with value equality is NOT provided — identity is by reference —
//          so an instance is compared only after conversion at the boundary.
// KEYWORDS: ink-tool, view-transform, stroke-blob, committed-stroke, latency-sample,
//           palm-observation, value-types
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

/// The drawing tool the ink surface is currently using.
///
/// Mirrors the INK state of the editor's tool state machine. The eraser is a tool rather than a
/// gesture so that the same finger or stylus motion means the same thing in every mode.
enum InkTool {
  /// Fine opaque ink.
  pen,

  /// Wide translucent ink, drawn beneath the pen layer.
  highlighter,

  /// Removes whole strokes rather than pixels, so erasing is reversible by data.
  eraser,
}

/// The scroll and zoom mapping shared by the chart canvas and the ink overlay.
///
/// This is the scroll/zoom subset of the full view matrix: uniform [scale] followed by a
/// [translation]. Only that subset is expressible, which is deliberate — a rotation or a skew
/// applied to one layer but not the other would put the ink and the chords in different places,
/// and a type that cannot represent that state cannot reach it by accident.
class InkViewTransform {
  /// Creates a transform from a uniform [scale] and a [translation] in logical pixels.
  const InkViewTransform({required this.scale, required this.translation});

  /// The identity transform: no zoom, no pan.
  static const InkViewTransform identity = InkViewTransform(
    scale: 1,
    translation: Offset.zero,
  );

  /// Uniform zoom factor; 1 means the chart is drawn at its natural size.
  final double scale;

  /// Pan offset in logical pixels, applied after scaling.
  final Offset translation;
}

/// One stored stroke, in the coordinates of the anchor it was captured against.
///
/// The bytes are in the native format named by [format] — PencilKit's archive on iOS, the
/// InkView serialisation on Android. The plugin deliberately does not define a portable stroke
/// format: the native engines replay their own formats at the latency this project is built
/// around, and a translation layer would be on the critical path of every stroke.
class InkStrokeBlob {
  /// Creates a blob for stroke [id], anchored by [anchor], encoded in [format].
  const InkStrokeBlob({
    required this.id,
    required this.anchor,
    required this.format,
    required this.bytes,
  });

  /// Stable identifier of this stroke, unique within a document.
  final String id;

  /// The anchor this stroke was captured against, as the anchor object of the document model:
  /// a section, bar and beat, plus an optional step. It is carried as a map rather than as a
  /// domain type because this package must not depend on the chart domain — the app computes
  /// the anchor, and this interface only transports it.
  ///
  /// Coordinates inside [bytes] are anchor-local, which is what lets a stroke survive
  /// transposition and reflow: when the anchor moves, the stroke moves with it and its own
  /// geometry is unchanged.
  final Map<String, Object?> anchor;

  /// Native encoding of [bytes], e.g. `pencilkit` or `inkview`.
  final String format;

  /// The encoded stroke.
  final Uint8List bytes;
}

/// A stroke the native surface has just finished drawing.
///
/// The native side reports only where the stroke landed, not what it means: the app turns the
/// bounding box centre into a document anchor. Keeping that decision on the Dart side is what
/// lets the anchoring rule change without a native release.
class CommittedStroke {
  /// Creates a report for stroke [blobId] whose bounding box has centre [bboxCenter].
  const CommittedStroke({
    required this.blobId,
    required this.bboxCenter,
    required this.bboxSize,
  });

  /// Identifier of the stroke that was committed, matching the blob later returned by
  /// `exportStrokes`.
  final String blobId;

  /// Centre of the stroke's bounding box, in document coordinates.
  final Offset bboxCenter;

  /// Size of the stroke's bounding box, in document coordinates.
  final Size bboxSize;
}

/// Which physical pointer produced an input sample.
///
/// [wireName] is the value written to a bench log as `pointerType` and the value the owner
/// compares against a threshold, so the two spellings the acceptance protocol uses (`sPen` and
/// `finger`) are fixed here rather than by whichever implementation happens to emit them.
enum InkPointerKind {
  /// A stylus in writing mode. The 45 ms p95 Android budget is written against this kind.
  sPen('sPen'),

  /// A stylus in eraser mode, i.e. the digitizer reports the raw tool type for an eraser. Kept
  /// separate from [sPen] because the eraser is a different tool on the digitizer and its
  /// latency is not what the pen budget was measured against.
  sPenEraser('sPenEraser'),

  /// A finger or palm contact the platform classified as a finger. The 60 ms p95 budget is
  /// written against this kind.
  finger('finger'),

  /// A contact the platform itself classified as a palm. Whether this kind ever appears is the
  /// observation palm rejection is judged by: an empty count means the digitizer or the
  /// platform removed the palm before the app saw it, not that the app suppressed it.
  palm('palm'),

  /// A mouse or trackpad pointer.
  mouse('mouse'),

  /// A pointer whose tool type is none of the above.
  unknown('unknown');

  /// Creates the kind whose log spelling is [wireName].
  const InkPointerKind(this.wireName);

  /// Stable spelling used in bench logs and on screen.
  final String wireName;

  /// Looks up the kind spelled [name], falling back to [unknown].
  ///
  /// A fallback rather than a throw: an implementation that reports a pointer kind this version
  /// does not know about must still produce a usable run, and counting the unknown pointer
  /// separately is the honest outcome.
  static InkPointerKind fromWireName(String? name) {
    for (final InkPointerKind kind in InkPointerKind.values) {
      if (kind.wireName == name) {
        return kind;
      }
    }
    return InkPointerKind.unknown;
  }
}

/// Where the presentation timestamp of a frame came from.
///
/// This is carried with every sample because it changes what the number means, and a reader who
/// cannot see which source produced a p95 cannot tell a measurement from an estimate.
enum InkPresentationSource {
  /// The display pipeline's own frame timeline: the preferred frame's
  /// `getExpectedPresentationTimeNanos` from `Choreographer.postVsyncCallback`, public API 33.
  /// This is the platform's estimate of when the frame reaches the display, not a clock
  /// arithmetic the app performed.
  frameTimeline('frameTimeline'),

  /// `frameTimeNanos` plus one vsync interval, used when the frame timeline is unavailable
  /// (Android 12 and below). This is a LOWER BOUND on presentation: it assumes the buffer the
  /// app produces in this frame is presented at the next vsync and that no frame was missed,
  /// so it under-states latency whenever composition slips a frame.
  vsyncPlusDelay('vsyncPlusDelay');

  /// Creates the source whose log spelling is [wireName].
  const InkPresentationSource(this.wireName);

  /// Stable spelling used in bench logs and on screen.
  final String wireName;

  /// Looks up the source spelled [name].
  ///
  /// Falls back to [vsyncPlusDelay] because that is the weaker claim: a report that cannot say
  /// where a timestamp came from must not claim it came from the display pipeline.
  static InkPresentationSource fromWireName(String? name) {
    for (final InkPresentationSource source in InkPresentationSource.values) {
      if (source.wireName == name) {
        return source;
      }
    }
    return InkPresentationSource.vsyncPlusDelay;
  }
}

/// One drawn input sample and the time it became visible.
///
/// A sample is one point of the digitizer stream, including the coalesced samples a single
/// motion event carries in its history. Reporting per sample rather than per stroke is
/// deliberate: it is what makes a dropped coalesced sample visible as a smaller count instead
/// of as a quietly better average.
class InkLatencySample {
  /// Creates a sample measurement.
  const InkLatencySample({
    required this.strokeId,
    required this.sampleIndex,
    required this.pointerKind,
    required this.presentationSource,
    required this.touchToPresentMs,
    required this.eventTimeNanos,
    required this.presentTimeNanos,
    required this.pressure,
    required this.tiltRadians,
    required this.orientationRadians,
    required this.touchMajorPx,
    required this.isHistorical,
    required this.eventAction,
    required this.sourceIsStylus,
    required this.rawToolType,
    required this.rawSource,
    required this.x,
    required this.y,
  });

  /// Identifier of the stroke this sample belongs to, unique within a run.
  final int strokeId;

  /// Zero-based position of this sample within its stroke, counting historical samples.
  final int sampleIndex;

  /// Which pointer produced it.
  final InkPointerKind pointerKind;

  /// Which clock produced [presentTimeNanos].
  final InkPresentationSource presentationSource;

  /// The measurement: milliseconds from the sample's event time to the time the frame carrying
  /// it was expected to be presented. This is the value written as `touchToPresentMs`.
  final double touchToPresentMs;

  /// The sample's event time, already converted into the frame clock's time base.
  final int eventTimeNanos;

  /// The frame's expected presentation time, in nanoseconds.
  final int presentTimeNanos;

  /// Normalized pressure as the platform reported it, typically `[0, 1]`.
  final double pressure;

  /// Tilt from the surface normal in radians, as the tilt axis reports it.
  final double tiltRadians;

  /// Pointer orientation in radians, as the orientation axis reports it.
  final double orientationRadians;

  /// Contact major axis length in surface pixels, as the touch-major axis reports it. This is
  /// the number that distinguishes an uncrushed palm from a fingertip when the platform
  /// classified a palm contact as a finger.
  final double touchMajorPx;

  /// True when the sample came from the motion event's historical queue rather than from the
  /// current pointer position. A run whose samples are all non-historical means coalescing was
  /// not exercised and the drawing path accepted only one point per event.
  final bool isHistorical;

  /// The motion event action this sample arrived under: `down`, `move`, `up`, `cancel`, or
  /// `pointerDown`/`pointerUp` for a secondary pointer.
  final String eventAction;

  /// Whether the raw input device source carried the stylus source flag. Reported next to
  /// [pointerKind] because the two can disagree and the disagreement is the finding.
  final bool sourceIsStylus;

  /// The raw tool type the digitizer reported, so an unexpected classification can be traced
  /// back to that number rather than to this package's mapping of it.
  final int rawToolType;

  /// The raw input device source value.
  final int rawSource;

  /// Sample position in surface-local pixels, after the view transform was removed.
  final double x;

  /// Sample position in surface-local pixels, after the view transform was removed.
  final double y;
}

/// What the surface observed about one stroke's contact geometry, for judging palm rejection.
///
/// Palm rejection is reported as an observation and never as a verdict: the app cannot see the
/// events a digitizer removed before delivering them, so the only honest statement is what
/// arrived and what the surface did with it.
///
/// The admission fields were added together because a bare [drawAdmitted] boolean cannot be
/// checked: it says what happened but not which number caused it, so a contact of palm-like width
/// that was admitted could only be found by digging through the width list afterwards. With them,
/// every stroke carries the reason, the compared width, the threshold it was compared against, the
/// width result and whether a stylus was in play, and the bench re-runs the `PalmWidthRule.decide`
/// predicate on the reported numbers to check that the documented rule and the native decision
/// agree.
class InkPalmObservation {
  /// Creates an observation for one stroke.
  const InkPalmObservation({
    required this.strokeId,
    required this.pointerKind,
    required this.eventCount,
    required this.maxTouchMajorPx,
    required this.meanTouchMajorPx,
    required this.rawToolType,
    required this.drawAdmitted,
    required this.concurrentPointerSamples,
    required this.concurrentMaxTouchMajorPx,
    required this.admissionReason,
    required this.palmLikeWidth,
    required this.decidingTouchMajor,
    required this.palmWidthThreshold,
    required this.stylusInPlay,
  });

  /// Identifier of the stroke this observation belongs to.
  final int strokeId;

  /// Kind the surface assigned to the contact that owned this stroke.
  final InkPointerKind pointerKind;

  /// Number of input samples in the stroke.
  final int eventCount;

  /// Largest touch-major value seen in the stroke, in `AXIS_TOUCH_MAJOR` units.
  ///
  /// The `Px` suffix is inherited from the field's first version and is not a claim of physical
  /// size: `PalmWidthRule.thresholdUnitEvidence` records why the value cannot be read as a
  /// contact diameter and must not be converted through the display density.
  final double maxTouchMajorPx;

  /// Mean touch-major value seen in the stroke, in the same units as [maxTouchMajorPx].
  final double meanTouchMajorPx;

  /// The raw tool type of the owning pointer.
  final int rawToolType;

  /// True when the stroke was allowed to draw, false when the surface suppressed it. A
  /// suppressed observation is evidence the surface did something; an absent one is not
  /// evidence that the digitizer sent nothing.
  final bool drawAdmitted;

  /// How many contact samples were observed from pointers that did NOT own this stroke while it
  /// was being drawn. This is the field that answers "what happens when a palm rests on the
  /// surface while the pen draws": a non-zero count with a large
  /// [concurrentMaxTouchMajorPx] is a palm that reached the app and was ignored.
  final int concurrentPointerSamples;

  /// Largest touch-major value among the non-owning contacts counted by
  /// [concurrentPointerSamples], in the same units as [maxTouchMajorPx], or 0 when there were none.
  final double concurrentMaxTouchMajorPx;

  /// Stable wire spelling of why the contact was admitted or rejected.
  ///
  /// One of the `PalmWidthRule.reason*` constants: `platform-palm-tool-type`, `stylus-tool`,
  /// `mouse-tool`, `width-below-threshold`, `palm-like-width` or `palm-like-width-no-stylus`. A
  /// string rather than an enum because a surface built against a newer rule must still describe
  /// itself to an older reader, and an unrecognised reason is then visibly unrecognised instead of
  /// mapped to a neighbour.
  final String admissionReason;

  /// Whether [decidingTouchMajor] was at or above [palmWidthThreshold].
  ///
  /// This is the width test alone: it is true for a wide finger that was admitted because no stylus
  /// was in play, which is what makes the touch-parity case visible. Reported by the surface; the
  /// bench recomputes it with `PalmWidthRule.isPalmLikeWidth` and reports any disagreement, so this
  /// field is checkable rather than trusted.
  final bool palmLikeWidth;

  /// The touch-major value that the surface compared against [palmWidthThreshold], in
  /// `AXIS_TOUCH_MAJOR` units. For a decision taken at pointer-down this is the down sample's
  /// value; [maxTouchMajorPx] is the whole stroke's maximum and may be larger.
  final double decidingTouchMajor;

  /// The palm-width threshold in force, in the same units as [decidingTouchMajor], when this
  /// stroke was decided.
  ///
  /// Carried per stroke rather than only once per run so a decision can never be read against a
  /// threshold from a different moment or a different surface.
  final double palmWidthThreshold;

  /// Whether a stylus was in play when this contact was decided.
  ///
  /// Reported rather than re-derived on the Dart side because the proximity window is a property of
  /// the surface's own event stream. It is the second half of the admission rule: a palm-like width
  /// is only rejected while this is true.
  final bool stylusInPlay;
}

// PURPOSE: Describe the ink surface this bench is running on, so a run's artifact records what
//          produced its numbers: the platform view mode, the presentation clock, the display,
//          and the palm-width rule in force.
// INPUTS: None; every field is read from the surface.
// OUTPUTS: A description object. Fields the surface could not read are reported as zero or an
//          empty string, never as a plausible default, so "not measured" stays distinguishable
//          from "measured as zero".
// KEYWORDS: surface-description, provenance, measurement-limits, palm-rule, bench
/// What a native surface is actually measuring, read once per bench run.
///
/// The bench prints this above the numbers because the same p95 means different things on a
/// device whose frame timeline is available and on one measuring a lower bound.
class InkSurfaceInfo {
  /// Creates a description of the surface.
  const InkSurfaceInfo({
    required this.platformViewMode,
    required this.presentationSource,
    required this.apiLevel,
    required this.refreshRateHz,
    required this.clockOffsetMs,
    required this.clockOffsetDriftMs,
    required this.deviceModel,
    required this.androidRelease,
    required this.eventTimePrecision,
    required this.usedTimelinePoster,
    required this.displayDensity,
    required this.palmWidthThreshold,
    required this.palmStylusProximityWindowMs,
    required this.stylusHoverEventCount,
  });

  /// How the native view reaches Flutter: `hybridComposition` is a real view in the Android
  /// hierarchy, `virtualDisplay` is a rendered texture, and `none` means no native surface.
  final String platformViewMode;

  /// Which clock the surface can read for a frame's presentation time.
  final InkPresentationSource presentationSource;

  /// Android API level of the running device, or 0 when unknown.
  final int apiLevel;

  /// The device model as the build reports it, or an empty string when unknown.
  ///
  /// Carried because a bench number is only meaningful next to the hardware that produced it, and
  /// the reference device for the ink thresholds is a specific one.
  final String deviceModel;

  /// The Android release string, e.g. `12`, or an empty string when unknown.
  ///
  /// Reported next to [apiLevel] because the API level decides which presentation clock is
  /// available and the release string is what a human checks the device against.
  final String androidRelease;

  /// The resolution of the input timestamps: `nanosecond` or `millisecond`.
  ///
  /// Worth a field of its own because a millisecond stamp quantises every sample by up to half a
  /// millisecond, which is small against a 45 ms budget but is a floor on what any measurement on
  /// that device can resolve. `MotionEvent.getEventTimeNanos` is public only from API 34, so this
  /// is `millisecond` on Android 13 and below.
  final String eventTimePrecision;

  /// Whether a frame-timeline poster was installed at all, as opposed to falling back.
  ///
  /// Distinguished from [presentationSource], which reports the clock the last frame actually used:
  /// a poster can be installed and still fall back per frame when the platform reports no usable
  /// timeline for it.
  final bool usedTimelinePoster;

  /// The display's refresh rate in Hz, or 0 when unknown. Measured at the surface, not read
  /// from a setting, because a 60 Hz panel makes the 45 ms budget unmeasurable.
  final double refreshRateHz;

  /// The offset measured between the digitizer's clock and the frame clock, in milliseconds. A
  /// value near zero confirms the two share an origin, which is what makes subtracting them
  /// meaningful; a large value would mean the surface corrected a real difference rather than
  /// assuming one away.
  final double clockOffsetMs;

  /// Largest change in [clockOffsetMs] observed since the surface started, in milliseconds. It
  /// is reported so a drifting clock is visible rather than silently folded into the latency.
  final double clockOffsetDriftMs;

  /// The display density the surface reports (`Resources.getDisplayMetrics().density`), or 0 when
  /// it could not be read.
  ///
  /// Carried as a fact about the device, and deliberately NOT used to convert the palm rule's
  /// threshold: version 1 of that rule multiplied the threshold by this number and called the
  /// result pixels, which asserted a physical size the touch-major value does not have. See
  /// `PalmWidthRule.thresholdUnitEvidence`.
  final double displayDensity;

  /// The palm-width threshold as the surface computed it, in `AXIS_TOUCH_MAJOR` units, or 0 when
  /// there is no surface.
  ///
  /// Reported on the surface description as well as per observation so a run in which no contact
  /// was ever palm-like still states the threshold it was judged by; a rule nobody can see is a
  /// rule nobody can check.
  final double palmWidthThreshold;

  /// How long, in milliseconds, a stylus counts as in play after the surface last saw one, as the
  /// surface applies it, or 0 when there is no surface.
  ///
  /// The other half of the admission rule: a palm-like width is rejected only inside this window,
  /// so reporting it is what lets a reader tell a rejection that was gated from one that was not.
  final int palmStylusProximityWindowMs;

  /// How many hover events the surface received, or 0 when there is no surface.
  ///
  /// Hover is where the gate learns that a pen is near the glass without it touching, so a zero
  /// here on a run made with a pen in hand means the proximity signal never reached the view and
  /// the gate was open only during and just after pen strokes. Reporting the count is what makes
  /// that difference measurable instead of a guess.
  final int stylusHoverEventCount;
}
