// PURPOSE: Encode and decode the Android ink surface's own stroke format, so a stroke drawn with
//          the pen can be exported as bytes, stored by the app and loaded back without the app
//          knowing anything about how this surface keeps strokes in memory. The platform
//          contract deliberately defines no portable ink format, so each native engine owns its
//          own; this is Android's.
// INPUTS: encode takes the surface's committed stroke records. decode takes the byte array a
//         previous encode produced, or a corrupted one.
// OUTPUTS: encode returns a new byte array, little-endian, laid out as
//          `"INKV" | version:u8 | strokeCount:u32 | stroke*`, where each stroke is
//          `id:i32 | tool:u8 | pointerKind:u8 | anchorLength:u16 | anchorUtf8 | pointCount:u32`
//          followed by points of `x:f32 y:f32 pressure:f32 tilt:f32 orientation:f32`.
//          The format name reported to Dart is `inkview`.
//          decode throws [IllegalArgumentException] on a short, mistyped or truncated buffer
//          rather than returning a partial stroke list, because a silently half-decoded document
//          would look like data loss the user caused; the caller reports the failure.
//          A stroke with no points encodes and decodes to a stroke with no points.
// KEYWORDS: stroke-codec, inkview-format, serialization, binary-format, round-trip
package com.chartapp.ink_native_android

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets

/** The format name written into `InkStrokeBlob.format` for bytes from [InkStrokeCodec]. */
const val INKVIEW_FORMAT: String = "inkview"

/** The version byte [InkStrokeCodec] writes and the only one it reads. */
const val INKVIEW_VERSION: Int = 1

// PURPOSE: Own the byte layout of the Android stroke format so the drawing view does not mix
//          rendering with persistence, and so a format change is one file to read.
// INPUTS: None; both entry points are static.
// OUTPUTS: Byte arrays and stroke records as described on [InkStrokeCodec.encode] and
//          [InkStrokeCodec.decode].
// KEYWORDS: codec, inkview, byte-buffer, little-endian, defensive-parsing
object InkStrokeCodec {
    private val MAGIC = byteArrayOf('I'.code.toByte(), 'N'.code.toByte(), 'K'.code.toByte(), 'V'.code.toByte())

    /**
     * Encodes [strokes] into the inkview format.
     *
     * The point list is written in the order the samples arrived, which is the same order they
     * were drawn in; nothing is reordered or decimated, because a stroke that replays with
     * dropped coalesced samples would look like a different stroke.
     */
    fun encode(strokes: List<InkStrokeRecord>): ByteArray {
        var size = 4 + 1 + 4
        val anchors = ArrayList<ByteArray>(strokes.size)
        for (stroke in strokes) {
            val anchorBytes = stroke.anchorJson.toByteArray(StandardCharsets.UTF_8)
            anchors.add(anchorBytes)
            size += 4 + 1 + 1 + 2 + anchorBytes.size + 4 + stroke.points.size * 20
        }
        val buffer = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put(MAGIC)
        buffer.put(INKVIEW_VERSION.toByte())
        buffer.putInt(strokes.size)
        for ((index, stroke) in strokes.withIndex()) {
            buffer.putInt(stroke.id)
            buffer.put(stroke.tool.ordinal.toByte())
            buffer.put(stroke.pointerKind.ordinal.toByte())
            val anchorBytes = anchors[index]
            buffer.putShort(anchorBytes.size.toShort())
            buffer.put(anchorBytes)
            buffer.putInt(stroke.points.size)
            for (point in stroke.points) {
                buffer.putFloat(point.x)
                buffer.putFloat(point.y)
                buffer.putFloat(point.pressure.toFloat())
                buffer.putFloat(point.tiltRadians.toFloat())
                buffer.putFloat(point.orientationRadians.toFloat())
            }
        }
        return buffer.array()
    }

    /**
     * Decodes bytes produced by [encode].
     *
     * @throws IllegalArgumentException when the magic, version, declared lengths or declared
     *         counts do not fit the supplied bytes.
     */
    fun decode(bytes: ByteArray): List<InkStrokeRecord> {
        if (bytes.size < 9) {
            throw IllegalArgumentException("inkview blob is ${bytes.size} bytes, too short for a header")
        }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val magic = ByteArray(4)
        buffer.get(magic)
        if (!magic.contentEquals(MAGIC)) {
            throw IllegalArgumentException("inkview blob does not start with the INKV magic")
        }
        val version = buffer.get().toInt()
        if (version != INKVIEW_VERSION) {
            throw IllegalArgumentException("inkview version $version is not supported")
        }
        val strokeCount = buffer.intOrThrow("stroke count")
        if (strokeCount < 0) {
            throw IllegalArgumentException("inkview stroke count $strokeCount is negative")
        }
        val strokes = ArrayList<InkStrokeRecord>(strokeCount)
        repeat(strokeCount) {
            val id = buffer.intOrThrow("stroke id")
            val tool = toolOrThrow(buffer.get().toInt())
            val kind = kindOrThrow(buffer.get().toInt())
            val anchorLength = buffer.shortOrThrow("anchor length").toInt() and 0xFFFF
            if (buffer.remaining() < anchorLength) {
                throw IllegalArgumentException("inkview anchor of $anchorLength bytes runs past the end")
            }
            val anchorBytes = ByteArray(anchorLength)
            buffer.get(anchorBytes)
            val pointCount = buffer.intOrThrow("point count")
            if (pointCount < 0 || buffer.remaining() < pointCount * 20) {
                throw IllegalArgumentException("inkview point count $pointCount does not fit the blob")
            }
            val stroke = InkStrokeRecord(id, tool, kind, rawToolType = 0)
            stroke.anchorJson = String(anchorBytes, StandardCharsets.UTF_8)
            repeat(pointCount) { index ->
                val x = buffer.floatOrThrow("point x")
                val y = buffer.floatOrThrow("point y")
                val pressure = buffer.floatOrThrow("point pressure")
                val tilt = buffer.floatOrThrow("point tilt")
                val orientation = buffer.floatOrThrow("point orientation")
                // A reloaded sample carries geometry but no measured latency: the timestamps
                // belong to the run that produced it, and inventing them here would put a made-up
                // number next to measured ones in a bench log.
                stroke.add(
                    InkSampleRecord(
                        sampleIndex = index,
                        pointerKind = kind,
                        presentationSource = PresentationSourceKind.VSYNC_PLUS_DELAY,
                        touchToPresentMs = Double.NaN,
                        eventTimeNanos = 0L,
                        presentTimeNanos = 0L,
                        pressure = pressure.toDouble(),
                        tiltRadians = tilt.toDouble(),
                        orientationRadians = orientation.toDouble(),
                        touchMajorPx = 0.0,
                        isHistorical = false,
                        eventAction = "loaded",
                        sourceIsStylus = kind == InkPointerKind.S_PEN || kind == InkPointerKind.S_PEN_ERASER,
                        rawToolType = 0,
                        rawSource = 0,
                        x = x,
                        y = y,
                    ),
                )
            }
            strokes.add(stroke)
        }
        return strokes
    }

    private fun toolOrThrow(ordinal: Int): InkToolKind {
        val values = InkToolKind.entries
        if (ordinal < 0 || ordinal >= values.size) {
            throw IllegalArgumentException("inkview tool ordinal $ordinal is out of range")
        }
        return values[ordinal]
    }

    private fun kindOrThrow(ordinal: Int): InkPointerKind {
        val values = InkPointerKind.entries
        if (ordinal < 0 || ordinal >= values.size) {
            throw IllegalArgumentException("inkview pointer kind ordinal $ordinal is out of range")
        }
        return values[ordinal]
    }

    private fun ByteBuffer.intOrThrow(field: String): Int {
        if (remaining() < 4) {
            throw IllegalArgumentException("inkview blob ends before $field")
        }
        return int
    }

    private fun ByteBuffer.shortOrThrow(field: String): Short {
        if (remaining() < 2) {
            throw IllegalArgumentException("inkview blob ends before $field")
        }
        return short
    }

    private fun ByteBuffer.floatOrThrow(field: String): Float {
        if (remaining() < 4) {
            throw IllegalArgumentException("inkview blob ends before $field")
        }
        return float
    }
}
