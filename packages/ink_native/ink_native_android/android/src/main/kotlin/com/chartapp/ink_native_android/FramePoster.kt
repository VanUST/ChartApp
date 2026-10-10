// PURPOSE: Supply the time at which the frame currently being drawn is expected to reach the
//          display, and say which clock that time came from, so the ink surface can measure
//          input-to-present rather than input-to-draw. Two implementations exist because the
//          display pipeline's own frame timeline is public API only from Android 13, and a
//          Galaxy Tab S8+ may be running Android 12.
// INPUTS: A Choreographer on the UI thread, the display's refresh period in nanoseconds, and a
//         callback to receive the presentation time.
// OUTPUTS: Exactly one invocation of the supplied callback per posted frame, unless the frame
//          is cancelled by [FramePoster.cancel]. A frame whose timeline is invalid reports the
//          VSYNC_PLUS_DELAY source rather than passing on a nonsense timestamp.
// KEYWORDS: choreographer, presentation-timeline, vsync, frame-callback, latency-floor
package com.chartapp.ink_native_android

import android.os.Build
import android.view.Choreographer

// PURPOSE: Abstract the two ways of learning when a frame will be shown, so the surface asks for
//          a presentation time without branching on the API level at every call site.
// INPUTS: None; implementations are posted and cancelled.
// OUTPUTS: [post] schedules one callback with a presentation time and its provenance; [cancel]
//          withdraws a pending callback. Implementations must tolerate [cancel] with nothing
//          posted, because a view can be detached between a post and its frame.
// KEYWORDS: frame-poster, abstraction, api-gating, presentation-time
interface FramePoster {
    /** Which clock this poster normally reports; the callback may still override it per frame. */
    val defaultSource: PresentationSourceKind

    /**
     * Schedules [onPresent] for the next frame.
     *
     * Calling this again before the callback fires replaces the pending sink rather than
     * queueing a second callback, because the surface only ever needs the newest frame's
     * presentation time and a queue would deliver stale frames after a slow draw.
     */
    fun post(onPresent: (presentNanos: Long, source: PresentationSourceKind) -> Unit)

    /** Withdraws a pending callback, if any. Safe to call when nothing is posted. */
    fun cancel()
}

// PURPOSE: Report a frame's presentation time on every API level, using frameTimeNanos plus one
//          refresh interval when the display pipeline's own frame timeline is unavailable.
// INPUTS: The UI thread's Choreographer and the display's refresh period in nanoseconds.
// OUTPUTS: A presentation time that is a LOWER BOUND: it assumes the buffer produced in this
//          frame is shown at the next vsync and that the frame met its deadline. A frame that
//          missed its deadline is presented a full interval later, which this cannot see.
// KEYWORDS: vsync-plus-delay, lower-bound, fallback, frame-callback
class LegacyFramePoster(
    private val choreographer: Choreographer,
    private val refreshPeriodNanos: Long,
) : FramePoster {
    override val defaultSource: PresentationSourceKind =
        PresentationSourceKind.VSYNC_PLUS_DELAY

    private var sink: ((Long, PresentationSourceKind) -> Unit)? = null
    private var posted = false

    private val callback = Choreographer.FrameCallback { frameTimeNanos ->
        posted = false
        val target = sink
        sink = null
        // frameTimeNanos is the frame's start in the System.nanoTime time base; the buffer the
        // app produces now is shown one refresh interval later, which is the floor this reports.
        target?.invoke(
            frameTimeNanos + refreshPeriodNanos,
            PresentationSourceKind.VSYNC_PLUS_DELAY,
        )
    }

    override fun post(onPresent: (Long, PresentationSourceKind) -> Unit) {
        sink = onPresent
        if (!posted) {
            posted = true
            choreographer.postFrameCallback(callback)
        }
    }

    override fun cancel() {
        sink = null
        if (posted) {
            posted = false
            choreographer.removeFrameCallback(callback)
        }
    }
}

// PURPOSE: Choose the best available frame poster for the running API level, without verifying
//          the Android 13 poster's class on a device that does not have it.
// INPUTS: sdkInt — the device's API level; choreographer — the UI thread's Choreographer;
//         refreshPeriodNanos — the display's refresh period.
// OUTPUTS: A TimelineFramePoster on Android 13 and above, and a LegacyFramePoster otherwise. The
//          Android 13 class is named only inside the guarded branch, so ART never has to resolve
//          Choreographer.VsyncCallback on a device whose framework lacks it.
// KEYWORDS: api-gating, factory, verifier-safety, presentation-timeline
object FramePosterFactory {
    /** The API level at which `Choreographer.postVsyncCallback` became public. */
    const val TIMELINE_API_LEVEL: Int = Build.VERSION_CODES.TIRAMISU

    /** Builds the best poster [sdkInt] supports. */
    fun create(
        sdkInt: Int,
        choreographer: Choreographer,
        refreshPeriodNanos: Long,
    ): FramePoster = if (sdkInt >= TIMELINE_API_LEVEL) {
        TimelineFramePoster(choreographer, refreshPeriodNanos)
    } else {
        LegacyFramePoster(choreographer, refreshPeriodNanos)
    }
}
