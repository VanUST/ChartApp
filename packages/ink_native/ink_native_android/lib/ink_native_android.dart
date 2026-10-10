// PURPOSE: Implement the ink platform contract on Android by talking to the Kotlin ink surface,
//          so the app drives one API on every platform and the Kotlin view is an implementation
//          detail. It also forwards the surface's measurements upward, which is what makes an
//          input-to-present latency measurable at all: the timestamps exist only where the
//          digitizer and the Choreographer exist, and that is behind this channel.
// INPUTS: Method calls from the app (`initialize`, `setTool`, `setTransform`, `loadStrokes`,
//         `exportStrokes`, `describeSurface`, `benchLogDirectory`) and `onStrokeFinished`
//         callbacks pushed by the Kotlin plugin, each stroke carrying its contact-admission
//         decision (reason, compared width, threshold) alongside its geometry.
// OUTPUTS: Futures that complete when the native side has applied a change; broadcast streams
//          `onStrokeCommitted`, `onLatencySample` and `onPalmObservation`; and a description of
//          what the surface measures, including the palm-width threshold it applied.
//          A latency sample is emitted only for a sample the surface actually drew. An eraser
//          gesture and a suppressed palm contact therefore produce none, because nothing was
//          presented for them and a latency for them would be a measurement of nothing.
// KEYWORDS: ink-native, android, platform-view, method-channel, federated-implementation,
//           latency-samples, registration
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ink_native_platform_interface/ink_native_platform_interface.dart';

// PURPOSE: Name the platform-view type the Dart widget tree must request, so the string that has
//          to match on both sides of the channel lives in exactly one place per side.
// INPUTS: None.
// OUTPUTS: The view type the Kotlin factory is registered under.
// KEYWORDS: platform-view, view-type, wire-constant
/// The Android platform-view type that renders the native ink surface.
const String inkSurfaceViewType = 'ink_native_android/surface';

/// The Android implementation of the ink platform contract.
class InkNativeAndroid extends InkNativePlatform {
  /// Creates the Android implementation.
  ///
  /// It deliberately touches no platform channel here. The generated Dart plugin registrant calls
  /// [registerWith] before the `WidgetsFlutterBinding` exists, and a `setMethodCallHandler` call at
  /// that point throws `Cannot set the method call handler before the binary messenger has been
  /// initialized` — measured on a Galaxy Tab S8+ running Android 12, where the thrown error left
  /// this implementation unregistered and the app on the desktop no-op. The handler is installed by
  /// [initialize] instead, which the contract already requires a caller to await before any other
  /// call.
  InkNativeAndroid();

  /// Installs this implementation, called by the generated plugin registrant at startup.
  ///
  /// The registrant runs before `main`, so the app-facing fallback never claims the slot on
  /// Android and [InkNativePlatform.supportsInk] is already true by the time a widget reads it.
  static void registerWith() {
    InkNativePlatform.instance = InkNativeAndroid();
  }

  static const String _channelName = 'ink_native_android';

  final MethodChannel _channel = const MethodChannel(_channelName);

  bool _handlerInstalled = false;

  final StreamController<CommittedStroke> _committedController =
      StreamController<CommittedStroke>.broadcast();

  final StreamController<InkLatencySample> _latencyController =
      StreamController<InkLatencySample>.broadcast();

  final StreamController<InkPalmObservation> _palmController =
      StreamController<InkPalmObservation>.broadcast();

  /// The most recent description read from the surface, or null before one has been read.
  InkSurfaceInfo? _lastSurfaceInfo;

  /// The last description read from the surface, or null when none has been read yet.
  InkSurfaceInfo? get lastSurfaceInfo => _lastSurfaceInfo;

  @override
  bool get supportsInk => true;

  @override
  Stream<CommittedStroke> get onStrokeCommitted => _committedController.stream;

  @override
  Stream<InkLatencySample> get onLatencySample => _latencyController.stream;

  @override
  Stream<InkPalmObservation> get onPalmObservation => _palmController.stream;

  @override
  Future<void> initialize() async {
    _installHandler();
    await _channel.invokeMethod<void>('initialize');
  }

  void _installHandler() {
    if (_handlerInstalled) {
      return;
    }
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  Future<void> setTool(InkTool tool) async {
    await _channel.invokeMethod<void>('setTool', <String, Object?>{
      'tool': switch (tool) {
        InkTool.pen => 'pen',
        InkTool.highlighter => 'highlighter',
        InkTool.eraser => 'eraser',
      },
    });
  }

  @override
  Future<void> setTransform(InkViewTransform transform) async {
    await _channel.invokeMethod<void>('setTransform', <String, Object?>{
      'scale': transform.scale,
      'translationX': transform.translation.dx,
      'translationY': transform.translation.dy,
    });
  }

  @override
  Future<void> loadStrokes(Iterable<InkStrokeBlob> strokes) async {
    await _channel.invokeMethod<void>('loadStrokes', <Map<String, Object?>>[
      for (final InkStrokeBlob stroke in strokes)
        <String, Object?>{
          'id': stroke.id,
          'anchor': stroke.anchor,
          'format': stroke.format,
          'bytes': stroke.bytes,
        },
    ]);
  }

  @override
  Future<List<InkStrokeBlob>> exportStrokes() async {
    final Object? raw = await _channel.invokeMethod<Object?>('exportStrokes');
    if (raw is! List<Object?>) {
      return const <InkStrokeBlob>[];
    }
    final List<InkStrokeBlob> strokes = <InkStrokeBlob>[];
    for (final Object? entry in raw) {
      if (entry is! Map<Object?, Object?>) {
        continue;
      }
      final Object? bytes = entry['bytes'];
      if (bytes is! Uint8List) {
        continue;
      }
      strokes.add(
        InkStrokeBlob(
          id: _stringOf(entry['id']) ?? '',
          anchor: _anchorOf(entry['anchor']),
          format: _stringOf(entry['format']) ?? '',
          bytes: bytes,
        ),
      );
    }
    return strokes;
  }

  @override
  Future<InkSurfaceInfo> describeSurface() async {
    final Object? raw = await _channel.invokeMethod<Object?>('describeSurface');
    final Map<Object?, Object?> map = raw is Map<Object?, Object?>
        ? raw
        : const <Object?, Object?>{};
    final InkSurfaceInfo info = InkSurfaceInfo(
      platformViewMode: _stringOf(map['platformViewMode']) ?? 'unknown',
      presentationSource: InkPresentationSource.fromWireName(
        _stringOf(map['presentSource']),
      ),
      apiLevel: _intOf(map['apiLevel']),
      refreshRateHz: _doubleOf(map['refreshRateHz']),
      clockOffsetMs: _doubleOf(map['clockOffsetMs']),
      clockOffsetDriftMs: _doubleOf(map['clockOffsetDriftMs']),
      deviceModel: _stringOf(map['deviceModel']) ?? '',
      androidRelease: _stringOf(map['androidRelease']) ?? '',
      eventTimePrecision: _stringOf(map['eventTimePrecision']) ?? 'unknown',
      usedTimelinePoster: map['usedTimelinePoster'] == true,
      displayDensity: _doubleOf(map['displayDensity']),
      palmWidthThreshold: _doubleOf(map['palmWidthThreshold']),
      palmStylusProximityWindowMs: _intOf(map['palmStylusProximityWindowMs']),
      stylusHoverEventCount: _intOf(map['stylusHoverEvents']),
    );
    _lastSurfaceInfo = info;
    return info;
  }

  @override
  Future<String?> benchLogDirectory() async =>
      _channel.invokeMethod<String>('benchLogDirectory');

  /// Removes every stroke from the native surface.
  ///
  /// Not part of the platform contract: the contract replaces strokes wholesale through
  /// `loadStrokes`, and clearing is `loadStrokes(const [])`. It exists because the bench needs to
  /// start a fresh page without rebuilding the whole stroke list.
  Future<void> clearStrokes() async {
    await _channel.invokeMethod<void>('clearStrokes');
  }

  // PURPOSE: Run the stroke format's round trip inside the device process, so the serializer can
  //          be checked where it actually runs instead of only where it was written.
  // INPUTS: None.
  // OUTPUTS: A map with `ok`, the stroke and point counts before and after, and an `error`
  //          message when it failed. Never throws for a failed round trip.
  // KEYWORDS: round-trip, self-check, on-device-verification, codec
  /// Encodes the surface's strokes and decodes them again, reporting whether the counts survived.
  Future<Map<Object?, Object?>> strokesRoundTripCheck() async {
    final Object? raw = await _channel.invokeMethod<Object?>(
      'strokesRoundTripCheck',
    );
    return raw is Map<Object?, Object?> ? raw : const <Object?, Object?>{};
  }

  /// Releases the surface's streams. The implementation is a process-lifetime singleton, so this
  /// exists for tests and for an orderly shutdown rather than for normal operation.
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    _handlerInstalled = false;
    await _committedController.close();
    await _latencyController.close();
    await _palmController.close();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onStrokeFinished') {
      return;
    }
    final Object? raw = call.arguments;
    if (raw is! Map<Object?, Object?>) {
      return;
    }
    final String tool = _stringOf(raw['tool']) ?? '';
    final bool drawAdmitted = raw['drawAdmitted'] == true;
    if (drawAdmitted && tool != 'eraser') {
      _committedController.add(
        CommittedStroke(
          blobId: _stringOf(raw['blobId']) ?? '',
          bboxCenter: Offset(
            _doubleOf(raw['bboxCenterX']),
            _doubleOf(raw['bboxCenterY']),
          ),
          bboxSize: Size(
            _doubleOf(raw['bboxWidth']),
            _doubleOf(raw['bboxHeight']),
          ),
        ),
      );
    }
    final Object? samples = raw['samples'];
    final int strokeId = _intOf(raw['strokeId']);
    if (samples is List<Object?>) {
      for (final Object? entry in samples) {
        if (entry is Map<Object?, Object?>) {
          _latencyController.add(_sampleOf(strokeId, entry));
        }
      }
    }
    _palmController.add(
      InkPalmObservation(
        strokeId: strokeId,
        pointerKind: InkPointerKind.fromWireName(_stringOf(raw['pointerType'])),
        eventCount: _intOf(raw['sampleCount']),
        maxTouchMajorPx: _doubleOf(raw['maxTouchMajorPx']),
        meanTouchMajorPx: _doubleOf(raw['meanTouchMajorPx']),
        rawToolType: _intOf(raw['rawToolType']),
        drawAdmitted: drawAdmitted,
        concurrentPointerSamples: _intOf(raw['concurrentPointerSamples']),
        concurrentMaxTouchMajorPx: _doubleOf(raw['concurrentMaxTouchMajorPx']),
        admissionReason: _stringOf(raw['admissionReason']) ?? '',
        palmLikeWidth: raw['palmLikeWidth'] == true,
        decidingTouchMajor: _doubleOf(raw['decidingTouchMajor']),
        palmWidthThreshold: _doubleOf(raw['palmWidthThreshold']),
        stylusInPlay: raw['stylusInPlay'] == true,
      ),
    );
  }

  static InkLatencySample _sampleOf(int strokeId, Map<Object?, Object?> map) =>
      InkLatencySample(
        strokeId: strokeId,
        sampleIndex: _intOf(map['sampleIndex']),
        pointerKind: InkPointerKind.fromWireName(_stringOf(map['pointerType'])),
        presentationSource: InkPresentationSource.fromWireName(
          _stringOf(map['presentSource']),
        ),
        touchToPresentMs: _doubleOf(map['touchToPresentMs']),
        eventTimeNanos: _intOf(map['eventTimeNanos']),
        presentTimeNanos: _intOf(map['presentTimeNanos']),
        pressure: _doubleOf(map['pressure']),
        tiltRadians: _doubleOf(map['tiltRadians']),
        orientationRadians: _doubleOf(map['orientationRadians']),
        touchMajorPx: _doubleOf(map['touchMajorPx']),
        isHistorical: map['isHistorical'] == true,
        eventAction: _stringOf(map['eventAction']) ?? '',
        sourceIsStylus: map['sourceIsStylus'] == true,
        rawToolType: _intOf(map['rawToolType']),
        rawSource: _intOf(map['rawSource']),
        x: _doubleOf(map['x']),
        y: _doubleOf(map['y']),
      );

  static Map<String, Object?> _anchorOf(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        entry.key.toString(): entry.value,
    };
  }

  static String? _stringOf(Object? value) => value is String ? value : null;

  static int _intOf(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : 0;

  static double _doubleOf(Object? value) => value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value) ?? 0
      : 0;
}
