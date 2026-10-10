// PURPOSE: Connect Flutter to the Android ink surface: register the view factory, carry commands
//          down and measurements up, and keep the anchor the app computed opaque on the way
//          through. It is the only class in this package that knows a method channel exists.
// INPUTS: Method calls from the Dart side (`initialize`, `setTool`, `setTransform`,
//         `loadStrokes`, `exportStrokes`, `clearStrokes`, `describeSurface`,
//         `benchLogDirectory`, `strokesRoundTripCheck`) and [InkSurfaceView] stroke reports.
// OUTPUTS: Method-call results, plus two calls up to Dart: `onStrokeFinished` for each stroke the
//          surface ends, and nothing else. A call arriving before a surface exists is answered
//          from the standalone surface description rather than by throwing, because a hot restart
//          can ask for it while the platform view is being rebuilt.
// KEYWORDS: plugin, method-channel, platform-view-registration, stroke-report, anchor-passthrough
package com.chartapp.ink_native_android

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** InkNativeAndroidPlugin */
class InkNativeAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    InkSurfaceView.Listener {
    /**
     * The MethodChannel that carries commands to this plugin and reports up to Dart.
     *
     * Registered in [onAttachedToEngine] and unregistered in [onDetachedFromEngine] so a detached
     * engine cannot be called by a surface that outlived it.
     */
    private lateinit var channel: MethodChannel

    /** Application context, used only to answer where a bench log may be written. */
    private lateinit var appContext: Context

    /** The most recently created surface, or null before the platform view exists. */
    private var surface: InkSurfaceView? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            INK_SURFACE_VIEW_TYPE,
            InkSurfaceViewFactory { created ->
                created.listener = this
                surface = created
            },
        )
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        // getPlatformVersion is answered without touching any lateinit field, because the plugin's
        // existing unit test constructs the plugin without an engine and calls exactly this.
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "initialize" -> result.success(null)
            "setTool" -> {
                surface?.setTool(InkToolKind.fromWireName(call.argument("tool")))
                result.success(null)
            }
            "setTransform" -> {
                surface?.setTransform(
                    (call.argument<Double>("scale") ?: 1.0).toFloat(),
                    (call.argument<Double>("translationX") ?: 0.0).toFloat(),
                    (call.argument<Double>("translationY") ?: 0.0).toFloat(),
                )
                result.success(null)
            }
            "clearStrokes" -> {
                surface?.clearStrokes()
                result.success(null)
            }
            "loadStrokes" -> {
                loadStrokes(call)
                result.success(null)
            }
            "exportStrokes" -> result.success(exportStrokes())
            "describeSurface" -> result.success(describeSurface())
            "benchLogDirectory" -> result.success(appContext.getExternalFilesDir(null)?.absolutePath)
            "strokesRoundTripCheck" -> result.success(strokesRoundTripCheck())
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        surface?.listener = null
        surface = null
    }

    // PURPOSE: Carry one finished stroke to Dart, with every measured sample, in one call, so the
    //          drawing hot path is not crossed once per sample.
    // INPUTS: The surface's completed stroke record, including suppressed palm contacts.
    // OUTPUTS: One `onStrokeFinished` invocation. Samples whose latency is not finite are
    //          omitted rather than sent: a loaded stroke and a suppressed palm contact have no
    //          presentation, and sending a zero for them would put a fabricated measurement into
    //          a percentile. A negative latency is sent, because it is a real observation that the
    //          clocks disagreed and hiding it would be worse than reporting it.
    // KEYWORDS: stroke-report, latency-samples, finite-guard, channel-batching
    override fun onStrokeFinished(stroke: InkStrokeRecord) {
        // An eraser gesture presents no ink, so a latency for it would be a measurement of
        // nothing being shown. Omitting it here keeps a bench log from containing a number that
        // no budget was ever written against.
        val samples = ArrayList<Map<String, Any?>>(stroke.points.size)
        if (stroke.tool != InkToolKind.ERASER) {
            for (point in stroke.points) {
                if (!point.touchToPresentMs.isFinite()) {
                    continue
                }
                samples.add(samplePayload(point))
            }
        }
        val payload = mapOf(
            "strokeId" to stroke.id,
            "blobId" to "inkview-${stroke.id}",
            "tool" to stroke.tool.name.lowercase(),
            "pointerType" to stroke.pointerKind.wireName,
            "drawAdmitted" to stroke.drawAdmitted,
            "rawToolType" to stroke.rawToolType,
            "sampleCount" to stroke.points.size,
            "bboxCenterX" to stroke.bboxCenterX().toDouble(),
            "bboxCenterY" to stroke.bboxCenterY().toDouble(),
            "bboxWidth" to stroke.bboxWidth().toDouble(),
            "bboxHeight" to stroke.bboxHeight().toDouble(),
            "maxTouchMajorPx" to stroke.maxTouchMajorPx,
            "meanTouchMajorPx" to stroke.meanTouchMajorPx(),
            "concurrentPointerSamples" to stroke.concurrentPointerSamples,
            "concurrentMaxTouchMajorPx" to stroke.concurrentMaxTouchMajorPx,
            "samples" to samples,
        )
        channel.invokeMethod("onStrokeFinished", payload)
    }

    /** Converts one measured sample into the flat map Dart receives. */
    private fun samplePayload(point: InkSampleRecord): Map<String, Any?> = mapOf(
        "sampleIndex" to point.sampleIndex,
        "pointerType" to point.pointerKind.wireName,
        "presentSource" to point.presentationSource.wireName,
        "touchToPresentMs" to point.touchToPresentMs,
        "eventTimeNanos" to point.eventTimeNanos,
        "presentTimeNanos" to point.presentTimeNanos,
        "pressure" to point.pressure,
        "tiltRadians" to point.tiltRadians,
        "orientationRadians" to point.orientationRadians,
        "touchMajorPx" to point.touchMajorPx,
        "isHistorical" to point.isHistorical,
        "eventAction" to point.eventAction,
        "sourceIsStylus" to point.sourceIsStylus,
        "rawToolType" to point.rawToolType,
        "rawSource" to point.rawSource,
        "x" to point.x.toDouble(),
        "y" to point.y.toDouble(),
    )

    // PURPOSE: Describe what the surface is measuring, or answer honestly that there is no surface
    //          yet, so a bench can print why it has no numbers instead of showing zeroes.
    // INPUTS: None.
    // OUTPUTS: The surface's own description when a view exists; otherwise a map whose
    //          `platformViewMode` is `none` and whose counts are zero.
    // KEYWORDS: surface-description, absent-surface, bench-preconditions
    private fun describeSurface(): Map<String, Any?> = surface?.describeSurface() ?: mapOf(
        "presentSource" to PresentationSourceKind.VSYNC_PLUS_DELAY.wireName,
        "timelineDelivered" to false,
        "usedTimelinePoster" to false,
        "apiLevel" to android.os.Build.VERSION.SDK_INT,
        "refreshRateHz" to 0.0,
        "refreshPeriodNanos" to 0L,
        "clockOffsetMs" to 0.0,
        "clockOffsetDriftMs" to 0.0,
        "eventTimePrecision" to if (android.os.Build.VERSION.SDK_INT >= 34) "nanosecond" else "millisecond",
        "platformViewMode" to "none",
        "deviceModel" to "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}".trim(),
        "androidRelease" to android.os.Build.VERSION.RELEASE.orEmpty(),
        "palmContactsSuppressed" to 0,
        "concurrentContactSamples" to 0,
        "concurrentMaxTouchMajorPx" to 0.0,
        "committedStrokeCount" to 0,
    )

    // PURPOSE: Encode the surface's strokes for the app, converting the opaque anchor text back
    //          into the map the contract requires.
    // INPUTS: None.
    // OUTPUTS: One map per stroke with `id`, `anchor`, `format` and `bytes`. An anchor that fails
    //          to parse becomes an empty map rather than failing the export, because losing the
    //          anchor must not lose the stroke.
    // KEYWORDS: export, stroke-blob, anchor-map, inkview-format
    private fun exportStrokes(): List<Map<String, Any?>> {
        val current = surface?.exportStrokes() ?: emptyList()
        return current.map { stroke ->
            mapOf(
                "id" to "inkview-${stroke.id}",
                "anchor" to anchorFromJson(stroke.anchorJson),
                "format" to INKVIEW_FORMAT,
                "bytes" to InkStrokeCodec.encode(listOf(stroke)),
            )
        }
    }

    /**
     * Replaces the surface's strokes from a list of blobs.
     *
     * A blob that does not decode is skipped and the rest are still loaded, because one corrupt
     * stroke should not cost the user every other stroke in the document.
     */
    private fun loadStrokes(call: MethodCall) {
        val entries = call.arguments as? List<*> ?: return
        val records = ArrayList<InkStrokeRecord>()
        for (entry in entries) {
            val blob = entry as? Map<*, *> ?: continue
            val bytes = blob["bytes"] as? ByteArray ?: continue
            val anchorJson = anchorToJson(blob["anchor"])
            val decoded = try {
                InkStrokeCodec.decode(bytes)
            } catch (error: IllegalArgumentException) {
                continue
            }
            for (record in decoded) {
                record.anchorJson = anchorJson
                records.add(record)
            }
        }
        surface?.loadStrokes(records)
    }

    // PURPOSE: Exercise the stroke format end to end on the device, so the round-trip property can
    //          be checked by the owner without a JVM test the project does not keep.
    // INPUTS: None.
    // OUTPUTS: `{ok, strokesBefore, strokesAfter, pointsBefore, pointsAfter, error}`. `ok` is true
    //          only when the counts survive the round trip; a failure names the exception.
    // KEYWORDS: round-trip, self-check, on-device-verification, codec
    private fun strokesRoundTripCheck(): Map<String, Any?> {
        val current = surface?.exportStrokes() ?: emptyList()
        val pointsBefore = current.sumOf { it.points.size }
        return try {
            val bytes = InkStrokeCodec.encode(current)
            val decoded = InkStrokeCodec.decode(bytes)
            val pointsAfter = decoded.sumOf { it.points.size }
            mapOf(
                "ok" to (decoded.size == current.size && pointsAfter == pointsBefore),
                "strokesBefore" to current.size,
                "strokesAfter" to decoded.size,
                "pointsBefore" to pointsBefore,
                "pointsAfter" to pointsAfter,
                "error" to null,
            )
        } catch (error: IllegalArgumentException) {
            mapOf(
                "ok" to false,
                "strokesBefore" to current.size,
                "strokesAfter" to 0,
                "pointsBefore" to pointsBefore,
                "pointsAfter" to 0,
                "error" to error.message,
            )
        }
    }

    private companion object {
        const val CHANNEL_NAME = "ink_native_android"

        /** Converts a plain Dart map into anchor JSON text; empty for anything unusable. */
        fun anchorToJson(anchor: Any?): String {
            val map = anchor as? Map<*, *> ?: return ""
            if (map.isEmpty()) {
                return ""
            }
            val plain = LinkedHashMap<String, Any?>()
            for ((key, value) in map) {
                plain[key.toString()] = toJsonValue(value)
            }
            return JSONObject(plain).toString()
        }

        /** Recursively converts a Dart-side value into something org.json can serialise. */
        fun toJsonValue(value: Any?): Any? = when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> {
                val plain = LinkedHashMap<String, Any?>()
                for ((key, nested) in value) {
                    plain[key.toString()] = toJsonValue(nested)
                }
                JSONObject(plain)
            }
            is Iterable<*> -> JSONArray(value.map { toJsonValue(it) })
            is Boolean, is Int, is Long, is Float, is Double, is String -> value
            is Number -> value.toDouble()
            else -> value.toString()
        }

        /** Parses anchor JSON text back into a plain map; empty when it cannot be parsed. */
        fun anchorFromJson(json: String): Map<String, Any?> {
            if (json.isEmpty()) {
                return emptyMap()
            }
            return try {
                val parsed = JSONObject(json)
                parsed.keys().asSequence().associateWith { key -> fromJsonValue(parsed.get(key)) }
            } catch (error: JSONException) {
                emptyMap()
            }
        }

        /** Recursively converts an org.json value into a plain map, list or scalar. */
        fun fromJsonValue(value: Any?): Any? = when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> value.keys().asSequence().associateWith { key ->
                fromJsonValue(value.get(key))
            }
            is JSONArray -> (0 until value.length()).map { index -> fromJsonValue(value.get(index)) }
            else -> value
        }
    }
}
