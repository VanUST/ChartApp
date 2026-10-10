// PURPOSE: Put the live pointer stream in front of the ink capture layer without taking the chart's
//          own gestures away from it. It is a widget and not a bare `Listener` in the viewer because
//          the three things it must get right are easy to get wrong once and hard to see afterwards:
//          it must capture every pointer that lands, including one that lands on the white space
//          between two systems; it must forward a cancelled pointer as a cancel rather than as a
//          finish; and it must do nothing at all when the platform delivers a trackpad gesture
//          rather than a contact.
// INPUTS: An [InkCaptureLayer], the [PageLayout] currently on screen, and the child to overlay.
// OUTPUTS: The child, wrapped in a hit-testing region that reports pointer events to the layer. It
//          never prevents a default or stops an event, so the gesture arena above it still resolves
//          a gesture normally; the layer's decision, exposed to the caller through
//          `decideContact`, is what separates a contact that draws from one that selects.
// KEYWORDS: ink-surface, listener, pointer-capture, hit-test-opaque, cancel-forwarding, ink-mode
import 'package:chart_core/chart_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'ink_layer.dart';

/// Routes live pointer contacts into [InkCaptureLayer].
class RawPointerCapture extends StatelessWidget {
  /// Creates the capture surface over [child].
  const RawPointerCapture({
    super.key,
    required this.layer,
    required this.page,
    required this.child,
  });

  /// The layer every contact is reported to.
  final InkCaptureLayer layer;

  /// The page on screen, whose scale turns a surface point into a page point.
  final PageLayout page;

  /// The chart, which is what actually receives the events.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // OPAQUE, so a contact on the page's own white space still arrives here. A page paints no
      // widget over most of its area, and a deferring listener would let exactly those contacts fall
      // through — which is where a musician's quick mark most often lands.
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      // HOVER IS THE PALM GATE'S OTHER HALF. A browser delivers the pen's approach as hover, and
      // without it the gate would open between two strokes and a palm resting on the glass would
      // draw. The decoder also updates the ink mode, so a hover carries no stroke of its own.
      onPointerHover: _onHover,
      child: child,
    );
  }

  void _onDown(PointerDownEvent event) {
    final InkContactDecision? decision = layer.decideContact(
      kind: event.kind,
      width: InkInputMapper.contactWidthOf(event),
      time: InkInputMapper.millisOf(event),
      pressure: InkInputMapper.pressureOf(event),
      tilt: event.tilt,
    );
    if (decision == null) {
      return;
    }
    debugPrint(
      'ink.contact.down pointer=${event.pointer} ${decision.toString()} '
      'at=(${event.localPosition.dx.toStringAsFixed(1)},'
      '${event.localPosition.dy.toStringAsFixed(1)}) '
      'tilt=${event.tilt.toStringAsFixed(3)}',
    );
    if (!decision.mayInk) {
      return;
    }
    layer.beginStroke(
      pointer: event.pointer,
      page: page,
      kind: event.kind,
      position: InkInputMapper.positionOf(event),
      pressure: InkInputMapper.pressureOf(event),
      time: InkInputMapper.millisOf(event),
    );
  }

  void _onMove(PointerMoveEvent event) {
    layer.addSample(
      pointer: event.pointer,
      page: page,
      position: InkInputMapper.positionOf(event),
      pressure: InkInputMapper.pressureOf(event),
      time: InkInputMapper.millisOf(event),
    );
  }

  void _onUp(PointerUpEvent event) {
    layer.endStroke(pointer: event.pointer, page: page);
  }

  void _onCancel(PointerCancelEvent event) {
    layer.cancelStroke(event.pointer);
  }

  void _onHover(PointerHoverEvent event) {
    layer.decideContact(
      kind: event.kind,
      width: InkInputMapper.contactWidthOf(event),
      time: InkInputMapper.millisOf(event),
      pressure: InkInputMapper.pressureOf(event),
      tilt: event.tilt,
      isHover: true,
    );
  }
}
