// PURPOSE: Measure what a REAL browser delivers to the page for stylus and finger input, separately
//          from what Flutter's own pointer stream reports, so the decision "does the pen need a raw
//          JavaScript capture layer, or is Flutter's mapped stream enough?" rests on two numbers
//          read from the same page at the same moment rather than on an assumption about either.
//
//          WHY A DOM LISTENER AND NOT FLUTTER'S EVENT. Flutter's stream is the thing under test.
//          Observing it with itself proves nothing, so the second observer is attached to the
//          document in the capture phase, BEFORE Flutter's own listener sees the event, and records
//          the browser's own `pressure`, `tiltX`, `tiltY`, `width`, `pointerType` and the coalesced
//          samples of each move. The two streams are then compared field by field.
//
//          IT IS AN OBSERVER AND NOT A HANDLER. The listeners are passive, they call no
//          `preventDefault`, they do not stop propagation, and they never touch Flutter's event
//          objects. A measurement taken with a probe that changed the input path would be a
//          measurement of the probe.
// INPUTS: A callback for each raw sample, so a Dart-side accumulator can hold the same numbers
//         without crossing the JavaScript boundary per event.
// OUTPUTS: [InkProbeControl.report] with `supported: true`, the user agent, and for both the
//          browser's stream and nothing else: per-stroke counts, the number of DISTINCT pressure and
//          tilt values, the coalesced-to-event ratio, and the hover count. Distinct values are the
//          number that matters — a constant pressure axis and a working one have the same mean.
// KEYWORDS: measurement, pointer-events, raw-stream, pressure, tilt, coalesced-events, hover, web,
//           js-interop, observer-only
//
// WHAT THIS CANNOT MEASURE, AND DOES NOT CLAIM TO.
//   - Presentation latency. There is no browser API for the moment a frame reaches the glass, so
//     the spike's `paintLatency` was input-to-our-paint and is a lower bound. This probe does not
//     measure latency at all.
//   - Whether a device HARDLY HAS a pen. Every number here describes what arrived, and a run with
//     no stylus in play says so by reporting zero pressure variation and zero hover events.
//   - Whether a palm was suppressed by the platform before delivery. A palm that never reaches the
//     page is indistinguishable here from a palm that was never on the glass.
//   - Pointer capture. The DOM listener is on the document, so it sees events whether or not a
//     capture is held elsewhere; that is deliberate, because the probe must not depend on Flutter
//     having captured the pointer.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'ink_pointer_probe_contract.dart';

/// The browser's own pointer event, with only the fields this probe reads.
extension type const _PointerEvent(JSObject _) implements JSObject {
  /// The pointer kind the browser reports: `pen`, `touch` or `mouse`.
  external String? get pointerType;

  /// Pressure in `[0, 1]`, or 0.5 for a device that reports none.
  external double? get pressure;

  /// Tilt about the X axis, in degrees in `[-90, 90]`.
  external double? get tiltX;

  /// Tilt about the Y axis, in degrees in `[-90, 90]`.
  external double? get tiltY;

  /// Contact width in CSS pixels, or 0 when the platform reports none.
  external double? get width;

  /// Contact height in CSS pixels.
  external double? get height;

  /// Horizontal position in the viewport, in CSS pixels.
  external double? get clientX;

  /// Vertical position in the viewport, in CSS pixels.
  external double? get clientY;

  /// Horizontal position within the event's target, in CSS pixels.
  external double? get offsetX;

  /// Vertical position within the event's target, in CSS pixels.
  external double? get offsetY;

  /// The high-rate samples the browser coalesced into this event.
  external JSArray<JSAny?> getCoalescedEvents();
}

/// The browser's `window`, which is where the probe keeps both of its handles.
///
/// `onEvent` holds the Dart function the browser calls for each pointer event and `inkProbe` holds
/// the object a browser-driving tool uses to reset and read the counters. Reusing `onEvent` rather
/// than inventing a property name is deliberate: it is a standard slot whose owner is whoever is
/// currently listening, and this probe is the only listener the application installs on it.
extension type const _Window(JSObject _) implements JSObject {
  /// The Dart function the browser invokes for each observed pointer event.
  external set onEvent(JSFunction value);

  /// The browser's `navigator`, read for the user agent.
  external _Navigator? get navigator;
}

/// The browser's `navigator`, read for one field.
extension type const _Navigator(JSObject _) implements JSObject {
  /// The browser's user agent string.
  external String? get userAgent;
}

/// Per-stream accumulators for one source of pointer samples.
class _StreamTally {
  int samples = 0;
  int events = 0;
  int coalesced = 0;
  int penSamples = 0;
  int touchSamples = 0;
  int mouseSamples = 0;
  int hoverSeen = 0;
  int penHoverSeen = 0;
  int downSamples = 0;
  int upSamples = 0;
  final Set<double> pressureValues = <double>{};
  final Set<int> tiltValues = <int>{};
  final Set<int> widths = <int>{};
  double pressureMin = double.infinity;
  double pressureMax = double.negativeInfinity;
  double firstClientX = -1;
  double firstClientY = -1;
  double firstOffsetX = -1;
  double firstOffsetY = -1;
  double lastClientX = -1;
  double lastClientY = -1;
  double lastOffsetX = -1;
  double lastOffsetY = -1;

  /// How many events this stream carried, and how many samples it expanded to.
  double get coalescedPerEvent => events == 0 ? 0 : coalesced / events;

  /// The tally as a flat map, so one report shape is used for both streams.
  ///
  /// The positions are carried so a run can check WHERE a stroke landed as well as how many samples
  /// it took: a stroke the application drew at the right place and one it drew at the wrong place
  /// have the same sample count, and only the coordinates can tell them apart.
  Map<String, Object?> toJson() => <String, Object?>{
    'samples': samples,
    'events': events,
    'coalescedPerEvent': double.parse(coalescedPerEvent.toStringAsFixed(2)),
    'penSamples': penSamples,
    'touchSamples': touchSamples,
    'mouseSamples': mouseSamples,
    'hoverEvents': hoverSeen,
    'penHoverEvents': penHoverSeen,
    'downSamples': downSamples,
    'upSamples': upSamples,
    'distinctPressureValues': pressureValues.length,
    'distinctTiltValues': tiltValues.length,
    'widthsSeen': widths.toList()..sort(),
    'pressureMin': pressureMin.isFinite
        ? double.parse(pressureMin.toStringAsFixed(3))
        : null,
    'pressureMax': pressureMax.isFinite
        ? double.parse(pressureMax.toStringAsFixed(3))
        : null,
    'firstClient': <double>[firstClientX, firstClientY],
    'lastClient': <double>[lastClientX, lastClientY],
    'firstOffset': <double>[firstOffsetX, firstOffsetY],
    'lastOffset': <double>[lastOffsetX, lastOffsetY],
  };
}

/// The browser implementation of the ink input probe.
abstract final class InkInputProbe {
  /// Installs the document listeners and returns the control that reads their counters.
  ///
  /// The sample callback is invoked once per raw sample, with coalesced samples included, so a
  /// Flutter-side accumulator holds the same numbers without an interop crossing per sample. The
  /// callback must not throw: it runs inside the browser's event dispatch.
  static InkProbeControl install({
    required void Function(InkProbeSample sample) onRawSample,
  }) {
    final _BrowserInkProbe probe = _BrowserInkProbe(onRawSample);
    probe.install();
    return probe.control;
  }
}

/// The state of one installed probe.
class _BrowserInkProbe {
  _BrowserInkProbe(this._onRawSample);

  final void Function(InkProbeSample sample) _onRawSample;
  final _StreamTally _tally = _StreamTally();

  /// The handle the app reads.
  InkProbeControl get control =>
      InkProbeControl.measured(reset: reset, report: _report);

  /// How many strokes a browser stream has carried, counted as a `pointerdown` per stream sample.
  ///
  /// Not a Dart-side stroke count: the app's own document is the authority on that, and the probe
  /// reports only what the raw stream contained so the two can be compared.
  int get _downs => _tally.downSamples;

  /// Installs the document listeners, and a global handle so a browser-driving tool can reset and
  /// read the counters without a second import path into the app.
  ///
  /// The handle is built as a plain JavaScript object of two function properties rather than through
  /// `createJSInteropWrapper`, because that helper requires a `@JSExport` annotation on the class it
  /// wraps and the wrapper's own members are what the compiler then demands — including the private
  /// state this class keeps. Two closures converted with `toJS` give the same handle with nothing
  /// exported but what a browser is meant to call.
  void install() {
    final _Window window = _Window(globalContext);
    final JSFunction onEvent = ((JSObject event) => _handle(event)).toJS;
    window.onEvent = onEvent;
    globalContext.setProperty(
      'chartappInkProbe'.toJS,
      <String, Object?>{
        'reset': (() => reset()).toJS,
        // The report crosses the boundary as a plain object rather than as a Dart map: a function
        // converted with `toJS` may only take and return types JavaScript has, and a `Map` is not one
        // of them. `jsify` performs that conversion inside the closure, and returning `JSObject` is
        // the one shape the compiler accepts.
        'report': (() => _report().jsify()! as JSObject).toJS,
        // The application's own ink state, LIVE: read from the controller on the spot rather than
        // from the last published line. The published line is written when the application rebuilds,
        // and an inspector that reads it right after dispatching input sees the state from BEFORE
        // that input — a stale reading that looks exactly like a feature that did nothing. This path
        // is the one that reports what is true now.
        'inkState': (() => (InkProbeControl.publishedInkState ?? '').toJS).toJS,
        'inkReport': (() => inkStateReader().jsify()! as JSObject).toJS,
        'strokeCount': (() => strokeCountReader()).toJS,
        'inkInput': (() => inkInputCountersReader().jsify()! as JSObject).toJS,
        'page': (() => pageGeometryReader().jsify()! as JSObject).toJS,
      }.jsify()!,
    );
    final JSObject document = globalContext['document'] as JSObject;
    for (final String type in <String>[
      'pointerdown',
      'pointermove',
      'pointerup',
      'pointercancel',
      'pointerover',
    ]) {
      document.callMethod<JSAny?>(
        'addEventListener'.toJS,
        type.toJS,
        onEvent,
        _passiveCapture,
      );
    }
    debugPrint(
      'ink.probe.install supported=true pointer_types=pen,touch,mouse '
      'coalesced=true passive=true',
    );
  }

  /// Discards every counter, so a run can mark the moment before its own input began.
  void reset() {
    _tally
      ..samples = 0
      ..events = 0
      ..coalesced = 0
      ..penSamples = 0
      ..touchSamples = 0
      ..mouseSamples = 0
      ..hoverSeen = 0
      ..penHoverSeen = 0
      ..downSamples = 0
      ..upSamples = 0
      ..pressureValues.clear()
      ..tiltValues.clear()
      ..widths.clear()
      ..pressureMin = double.infinity
      ..pressureMax = double.negativeInfinity;
  }

  /// Handles one DOM event: reads the event itself and, for a move, its coalesced samples too.
  void _handle(JSObject event) {
    final _PointerEvent pointer = _PointerEvent(event);
    final String type = _typeOf(pointer);
    final bool isHover = type == 'pointerover';
    final String kind = pointer.pointerType ?? 'unknown';
    if (isHover) {
      _tally.hoverSeen++;
      if (kind == 'pen') {
        _tally.penHoverSeen++;
      }
      return;
    }
    _tally.events++;
    if (type == 'pointerdown') {
      _tally.downSamples++;
    } else if (type == 'pointerup') {
      _tally.upSamples++;
    }

    final List<_PointerEvent> samples = <_PointerEvent>[pointer];
    try {
      final JSArray<JSAny?> coalesced = pointer.getCoalescedEvents();
      if (coalesced.length > 0) {
        samples
          ..clear()
          ..addAll(coalesced.toDart.cast<_PointerEvent>());
      }
    } catch (_) {
      // A browser that advertises the method and then throws is a real WebKit bug; treating the
      // event itself as the only sample is the honest fallback and is what the count then reports.
    }
    for (final _PointerEvent sample in samples) {
      _record(sample, kind: kind, type: type, coalesced: samples.length > 1);
    }
  }

  /// Accumulates one sample and forwards it to the Dart-side callback.
  void _record(
    _PointerEvent sample, {
    required String kind,
    required String type,
    required bool coalesced,
  }) {
    final double pressure = sample.pressure ?? 0;
    final double tiltX = sample.tiltX ?? 0;
    final double tiltY = sample.tiltY ?? 0;
    final double width = sample.width ?? 0;
    final double browserTime = _timeStampOf(sample);
    _tally.samples++;
    _tally.coalesced++;
    _tally.pressureValues.add((pressure * 100).round() / 100);
    _tally.tiltValues.add((tiltX / 5).round() * 5);
    _tally.widths.add(width.round());
    switch (kind) {
      case 'pen':
        _tally.penSamples++;
      case 'touch':
        _tally.touchSamples++;
      default:
        _tally.mouseSamples++;
    }
    if (pressure < _tally.pressureMin) {
      _tally.pressureMin = pressure;
    }
    if (pressure > _tally.pressureMax) {
      _tally.pressureMax = pressure;
    }
    if (_tally.samples == 1) {
      _tally.firstClientX = sample.clientX ?? -1;
      _tally.firstClientY = sample.clientY ?? -1;
      _tally.firstOffsetX = sample.offsetX ?? -1;
      _tally.firstOffsetY = sample.offsetY ?? -1;
    }
    _tally.lastClientX = sample.clientX ?? -1;
    _tally.lastClientY = sample.clientY ?? -1;
    _tally.lastOffsetX = sample.offsetX ?? -1;
    _tally.lastOffsetY = sample.offsetY ?? -1;
    _onRawSample(
      InkProbeSample(
        pointerType: kind,
        pressure: pressure,
        tiltXDegrees: tiltX,
        tiltYDegrees: tiltY,
        width: width,
        isCoalesced: coalesced,
        eventType: type,
        browserTimeMs: browserTime,
      ),
    );
  }

  /// The browser's own `timeStamp` for a pointer event, in milliseconds.
  ///
  /// `timeStamp` is a `DOMHighResTimeStamp` measured from the same origin as `performance.now()`,
  /// which is the same origin the engine converts a Flutter `PointerEvent.timeStamp` from — that is
  /// what makes the two streams' times comparable. A non-finite or missing value falls back to
  /// `performance.now()` read at this moment, which is measured from that same origin.
  double _timeStampOf(_PointerEvent event) {
    final double? stamp = (event as JSObject)
        .getProperty<JSNumber?>('timeStamp'.toJS)
        ?.toDartDouble;
    if (stamp != null && stamp.isFinite) {
      return stamp;
    }
    return _nowMs();
  }

  /// `performance.now()`, in milliseconds from the page's own time origin.
  double _nowMs() => (globalContext['performance'] as JSObject)
      .callMethod<JSNumber>('now'.toJS)
      .toDartDouble;

  /// The DOM event type, read off the event's own `type` property.
  ///
  /// `type` is a member of every `Event` and is populated for a dispatched event, so reading it here
  /// is the same value the browser's own listener would branch on.
  String _typeOf(_PointerEvent event) =>
      (event as JSObject).getProperty<JSString?>('type'.toJS)?.toDart ??
      'pointermove';

  /// The measurements, as a plain map.
  ///
  /// It writes nothing: the handle returned by [InkInputProbe.install] is what a tool calls, and the
  /// application's own ink state is read through [inkStateReader], which answers at the moment it is
  /// asked. Writing the document title here was tried and removed — Flutter's `Title` widget
  /// rewrites it on every rebuild, so a state published there is gone within a frame.
  Map<String, Object?> _report() => <String, Object?>{
    'name': 'ink.pointer.probe',
    'supported': true,
    'userAgent': _Window(globalContext).navigator?.userAgent,
    'raw': _tally.toJson(),
    'rawDownEvents': _downs,
  };
}

/// The options object for a passive capture-phase listener.
///
/// Passive because the probe must not be able to delay or cancel the input it observes, and capture
/// because the browser's value has to be read before anything else can modify the event.
final JSAny _passiveCapture = <String, Object?>{
  'passive': true,
  'capture': true,
}.jsify()!;
