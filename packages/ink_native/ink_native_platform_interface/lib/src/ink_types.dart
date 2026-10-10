// PURPOSE: Define the value types that cross the Dart/native boundary for ink, so that the
//          three platform implementations and the app agree on what a tool, a transform, a
//          stored stroke and a committed stroke are, and a change to one of them is a
//          compile error in all of them rather than a silent mismatch at runtime.
// INPUTS: None; these are plain immutable values.
// OUTPUTS: Immutable objects with value equality is NOT provided — identity is by reference —
//          so an instance is compared only after conversion at the boundary.
// KEYWORDS: ink-tool, view-transform, stroke-blob, committed-stroke, value-types
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
