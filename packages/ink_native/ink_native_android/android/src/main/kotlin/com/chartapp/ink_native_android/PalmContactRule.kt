// PURPOSE: Decide whether one contact may draw, from the platform's own classification, its
//          measured touch-major value and whether a stylus is in play, and carry the inputs that
//          decided it back to Dart. It exists because the old surface's only palm test was
//          `MotionEvent.TOOL_TYPE_PALM` — an invisible platform constant — so a 91-unit-wide
//          contact the platform called a finger was drawn as ink and nothing said why.
//
//          THE GATE IS THE POINT. A palm-like width is rejected only while a stylus is in play, so
//          a finger draws however wide it is when no pen has been seen. Touch parity is a product
//          decision that outranks palm rejection.
// INPUTS: The pointer kind the tool type mapped to, the contact's `AXIS_TOUCH_MAJOR` value, the
//         threshold in those same units, and whether a stylus was in play.
// OUTPUTS: An [Admission] naming the outcome, the stable reason spelling, and the inputs. Never
//          throws; a non-finite width is never palm-like.
// KEYWORDS: palm-rejection, touch-major, threshold, admission-reason, stylus-gate, touch-parity
package com.chartapp.ink_native_android

/**
 * The rule that decides whether a contact is treated as a palm.
 *
 * This is a deliberate second implementation of `PalmWidthRule` in the Dart platform interface,
 * because the drawing decision has to be taken on the UI thread where the events are. The two are
 * kept honest not by discipline but by measurement: the surface reports [Admission.reason],
 * [Admission.decidingTouchMajor], [Admission.thresholdTouchMajor] and [Admission.stylusInPlay] with
 * every stroke, and the bench re-runs the Dart predicate on those numbers and reports every
 * disagreement.
 *
 * The threshold, the window and the evidence for the unit are documented on the Dart
 * `PalmWidthRule`; the values below must equal them.
 */
object PalmContactRule {
    /** Version of this rule; a change to the threshold, the gate or the reasons bumps it. */
    const val VERSION: Int = 2

    /**
     * The value at or above which a non-stylus contact is palm-like, in `AXIS_TOUCH_MAJOR` units.
     *
     * PROVENANCE — not a platform constant: Android publishes none, and the axis is vendor-scaled,
     * so the value comes from the owner's SM-X806B run (`bench-20261010T143629`), where admitted
     * finger contacts measured 13.0-15.0 units and the two palm-like contacts measured 86.0 and
     * 91.0. 40.0 sits between those populations.
     *
     * NOT density-scaled. The unit is `AXIS_TOUCH_MAJOR` as the app sees it: Android's declared
     * range for this panel is 0..3302.954 px (the diagonal) while the kernel axis is 0..255, yet a
     * fingertip measures 13-15, which cannot be a physical width. Converting through the display
     * density would invent a physical meaning the number does not have, so the threshold is a
     * device-calibrated axis value, validated for this digitizer family only.
     */
    const val THRESHOLD_TOUCH_MAJOR: Double = 40.0

    /**
     * How long a stylus counts as in play after the surface last saw one, in milliseconds.
     *
     * The pen's event stream is not continuous — it stops while the pen is lifted between strokes
     * and between hover reports — and a palm that lands in one of those gaps is the case this rule
     * is for. A thousand milliseconds is a judgement: far longer than any gap between pen reports
     * at 120 Hz, long enough to span a pen lift mid-writing, and short enough that switching to a
     * finger works within a second.
     */
    const val STYLUS_PROXIMITY_WINDOW_MS: Long = 1000L

    /** Reason recorded when the platform itself classified the contact as a palm. */
    const val REASON_PLATFORM_PALM: String = "platform-palm-tool-type"

    /** Reason recorded for a stylus or eraser contact, to which the width rule is never applied. */
    const val REASON_STYLUS: String = "stylus-tool"

    /** Reason recorded for a mouse or trackpad pointer. */
    const val REASON_MOUSE: String = "mouse-tool"

    /** Reason recorded for a non-stylus contact below the threshold. */
    const val REASON_WIDTH_BELOW_THRESHOLD: String = "width-below-threshold"

    /** Reason recorded for a palm-like-width contact rejected while a stylus was in play. */
    const val REASON_PALM_LIKE_WIDTH: String = "palm-like-width"

    /** Reason recorded for a palm-like-width contact admitted because no stylus was in play. */
    const val REASON_PALM_LIKE_WIDTH_NO_STYLUS: String = "palm-like-width-no-stylus"

    /**
     * Whether [touchMajor] is palm-like against [thresholdTouchMajor].
     *
     * Inclusive, so the boundary is decided rather than left to a rounding direction; a non-finite
     * value is never palm-like.
     */
    fun isPalmLikeWidth(touchMajor: Double, thresholdTouchMajor: Double): Boolean =
        touchMajor.isFinite() && touchMajor >= thresholdTouchMajor

    /**
     * Decides whether a contact may draw, and names the inputs that decided it.
     *
     * The platform's classification wins over everything; a stylus or mouse is never subject to the
     * width rule; and a palm-like width is rejected ONLY while [stylusInPlay] is true, which is the
     * touch-parity guarantee.
     */
    fun decide(
        kind: InkPointerKind,
        touchMajor: Double,
        thresholdTouchMajor: Double,
        stylusInPlay: Boolean,
    ): Admission {
        val palmLike = isPalmLikeWidth(touchMajor, thresholdTouchMajor)
        if (kind == InkPointerKind.PALM) {
            return Admission(false, REASON_PLATFORM_PALM, palmLike, touchMajor, thresholdTouchMajor, stylusInPlay)
        }
        if (kind == InkPointerKind.S_PEN || kind == InkPointerKind.S_PEN_ERASER) {
            return Admission(true, REASON_STYLUS, false, touchMajor, thresholdTouchMajor, stylusInPlay)
        }
        if (kind == InkPointerKind.MOUSE) {
            return Admission(true, REASON_MOUSE, false, touchMajor, thresholdTouchMajor, stylusInPlay)
        }
        if (palmLike && stylusInPlay) {
            return Admission(
                admitted = false,
                reason = REASON_PALM_LIKE_WIDTH,
                palmLikeWidth = true,
                decidingTouchMajor = touchMajor,
                thresholdTouchMajor = thresholdTouchMajor,
                stylusInPlay = true,
            )
        }
        return Admission(
            admitted = true,
            reason = if (palmLike) REASON_PALM_LIKE_WIDTH_NO_STYLUS else REASON_WIDTH_BELOW_THRESHOLD,
            palmLikeWidth = palmLike,
            decidingTouchMajor = touchMajor,
            thresholdTouchMajor = thresholdTouchMajor,
            stylusInPlay = stylusInPlay,
        )
    }

    /** One contact's admission decision and the inputs to it. */
    data class Admission(
        /** Whether the contact may be drawn. */
        val admitted: Boolean,
        /** Stable wire spelling of why. */
        val reason: String,
        /** Whether the compared value was at or above the threshold. */
        val palmLikeWidth: Boolean,
        /** The `AXIS_TOUCH_MAJOR` value that was compared, in axis units. */
        val decidingTouchMajor: Double,
        /** The threshold in force, in the same units, when the comparison was made. */
        val thresholdTouchMajor: Double,
        /** Whether a stylus was in play when the comparison was made. */
        val stylusInPlay: Boolean,
    )
}
