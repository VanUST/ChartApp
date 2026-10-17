// PURPOSE: Recognise the ONE touch gesture owner decision D34 gives the view — two fingers
//          together, which pans, and a pinch, which zooms — and refuse to recognise anything a
//          single finger does. It exists because the gesture has to WIN the gesture arena before the
//          page's own horizontal swipe can turn a page: a `GestureDetector`'s scale recogniser only
//          accepts after a slop of its own, by which time a two-finger drag has already been taken
//          by the `PageView` under it and the chart has changed page instead of moving.
//
//          WHAT IT DELIBERATELY IGNORES. A stylus is never a view gesture: D34's first clause is
//          that the pen ALWAYS writes, so a stylus contact is not tracked here at all and can never
//          be part of a pan or a pinch. A mouse is ignored for the same reason (a mouse button does
//          not pan a touch surface). Only `PointerDeviceKind.touch` counts, which on the owner's
//          tablet is his fingers and, on a platform whose stylus fusion merges the S Pen into the
//          touch stream, may also be his pen — that platform limitation is named in `docs/sdd.md`
//          A63 rather than papered over here.
//
//          WHY A REFUSED TOUCH IS NOT SIMPLY A TOUCH THIS RECOGNISER DOES NOT WANT, AND WHY THE
//          SCREEN DECIDES IT. The owner reported that a palm resting on the glass while he wrote was
//          read as a two-finger gesture, so the chart panned under his hand. A finger count is not
//          enough to tell that apart from two fingers: a palm plus the pen, or a palm plus a stray
//          touch, is exactly two contacts. The recogniser therefore asks [refuseTouch] before it
//          counts a touch, and that callback is answered by the ink layer — the one object that knows
//          the contact's width and whether a pen is in play — so this file holds no second copy of
//          the palm rule. A refused touch is not tracked and the base class is not told about it, so
//          `touchCount` and the framework's own pointer count stay the same number.
//
//          WHY IT COMPUTES ITS OWN FOCAL POINT AND SPAN INSTEAD OF READING `ScaleUpdateDetails`.
//          The base class's `scale` is relative to a baseline it resets whenever the pointer
//          configuration changes, and it tracks every pointer the framework offers it; a handler
//          built on that inherits two behaviours it cannot see and cannot test. The positions of
//          the tracked pointers are the whole of what a pan and a pinch are, so they are kept here,
//          the centroid and the mean radius are computed here, and the callback carries those two
//          numbers. That makes the arithmetic checkable without a device.
// INPUTS: A `RawGestureDetector` feeds it the pointer stream. [callbacks] is set by the screen that
//         owns the view state, and [refuseTouch] by the screen that owns the ink rule.
// OUTPUTS: [TwoFingerViewSample] values through [TwoFingerViewCallbacks]: one `onStart` when the
//          second touch lands, an `onUpdate` per move while two or more are down, and one `onEnd`
//          when the last touch lifts or the arena rejects the gesture. Nothing is emitted for a
//          single touch, so a one-finger drag is left entirely to whatever else wants it.
// KEYWORDS: two-finger-pan, pinch-zoom, gesture-recognizer, gesture-arena, d34, stylus-excluded,
//           palm-refusal, admission-callback
import 'package:flutter/gestures.dart';

/// One observation of the two-finger gesture: where its middle is and how far apart the fingers are.
///
/// [span] is the MEAN DISTANCE from [focal] to the tracked touches, which is the radius of the
/// circle the fingers lie on rather than their separation: the ratio of two spans is the pinch
/// factor, and using a mean rather than a pairwise distance keeps the number meaningful when a
/// third finger is resting on the glass.
class TwoFingerViewSample {
  /// Creates a sample with the given [focal] point and [span], from [pointerCount] touches.
  const TwoFingerViewSample({
    required this.focal,
    required this.span,
    required this.pointerCount,
  });

  /// The centroid of the tracked touches, in the coordinates of the widget the gesture detector
  /// wraps — which for this screen is the chart pane, the same space a pointer event's
  /// `localPosition` arrives in.
  final Offset focal;

  /// The mean distance from [focal] to each tracked touch, in logical pixels.
  final double span;

  /// How many touches the sample was taken from. At least two: a sample is never emitted below that,
  /// because one finger is not this gesture.
  final int pointerCount;

  @override
  String toString() =>
      'TwoFingerViewSample($pointerCount, focal=(${focal.dx.toStringAsFixed(1)},'
      '${focal.dy.toStringAsFixed(1)}), span=${span.toStringAsFixed(1)})';
}

/// The three moments of the two-finger gesture the screen handles.
///
/// All three are nullable fields on the recogniser rather than constructor arguments, because the
/// recogniser is created by a `RawGestureDetector` factory that only knows how to build one.
class TwoFingerViewCallbacks {
  /// Creates a set of callbacks.
  const TwoFingerViewCallbacks({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  /// Called once, when the second touch lands and the gesture has been accepted.
  final void Function(TwoFingerViewSample sample) onStart;

  /// Called for every move while two or more touches are down.
  final void Function(TwoFingerViewSample sample) onUpdate;

  /// Called once, when the last tracked touch lifts or the arena rejects the gesture.
  final void Function() onEnd;
}

// PURPOSE: Track the touch pointers a view gesture is made of and win the arena as soon as there are
//          two of them, so that the two-finger gesture is never handed to the pager underneath. It
//          counts only the touches the ink layer admits, so a palm — or any contact that lands while
//          a pen is in play — is not one of the fingers.
// INPUTS: Pointer events from a `RawGestureDetector`. [callbacks] must be set by the owner before
//         the first touch, [refuseTouch] by the owner of the ink rule, and `scale` behaviour of the
//         base class is deliberately unused.
// OUTPUTS: [TwoFingerViewSample]s through [callbacks]. A stylus, a mouse or any other non-touch kind
//          is not tracked at all, and neither is a touch the gate refused, so none of them can
//          start or join the gesture.
// KEYWORDS: gesture-arena, immediate-accept, two-touch, pan-zoom-source, pointer-accounting, d34,
//           palm-refusal, admission-gate
/// The recogniser that owns the two-finger pan and pinch, and nothing else.
class TwoFingerViewGestureRecognizer extends ScaleGestureRecognizer {
  /// Creates the recognizer. Assign [callbacks] before it receives a pointer.
  TwoFingerViewGestureRecognizer();

  /// Where the gesture's three moments are reported, or null when the screen has not set them.
  ///
  /// Nullable rather than required because the framework's own
  /// `GestureRecognizerFactoryWithHandlers` builds the object before it can be configured, and a
  /// recogniser with no listeners must be harmless rather than throw.
  TwoFingerViewCallbacks? callbacks;

  /// Answers whether one touch may join the gesture, or null when the screen set no gate.
  ///
  /// A `String?` rather than a boolean, because the REFUSAL has to be nameable: the owner's report
  /// is "a palm was read as two fingers", and a bare `false` could not say whether the palm half or
  /// the pen half of the rule refused the contact. The return is the reason token, or null to admit.
  ///
  /// Null means admit, which is the behaviour this recogniser had before the gate existed, so a
  /// recogniser built without a screen around it — as a unit test may — still tracks touches.
  String? Function(PointerDownEvent event)? refuseTouch;

  /// Called once for each touch the gate refused, with the reason it gave.
  ///
  /// Separate from [refuseTouch] so the rule stays pure and the LOGGING stays the screen's: a
  /// predicate that printed would put the cost of a log line on the gesture path for every caller,
  /// and this project has already paid once for a probe that ran on the pen's own thread.
  void Function(PointerDownEvent event, String reason)? onTouchRefused;

  /// How many touches the gate has refused since this recogniser was built.
  int get refusedCount => _refused;

  int _refused = 0;

  /// The touch pointers currently down, by pointer id, with their latest position.
  ///
  /// Only touches are ever added, which is the whole of "the pen is not part of this gesture": a
  /// stylus never reaches this map, so it can never make the count reach two.
  final Map<int, Offset> _touches = <int, Offset>{};

  /// How many touches are down. Two or more is the gesture.
  int get touchCount => _touches.length;

  /// Whether the gesture currently owns two or more touches.
  bool get isActive => _touches.length >= 2;

  bool _started = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      // Not a finger, so not this gesture. The pointer is not tracked and the base class is not
      // told about it either, which is what keeps `isActive` and the framework's own pointer count
      // the same number.
      return;
    }
    // THE GATE, ASKED BEFORE THE COUNT IS TOUCHED. A palm-like contact, or any contact that lands
    // while a pen is in play, is not a finger of this gesture: it is not tracked and the base class
    // is not told, so it can neither start a pan nor join one already running. The chart therefore
    // cannot move under a hand that is writing — which is the defect the owner reported.
    final String? refusal = refuseTouch?.call(event);
    if (refusal != null) {
      _refused++;
      onTouchRefused?.call(event, refusal);
      return;
    }
    _touches[event.pointer] = event.localPosition;
    super.addAllowedPointer(event);
    if (_touches.length >= 2) {
      // ACCEPT IMMEDIATELY, AND THAT IS THE WHOLE REASON THIS CLASS EXISTS. A horizontal drag
      // recogniser under this one resolves once the first finger has travelled `kTouchSlop`; the
      // base class's own pan slop is twice that, so without this line a two-finger drag turns the
      // page before the view gesture is ever consulted. First to accept wins the arena, and the
      // finger count is the evidence that this is the gesture the musician asked for.
      resolve(GestureDisposition.accepted);
      _emitStartIfNeeded();
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    final bool tracked = _touches.containsKey(event.pointer);
    if (tracked) {
      if (event is PointerMoveEvent) {
        _touches[event.pointer] = event.localPosition;
      } else if (event is PointerUpEvent || event is PointerCancelEvent) {
        _touches.remove(event.pointer);
      }
      // A SAMPLE IS ONLY EVER TAKEN FROM TWO OR MORE TOUCHES. One finger is not this gesture, and
      // emitting for it would tell the screen that a pan had begun on the first millimetre of every
      // single-finger drag — which is exactly what the test for "a finger draws in ink mode" caught.
      if (_touches.length >= 2) {
        _emitUpdate();
      }
      if (_touches.isEmpty) {
        _finish();
      }
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _touches.remove(pointer);
    super.rejectGesture(pointer);
    if (_touches.isEmpty) {
      _finish();
    }
  }

  @override
  void dispose() {
    _touches.clear();
    super.dispose();
  }

  // PURPOSE: Refuse to win the gesture arena on ONE touch, whatever the base class's scale machinery
  //          decides, so that a single contact is left to the tap and to the one-contact pan.
  // INPUTS: disposition — what the base class is about to tell the arena.
  // OUTPUTS: Nothing. An `accepted` disposition is dropped while fewer than two touches are counted;
  //          every other disposition is passed through unchanged.
  //
  //          WHY THIS OVERRIDE EXISTS, AND IT IS A DEFECT FOUND BY A TEST THAT OWED NOTHING TO THE
  //          OLD CODE. `ScaleGestureRecognizer` accepts a drag of its own once its slop is crossed,
  //          and it counts pointers the framework gave it rather than the touches this class
  //          admitted. In a pumped test the base class declared itself the ARENA WINNER on the very
  //          first `PointerDownEvent` — the arena log printed `Accepting:
  //          TwoFingerViewGestureRecognizer` on a single touch — which rejected the page's
  //          `TapGestureRecognizer` and the one-contact pan before either could look at the pointer.
  //          The symptom was not a wrong picture but an unreachable gesture: the page's tap and the
  //          Select tool's pan both stopped arriving, and nothing in the old tests could see it
  //          because they only ever asserted what the two-finger gesture EMITS, never what it takes
  //          away. It is dropped here rather than by not calling `super`, because the base class's
  //          own bookkeeping (velocity, pointer queue) must still happen.
  // KEYWORDS: gesture-arena, single-touch-refusal, tap-preserved, pan-preserved, base-class-guard
  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && _touches.length < 2) {
      return;
    }
    super.resolve(disposition);
  }

  /// Emits the start sample once, when the second touch has been counted.
  void _emitStartIfNeeded() {
    if (_started) {
      return;
    }
    _started = true;
    callbacks?.onStart(_sample());
  }

  /// Emits one update per move, and never before the start.
  void _emitUpdate() {
    if (!_started) {
      return;
    }
    callbacks?.onUpdate(_sample());
  }

  /// Ends the gesture, once.
  void _finish() {
    if (!_started) {
      return;
    }
    _started = false;
    callbacks?.onEnd();
  }

  /// The current observation of the tracked touches.
  TwoFingerViewSample _sample() {
    double x = 0;
    double y = 0;
    for (final Offset position in _touches.values) {
      x += position.dx;
      y += position.dy;
    }
    final int count = _touches.length;
    final Offset focal = Offset(x / count, y / count);
    double deviation = 0;
    for (final Offset position in _touches.values) {
      deviation += (position - focal).distance;
    }
    return TwoFingerViewSample(
      focal: focal,
      span: deviation / count,
      pointerCount: count,
    );
  }
}
