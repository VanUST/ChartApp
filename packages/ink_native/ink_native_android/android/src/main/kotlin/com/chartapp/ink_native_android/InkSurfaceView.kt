// PURPOSE: Draw stylus and finger strokes as the digitizer produces them, and measure how long
//          each drawn sample took to reach the display, on the device, because that interval is
//          a property of the glass and the compositor and cannot be measured anywhere else.
//
// WHAT THE NUMBER INCLUDES, AND WHAT IT EXCLUDES. This is the part that decides whether a p95 is
// evidence or decoration, so it is stated in full.
//
//   touchToPresentMs = (expected presentation time of the frame that first drew the sample)
//                    - (the sample's event timestamp)
//
// Included:
//   * digitizer-to-app delivery: `MotionEvent.getEventTime` is stamped by the input system when
//     the driver report is drained, and the real forwarding path to this view is measured from
//     there, so a Flutter-to-platform-view forwarding delay shows up in the number;
//   * this view's own drawing work (both the dot and the line for every sample, including the
//     coalesced historical samples, which are drawn rather than dropped);
//   * the app's remaining draw work in that frame, because the presentation time belongs to the
//     whole frame and not to this view;
//   * the platform's compositor scheduling, when the frame timeline answers: on Android 13 and
//     above the number is `FrameTimeline.getExpectedPresentationTimeNanos`, which is
//     SurfaceFlinger's own estimate of when this frame's buffer reaches the display, so a frame
//     that misses its deadline is reported as late rather than as fast.
//
// Excluded, and therefore this number UNDER-STATES the true input-to-photon latency:
//   * the digitizer's own sampling and kernel-side handling before `getEventTime` is stamped,
//     typically a few milliseconds and invisible to any app;
//   * the display's panel latency between the compositor's presentation deadline and photons,
//     which is hardware and not measurable from inside the process;
//   * the touch-to-scanout interval of the panel's own input path.
// On Android 12 and below the presentation time falls back to `frameTimeNanos + one refresh
// period`, which is a FLOOR, not an estimate: it assumes the frame met its deadline. Each sample
// carries the source it used, so a report can separate the two regimes instead of averaging them.
//
// Because the surface is inserted as a real view in the Android hierarchy (hybrid composition,
// `PlatformViewsService.initExpensiveAndroidView`), there is no PlatformView texture copy between
// this view's frame and Flutter's frame, and the frame measured here is the Flutter frame. Had the
// texture path been used, one texture copy and possibly one extra frame would sit between the two
// and this number would under-state by that much.
//
// INPUTS: `MotionEvent` streams from the platform; commands from the plugin (tool, transform,
//         strokes); the display's refresh rate.
// OUTPUTS: pixels on the surface, plus `InkStrokeRecord`s handed to [Listener.onStrokeFinished]
//          with per-sample latencies, and the properties [describeSurface] reports.
// KEYWORDS: ink-surface, platform-view, latency-measurement, coalesced-samples, historical-samples,
//           frame-timeline, palm-observation, hybrid-composition
package com.chartapp.ink_native_android

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import android.view.Choreographer
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.os.SystemClock
import kotlin.math.abs
import kotlin.math.max

/**
 * A `View` that draws ink and measures its own input-to-present latency.
 *
 * The view owns three pieces of state that must not drift apart: the committed strokes, the
 * bitmap those strokes are rasterised into, and the list of input samples that have been received
 * but not yet attributed to a frame. Samples wait for a frame because their measurement is the
 * frame's presentation time, and a sample drawn in a frame whose time is not yet known cannot be
 * reported.
 */
class InkSurfaceView(
    context: Context,
    /** How this view reaches Flutter; reported rather than assumed. */
    private val platformViewMode: String,
) : View(context) {

    // PURPOSE: Receive finished strokes from the surface without the surface knowing anything
    //          about method channels, so the drawing path stays free of transport concerns.
    // INPUTS: [onStrokeFinished] with every stroke that ends, including suppressed palm contacts.
    // OUTPUTS: Nothing; the implementation reports the stroke.
    // KEYWORDS: listener, plugin-boundary, stroke-report
    interface Listener {
        /** Called on the UI thread once a stroke has ended, for both drawn and suppressed ones. */
        fun onStrokeFinished(stroke: InkStrokeRecord)
    }

    /** Where finished strokes are reported; null until the plugin attaches. */
    var listener: Listener? = null

    /**
     * The tool new strokes are drawn with.
     *
     * Named `currentTool` rather than `tool` because a Kotlin property named `tool` would generate
     * a `setTool` method and collide on the JVM with the [setTool] command below.
     */
    var currentTool: InkToolKind = InkToolKind.PEN

    // -----------------------------------------------------------------------------------------
    // Committed stroke model and the bitmap it is rasterised into.
    // -----------------------------------------------------------------------------------------

    private val strokes = mutableListOf<InkStrokeRecord>()
    private var nextStrokeId = 1

    private var buffer: Bitmap? = null
    private var bufferCanvas: Canvas? = null

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    /** Width in pixels of the currently configured tool, shared by the line and dot paints. */
    private var strokeWidthPx: Float = 3f

    private val density: Float = context.resources.displayMetrics.density

    // -----------------------------------------------------------------------------------------
    // View transform, applied when the bitmap is rasterised.
    // -----------------------------------------------------------------------------------------

    private var transformScale = 1f
    private var transformTx = 0f
    private var transformTy = 0f

    // -----------------------------------------------------------------------------------------
    // Samples awaiting a frame, and the stroke they belong to.
    // -----------------------------------------------------------------------------------------

    private class PendingSample(
        val stroke: InkStrokeRecord,
        val historical: Boolean,
        val action: String,
        val rawToolType: Int,
        val rawSource: Int,
        val sourceIsStylus: Boolean,
        val rawEventTimeNanos: Long,
        val pressure: Double,
        val tiltRadians: Double,
        val orientationRadians: Double,
        val touchMajorPx: Double,
        val x: Float,
        val y: Float,
    )

    private val pending = ArrayList<PendingSample>()

    private var activeStroke: InkStrokeRecord? = null
    private var activePointerId = MotionEvent.INVALID_POINTER_ID

    /**
     * A stroke whose pointer has lifted but whose final samples are still waiting for a frame.
     *
     * Reporting it before its frames close would drop the last samples of every stroke, which on a
     * fast flick is most of them.
     */
    private var closingStroke: InkStrokeRecord? = null

    // -----------------------------------------------------------------------------------------
    // Frame clock and measurement state.
    // -----------------------------------------------------------------------------------------

    private var refreshPeriodNanos: Long = 16_666_667L
    private val choreographer: Choreographer = Choreographer.getInstance()

    private var usingTimeline: Boolean = Build.VERSION.SDK_INT >= FramePosterFactory.TIMELINE_API_LEVEL
    private var timelineConfirmed = false
    private var timelineWatchdogPosted = false

    private var framePoster: FramePoster = FramePosterFactory.create(
        Build.VERSION.SDK_INT,
        choreographer,
        refreshPeriodNanos,
    )

    private val frameSink: (Long, PresentationSourceKind) -> Unit = { present, source ->
        closePending(present, source)
    }

    private val timelineWatchdog = Runnable {
        // A registered vsync callback that never fires would leave every sample undelivered,
        // which reads as "no data" rather than as a wrong number. Falling back makes it work.
        if (!timelineConfirmed && usingTimeline) {
            usingTimeline = false
            framePoster.cancel()
            framePoster = LegacyFramePoster(choreographer, refreshPeriodNanos)
            framePoster.post(frameSink)
        }
    }

    private var presentSource: PresentationSourceKind =
        if (usingTimeline) PresentationSourceKind.FRAME_TIMELINE else PresentationSourceKind.VSYNC_PLUS_DELAY

    private var observedRefreshRateHz: Float = 0f

    /**
     * `System.nanoTime() - SystemClock.uptimeMillis() * 1e6`, measured here.
     *
     * Sample timestamps and frame timestamps are documented to share the `System.nanoTime` base,
     * but a documented time base is still an assumption about the framework. Measuring the
     * difference turns it into a number the report can show: a value near zero confirms the two
     * clocks share an origin, and a large one means this surface corrected a real difference
     * instead of assuming it away.
     */
    private var clockOffsetNanos = 0L
    private var initialClockOffsetNanos = 0L
    private var maxClockDriftNanos = 0L
    private var clockOffsetMeasured = false

    // -----------------------------------------------------------------------------------------
    // Palm and concurrent-contact observations.
    // -----------------------------------------------------------------------------------------

    private var palmSuppressedCount = 0
    private var concurrentContactSamples = 0
    private var concurrentMaxTouchMajorPx = 0.0

    init {
        setWillNotDraw(false)
        // Hardware acceleration is left on: the buffer is blitted by the hardware canvas, and
        // turning it off would measure a slower path than the product uses.
        applyToolPaints(InkToolKind.PEN)
    }

    // -----------------------------------------------------------------------------------------
    // Public commands, called by the plugin on the UI thread.
    // -----------------------------------------------------------------------------------------

    /** Selects the tool used for new strokes. Existing strokes keep the tool they were drawn with. */
    fun setTool(tool: InkToolKind) {
        currentTool = tool
        applyToolPaints(tool)
    }

    /**
     * Applies the shared scroll/zoom transform.
     *
     * The transform is baked into the rasterised bitmap, so changing it re-rasterises every
     * stroke. The alternative — transforming at blit time — would keep the transform out of the
     * stroke data but would also make the bitmap's pixels meaningless for the eraser's hit test
     * and for the bounding box the app turns into an anchor.
     */
    fun setTransform(scale: Float, translationX: Float, translationY: Float) {
        transformScale = if (scale == 0f) 1f else scale
        transformTx = translationX
        transformTy = translationY
        rebuildBuffer()
        invalidate()
    }

    /** Replaces every stroke with [newStrokes] and redraws. */
    fun loadStrokes(newStrokes: List<InkStrokeRecord>) {
        strokes.clear()
        strokes.addAll(newStrokes)
        nextStrokeId = (newStrokes.maxOfOrNull { it.id } ?: 0) + 1
        rebuildBuffer()
        invalidate()
    }

    /** Removes every stroke. */
    fun clearStrokes() {
        strokes.clear()
        rebuildBuffer()
        invalidate()
    }

    /** The committed strokes, for export. */
    fun exportStrokes(): List<InkStrokeRecord> = ArrayList(strokes)

    /** Releases native resources; called when the platform view is disposed. */
    fun dispose() {
        framePoster.cancel()
        removeCallbacks(timelineWatchdog)
        listener = null
        buffer?.recycle()
        buffer = null
        bufferCanvas = null
        strokes.clear()
        pending.clear()
        activeStroke = null
        closingStroke = null
    }

    // -----------------------------------------------------------------------------------------
    // Measurement description.
    // -----------------------------------------------------------------------------------------

    // PURPOSE: Describe what this surface measured and on which clock, so a bench report can say
    //          whether a given p95 is a frame-timeline measurement or a lower bound, and how
    //          precisely the input timestamps were stamped.
    // INPUTS: None; every field is observed state accumulated by the surface.
    // OUTPUTS: A flat map of scalars ready to cross the method channel. No field is a guess: a
    //          value that was never observed is reported as zero or false, never filled in from
    //          the API level's promises.
    // KEYWORDS: surface-description, provenance, measurement-limits, palm-observation
    fun describeSurface(): Map<String, Any?> = mapOf(
        "presentSource" to presentSource.wireName,
        "timelineDelivered" to timelineConfirmed,
        "usedTimelinePoster" to usingTimeline,
        "apiLevel" to Build.VERSION.SDK_INT,
        "refreshRateHz" to observedRefreshRateHz.toDouble(),
        "refreshPeriodNanos" to refreshPeriodNanos,
        "clockOffsetMs" to clockOffsetNanos / 1_000_000.0,
        "clockOffsetDriftMs" to maxClockDriftNanos / 1_000_000.0,
        "eventTimePrecision" to if (Build.VERSION.SDK_INT >= 34) "nanosecond" else "millisecond",
        "platformViewMode" to platformViewMode,
        "deviceModel" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}".trim(),
        "androidRelease" to android.os.Build.VERSION.RELEASE.orEmpty(),
        "palmContactsSuppressed" to palmSuppressedCount,
        "concurrentContactSamples" to concurrentContactSamples,
        "concurrentMaxTouchMajorPx" to concurrentMaxTouchMajorPx,
        "committedStrokeCount" to strokes.size,
    )

    // -----------------------------------------------------------------------------------------
    // Input.
    // -----------------------------------------------------------------------------------------

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN,
            MotionEvent.ACTION_POINTER_DOWN,
            -> handlePointerDown(event, event.actionIndex)

            MotionEvent.ACTION_MOVE -> handleMove(event)

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_POINTER_UP,
            -> handlePointerUp(event, event.actionIndex)

            MotionEvent.ACTION_CANCEL -> handleCancel()

            else -> return false
        }
        return true
    }

    private fun handlePointerDown(event: MotionEvent, pointerIndex: Int) {
        maybeFinalizeClosing()
        val toolType = event.getToolType(pointerIndex)
        val kind = InkPointerKind.fromToolType(toolType)
        val action = "down"

        if (kind == InkPointerKind.PALM) {
            suppressPalmContact(event, pointerIndex, toolType)
            return
        }
        if (activeStroke != null) {
            // A second contact arrived while a stroke is live. It is observed rather than drawn:
            // starting a second stroke here would make one hand's motion two strokes.
            noteConcurrentContact(event, pointerIndex)
            return
        }
        val stroke = InkStrokeRecord(nextStrokeId++, currentTool, kind, toolType)
        activeStroke = stroke
        activePointerId = event.getPointerId(pointerIndex)
        collect(event, pointerIndex, action)
    }

    private fun handleMove(event: MotionEvent) {
        val stroke = activeStroke ?: return
        val index = event.findPointerIndex(activePointerId)
        if (index < 0) {
            return
        }
        collect(event, index, "move")
        for (pointerIndex in 0 until event.pointerCount) {
            if (pointerIndex != index) {
                noteConcurrentContact(event, pointerIndex)
            }
        }
    }

    private fun handlePointerUp(event: MotionEvent, pointerIndex: Int) {
        val stroke = activeStroke ?: return
        if (event.getPointerId(pointerIndex) != activePointerId) {
            return
        }
        collect(event, pointerIndex, "up")
        activeStroke = null
        activePointerId = MotionEvent.INVALID_POINTER_ID
        closingStroke = stroke
        // The up sample is still waiting for a frame; if nothing is pending (a zero-length
        // gesture whose samples were already attributed), the stroke can be reported now.
        maybeFinalizeClosing()
    }

    private fun handleCancel() {
        val stroke = activeStroke ?: return
        activeStroke = null
        activePointerId = MotionEvent.INVALID_POINTER_ID
        closingStroke = stroke
        maybeFinalizeClosing()
    }

    /**
     * Appends every sample a motion event carries for [pointerIndex], historical ones included.
     *
     * The historical queue is the coalesced part of the stream: a single event on a 120 Hz S Pen
     * can carry four or five sub-frame samples. They are appended in their original order and
     * drawn, because dropping them would leave gaps in the stroke and would also remove the
     * samples whose latency the digitizer is actually reporting.
     */
    private fun collect(event: MotionEvent, pointerIndex: Int, action: String) {
        val stroke = activeStroke ?: return
        val toolType = event.getToolType(pointerIndex)
        val source = event.source
        val sourceIsStylus = isStylusSource(source)

        val historySize = event.historySize
        for (position in 0 until historySize) {
            val local = toLocal(
                event.getHistoricalX(pointerIndex, position),
                event.getHistoricalY(pointerIndex, position),
            )
            pending.add(
                PendingSample(
                    stroke = stroke,
                    historical = true,
                    action = action,
                    rawToolType = toolType,
                    rawSource = source,
                    sourceIsStylus = sourceIsStylus,
                    rawEventTimeNanos = historicalEventTimeNanos(event, position),
                    pressure = event.getHistoricalAxisValue(
                        MotionEvent.AXIS_PRESSURE,
                        pointerIndex,
                        position,
                    ).toDouble(),
                    tiltRadians = event.getHistoricalAxisValue(
                        MotionEvent.AXIS_TILT,
                        pointerIndex,
                        position,
                    ).toDouble(),
                    orientationRadians = event.getHistoricalAxisValue(
                        MotionEvent.AXIS_ORIENTATION,
                        pointerIndex,
                        position,
                    ).toDouble(),
                    touchMajorPx = event.getHistoricalAxisValue(
                        MotionEvent.AXIS_TOUCH_MAJOR,
                        pointerIndex,
                        position,
                    ).toDouble(),
                    x = local.first,
                    y = local.second,
                ),
            )
        }

        val local = toLocal(event.getX(pointerIndex), event.getY(pointerIndex))
        pending.add(
            PendingSample(
                stroke = stroke,
                historical = false,
                action = action,
                rawToolType = toolType,
                rawSource = source,
                sourceIsStylus = sourceIsStylus,
                rawEventTimeNanos = currentEventTimeNanos(event),
                pressure = event.getAxisValue(MotionEvent.AXIS_PRESSURE, pointerIndex).toDouble(),
                tiltRadians = event.getAxisValue(MotionEvent.AXIS_TILT, pointerIndex).toDouble(),
                orientationRadians = event.getAxisValue(
                    MotionEvent.AXIS_ORIENTATION,
                    pointerIndex,
                ).toDouble(),
                touchMajorPx = event.getAxisValue(
                    MotionEvent.AXIS_TOUCH_MAJOR,
                    pointerIndex,
                ).toDouble(),
                x = local.first,
                y = local.second,
            ),
        )
        scheduleFrame()
    }

    // -----------------------------------------------------------------------------------------
    // Frame handling: attribute every pending sample to the frame that drew it.
    // -----------------------------------------------------------------------------------------

    private fun scheduleFrame() {
        if (usingTimeline && !timelineConfirmed && !timelineWatchdogPosted) {
            timelineWatchdogPosted = true
            postDelayed(timelineWatchdog, TIMELINE_WATCHDOG_MS)
        }
        framePoster.post(frameSink)
    }

    /**
     * Attributes every pending sample to [presentNanos] and draws it.
     *
     * This runs from the Choreographer's animation phase, before the traversal of the same frame,
     * so a sample drawn here is in the buffer that this frame presents and the timestamp applies
     * to it. Every sample in the batch shares one presentation time because one frame showed them
     * all; their latencies differ because their event timestamps do.
     */
    private fun closePending(presentNanos: Long, source: PresentationSourceKind) {
        timelineConfirmed = true
        presentSource = source
        observeRefreshRate()
        val offsetNanos = measureClockOffset()
        if (pending.isEmpty()) {
            maybeFinalizeClosing()
            return
        }

        val batch = ArrayList(pending)
        pending.clear()

        for (sample in batch) {
            val eventTimeNanos = sample.rawEventTimeNanos + offsetNanos
            val stroke = sample.stroke
            stroke.add(
                InkSampleRecord(
                    sampleIndex = stroke.points.size,
                    pointerKind = stroke.pointerKind,
                    presentationSource = source,
                    touchToPresentMs = (presentNanos - eventTimeNanos) / 1_000_000.0,
                    eventTimeNanos = eventTimeNanos,
                    presentTimeNanos = presentNanos,
                    pressure = sample.pressure,
                    tiltRadians = sample.tiltRadians,
                    orientationRadians = sample.orientationRadians,
                    touchMajorPx = sample.touchMajorPx,
                    isHistorical = sample.historical,
                    eventAction = sample.action,
                    sourceIsStylus = sample.sourceIsStylus,
                    rawToolType = sample.rawToolType,
                    rawSource = sample.rawSource,
                    x = sample.x,
                    y = sample.y,
                ),
            )
            drawSampleIntoBuffer(stroke, sample.x, sample.y)
        }

        invalidate()
        maybeFinalizeClosing()
    }

    private fun maybeFinalizeClosing() {
        val closing = closingStroke ?: return
        if (pending.any { it.stroke === closing }) {
            return
        }
        closingStroke = null
        finishStroke(closing)
    }

    private fun finishStroke(stroke: InkStrokeRecord) {
        if (stroke.points.isEmpty()) {
            return
        }
        if (stroke.tool == InkToolKind.ERASER) {
            eraseUnder(stroke)
            rebuildBuffer()
            invalidate()
        } else if (strokes.none { it === stroke }) {
            // Its pixels are already in the buffer from the incremental draws; adding it to the
            // model is what makes a later re-rasterisation able to reproduce them.
            strokes.add(stroke)
        }
        listener?.onStrokeFinished(stroke)
    }

    // -----------------------------------------------------------------------------------------
    // Drawing.
    // -----------------------------------------------------------------------------------------

    override fun onDraw(canvas: Canvas) {
        val bitmap = buffer ?: return
        canvas.drawBitmap(bitmap, 0f, 0f, null)
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        super.onSizeChanged(width, height, oldWidth, oldHeight)
        observeRefreshRate()
        rebuildBuffer()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        framePoster.cancel()
        removeCallbacks(timelineWatchdog)
    }

    /** Re-rasterises every stroke into a fresh bitmap; the only way the transform can change. */
    private fun rebuildBuffer() {
        val width = width
        val height = height
        if (width <= 0 || height <= 0) {
            return
        }
        val previous = buffer
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        buffer = bitmap
        bufferCanvas = Canvas(bitmap)
        for (stroke in strokes) {
            drawStrokeIntoBuffer(stroke)
        }
        previous?.recycle()
    }

    private fun drawStrokeIntoBuffer(stroke: InkStrokeRecord) {
        if (stroke.tool == InkToolKind.ERASER) {
            return
        }
        applyToolPaints(stroke.tool)
        var previousX = 0f
        var previousY = 0f
        var hasPrevious = false
        for (point in stroke.points) {
            drawSegment(point.x, point.y, previousX, previousY, hasPrevious)
            previousX = point.x
            previousY = point.y
            hasPrevious = true
        }
    }

    private fun drawSampleIntoBuffer(stroke: InkStrokeRecord, x: Float, y: Float) {
        if (stroke.tool == InkToolKind.ERASER) {
            return
        }
        applyToolPaints(stroke.tool)
        val index = stroke.points.size - 1
        val previous = if (index >= 1) stroke.points[index - 1] else null
        drawSegment(
            x,
            y,
            previous?.x ?: x,
            previous?.y ?: y,
            previous != null,
        )
    }

    private fun drawSegment(
        x: Float,
        y: Float,
        previousX: Float,
        previousY: Float,
        hasPrevious: Boolean,
    ) {
        val canvas = bufferCanvas ?: return
        canvas.save()
        canvas.translate(transformTx, transformTy)
        canvas.scale(transformScale, transformScale)
        canvas.drawCircle(x, y, strokeWidthPx / 2f, dotPaint)
        if (hasPrevious) {
            canvas.drawLine(previousX, previousY, x, y, linePaint)
        }
        canvas.restore()
    }

    private fun applyToolPaints(tool: InkToolKind) {
        when (tool) {
            InkToolKind.PEN -> {
                strokeWidthPx = PEN_WIDTH_DP * density
                linePaint.color = Color.BLACK
                dotPaint.color = Color.BLACK
                linePaint.alpha = 255
                dotPaint.alpha = 255
            }

            InkToolKind.HIGHLIGHTER -> {
                strokeWidthPx = HIGHLIGHTER_WIDTH_DP * density
                linePaint.color = HIGHLIGHTER_COLOR
                dotPaint.color = HIGHLIGHTER_COLOR
                linePaint.alpha = HIGHLIGHTER_ALPHA
                dotPaint.alpha = HIGHLIGHTER_ALPHA
            }

            InkToolKind.ERASER -> {
                strokeWidthPx = ERASER_WIDTH_DP * density
                linePaint.color = Color.BLACK
                dotPaint.color = Color.BLACK
                linePaint.alpha = 255
                dotPaint.alpha = 255
            }
        }
    }

    /**
     * Removes whole strokes whose bounding box meets the eraser's.
     *
     * Whole-stroke removal rather than pixel erasure is what the platform contract asks for and
     * what makes erasing reversible by data; it also means the eraser needs the stroke model,
     * which is why the eraser's own path is not rasterised.
     */
    private fun eraseUnder(eraser: InkStrokeRecord) {
        if (eraser.points.isEmpty()) {
            return
        }
        // The eraser's own radius, not the shared paint width: an eraser path is never rasterised,
        // so strokeWidthPx still holds whatever tool was drawn last and using it here would give
        // the eraser the highlighter's reach.
        val radius = ERASER_WIDTH_DP * density / 2f
        val left = eraser.minX() - radius
        val right = eraser.maxX() + radius
        val top = eraser.minY() - radius
        val bottom = eraser.maxY() + radius
        strokes.removeAll { candidate ->
            candidate !== eraser &&
                candidate.maxX() >= left &&
                candidate.minX() <= right &&
                candidate.maxY() >= top &&
                candidate.minY() <= bottom
        }
    }

    // -----------------------------------------------------------------------------------------
    // Palm and concurrent-contact observation.
    // -----------------------------------------------------------------------------------------

    /**
     * Records a contact the platform classified as a palm and refuses to draw it.
     *
     * This is an observation, not a rejection filter: the surface can only report what the
     * digitizer delivered. If Samsung's palm rejection already removed the contact upstream, this
     * is never called and the count stays zero, which is the evidence that rejection happened
     * somewhere the app cannot see.
     */
    private fun suppressPalmContact(event: MotionEvent, pointerIndex: Int, toolType: Int) {
        palmSuppressedCount++
        val stroke = InkStrokeRecord(nextStrokeId++, currentTool, InkPointerKind.PALM, toolType)
        stroke.drawAdmitted = false
        stroke.anchorJson = ""
        // One synthetic point carries the contact geometry: a palm has no measured latency
        // because nothing about it was presented, and reporting a latency for it would be
        // reporting a number for pixels that were never drawn.
        stroke.add(
            InkSampleRecord(
                sampleIndex = 0,
                pointerKind = InkPointerKind.PALM,
                presentationSource = presentSource,
                touchToPresentMs = Double.NaN,
                eventTimeNanos = currentEventTimeNanos(event),
                presentTimeNanos = 0L,
                pressure = event.getAxisValue(MotionEvent.AXIS_PRESSURE, pointerIndex).toDouble(),
                tiltRadians = event.getAxisValue(MotionEvent.AXIS_TILT, pointerIndex).toDouble(),
                orientationRadians = event.getAxisValue(
                    MotionEvent.AXIS_ORIENTATION,
                    pointerIndex,
                ).toDouble(),
                touchMajorPx = event.getAxisValue(
                    MotionEvent.AXIS_TOUCH_MAJOR,
                    pointerIndex,
                ).toDouble(),
                isHistorical = false,
                eventAction = "down",
                sourceIsStylus = false,
                rawToolType = toolType,
                rawSource = event.source,
                x = event.getX(pointerIndex),
                y = event.getY(pointerIndex),
            ),
        )
        listener?.onStrokeFinished(stroke)
    }

    /** Records contact from a pointer that does not own the live stroke, without drawing it. */
    private fun noteConcurrentContact(event: MotionEvent, pointerIndex: Int) {
        concurrentContactSamples++
        val major = event.getAxisValue(MotionEvent.AXIS_TOUCH_MAJOR, pointerIndex).toDouble()
        if (major > concurrentMaxTouchMajorPx) {
            concurrentMaxTouchMajorPx = major
        }
        // Also attributed to the live stroke, so the observation reaches the report attached to
        // the stroke it happened during rather than only as a surface-lifetime total.
        val stroke = activeStroke ?: return
        stroke.concurrentPointerSamples++
        if (major > stroke.concurrentMaxTouchMajorPx) {
            stroke.concurrentMaxTouchMajorPx = major
        }
    }

    // -----------------------------------------------------------------------------------------
    // Clocks and display observation.
    // -----------------------------------------------------------------------------------------

    /** Refreshes the observed refresh rate and the vsync period derived from it. */
    private fun observeRefreshRate() {
        val display = display ?: return
        val rate = display.refreshRate
        if (rate > 0f) {
            observedRefreshRateHz = rate
            refreshPeriodNanos = max(1L, (1_000_000_000.0 / rate).toLong())
        }
    }

    private fun measureClockOffset(): Long {
        // The millisecond clock is read first, so the difference is the elapsed time between the
        // two reads and never negative.
        val uptimeMillis = SystemClock.uptimeMillis()
        val nanoTime = System.nanoTime()
        val offset = nanoTime - uptimeMillis * 1_000_000L
        if (!clockOffsetMeasured) {
            initialClockOffsetNanos = offset
            clockOffsetMeasured = true
        }
        val drift = abs(offset - initialClockOffsetNanos)
        if (drift > maxClockDriftNanos) {
            maxClockDriftNanos = drift
        }
        clockOffsetNanos = offset
        return offset
    }

    private fun currentEventTimeNanos(event: MotionEvent): Long =
        if (Build.VERSION.SDK_INT >= 34) {
            event.eventTimeNanos
        } else {
            // getEventTimeNanos is public only from API 34; below that the millisecond stamp is
            // the only one the platform exposes, which quantises the input timestamp to 1 ms and
            // is reported as `eventTimePrecision = millisecond`.
            event.eventTime * 1_000_000L
        }

    private fun historicalEventTimeNanos(event: MotionEvent, position: Int): Long =
        if (Build.VERSION.SDK_INT >= 34) {
            event.getHistoricalEventTimeNanos(position)
        } else {
            event.getHistoricalEventTime(position) * 1_000_000L
        }

    private fun isStylusSource(source: Int): Boolean =
        (source and InputDevice.SOURCE_STYLUS) == InputDevice.SOURCE_STYLUS

    /** Removes the shared transform from a raw view coordinate. */
    private fun toLocal(viewX: Float, viewY: Float): Pair<Float, Float> =
        Pair((viewX - transformTx) / transformScale, (viewY - transformTy) / transformScale)

    private companion object {
        const val PEN_WIDTH_DP = 3f
        const val HIGHLIGHTER_WIDTH_DP = 22f
        const val ERASER_WIDTH_DP = 28f
        const val HIGHLIGHTER_ALPHA = 110
        const val TIMELINE_WATCHDOG_MS = 500L

        /** Opaque yellow. Declared as a value rather than a const because the literal is a Long. */
        val HIGHLIGHTER_COLOR = 0xFFFFEB3B.toInt()
    }
}
