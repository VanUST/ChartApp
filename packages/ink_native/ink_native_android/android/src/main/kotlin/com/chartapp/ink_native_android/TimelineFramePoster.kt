// PURPOSE: Read the display pipeline's own expected presentation time for the frame being drawn,
//          which is the only timestamp on the device that accounts for compositor scheduling
//          rather than assuming it. Kept in its own file so that loading it is itself the
//          API-level guard: this class names Choreographer.VsyncCallback, which exists only from
//          Android 13, and it is instantiated only from the guarded branch in FramePosterFactory.
// INPUTS: A Choreographer on the UI thread and the display's refresh period in nanoseconds, used
//         as the fallback when the platform reports no usable timeline for a frame.
// OUTPUTS: One callback per posted frame carrying `FrameTimeline.getExpectedPresentationTimeNanos`
//          of the preferred timeline, tagged FRAME_TIMELINE. A frame whose preferred timeline is
//          the invalid sentinel (or is not in the future of the frame start) reports
//          frameTimeNanos + refresh period tagged VSYNC_PLUS_DELAY, so the callback's provenance
//          is always a statement about the number it delivers.
// KEYWORDS: frame-timeline, expected-presentation, android-13, vsync-callback, provenance
package com.chartapp.ink_native_android

import android.view.Choreographer

/**
 * Frame poster backed by `Choreographer.postVsyncCallback`.
 *
 * `postVsyncCallback` registers on the Choreographer's animation phase, which runs before the
 * traversal phase of the same frame, so a view that invalidates itself from [post]'s callback is
 * drawn in that same frame and the timeline it was given applies to it.
 *
 * The public API since Android 13 does not include `Choreographer.FrameInfo`, which is
 * `@SystemApi`; `FrameData` and `FrameTimeline` from `postVsyncCallback` are its public
 * replacement and are what this class reads.
 */
@Suppress("NewApi")
class TimelineFramePoster(
    private val choreographer: Choreographer,
    private val refreshPeriodNanos: Long,
) : FramePoster {
    override val defaultSource: PresentationSourceKind =
        PresentationSourceKind.FRAME_TIMELINE

    private var sink: ((Long, PresentationSourceKind) -> Unit)? = null
    private var posted = false

    private val callback = Choreographer.VsyncCallback { frameData ->
        posted = false
        val target = sink
        sink = null
        if (target == null) {
            return@VsyncCallback
        }
        val frameStartNanos = frameData.frameTimeNanos
        val expectedPresentNanos =
            frameData.preferredFrameTimeline.expectedPresentationTimeNanos
        // The invalid timeline reports Long.MAX_VALUE as its presentation time. Passing that on
        // would produce a latency of several million years, so it is replaced by the same lower
        // bound the legacy poster would have given, and the sample says so.
        if (expectedPresentNanos > frameStartNanos) {
            target.invoke(expectedPresentNanos, PresentationSourceKind.FRAME_TIMELINE)
        } else {
            target.invoke(
                frameStartNanos + refreshPeriodNanos,
                PresentationSourceKind.VSYNC_PLUS_DELAY,
            )
        }
    }

    override fun post(onPresent: (Long, PresentationSourceKind) -> Unit) {
        sink = onPresent
        if (!posted) {
            posted = true
            choreographer.postVsyncCallback(callback)
        }
    }

    override fun cancel() {
        sink = null
        if (posted) {
            posted = false
            choreographer.removeVsyncCallback(callback)
        }
    }
}
