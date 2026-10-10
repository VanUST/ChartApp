// PURPOSE: Turn a stream of Flutter pointer events into committed strokes, and decide — once per
//          contact, from the two signals the rule allows — whether that contact draws or selects.
//          It is the one place in the app where "the pen is drawing" becomes "the document has a
//          stroke", so the palm rule, the coordinate conversion, the anchor choice and the write
//          through the operation log are decided together and cannot drift apart.
//
//          WHY THIS HOLDS A PALM RULE RATHER THAN CALLING INTO THE NATIVE ONE. The rule itself is
//          shared — it lives in `chart_core`'s `InkPalmRule` and is applied identically by the
//          Android surface — but this class owns the WINDOW that makes it work: which contact last
//          proved a stylus is near the glass, and how long ago. A window is state, and state belongs
//          to whoever sees the event stream.
// INPUTS: A live [EditSession], the current [PageLayout], and pointer events in the widget's own
//         logical pixels.
// OUTPUTS: Nothing directly: it appends an [InkStrokeAddEvent] through the session when a stroke
//          finishes, and answers [decideContact] so the widget can route a tap to selection instead.
//          A stroke whose first point lies over no bar is dropped, counted, and reported; it is not
//          attached to the nearest bar, because that would be a guess about intent.
// KEYWORDS: ink-mode, pointer-routing, palm-rule, stylus-proximity, op-log-writer, commit,
//           anchor-local, web-ink
//
// WHAT THIS DOES NOT DO. It does not render: a committed stroke reaches the screen because the
// document changed and the painter was rebuilt, and drawing it anywhere else would put the same
// information in two places. It does not own selection: it answers whether a contact would draw,
// and the widget decides what a contact that does not draw means.
import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

// PURPOSE: Report what one contact was and what was decided about it, so the widget routes a tap and
//          a log line can be audited against the rule instead of restating a boolean.
// INPUTS: A [PointerDeviceKind], its contact width in logical pixels, whether a stylus was in play,
//         whether the ink mode was on, and the time the contact arrived.
// OUTPUTS: An [InkContactDecision] when the kind is one the mapper knows, and null otherwise. Null
//          is a real answer for a trackpad's pan-zoom event, which is not a contact at all and must
//          not be given a stylus or a finger meaning.
// KEYWORDS: device-kind-mapping, pressure, width, tilt, trackpad-exclusion
/// Translates an engine pointer kind into the capture vocabulary the palm rule is written in.
class InkInputMapper {
  const InkInputMapper._();

  /// The capture kind for [kind], or null when the kind is not a physical contact.
  ///
  /// A `trackpad` is the only kind that returns null, deliberately: Flutter delivers a trackpad
  /// gesture as a pan-zoom sequence rather than as a contact, and treating it as a finger would put
  /// a stroke on the chart from a two-finger scroll.
  static InkCaptureKind? kindOf(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.stylus => InkCaptureKind.stylus,
    PointerDeviceKind.invertedStylus => InkCaptureKind.stylusEraser,
    PointerDeviceKind.touch => InkCaptureKind.finger,
    PointerDeviceKind.mouse => InkCaptureKind.mouse,
    PointerDeviceKind.trackpad => null,
    _ => InkCaptureKind.unknown,
  };

  /// One sample's position in the coordinate space of the widget the event arrived at.
  static LayoutOffset positionOf(PointerEvent event) =>
      LayoutOffset(event.localPosition.dx, event.localPosition.dy);

  /// One sample's time in milliseconds, using the event's own time base.
  ///
  /// The engine's `timeStamp` is a `Duration`; the stored stroke keeps differences between samples,
  /// so the absolute origin cancels out and only monotonicity matters.
  static double millisOf(PointerEvent event) =>
      event.timeStamp.inMicroseconds / 1000.0;

  /// One sample's pressure, clamped into `[0, 1]`.
  ///
  /// A mouse reports a constant 1 and a digitizer without a pressure axis reports 0 or 0.5; neither
  /// is a measurement of a hand, and the assembler substitutes the neutral half for a stroke whose
  /// every sample is zero. A non-finite value is reported as the neutral half here rather than
  /// passed on, because the stored form is a number in `[0, 1]` and `NaN` survives arithmetic.
  static double pressureOf(PointerEvent event) {
    final double pressure = event.pressure;
    if (!pressure.isFinite) {
      return 0.5;
    }
    return pressure < 0 ? 0 : (pressure > 1 ? 1 : pressure);
  }

  /// The contact's width in logical pixels as the FRAMEWORK reports it.
  ///
  /// WHAT THIS RETURNS ON THE WEB TARGET, MEASURED RATHER THAN ASSUMED: zero. Flutter's web
  /// `PointerBinding` builds each `PointerData` from the DOM event's position, pressure, tilt and
  /// pointer type and never reads the event's `width`, so `radiusMajor` — the field the framework
  /// exposes — arrives as the constructor default of 0.0. That is the reason the ink capture is not
  /// the whole story on this target: the browser DOES report a contact width (the web pen spike
  /// measured admitted fingers at 1-8 and palm-like contacts at 71 and 87), and the framework drops
  /// it on the way in, so the width half of the palm rule can only be fed by a raw pointer listener.
  /// See `ink_pointer_probe_web.dart` for the bridge and `ink_layer.dart` for how the two widths are
  /// combined.
  ///
  /// The major axis is read rather than the minor one because a palm is wide in one direction, and a
  /// radius is half a width, so the palm rule's threshold is expressed against the DIAMETER this
  /// function returns and is compared with the browser's own `width` on the same footing.
  static double contactWidthOf(PointerEvent event) {
    final double diameter = event.radiusMajor * 2;
    return diameter.isFinite ? diameter : 0;
  }
}

/// The one writer of ink in the app: pointer events in, strokes through the operation log out.
class InkCaptureLayer {
  /// Creates a capture layer over [session].
  ///
  /// [session] is read for the document it currently holds, so a stroke is always appended at the
  /// END of the story so far and an undo of an earlier edit is honoured without this class knowing
  /// about it. The named parameter is private because it is assigned straight to a private field and
  /// the class is not meant to be constructed from outside this package.
  InkCaptureLayer({required this._session});

  final EditSession _session;

  /// The stroke builders of the contacts that are currently drawing, by pointer id.
  final Map<int, InkStrokeAssembler> _assemblers = <int, InkStrokeAssembler>{};

  final List<ResolvedInkStroke> _live = <ResolvedInkStroke>[];

  /// Milliseconds of the last event of any kind that proved a stylus is near the glass.
  ///
  /// Set by a stylus contact AND by a stylus hover, because the second is the whole reason the
  /// window exists: the browser delivers hover without a touch, and a palm that lands in the gap
  /// between two pen strokes is refused only because this was updated by the hover in between.
  double _lastStylusSeenMs = double.negativeInfinity;

  /// Whether the musician has turned the pen on.
  bool _inkMode = false;

  /// How many strokes this layer has taken up but refused for want of an anchor.
  int _dropped = 0;

  /// What FLUTTER's own pointer stream delivered, accumulated here because this is the one place the
  /// engine's events arrive.
  ///
  /// It exists to be compared against the browser's own stream, which is counted separately and
  /// independently: a pressure axis that Flutter flattened would show a single distinct value here
  /// and sixty-five there, and the two numbers together are what decide whether the pen can be
  /// captured through the framework or needs its own raw listener.
  final _FlutterInputTally _flutterInput = _FlutterInputTally();

  /// Whether strokes are currently captured.
  bool get inkMode => _inkMode;

  /// How many strokes the document holds right now.
  int get strokeCount => _session.document.strokes.length;

  /// How many contacts this layer refused because their first point was over no bar.
  int get droppedStrokeCount => _dropped;

  /// How many contacts are drawing right now, which is normally zero or one.
  int get liveContactCount => _assemblers.length;

  /// Whether a contact is currently laying ink, which is what a page repaints on.
  ///
  /// Distinct from [lastPointWasInk], which answers "what did the contact that just arrived mean":
  /// a hover between two samples clears that flag, and a painter hung on it would stop following the
  /// pen the moment the browser reported the pen's proximity without a touch.
  bool get isDrawingInk => _assemblers.isNotEmpty;

  /// The strokes being drawn but not yet committed, for a live preview layer.
  List<ResolvedInkStroke> get liveStrokes =>
      List<ResolvedInkStroke>.unmodifiable(_live);

  /// The rule in force, with the state the last decision was taken under, for a report.
  Map<String, Object?> get ruleReport => <String, Object?>{
    'ruleVersion': InkPalmRule.version,
    'palmWidthThreshold': InkPalmRule.palmWidthThreshold,
    'stylusProximityWindowMs': InkPalmRule.stylusProximityWindowMs,
    'stylusProximityUnit':
        'logical pixels, as Flutter reports event.width on the web target',
  };

  /// What Flutter's own pointer stream delivered, for the delivery measurement.
  ///
  /// The values are the tally's own fields at the top level, so the same keys appear under the
  /// browser's arm and under this one and a reader can compare them field by field. `flutters` is the
  /// arm under test; the browser's own arm is measured by the pointer probe, and neither arm resets
  /// the other: a verification run resets both explicitly before it starts.
  Map<String, Object?> get inputReport => <String, Object?>{
    ..._flutterInput.toJson(),
    'inkMode': _inkMode,
    'documentStrokes': _session.document.strokes.length,
    'liveContacts': _assemblers.length,
    'droppedForWantOfAnchor': _dropped,
    'lastPointWasInk': _lastPointWasInk,
  };

  /// Whether the most recent pointer-down was decided to lay ink.
  ///
  /// Read by the widget to route a lift to selection or to a stroke; it is the layer's answer from
  /// the same contact rather than a second evaluation of the rule in the widget, which is how the
  /// two could come to disagree.
  bool _lastPointWasInk = false;

  /// Whether the most recent pointer-down was decided to lay ink.
  bool get lastPointWasInk => _lastPointWasInk;

  /// The most recent contact widths the RAW browser stream reported, newest last.
  ///
  /// A short queue rather than one field because the raw listener and the framework's own event are
  /// two deliveries of the SAME DOM event, and their timestamps cannot be assumed to be equal: the
  /// raw one carries the browser's `timeStamp`, the framework's carries the engine's own conversion
  /// of it. The queue is drained by time, and it holds only the last few contacts because a width
  /// older than one contact is evidence about a hand that has moved.
  final List<_RawContactWidth> _rawWidths = <_RawContactWidth>[];

  /// How long, in milliseconds, a raw contact width is considered to describe the framework's own
  /// contact with the same timestamp.
  ///
  /// A window rather than an equality because the two streams timestamp the same DOM event through
  /// different conversions, and an unmatched width is the same as no width: the rule then reads the
  /// framework's own value, which on the web target is zero.
  static const double rawWidthMatchWindowMs = 50;

  // PURPOSE: Record a contact width that the framework dropped, reported by the raw browser stream.
  // INPUTS: A sample the browser delivered, with the time the sample was seen on the Dart side and
  //         the time the browser stamped it.
  // OUTPUTS: Nothing. Only touch contacts are kept: a pen's contact geometry is not what the rule
  //          compares, and keeping it would let a pen sample be matched against a finger event.
  // KEYWORDS: raw-width-bridge, browser-dropped-field, touch-only, bounded-queue
  /// Records a contact width the framework dropped.
  /// Records a contact width the framework dropped.
  void recordRawContact({
    required String pointerType,
    required double width,
    required double browserTimeMs,
  }) {
    _rawWidths.add(
      _RawContactWidth(
        pointerType: pointerType,
        width: width,
        browserTimeMs: browserTimeMs,
      ),
    );
    // Three entries is enough to cover the deliveries of one DOM event without keeping a log of the
    // whole session in a list that every decision walks.
    while (_rawWidths.length > 3) {
      _rawWidths.removeAt(0);
    }
  }

  // PURPOSE: Find the width the raw stream reported for a framework event at [time].
  // INPUTS: time — the framework's timestamp for the event, in milliseconds, and the width the
  //         framework itself reported, which is preferred when it is non-zero.
  // OUTPUTS: The width to judge the contact by: the framework's own when it has one, otherwise the
  //          closest raw report inside [rawWidthMatchWindowMs], otherwise zero. Zero means "not
  //          measured" and the rule treats it as not palm-like, so an unmatched contact is a finger
  //          and selects — which is the safe direction to fail in, because refusing a contact the
  //          musician meant to make is worse than admitting a palm that a later sample will reject.
  // KEYWORDS: width-arbitration, framework-first, raw-fallback, nearest-within-window, fail-open
  /// Returns the width to judge a contact by.
  double contactWidthFor({
    required double time,
    required double frameworkWidth,
  }) {
    if (frameworkWidth > 0) {
      return frameworkWidth;
    }
    _RawContactWidth? best;
    double bestDistance = double.infinity;
    for (final _RawContactWidth candidate in _rawWidths) {
      final double distance = (candidate.browserTimeMs - time).abs();
      if (distance <= rawWidthMatchWindowMs && distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best?.width ?? 0;
  }

  /// Turns ink on or off, discarding anything half-drawn.
  ///
  /// A half-drawn stroke is abandoned rather than kept: the mode changed under the musician's hand,
  /// and committing a stroke whose beginning was captured under another mode would be a mark they
  /// did not finish making.
  set inkMode(bool on) {
    if (_inkMode == on) {
      return;
    }
    _inkMode = on;
    for (final InkStrokeAssembler assembler in _assemblers.values) {
      assembler.cancel();
    }
    _assemblers.clear();
    _live.clear();
    debugPrint('ink.mode on=$on strokes=${_session.document.strokes.length}');
  }

  // PURPOSE: Answer what one contact is and what may be done with it, which is the single entrance
  //          through which both drawing and selection are routed.
  // INPUTS: kind — the engine's pointer kind. width — the contact width in logical pixels, which is
  //         what the palm half of the rule compares. time — the contact's timestamp. pressure and
  //         tilt — the engine's own values for this event, recorded for the delivery measurement and
  //         used for nothing else here: the rule does not read them, because a pressure reading is a
  //         measurement of a hand and not evidence of which tool is in it. isHover — whether this is
  //         a hover rather than a contact, which changes only what is recorded.
  // OUTPUTS: The decision, or null for a kind that is not a contact.
  //
  //          As a side effect it records the contact as evidence that a stylus is near when it IS a
  //          stylus, because that evidence must be updated for hover too and hover arrives through
  //          the same door.
  // KEYWORDS: routing-decision, palm-rule-call, stylus-evidence, null-for-non-contact, tally
  /// Returns what one contact is and what may be done with it.
  InkContactDecision? decideContact({
    required PointerDeviceKind kind,
    required double width,
    required double time,
    double pressure = 0,
    double tilt = 0,
    bool isHover = false,
  }) {
    final InkCaptureKind? captureKind = InkInputMapper.kindOf(kind);
    if (captureKind == null) {
      return null;
    }
    _flutterInput.record(
      kind: captureKind,
      pressure: pressure,
      tilt: tilt,
      width: width,
      isHover: isHover,
    );
    if (captureKind.isStylus) {
      _lastStylusSeenMs = time;
    }
    if (!isHover) {
      _lastPointWasInk = false;
    }
    // The framework's width first, and the raw browser's only when the framework reported none.
    // Measured on the web target, the framework always reports none: Flutter's web binding never
    // reads the DOM event's `width`, so on that target this is the one path by which the width half
    // of the palm rule can fire at all.
    final double decidingWidth = contactWidthFor(
      time: time,
      frameworkWidth: width,
    );
    _flutterInput.noteDecidingWidth(
      frameworkWidth: width,
      decidingWidth: decidingWidth,
    );
    return InkPalmRule.decide(
      kind: captureKind,
      width: decidingWidth,
      stylusInPlay: stylusInPlay(time),
      inkModeOn: _inkMode,
    );
  }

  // PURPOSE: Report whether a stylus counts as in play at [time], which is the gate the palm half of
  //          the rule turns on.
  // INPUTS: time — the timestamp to judge, in the same base as the events.
  // OUTPUTS: True when a stylus was seen within the proximity window. A window of zero or negative
  //          length, which nothing in this app produces, makes this always false rather than always
  //          true, because a rule that cannot be satisfied must not silently become one that never
  //          rejects.
  // KEYWORDS: proximity-window, stylus-in-play, elapsed, defensive
  /// Whether a stylus counts as in play at [time].
  bool stylusInPlay(double time) =>
      time - _lastStylusSeenMs <= InkPalmRule.stylusProximityWindowMs;

  // PURPOSE: Begin drawing a contact that the rule admitted.
  // INPUTS: pointer — the engine's pointer id, which is the identity of this contact. page — the
  //         layout being drawn on. kind — the pointer kind. position — where the contact landed, in
  //         the widget's pixels. pressure and time — the first sample's values.
  // OUTPUTS: True when a stroke was opened; false when the first point resolved to no anchor, in
  //          which case the contact is tracked as refused and no stroke will be committed. A second
  //          contact with the same pointer id replaces the first, because one pointer id cannot be
  //          two contacts and the older one is a leaked stroke rather than a real second hand.
  // KEYWORDS: begin-stroke, anchor-resolution, admitted-contact, replace-guard
  /// Begins drawing a contact the rule admitted.
  bool beginStroke({
    required int pointer,
    required PageLayout page,
    required PointerDeviceKind kind,
    required LayoutOffset position,
    required double pressure,
    required double time,
  }) {
    final InkCaptureKind captureKind =
        InkInputMapper.kindOf(kind) ?? InkCaptureKind.unknown;
    final InkStrokeAssembler assembler = InkStrokeAssembler(
      tool: StrokeTool.pen,
      color: _penColorFor(captureKind),
      size: _nibFor(captureKind),
    );
    final bool opened = assembler.begin(
      page: page,
      surfacePoint: position,
      pressure: pressure,
      time: time,
    );
    if (!opened) {
      _dropped++;
      debugPrint(
        'ink.stroke.refused pointer=$pointer kind=${captureKind.token} '
        'reason=no-anchor-at-start surface=(${position.x.toStringAsFixed(1)},'
        '${position.y.toStringAsFixed(1)}) scale=${page.scale}',
      );
      return false;
    }
    _assemblers[pointer] = assembler;
    _lastPointWasInk = true;
    _refreshLive(page);
    debugPrint(
      'ink.stroke.begin pointer=$pointer kind=${captureKind.token} '
      'anchor=${assembler.anchor} '
      'surface=(${position.x.toStringAsFixed(1)},${position.y.toStringAsFixed(1)}) '
      'scale=${page.scale} pressure=${pressure.toStringAsFixed(2)}',
    );
    return true;
  }

  // PURPOSE: Record one more sample of a contact that is drawing.
  // INPUTS: pointer — the contact. page — the layout being drawn on, needed for its scale only.
  //         position, pressure, time — the sample.
  // OUTPUTS: Nothing. A sample for a contact that is not drawing is dropped, which is the ordinary
  //          case for the first move of a contact the rule refused.
  // KEYWORDS: add-sample, live-preview, silent-when-absent
  /// Records one more sample of a contact that is drawing.
  void addSample({
    required int pointer,
    required PageLayout page,
    required LayoutOffset position,
    required double pressure,
    required double time,
  }) {
    final InkStrokeAssembler? assembler = _assemblers[pointer];
    if (assembler == null) {
      return;
    }
    assembler.add(surfacePoint: position, pressure: pressure, time: time);
    _refreshLive(page);
  }

  // PURPOSE: Finish a drawing contact and commit what it drew.
  // INPUTS: pointer — the contact. page — the layout, needed to convert the samples back into page
  //         coordinates.
  // OUTPUTS: The committed [InkStroke], or null when the contact was not drawing or its anchor had
  //          gone. The stroke is appended as an [InkStrokeAddEvent] at the END of the document's
  //          stroke list, because the log is the only writer: nothing here assigns to the document.
  //
  //          A stroke that a transposition made unanchorable between its first and last sample is
  //          committed anyway if the anchor resolved at the beginning, because the anchor's ADDRESS
  //          is what was stored and an address survives a reflow. The page is used here only for its
  //          scale, which is a property of how the page is drawn and not of where the bar is.
  // KEYWORDS: end-stroke, commit, ink-stroke-add, append-at-end, single-writer
  /// Finishes a drawing contact and commits what it drew.
  InkStroke? endStroke({required int pointer, required PageLayout page}) {
    final InkStrokeAssembler? assembler = _assemblers.remove(pointer);
    if (assembler == null) {
      return null;
    }
    final InkStroke? stroke = assembler.end(
      page: page,
      id: _nextStrokeId(assembler),
    );
    _refreshLive(page);
    if (stroke == null) {
      return null;
    }
    _session.apply(
      InkStrokeAddEvent(
        docId: _session.docId,
        seq: _session.seq,
        index: _session.document.strokes.length,
        stroke: stroke,
      ),
    );
    debugPrint(
      'ink.stroke.commit id=${stroke.id} tool=${stroke.tool.token} '
      'anchor=${stroke.anchor} points=${stroke.points.length} '
      'strokes=${_session.document.strokes.length} seq=${_session.seq} '
      'first_local=(${stroke.points.first.x.toStringAsFixed(1)},'
      '${stroke.points.first.y.toStringAsFixed(1)}) '
      'last_local=(${stroke.points.last.x.toStringAsFixed(1)},'
      '${stroke.points.last.y.toStringAsFixed(1)})'
      '${stroke.points.first.w == 0.5 && stroke.points.every((InkPoint p) => p.w == 0.5) ? ' pressure=neutral-fallback' : ''}',
    );
    return stroke;
  }

  // PURPOSE: Abandon a drawing contact without committing anything, which is what the platform
  //          means when it cancels a pointer: the contact was taken away rather than finished.
  // INPUTS: pointer — the contact.
  // OUTPUTS: Nothing.
  // KEYWORDS: cancel, discard, pointer-cancel
  /// Abandons a drawing contact without committing anything.
  void cancelStroke(int pointer) {
    final InkStrokeAssembler? assembler = _assemblers.remove(pointer);
    assembler?.cancel();
    _live.clear();
    debugPrint('ink.stroke.cancel pointer=$pointer dropped=$_dropped');
  }

  // PURPOSE: Rebuild the live preview from the open assemblers, so the stroke under the pen is
  //          visible before it is committed.
  // INPUTS: page — the layout, used to resolve each open stroke's anchor rectangle.
  // OUTPUTS: Nothing. The list is rebuilt rather than mutated so a painter holding the previous list
  //          keeps a value rather than seeing it change underneath it.
  // KEYWORDS: live-preview, rebuild, anchor-resolution, immutability
  void _refreshLive(PageLayout page) {
    final List<ResolvedInkStroke> next = <ResolvedInkStroke>[];
    for (final InkStrokeAssembler assembler in _assemblers.values) {
      final EventAnchor? anchor = assembler.anchor;
      if (anchor == null) {
        continue;
      }
      final InkPlacement? placement = resolveEventAnchor(page, anchor);
      if (placement == null) {
        continue;
      }
      next.add(
        ResolvedInkStroke(
          stroke: InkStroke(
            id: 'live',
            tool: StrokeTool.pen,
            color: _penColorFor(InkCaptureKind.stylus),
            size: _nibFor(InkCaptureKind.stylus),
            anchor: anchor,
            points: assembler.pointsSnapshot(page),
          ),
          origin: placement.origin,
        ),
      );
    }
    _live
      ..clear()
      ..addAll(next);
  }

  // PURPOSE: Name the colour a stroke is stored with, per tool.
  // INPUTS: kind — the capture kind, which selects the tool.
  // OUTPUTS: A `#rrggbb` string. The pen is the chart's own ink colour and the eraser's other end
  //          draws as a pen, because the eraser is an operation on the stroke list and not ink.
  // KEYWORDS: colour, tool, pen, hex-string
  String _penColorFor(InkCaptureKind kind) =>
      kind.isStylus ? '#102a43' : '#2f80ed';

  /// The nib width a stroke is stored with, in anchor-local logical pixels.
  ///
  /// Three logical pixels at the tablet's page scale is a legible hairline: wide enough to read on a
  /// chart whose chord symbols are fifteen pixels tall, narrow enough that a bar's worth of quick
  /// marks does not cover the music. The number is a starting point, not a tuning, and it is stored
  /// per stroke so changing it later cannot alter a stroke already drawn.
  double _nibFor(InkCaptureKind kind) => kind.isStylus ? 3 : 4;

  // PURPOSE: Give a committed stroke an identity that is unique in its document.
  // INPUTS: assembler — the stroke being committed, read for its anchor and the time it began.
  // OUTPUTS: A string id built from the anchor and the stroke's own start time, so it is unique
  //          across two runs of the application — an id that counted from one would collide with a
  //          stroke an opened file already carried, and the reducer refuses a duplicate. Readable
  //          rather than random because the identity is written to a file and a support log is
  //          diagnosable when it can be read.
  // KEYWORDS: stroke-id, uniqueness, readable, anchor-derived, start-time
  String _nextStrokeId(InkStrokeAssembler assembler) {
    final EventAnchor anchor =
        assembler.anchor ?? const EventAnchor(sectionId: 'unresolved', bar: 0);
    return 'ink-${anchor.sectionId}-${anchor.bar}-${anchor.beat ?? -1}-'
        '${anchor.step}-${assembler.startTime.round()}';
  }
}

// PURPOSE: Accumulate what Flutter's own pointer stream delivered, so the delivery measurement has
//          one arm it can read from inside the application. It is a tally and not a decision: the
//          rule reads none of it.
// INPUTS: The engine's own `pressure`, `tilt` and `width` for one event, and whether it was a
//         contact or a hover.
// OUTPUTS: Counters, and the set of DISTINCT values. Distinct values are what decides the question:
//          a pressure axis that Flutter flattened to a constant has one distinct value and a working
//          one has many, and a mean cannot tell the two apart.
// KEYWORDS: measurement, flutter-input, distinct-values, pressure, tilt, width, hover
class _FlutterInputTally {
  int events = 0;
  int penEvents = 0;
  int touchEvents = 0;
  int mouseEvents = 0;
  int hoverEvents = 0;
  int widthsSubstitutedFromRaw = 0;
  double lastFrameworkWidth = 0;
  double lastDecidingWidth = 0;
  final Set<double> pressureValues = <double>{};
  final Set<int> tiltDegrees = <int>{};
  final Set<int> widths = <int>{};
  final Set<int> decidingWidths = <int>{};
  double pressureMin = double.infinity;
  double pressureMax = double.negativeInfinity;

  /// Notes what widths the framework reported and what was actually compared, which is the pair of
  /// numbers that shows whether the raw bridge did any work.
  void noteDecidingWidth({
    required double frameworkWidth,
    required double decidingWidth,
  }) {
    lastFrameworkWidth = frameworkWidth;
    lastDecidingWidth = decidingWidth;
    decidingWidths.add(decidingWidth.round());
    if (decidingWidth != frameworkWidth) {
      widthsSubstitutedFromRaw++;
    }
  }

  /// Records one event's values.
  void record({
    required InkCaptureKind kind,
    required double pressure,
    required double tilt,
    required double width,
    required bool isHover,
  }) {
    events++;
    if (isHover) {
      hoverEvents++;
    }
    switch (kind) {
      case InkCaptureKind.stylus:
      case InkCaptureKind.stylusEraser:
        penEvents++;
      case InkCaptureKind.finger:
        touchEvents++;
      case InkCaptureKind.mouse:
        mouseEvents++;
      case InkCaptureKind.unknown:
        break;
    }
    // Rounded the same way the browser probe rounds its own readings, so the two arms' distinct
    // counts are comparable rather than differing by a rounding rule.
    pressureValues.add((pressure * 100).round() / 100);
    tiltDegrees.add((tilt * 180 / 3.141592653589793 / 5).round() * 5);
    widths.add(width.round());
    if (pressure < pressureMin) {
      pressureMin = pressure;
    }
    if (pressure > pressureMax) {
      pressureMax = pressure;
    }
  }

  /// The tally as a flat map, in the same shape the browser probe reports so a reader can compare
  /// the two arms field by field.
  Map<String, Object?> toJson() => <String, Object?>{
    'events': events,
    'penEvents': penEvents,
    'touchEvents': touchEvents,
    'mouseEvents': mouseEvents,
    'hoverEvents': hoverEvents,
    'distinctPressureValues': pressureValues.length,
    'distinctTiltValues': tiltDegrees.length,
    'widthsSeen': widths.toList()..sort(),
    'decidingWidthsSeen': decidingWidths.toList()..sort(),
    'widthsSubstitutedFromRaw': widthsSubstitutedFromRaw,
    'lastFrameworkWidth': lastFrameworkWidth,
    'lastDecidingWidth': lastDecidingWidth,
    'pressureMin': pressureMin.isFinite
        ? double.parse(pressureMin.toStringAsFixed(3))
        : null,
    'pressureMax': pressureMax.isFinite
        ? double.parse(pressureMax.toStringAsFixed(3))
        : null,
  };
}

// PURPOSE: Carry one contact width the RAW browser stream reported, so it can be matched against the
//          framework's own event for the same physical contact. It exists because the two streams
//          deliver one DOM event twice and the width is present in only one of them.
// INPUTS: The browser's `pointerType` and `width`, and the browser's `timeStamp`.
// OUTPUTS: An immutable value. The timestamp is the comparison key, because both streams state a time
//          measured from the page's own time origin.
// KEYWORDS: raw-contact, width, timestamp-pairing, bridge-value
class _RawContactWidth {
  /// Creates one raw contact width.
  const _RawContactWidth({
    required this.pointerType,
    required this.width,
    required this.browserTimeMs,
  });

  /// The browser's `pointerType`.
  final String pointerType;

  /// The browser's `width` in CSS pixels, which are logical pixels on this target.
  final double width;

  /// The browser's own `timeStamp`, in milliseconds.
  final double browserTimeMs;
}
