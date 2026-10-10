// PURPOSE: Hold the small value types the Android ink surface passes around internally and hands
//          to the plugin — the drawing tool, the classification of a physical pointer, one drawn
//          input sample, one stroke, and one palm observation. They live in their own file so
//          that the pointer classification and the sample record can be read and reasoned about
//          without reading the View that produces them.
// INPUTS: None; these are constructors and enums.
// OUTPUTS: Immutable-ish holders. InkStrokeRecord owns a mutable point list because samples are
//          appended as frames close; every other type is read-only after construction.
// KEYWORDS: ink-android, pointer-classification, latency-sample, stroke-record, palm-observation
package com.chartapp.ink_native_android

import android.view.MotionEvent

/** The drawing tool, mirroring the Dart `InkTool` enum one-for-one. */
enum class InkToolKind {
    /** Fine opaque ink. */
    PEN,

    /** Wide translucent ink. */
    HIGHLIGHTER,

    /** Removes whole strokes rather than pixels. */
    ERASER,
    ;

    companion object {
        /** Maps the wire spelling used over the method channel onto the enum. */
        fun fromWireName(name: String?): InkToolKind = when (name) {
            "highlighter" -> HIGHLIGHTER
            "eraser" -> ERASER
            else -> PEN
        }
    }
}

// PURPOSE: Classify a contact into the pointer kind a latency budget is written against, and
//          give that kind the exact spelling the bench log and the acceptance protocol use.
// INPUTS: MotionEvent.getToolType of the owning pointer.
// OUTPUTS: One of six kinds. An unrecognised tool type maps to UNKNOWN rather than to FINGER,
//          because silently counting an unidentified pointer against the finger budget would
//          make an unknown device look like a slow finger.
// KEYWORDS: tool-type, pointer-kind, stylus, finger, palm, classification
enum class InkPointerKind(
    /** Stable spelling written to the bench log as `pointerType`. */
    val wireName: String,
) {
    /** Stylus in writing mode; the 45 ms p95 Android budget is written against this kind. */
    S_PEN("sPen"),

    /** Stylus in eraser mode. Separate from [S_PEN] because it is a different digitizer tool. */
    S_PEN_ERASER("sPenEraser"),

    /** A contact the platform classified as a finger or an unclassified palm. */
    FINGER("finger"),

    /** A contact the platform itself classified as a palm. */
    PALM("palm"),

    /** A mouse or trackpad pointer. */
    MOUSE("mouse"),

    /** A pointer whose tool type this package does not recognise. */
    UNKNOWN("unknown"),
    ;

    companion object {
        /**
         * The platform's palm tool type.
         *
         * `MotionEvent.TOOL_TYPE_PALM` is marked `@hide` and is absent from the public SDK, so
         * the documented numeric value is repeated here. The raw number is reported alongside
         * every classification, which is what lets the observation be checked against the
         * digitizer rather than trusted.
         */
        const val TOOL_TYPE_PALM: Int = 3

        /** Classifies [toolType] as reported by `MotionEvent.getToolType`. */
        fun fromToolType(toolType: Int): InkPointerKind = when (toolType) {
            MotionEvent.TOOL_TYPE_STYLUS -> S_PEN
            MotionEvent.TOOL_TYPE_ERASER -> S_PEN_ERASER
            MotionEvent.TOOL_TYPE_FINGER -> FINGER
            MotionEvent.TOOL_TYPE_MOUSE -> MOUSE
            TOOL_TYPE_PALM -> PALM
            else -> UNKNOWN
        }
    }
}

// PURPOSE: Name the clock a frame's presentation timestamp came from, so a report can say
//          whether a number is the platform's own presentation estimate or a lower bound the
//          surface computed itself.
// INPUTS: None.
// OUTPUTS: One of two sources. FRAME_TIMELINE is the platform's frame timeline, available from
//          API 33; VSYNC_PLUS_DELAY is frameTimeNanos plus one refresh interval and is a floor.
// KEYWORDS: presentation-timeline, vsync, lower-bound, measurement-provenance
enum class PresentationSourceKind(
    /** Stable spelling written to the bench log as `presentSource`. */
    val wireName: String,
) {
    /** Choreographer frame timeline: the display pipeline's expected presentation time. */
    FRAME_TIMELINE("frameTimeline"),

    /** frameTimeNanos plus one refresh interval: a lower bound, see the header of the view. */
    VSYNC_PLUS_DELAY("vsyncPlusDelay"),
}

// PURPOSE: Carry one drawn input sample from the frame that presented it to the plugin, with
//          everything needed to both compute the acceptance number and audit what it was made
//          of.
// INPUTS: Built by InkSurfaceView when a frame closes, from a MotionEvent sample and the frame's
//         presentation time.
// OUTPUTS: A read-only record. touchToPresentMs is the single measurement; the raw nanosecond
//          timestamps are retained so a suspicious number can be recomputed by hand.
// KEYWORDS: latency-sample, touch-to-present, audit-trail, historical-sample
class InkSampleRecord(
    /** Zero-based position within the stroke, counting coalesced historical samples. */
    val sampleIndex: Int,
    /** Physical pointer that produced it. */
    val pointerKind: InkPointerKind,
    /** Which clock produced [presentTimeNanos]. */
    val presentationSource: PresentationSourceKind,
    /** The measurement: milliseconds from event time to expected presentation. */
    val touchToPresentMs: Double,
    /** Event time, already expressed in the frame clock's time base. */
    val eventTimeNanos: Long,
    /** The frame's expected presentation time, nanoseconds. */
    val presentTimeNanos: Long,
    /** Normalized pressure. */
    val pressure: Double,
    /** Tilt from the surface normal, radians. */
    val tiltRadians: Double,
    /** Pointer orientation, radians. */
    val orientationRadians: Double,
    /** Contact major axis, surface pixels. */
    val touchMajorPx: Double,
    /** True when the sample came from the coalesced historical queue. */
    val isHistorical: Boolean,
    /** The action string this sample arrived under. */
    val eventAction: String,
    /** Whether the raw source carried the stylus flag. */
    val sourceIsStylus: Boolean,
    /** Raw tool type as the digitizer reported it. */
    val rawToolType: Int,
    /** Raw input device source value. */
    val rawSource: Int,
    /** Sample x in surface-local pixels, transform removed. */
    val x: Float,
    /** Sample y in surface-local pixels, transform removed. */
    val y: Float,
)

// PURPOSE: Hold one stroke's samples while it is being drawn and after it commits, so the plugin
//          can report both the stroke's bounding box and every sample's latency from one object.
// INPUTS: The stroke index, the tool it was drawn with, and the owning pointer's classification.
// OUTPUTS: A record whose [points] grows while the stroke is live. Bounding box accessors return
//          a zero box for a stroke with no points rather than throwing, because a canceled
//          stroke with no sample must not crash the surface.
// KEYWORDS: stroke-record, bounding-box, commit, coalesced-points
class InkStrokeRecord(
    /** Stable identifier within the surface's lifetime; also the blob suffix. */
    val id: Int,
    /** Tool the stroke was drawn with. */
    val tool: InkToolKind,
    /** Classification of the pointer that owns the stroke. */
    val pointerKind: InkPointerKind,
    /** Raw tool type of the owning pointer. */
    val rawToolType: Int,
) {
    /** Every drawn sample of this stroke, in the order the digitizer produced them. */
    val points: MutableList<InkSampleRecord> = mutableListOf()

    /** Largest touch-major value seen, in pixels; zero for a stroke with no points. */
    var maxTouchMajorPx: Double = 0.0
        private set

    /** Running sum of touch-major values, for the mean; zero for a stroke with no points. */
    private var touchMajorSum: Double = 0.0

    /** True when the surface let this stroke draw; false when it suppressed it. */
    var drawAdmitted: Boolean = true

    /**
     * The document anchor for this stroke, as JSON text, or the empty string.
     *
     * The native surface never interprets an anchor: the app computes it from the stroke's
     * bounding box, per the platform contract, and passes it back when strokes are loaded. It is
     * carried as opaque text so that storing and returning a stroke cannot change the anchor the
     * app decided on.
     */
    var anchorJson: String = ""

    /**
     * Contacts observed from pointers that did NOT own this stroke, while it was being drawn.
     *
     * This is the field that answers "what happens when a palm rests on the surface while the pen
     * draws": the pen stroke keeps its own geometry and its own contact width, and the palm shows
     * up here as a contact the surface received and ignored.
     */
    var concurrentPointerSamples: Int = 0

    /** Largest touch-major value among those contacts, in pixels, or 0 when there were none. */
    var concurrentMaxTouchMajorPx: Double = 0.0

    /**
     * Appends [sample] and folds its contact width into the stroke's observation.
     *
     * Called once per drawn sample, from the frame callback rather than from `onTouchEvent`, so
     * that the sample's presentation time is already known when it is recorded.
     */
    fun add(sample: InkSampleRecord) {
        points.add(sample)
        touchMajorSum += sample.touchMajorPx
        if (sample.touchMajorPx > maxTouchMajorPx) {
            maxTouchMajorPx = sample.touchMajorPx
        }
    }

    /** Mean touch-major value in pixels, or 0.0 when the stroke has no points. */
    fun meanTouchMajorPx(): Double =
        if (points.isEmpty()) 0.0 else touchMajorSum / points.size

    /** Smallest x over all points, or 0.0 when the stroke has no points. */
    fun minX(): Float = points.minOfOrNull { it.x } ?: 0f

    /** Largest x over all points, or 0.0 when the stroke has no points. */
    fun maxX(): Float = points.maxOfOrNull { it.x } ?: 0f

    /** Smallest y over all points, or 0.0 when the stroke has no points. */
    fun minY(): Float = points.minOfOrNull { it.y } ?: 0f

    /** Largest y over all points, or 0.0 when the stroke has no points. */
    fun maxY(): Float = points.maxOfOrNull { it.y } ?: 0f

    /** Centre of the bounding box in surface-local pixels. */
    fun bboxCenterX(): Float = (minX() + maxX()) / 2f

    /** Centre of the bounding box in surface-local pixels. */
    fun bboxCenterY(): Float = (minY() + maxY()) / 2f

    /** Width of the bounding box in surface-local pixels. */
    fun bboxWidth(): Float = maxX() - minX()

    /** Height of the bounding box in surface-local pixels. */
    fun bboxHeight(): Float = maxY() - minY()
}
