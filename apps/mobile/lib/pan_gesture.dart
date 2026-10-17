// PURPOSE: Move the sheet with ONE contact, which is the gesture that was missing when the owner
//          reported "перемещение с помощью одного пальца вообще пропало" and could not navigate a
//          32-bar chart. Owner decision D34 gives the view a TWO-finger pan, and that decision is
//          kept; but with the pen in his hand the two-finger path is either refused by an admission
//          gate or simply not injectable by any instrument this project has, so the document needs a
//          pan that a musician can perform and a tool can measure.
//
//          WHY THE PAN LIVES IN THE SELECT TOOL AND NOWHERE ELSE. With the pen tool on, a single
//          contact is a STROKE — that is A61's decision and the reason D34 gave the pan to two
//          fingers in the first place — so a one-finger drag cannot mean "move the page" there
//          without taking writing away. In the SELECT tool nothing lays ink at all, so a drag has no
//          other meaning to compete with: the gesture is free BY CONSTRUCTION in exactly the sense
//          D34 used when it chose two fingers. The conflict the owner resolved is therefore not
//          reopened; a new, non-conflicting gesture is added in the one mode where it cannot
//          conflict.
//
//          WHY IT ACCEPTS AT `kTouchSlop` RATHER THAN AT THE PAN SLOP, AND WHY IT MAY DECLINE. The
//          pager under this recogniser turns a page at a horizontal `kTouchSlop` of travel. A pan
//          that waited for the larger `kPanSlop` would therefore lose every horizontal drag to the
//          page turn — the defect `TwoFingerViewGestureRecognizer` exists to avoid, one level down.
//          Accepting at the same distance resolves the arena first because recognisers are asked
//          deepest-first, so the sheet moves. AND IT DECLINES WHEN THERE IS NOWHERE TO MOVE: at zoom
//          1 the page exactly fills the pane and `PageLayout.withView` clamps every pan to zero, so
//          a drag there is left entirely to the pager. That is what keeps page turning alive in the
//          PAGES mode instead of silently trading it for a pan that could not have moved anything.
// INPUTS: Pointer events from a `RawGestureDetector`. [refusePan] answers whether a pan is possible
//         at all (and names the reason when it is not); [onPanStart]/[onPanUpdate]/[onPanEnd] are
//         the three moments the screen handles; [onPanRefused] reports a drag that was declined.
// OUTPUTS: [onPanStart] once when the contact has travelled past the slop and the pan was admitted,
//          one [onPanUpdate] per move after that carrying the LOCAL delta since the previous sample,
//          one [onPanEnd] when the contact lifts or is cancelled, and [onPanRefused] once for a drag
//          that was not admitted. A second contact does not join: this recogniser tracks one pointer
//          only, and the two-finger gesture above it owns what two contacts mean.
// KEYWORDS: one-finger-pan, select-tool, gesture-arena, immediate-accept, decline-with-reason,
//           d34-compatible, injectable-gesture, page-turn-preserved
import 'package:flutter/gestures.dart';

// PURPOSE: Track the one contact a pan is made of and win the arena as soon as it has travelled far
//          enough to be a drag rather than a tap, so that the sheet moves instead of the page
//          turning. It tracks ONE pointer and never counts a second, which is what keeps it from
//          competing with the two-finger gesture that owns what two contacts mean.
// INPUTS: Pointer events from a `RawGestureDetector`; [refusePan] must be set by the owner, the
//         three moments are optional.
// OUTPUTS: The callbacks described on the file. A contact of any kind EXCEPT a mouse may pan: with
//          the select tool on, a pen lays no ink either, so its drag is as free as a finger's.
// KEYWORDS: pan-recognizer, one-pointer, arena-first, local-delta, decline-reason
/// Recognises a one-contact drag as a pan of the page, and nothing else.
class PagePanGestureRecognizer extends OneSequenceGestureRecognizer {
  /// Creates the recogniser. Assign [refusePan] before it receives a pointer.
  PagePanGestureRecognizer();

  /// Answers whether a pan may start, or names the reason it may not.
  ///
  /// A `String?` rather than a boolean for the same reason the two-finger gesture's gate returns
  /// one: "the sheet did not move" has several causes — the tool writes, the view is locked, the
  /// page already fills the pane — and a bare `false` could not say which. Null means admit.
  String? Function()? refusePan;

  /// Called once, when the contact has travelled past the slop and the pan was admitted.
  void Function()? onPanStart;

  /// Called for every move after the start, with the delta in this widget's own pixels.
  void Function(Offset delta)? onPanUpdate;

  /// Called once, when the admitted pan ends — on the lift, or when the arena takes the pointer away.
  void Function()? onPanEnd;

  /// Called once for a drag that was declined, with the reason [refusePan] gave.
  ///
  /// Separate from the predicate so the rule stays pure and the LOGGING stays the screen's, exactly
  /// as `TwoFingerViewGestureRecognizer` splits them.
  void Function(String reason)? onPanRefused;

  /// Whether an admitted pan is in progress.
  bool get isPanning => _accepted;

  /// One line naming what this recogniser is tracking, for the framework's own diagnostics.
  ///
  /// Required by [GestureRecognizer] and worth writing rather than stubbing: `debugDumpGestureRecognizers`
  /// is how a recogniser that never wins the arena is told apart from one that was never asked, and
  /// this class exists precisely because a gesture that never started had no other symptom.
  @override
  String get debugDescription =>
      'PagePanGestureRecognizer; pointer=$_pointer '
      'accepted=$_accepted declined=$_declined';

  int? _pointer;
  Offset? _downAt;
  Offset? _lastAt;
  bool _accepted = false;

  /// Set once the drag was declined, so a decline is decided and reported exactly once per contact.
  bool _declined = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // A MOUSE IS NOT A PAN. A mouse button drags nothing on a touch surface, and this recogniser
    // exists for the contact a musician makes with a finger or a pen.
    if (event.kind == PointerDeviceKind.mouse) {
      return;
    }
    // ONE POINTER ONLY, AND A SECOND ONE TAKES OVER RATHER THAN JOINING. Two contacts are the
    // two-finger gesture's business (owner decision D34), and a pan that also claimed the second
    // would compete with it for the same pointer.
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _downAt = event.localPosition;
    _lastAt = event.localPosition;
    _accepted = false;
    _declined = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    if (event is PointerMoveEvent) {
      final Offset at = event.localPosition;
      final Offset last = _lastAt ?? at;
      if (!_accepted && !_declined) {
        final Offset down = _downAt ?? at;
        if ((at - down).distance <= kTouchSlop) {
          _lastAt = at;
          return;
        }
        final String? refusal = refusePan?.call();
        if (refusal != null) {
          // THE ARENA IS LEFT ALONE ON PURPOSE. Not resolving means the pager's own drag and the tap
          // recogniser go on competing exactly as they did before this class existed, which is what
          // keeps page turning and selection unchanged wherever a pan is not possible.
          _declined = true;
          _lastAt = at;
          onPanRefused?.call(refusal);
          return;
        }
        // FIRST TO ACCEPT WINS, AND THIS IS THE WHOLE REASON THE CLASS EXISTS: the pager accepts at
        // the same distance, and a recogniser that waited for `kPanSlop` would lose every horizontal
        // drag to the page turn.
        _accepted = true;
        resolve(GestureDisposition.accepted);
        onPanStart?.call();
      }
      _lastAt = at;
      if (_accepted) {
        onPanUpdate?.call(at - last);
      }
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finish();
    }
  }

  @override
  void rejectGesture(int pointer) {
    // The arena handed the pointer to someone else — a page turn, or a two-finger gesture that
    // claimed it. An admitted pan ends here rather than being left open; a declined one has nothing
    // to end.
    _finish();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
    _downAt = null;
    _lastAt = null;
    _declined = false;
  }

  /// Ends an admitted pan, once, and rewinds the per-contact state.
  void _finish() {
    if (_pointer != null) {
      stopTrackingPointer(_pointer!);
    }
    final bool wasPanning = _accepted;
    _accepted = false;
    _pointer = null;
    _downAt = null;
    _lastAt = null;
    if (wasPanning) {
      onPanEnd?.call();
    }
  }
}
