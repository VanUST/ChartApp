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
//          finishes, answers [decideContact] so the widget can route a tap to selection instead,
//          and ticks [liveRevision] so the ink layer of the screen repaints itself. A stroke whose
//          first sample lies over no bar at all is anchored to the bar nearest it — see
//          `chart_core`'s `resolveInkAnchor` — and is not attached to the nearest CELL, because a
//          cell is a column of time and a point outside the bar has none.
//
//          IT ALSO HOLDS THE ONE RULE THAT SAYS WHEN A CONTACT MUST NOT DRAW AT ALL, and that is the
//          two-finger view gesture of owner decision D34: [setViewGestureActive] is set by the
//          screen's recognizer, and while it is set nothing opens a stroke and any half-drawn one is
//          abandoned. The rule lives here, beside the palm rule and in front of the one call that
//          turns a contact into a stroke, so there is exactly one place where "may this contact
//          write?" is answered.
//
//          AND IT HOLDS THE MIRROR OF THAT RULE, which is what the owner reported as a defect that
//          breaks writing: A PALM RESTING ON THE GLASS WAS READ AS A TWO-FINGER GESTURE, so the page
//          panned out from under his hand and the mark he was drawing moved with it. The gesture's
//          admission is answered by [refuseViewGestureTouch] and nowhere else, for the same reason
//          the drawing decision is: two copies of "may this contact move the page?" would drift, and
//          the drift would be a page that moves while a pen is writing on it. A palm-like contact is
//          refused, and NO CONTACT AT ALL joins the gesture while a pen is in play — with the pen
//          defined by what is observable here rather than by the device kind, because on some
//          platforms the S Pen's contacts arrive as touches (see the method's own note).
//
//          WHY IT OWNS A REPAINT TICK, AND WHY THAT IS A PERFORMANCE DECISION RATHER THAN A
//          RENDERING ONE. A pen delivers samples far faster than the screen draws, and the page is
//          expensive to re-lay-out: on the owner's tablet, re-engraving during a stroke cost a
//          layout pass on 105 of the 246 samples of one stroke, and the screen's verification-state
//          publication cost 1 738 ms of a 2 882 ms stroke. Both were paid because a widget rebuilt
//          itself on every sample. The layer is the only object that knows when the live preview
//          actually changed, so the tick lives here and the screen listens to it — one small
//          subtree repaints, and nothing re-engraves the chart. It renders nothing itself; see the
//          file header on why the renderer stays in `chart_ui`.
// KEYWORDS: ink-mode, eraser-mode, pointer-routing, palm-rule, stylus-proximity, op-log-writer,
//           commit, erase-by-tap, anchor-local, web-ink, repaint-tick, latency
//
// WHY THE ERASER IS A MODE AND NOT A SECOND SWITCH, AND WHY IT REUSES THE PALM RULE. The model
// removes whole strokes (`oplog/ink.dart`), so erasing is an operation on the stroke list and not a
// kind of ink; the mode therefore sits on this layer beside the pen rather than being a third tool
// that a stroke could be stored with. Admission reuses `InkPalmRule` unchanged, because the rule's
// question is not "is this ink" but "is this a hand that means to act on the chart": a palm resting
// on the glass while a pen is in play must neither draw a smear nor delete a marking, and a finger
// with no pen in play must be able to erase exactly where it is able to draw. One rule for both
// modes is what makes that statement checkable instead of two rules that drift.
//
// WHY THE ERASE GESTURE IS NOW A DRAG THROUGH THE INK, AND WHY THE RULE THAT STOOD HERE WAS OUT OF
// DATE RATHER THAN MERELY UNPOPULAR.
//
// This place used to carry the opposite rule. It is quoted here so the change is on the record and
// not only in a diff:
//
//   "WHY THE ERASE GESTURE IS A TAP AND NOT A STROKE THROUGH THE INK. Touch a stroke, lift without
//    dragging, and that stroke is gone. ... It does not fight the pager. A horizontal swipe to turn
//    a page begins as a contact that may land on ink; a tap predicate (travel within
//    [eraseTapSlopPx]) leaves the swipe alone, while a stroke-through eraser would delete a stroke
//    whenever a page turn happened to start on one."
//
// THAT ARGUMENT NO LONGER HOLDS, AND WHAT KILLED IT IS AN OWNER DECISION RATHER THAN A TASTE. The
// collision it priced was "the eraser's drag is also the page's swipe". Owner decision D34 removed
// that swipe: the page is moved by TWO FINGERS, and only fingers — the pen never takes part in that
// gesture at all. A one-finger or pen drag is therefore no longer how anybody turns a page, so a
// drag eraser has nothing left to fight. The trade the old block bought — "land exactly and do not
// move, or nothing is erased" — was paid for a conflict that no longer exists, and the musician was
// still paying it in his own words: «надо попасть сразу, неудобно». The constant `eraseTapSlopPx`
// went with the rule: a slop with nothing left to protect is only a delay.
//
// WHAT REMAINS OF THE COLLISION, because it is not quite nothing and saying otherwise would be the
// same mistake pointing the other way. A TWO-finger pan can begin with its first finger on ink. That
// is answered here without reintroducing a slop, and the answer is the reason the deletions happen
// at the LIFT rather than under a moving contact: the crossings are collected while the hand is down
// and shown as a PREVIEW — the ink under the rubber disappears on screen — and the document is
// written only when the contact that began the gesture lifts. If the two-finger recognizer takes the
// contacts over, [setViewGestureActive] drops the trail and NOTHING is deleted, which is strictly
// better than a slop: a slop guesses which gesture this was, and this does not guess at all.
//
// THE REST OF THE OLD BLOCK, ANSWERED ONE BY ONE RATHER THAN DROPPED:
//   - "One deliberate act removes one stroke ... a drag through several strokes appends several
//     deletions in one motion and has to be walked back one at a time." THIS IS NOW THE COST, AND IT
//     IS STATED RATHER THAN DISCOVERED: a drag across twelve strokes appends twelve deletions, so
//     putting all twelve back is twelve presses of undo. It is accepted, for reasons that are
//     concrete rather than hopeful: whole-stroke removal is the model's decision, so each of those
//     twelve inverses is exact and independent — undo puts one stroke back at a time, in the reverse
//     of the order it was crossed, and every intermediate state is a chart the musician could have
//     made (some of his ink back, the rest still gone). It is NOT the failure A65 recorded for a
//     split stroke, where the intermediate states show a chart nobody wrote. The alternative — one
//     undo per gesture — was considered and NOT taken: it needs either a grouped `UndoOp`, a change
//     to the undo model every edit in this application rests on, or a compound event in the
//     operation log, which changes the `.chart` format on both platforms and is therefore the
//     owner's decision. The cost of not taking it is measured on the tablet and recorded in A69.
//   - "The aim question is asked at ONE point, with one answer the musician can predict." The aim is
//     now asked all along the path, and every sample is answered by the SAME rule the tap used —
//     nearest stroke, topmost on a near tie, from `chart_core`'s `ink_hit.dart`, where
//     `hitTestInkErase` is literally the one-point case of the trail. What replaces "the musician
//     sees each result before the next" is the preview: the ink under the rubber goes away while the
//     hand is still down, so he sees which strokes this gesture will remove BEFORE he lifts, and the
//     lift is the only thing that commits.
//   - "It costs nothing in reach." Still true, and now it costs no precision either: a long line is
//     still one pass rather than a trace along it, because the eraser removes the whole strokes it
//     passes over instead of nibbling.
//
// THE FAILURE THAT SURVIVES, NAMED RATHER THAN HIDDEN. A stroke that is several marks to the
// musician is one mark to the eraser: whole-stroke removal is the model's decision and partial
// erosion is deliberately not offered (A64's reasoning, unchanged).
//
// AND IT MUST NEVER TOUCH THE PEN, which is a property of where the strokes come from and not of a
// check. The trail is built from the DOCUMENT's strokes, once, when the contact lands: a stroke
// still under the pen is not in the document yet, so the eraser cannot cross it, and a stroke
// committed by another contact DURING this gesture is not in the trail's candidate list either, so
// a gesture cannot erase a stroke that began after it. The eraser writes nothing at all — it appends
// deletions and never a stroke — so an erase gesture cannot leave a stray mark on the chart.
//
// WHAT THIS DOES NOT DO. It does not render: a committed stroke reaches the screen because the
// document changed and the ink painter was told to repaint, and drawing it anywhere else would put
// the same information in two places. It does not own selection: it answers whether a contact would
// draw, and the widget decides what a contact that does not draw means.
import 'dart:math' as math;

import 'package:chart_core/chart_core.dart';
import 'package:chart_ui/chart_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

// PURPOSE: Name the tool a contact acts with, so that "ink is on" and "which tool is on" are one
//          piece of state rather than two booleans with a fourth, ambiguous combination. It is not
//          `StrokeTool`: that enum names the tools a STORED stroke can carry, and the eraser is
//          deliberately not one of them because it removes strokes rather than becoming one.
// INPUTS: None; it is a choice, not a measurement.
// OUTPUTS: One of three values, and exactly one is live at a time. [off] is the state the app
//          starts in, and switching between any two modes cancels whatever the previous one had
//          half-drawn, which is why the transition lives in one private method rather than in two
//          setters that could disagree.
// KEYWORDS: ink-mode, pen, eraser, exclusive-modes, capture-state, no-ambiguous-combination
/// The tool a contact acts with while the ink layer is active.
enum InkMode {
  /// Nothing acts on the ink: a pen and a finger both select.
  off('off'),

  /// A contact admitted by the rule lays down a stroke.
  pen('pen'),

  /// A contact admitted by the rule removes the whole stroke it touches.
  eraser('eraser');

  const InkMode(this.token);

  /// Stable spelling used in a log line and in the published state.
  final String token;
}

// PURPOSE: Name the act one admitted contact performs, so that "which tool is in the hand" is a
//          value decided once per contact rather than a mode read again at every sample. It is the
//          per-contact counterpart of [InkMode]: the mode is what the app bar was set to, and this is
//          what the contact that is actually on the glass is doing, which is not the same thing once
//          the pen can carry its own eraser.
// INPUTS: The reason that chose it, which is one of the four tokens `InkCaptureLayer` publishes.
// OUTPUTS: One of two acts. `erases` says which, `token` spells it for a log line, and `reason` names
//          what decided it so that "the app bar's eraser was on" and "the pen's own button was held"
//          can never be read as the same fact in a report.
// KEYWORDS: contact-act, per-contact-tool, eraser-reason, momentary-vs-mode, log-token
/// The act one admitted contact performs, and what decided it.
class InkContactAct {
  /// The contact erases, for [reason].
  const InkContactAct.erasing(this.reason) : erases = true;

  /// The contact writes, for [reason].
  const InkContactAct.writing([this.reason = 'mode-pen']) : erases = false;

  /// Whether this act removes strokes rather than laying one down.
  final bool erases;

  /// Stable token naming what chose the act, for a log line and the published state.
  final String reason;

  /// Stable spelling of the act, for a log line.
  String get token => erases ? 'eraser' : 'pen';

  @override
  String toString() => 'InkContactAct($token by $reason)';
}

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

  /// Ticks once whenever the live preview or the committed stroke list changed.
  ///
  /// A counter rather than a `ChangeNotifier` subclass, because the value is never read: what matters
  /// is that a listener is called, and `ValueNotifier` already fires exactly once per assignment to a
  /// new value. It is never disposed because its listener count is driven by the widget that
  /// listens, which removes its own listener when it is disposed — the notifier and the layer go
  /// together, so there is nothing left to notify after the layer is dropped.
  final ValueNotifier<int> _liveRevision = ValueNotifier<int>(0);

  /// The tick a screen listens to in order to repaint ONLY the ink layer while a stroke is drawn.
  ///
  /// See the file header for why the repaint is not a `setState`: a widget rebuild here re-engraves
  /// the whole chart, which was measured at 105 layout passes and 1 738 ms of probe publication for
  /// one 246-sample stroke on the owner's tablet.
  Listenable get liveRevision => _liveRevision;

  /// The committed strokes of the document this layer writes to, in render order.
  ///
  /// Read through the session rather than held: a screen that cached a list of strokes would keep
  /// drawing the document from before the last commit, and this getter is what lets the ink layer
  /// refresh itself without the surrounding widget rebuilding. The list is the WRITTEN document, so
  /// a stroke placed by address against the page on screen moves with the music when the chart is
  /// transposed.
  List<InkStroke> get documentStrokes => _session.document.strokes;

  /// The bar divisions the document holds, recognised from that ink or drawn by the musician.
  List<BarDivision> get documentDivisions => _session.document.divisions;

  /// Whether the application looks for bar divisions in what the pen writes.
  ///
  /// OFF UNTIL THE MUSICIAN TURNS IT ON, which is owner decision D37 rule 1 and the reason this
  /// feature cannot damage a chart nobody asked it to read: with the flag false the whole of it is
  /// a skipped branch at the end of [endStroke], [endErase] and the tap path, and every other line
  /// of this class behaves exactly as it did before the feature existed.
  ///
  /// It is a plain field rather than a mode beside [InkMode] because it is not a tool: the pen still
  /// writes and the eraser still erases, and this decides only whether a stroke that was written is
  /// ALSO read.
  bool recognitionEnabled = false;

  /// The divisions found in the ink of the page that has just been written on, newest last.
  ///
  /// Set by [recogniseBarDivisions] so that a screen can report what was found without asking the
  /// detector a second time, and so that a probe can read the same numbers the application acts on.
  List<BarDivision> get lastRecognisedDivisions => _lastRecognised;
  List<BarDivision> _lastRecognised = const <BarDivision>[];

  /// Whether the last contact that ended with the eraser removed a RECOGNISED DIVISION instead of a
  /// stroke, which is the one-action repair for a barline the detector should not have found.
  bool get lastEraseRejectedRecognition => _lastEraseRejectedRecognition;
  bool _lastEraseRejectedRecognition = false;

  /// The strokes whose notehead a recognition pass ACCEPTED, so that the screen hides exactly the
  /// handwriting the recognised notes replaced.
  ///
  /// IT IS A SET OF IDS AND NOT A GEOMETRIC FILTER, and that is the whole point: the reader already
  /// decided which ink became a head (the head carries its `strokeIds`), so hiding by distance from
  /// the head's centre would be a second answer to "which ink is this note" that could drift from
  /// the gates. The ink stays in the document either way (D37 rule 5); this set only decides what is
  /// DRAWN while recognition is on, and it is cleared for a stroke the moment the musician rejects
  /// the note it became.
  ///
  /// IT IS SESSION STATE AND NOT THE FILE, AND THAT IS A NAMED LIMIT rather than an oversight: a
  /// recognised note stores no stroke id (`BeatNote` is the model's own note and has nowhere to put
  /// one), so after a reload the application knows the notes and the ink but not that they are the
  /// same mark. The hiding is therefore rebuilt by the whole-page pass when recognition is switched
  /// on, and a chart reopened with recognition on shows both layers until that pass runs. Storing the
  /// provenance in the file is a FORMAT change and is the owner's decision, exactly like the single
  /// "replace this bar's melody" event the writer's own note leaves to him.
  Set<String> get recognisedNoteStrokeIds => _recognisedNoteStrokes;
  final Set<String> _recognisedNoteStrokes = <String>{};

  /// The last reading of each bar, so that a tap can name the note a stroke became without reading
  /// the ink a second time — and so that a rejection can find the head the musician pointed at.
  final Map<String, MelodyNoteReading> _noteReadings =
      <String, MelodyNoteReading>{};

  /// The note addresses the musician has REJECTED, as `section \u0000 bar \u0000 beat \u0000 step`.
  ///
  /// A rejected note is deleted from the model, which frees its address — so without this set the
  /// very next pass would read the same ink and write the same wrong note back, and the one-action
  /// repair would be a joke. It is session state for the same reason the switch is (A73 §7): the
  /// document has no place for "the musician said no to this". A rejection is forgotten when the ink
  /// that provoked it is erased, because ink he removed is not a mark he still means.
  final Set<String> _rejectedNoteAddresses = <String>{};

  /// Milliseconds of the last event of any kind that proved a stylus is near the glass.
  ///
  /// Set by a stylus contact AND by a stylus hover, because the second is the whole reason the
  /// window exists: the browser delivers hover without a touch, and a palm that lands in the gap
  /// between two pen strokes is refused only because this was updated by the hover in between.
  double _lastStylusSeenMs = double.negativeInfinity;

  /// The tool a contact acts with: off, the pen or the eraser.
  ///
  /// One value rather than two flags, because "pen on" and "eraser on" at once is not a state this
  /// layer could act on: the two modes answer the same pointer the same way and the last one set
  /// would silently win. See [InkMode].
  InkMode _mode = InkMode.off;

  /// How many strokes this layer took up but refused because the page carried no bar.
  ///
  /// A page with no bar is the only refusal left: a sample over the margin, between two systems or
  /// on the melody staff anchors to the bar nearest it, and is committed like any other. The count
  /// is kept because a refusal must be visible in the published state rather than only in the log.
  int _dropped = 0;

  /// What FLUTTER's own pointer stream delivered, accumulated here because this is the one place the
  /// engine's events arrive.
  ///
  /// It exists to be compared against the browser's own stream, which is counted separately and
  /// independently: a pressure axis that Flutter flattened would show a single distinct value here
  /// and sixty-five there, and the two numbers together are what decide whether the pen can be
  /// captured through the framework or needs its own raw listener.
  final _FlutterInputTally _flutterInput = _FlutterInputTally();

  /// The mode in force: off, the pen or the eraser.
  InkMode get mode => _mode;

  /// Whether the PEN is the active tool, which is what the app bar's ink switch shows.
  ///
  /// False while the eraser is on: exactly one tool acts, and a switch that read "drawing" while a
  /// contact would erase would be describing a mode the next contact will not honour.
  bool get inkMode => _mode == InkMode.pen;

  /// Whether the ERASER is the active tool.
  bool get eraserMode => _mode == InkMode.eraser;

  /// How many strokes the document holds right now.
  int get strokeCount => _session.document.strokes.length;

  /// How many contacts this layer refused because the page they landed on carried no bar.
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
    'mode': _mode.token,
    'inkMode': inkMode,
    'eraserMode': eraserMode,
    'documentStrokes': _session.document.strokes.length,
    'liveContacts': _assemblers.length,
    'droppedForWantOfAnchor': _dropped,
    'viewGestureRefused': _viewGestureRefused,
    'lastPointWasInk': _lastPointWasInk,
    'eraseArmed': eraseArmed,
    'eraseBy': _eraseReason,
    'pendingErase': _eraseTrail?.crossed.length ?? 0,
    'lastErase': _lastErase,
  };

  /// Whether the most recent pointer-down was decided to lay ink.
  ///
  /// Read by the widget to route a lift to selection or to a stroke; it is the layer's answer from
  /// the same contact rather than a second evaluation of the rule in the widget, which is how the
  /// two could come to disagree.
  bool _lastPointWasInk = false;

  /// Whether the most recent pointer-down was decided to lay ink.
  bool get lastPointWasInk => _lastPointWasInk;

  /// Whether the screen's own two-finger view gesture currently owns the contacts.
  ///
  /// Owner decision D34 makes TWO FINGERS TOGETHER the pan, and a pinch the zoom. Two fingers cannot
  /// write — the gesture does not exist in handwriting — so while they are down nothing may draw,
  /// and the composer that routes a lift must not select either. This flag is how the screen tells
  /// the layer that the gesture is live; the layer is where it matters, because the layer is the one
  /// place a contact becomes a stroke, and a second copy of the rule in a widget is how the two come
  /// to disagree about a contact that arrived mid-gesture.
  ///
  /// IT IS SET FROM THE GESTURE RECOGNIZER AND NOT FROM A CONTACT COUNT HERE. A recognizer knows
  /// whether the screen has awarded it the gesture; counting pointers in this class would be a
  /// second, weaker answer to the same question, and it could not defeat the page's own swipe.
  bool get viewGestureActive => _viewGestureActive;

  bool _viewGestureActive = false;

  // PURPOSE: Tell the layer that the screen's two-finger view gesture started or ended, so no
  //          contact draws while it is live and a contact that had already begun is abandoned.
  // INPUTS: active — true when a two-finger gesture has been accepted, false when it ended.
  // OUTPUTS: Nothing. Turning it ON abandons every open stroke and any armed erase, because those
  //          contacts are the fingers now panning: committing a stroke whose hand has moved on to
  //          panning would put a mark on the chart that the musician did not write, and an erase
  //          armed by one of those fingers would delete a stroke he meant to keep. Turning it OFF
  //          touches nothing: the contacts have already lifted.
  // KEYWORDS: two-finger-pan, view-gesture, stroke-cancel, erase-disarm, no-write-while-panning,
  //           d34
  /// Declares whether the two-finger view gesture is in force.
  void setViewGestureActive(bool active) {
    if (_viewGestureActive == active) {
      return;
    }
    _viewGestureActive = active;
    if (!active) {
      return;
    }
    final bool hadStrokes = _assemblers.isNotEmpty;
    for (final InkStrokeAssembler assembler in _assemblers.values) {
      assembler.cancel();
    }
    _assemblers.clear();
    _openStylusPointers.clear();
    _live.clear();
    final bool hadErase = _erasePointer != null;
    _clearErase();
    if (hadStrokes || hadErase) {
      _liveRevision.value++;
    }
    debugPrint(
      'ink.view.gesture active=$active cancelled_strokes=$hadStrokes '
      'cancelled_erase=$hadErase strokes=${_session.document.strokes.length}',
    );
  }

  /// The pointer of the contact currently armed to erase, or null when none is.
  ///
  /// The eraser decides at the LIFT and not at the touch (see the file header), so the down has to
  /// remember which contact it was and what it has crossed since — facts that only the down can
  /// supply and only the up can act on.
  int? _erasePointer;

  /// Where the armed erase contact landed, in surface logical pixels.
  ///
  /// Kept for the log and for the published state only: the crossings are [eraseTrail]'s, and this
  /// is what a report needs to say where the gesture began. The aim is not a single point any more —
  /// see the file header on why the gesture is a drag.
  LayoutOffset? _eraseAim;

  /// What the armed erase contact has crossed so far, in the order it crossed it.
  ///
  /// Built when the contact lands from the strokes the DOCUMENT holds at that moment, and captured
  /// for the whole gesture: the strokes it can reach are fixed at the touch, which is what keeps a
  /// stroke committed by another contact mid-gesture out of an eraser that began before it. The
  /// crossings are shown as a preview and turned into deletions only at the lift — see [endErase].
  InkEraseTrail? _eraseTrail;

  /// How the eraser was chosen for the armed contact, for the log and for the published state.
  ///
  /// One of the [erasesByMode], [erasesByStylusButton] or [erasesByStylusEraserEnd] tokens. It is
  /// carried rather than re-derived because the button's state at the DOWN is the only moment it
  /// can be read: a contact never changes tool while it is in flight.
  String? _eraseReason;

  /// The tool was chosen by the app bar's eraser switch, which stays on across contacts.
  static const String erasesByMode = 'mode-eraser';

  /// The tool was chosen by the app bar's pen switch, which is the eraser being OFF.
  static const String writesByMode = 'mode-pen';

  /// The tool was chosen by the pen's own side button, held when this contact landed.
  ///
  /// A MOMENTARY effect and not a mode: see [actFor], which explains why the button may not become
  /// a toggle.
  static const String erasesByStylusButton = 'stylus-button';

  /// The tool was chosen by the pen being turned round, so the eraser end is the one on the glass.
  static const String erasesByStylusEraserEnd = 'stylus-eraser-end';

  /// What the last completed erase did, for a log line and for a driving tool that cannot reach
  /// this object: the strokes removed, where they sat, and the distance that decided each.
  Map<String, Object?>? _lastErase;

  /// The strokes crossed so far by the armed contact, for the preview a painter filters by.
  ///
  /// Empty when no erase contact is armed, so the painter's filter is free on the pen's own path.
  Set<String> get pendingEraseIds =>
      _eraseTrail?.crossedIds ?? const <String>{};

  /// Whether an erase contact is armed right now, whatever chose the eraser.
  ///
  /// Distinct from [eraserMode], which is the app bar's switch: with a momentary eraser armed by the
  /// pen's own button or by the eraser end of the pen, the MODE is off and this is true.
  bool get eraseArmed => _erasePointer != null;

  /// How many edits this layer has appended to the operation log: strokes committed, strokes erased.
  ///
  /// A counter of CHANGES and not of samples, read by the screen once per contact lift to learn
  /// whether the page it drew is stale. The screen needs it because a gesture that moved never
  /// resolves as a tap, so the tap handler that used to carry "the document changed, rebuild" is not
  /// called for exactly the gestures this file now produces: a pen stroke that travelled, and an
  /// eraser drag. The ink layer repaints itself either way; this is about everything else on screen,
  /// the undo button included.
  int get documentEdits => _documentEdits;

  int _documentEdits = 0;

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

  /// Turns the PEN on or off, which is the app bar's ink switch.
  ///
  /// Turning it on sets the mode to [InkMode.pen]; turning it off sets [InkMode.off]. It is a
  /// separate setter from [eraserMode] so the two app-bar controls each name the mode they mean, and
  /// both funnel through [_setMode], where the half-drawn-stroke rule has one home.
  set inkMode(bool on) => _setMode(on ? InkMode.pen : InkMode.off);

  /// Turns the ERASER on or off, which is the app bar's eraser switch.
  ///
  /// Turning it on sets the mode to [InkMode.eraser]; turning it off sets [InkMode.off]. Erasing is
  /// not "ink with a different colour": it is an operation on the stroke list (see the file header),
  /// so the eraser is a mode of this layer and not a [StrokeTool].
  set eraserMode(bool on) => _setMode(on ? InkMode.eraser : InkMode.off);

  /// Moves the layer to [next], discarding anything half-drawn and any armed erase.
  ///
  /// A half-drawn stroke is abandoned rather than kept: the mode changed under the musician's hand,
  /// and committing a stroke whose beginning was captured under another mode would be a mark they
  /// did not finish making. An armed erase is dropped for the same reason — the contact that armed
  /// it was aimed at the old mode, and carrying it into the new one would delete a stroke on a lift
  /// the musician never intended as an eraser gesture.
  void _setMode(InkMode next) {
    if (_mode == next) {
      return;
    }
    _mode = next;
    for (final InkStrokeAssembler assembler in _assemblers.values) {
      assembler.cancel();
    }
    _assemblers.clear();
    _openStylusPointers.clear();
    _live.clear();
    _clearErase();
    debugPrint(
      'ink.mode mode=${next.token} strokes=${_session.document.strokes.length}',
    );
  }

  // PURPOSE: Say which act one admitted contact performs, from the app bar's mode and from the pen's
  //          own hardware, so that "the eraser" is one decision taken at one place instead of a
  //          widget reading a mode and guessing the rest.
  // INPUTS: kind — the engine's pointer kind, whose `invertedStylus` value means the pen was turned
  //         round. buttons — the event's own button bitmask. Only the stylus' PRIMARY side button
  //         counts, which the pinned Flutter defines as `kPrimaryStylusButton` (0x02, the same value
  //         as `kSecondaryButton`; verified in this project's 3.47.7 rather than remembered). The
  //         contact bit itself (`kStylusContact`, 0x01) is NOT a button and is ignored.
  // OUTPUTS: Which act the contact performs and which of the three reasons chose it, in the order
  //          the reasons are checked: the pen turned round first, then the side button, then the app
  //          bar's mode. Never null.
  //
  //          WHY A MOMENTARY ERASER AND NOT A TOGGLE. Both platforms put the eraser on a press-and-
  //          hold: the eraser END of a pen is momentary by construction, and every drawing surface
  //          with a barrel button erases while it is held. The deeper reason is the hard rule that
  //          the pen must keep working: a TOGGLE would leave the eraser armed after the musician put
  //          the button down, so his next stroke would erase instead of writing — the failure would
  //          be invisible until ink failed to appear, and it would be caused by the one control that
  //          is supposed to be a convenience. A momentary eraser cannot do that: the act is decided
  //          once, at the DOWN, and the contact keeps it until it lifts, so a stroke that began as
  //          ink can never turn into an erasure or the other way round mid-flight, whatever the
  //          platform reports afterwards.
  //
  //          WHY THE BUTTON IS NOT ADVERTISED IN THE INTERFACE. Nothing in the UI promises it. On
  //          Android the button reaches the framework only if the platform puts it in the pointer's
  //          button bitmask, and this project has not yet observed the bit on the owner's tablet
  //          (A69 records what was and was not measured); a control that is announced and does not
  //          arrive is worse than one that is simply there when the platform delivers it. The eraser
  //          switch in the app bar and the pen's own eraser end both keep working whatever this
  //          returns, so the button is an accelerator and never the only path.
  // KEYWORDS: tool-choice, momentary-eraser, barrel-button, inverted-stylus, pen-must-keep-writing,
  //           single-decision-at-down, platform-honest
  /// Returns the act a contact performs — erasing or writing — and what decided it.
  InkContactAct actFor({
    required PointerDeviceKind kind,
    required int buttons,
  }) {
    if (kind == PointerDeviceKind.invertedStylus) {
      return const InkContactAct.erasing(erasesByStylusEraserEnd);
    }
    if (kind == PointerDeviceKind.stylus &&
        (buttons & kPrimaryStylusButton) != 0) {
      return const InkContactAct.erasing(erasesByStylusButton);
    }
    return _mode == InkMode.eraser
        ? const InkContactAct.erasing(erasesByMode)
        : const InkContactAct.writing();
  }

  // PURPOSE: Take one admitted contact and route it to the act its tool names, so the widget above
  //          holds no copy of that decision and cannot disagree with it later in the gesture.
  // INPUTS: pointer — the contact's id. page — the layout on screen. kind and buttons — what the
  //         engine reported for this event, which is what [actFor] reads. position, pressure, time —
  //         the first sample. buttons is only read here and at no other point of the contact.
  // OUTPUTS: The act that was begun: erasing, or writing, with the reason. The stroke may still be
  //          refused by [beginStroke] for its own reasons (no bar to anchor to, or the two-finger
  //          gesture owning the contacts) and that refusal is logged there, not folded into this.
  //          One pointer id cannot be two contacts: a second contact with the same id begins again
  //          and replaces the first, exactly as each of the two halves documents on its own.
  // KEYWORDS: contact-routing, single-decision, tool-at-down, no-drifting-copy
  /// Begins the act the contact's tool names, returning which act that was.
  InkContactAct beginContact({
    required int pointer,
    required PageLayout page,
    required PointerDeviceKind kind,
    required int buttons,
    required LayoutOffset position,
    required double pressure,
    required double time,
  }) {
    final InkContactAct act = actFor(kind: kind, buttons: buttons);
    debugPrint(
      'ink.contact.act pointer=$pointer tool=${act.token} by=${act.reason} '
      'kind=${InkInputMapper.kindOf(kind)?.token ?? 'unknown'} '
      'buttons=0x${buttons.toRadixString(16)}',
    );
    if (act.erases) {
      beginErase(
        pointer: pointer,
        page: page,
        position: position,
        reason: act.reason,
      );
    } else {
      beginStroke(
        pointer: pointer,
        page: page,
        kind: kind,
        position: position,
        pressure: pressure,
        time: time,
      );
    }
    return act;
  }

  // PURPOSE: Carry one sample to whichever act this pointer began, so that the routing decision is
  //          made once and honoured for the whole contact even if the mode changes underneath it.
  // INPUTS: pointer — the contact. position — the sample. pressure and time — its other values,
  //         which only the pen half keeps. page — the layout, needed to resolve the live preview.
  // OUTPUTS: Nothing. A sample for a pointer that began neither act is dropped by both halves, which
  //          is what makes this safe to call for a contact the rule refused.
  // KEYWORDS: contact-move, routing, mode-change-safe, silent-when-absent
  /// Carries one sample to the act the contact began.
  void moveContact({
    required int pointer,
    required PageLayout page,
    required LayoutOffset position,
    required double pressure,
    required double time,
  }) {
    if (_eraseTrail != null && _erasePointer == pointer) {
      moveErase(pointer: pointer, position: position);
      return;
    }
    addSample(
      pointer: pointer,
      page: page,
      position: position,
      pressure: pressure,
      time: time,
    );
  }

  // PURPOSE: Finish whichever act this pointer began, which is where a stroke is committed and an
  //          erase's collected crossings become deletions.
  // INPUTS: pointer — the contact. page — the layout on screen, which the pen half needs to convert
  //         its samples back into anchor-local geometry and which the eraser half does not read (its
  //         page was captured when the contact landed). position — where it lifted, which is the
  //         eraser's last path point and is unused by the pen, whose stroke ends at its last sample.
  // OUTPUTS: The stroke committed when the contact was writing, else null; an erase reports its
  //          removals through `lastErase` and the log. Exactly one act runs, and which one is
  //          decided by what the pointer actually began rather than by the mode at the lift.
  // KEYWORDS: contact-end, commit-or-erase, routing, one-act-only
  /// Finishes the act the contact began.
  InkStroke? endContact({
    required int pointer,
    required PageLayout page,
    required LayoutOffset position,
  }) {
    if (_erasePointer == pointer) {
      endErase(pointer: pointer, position: position);
      return null;
    }
    return endStroke(pointer: pointer, page: page);
  }

  // PURPOSE: Cancel whichever act this pointer began, for the platform's own pointer-cancel.
  // INPUTS: pointer — the contact.
  // OUTPUTS: Nothing. Both halves are asked and each is a no-op for a pointer it is not tracking, so
  //          a contact whose mode changed under it cannot lose its cancel.
  // KEYWORDS: contact-cancel, both-halves, mode-change-safe
  /// Cancels the act the contact began.
  void cancelContact(int pointer) {
    cancelStroke(pointer);
    cancelErase(pointer);
  }

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
      inkModeOn: _mode != InkMode.off,
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

  /// Stable token: a contact was refused the view gesture because a STYLUS contact is open.
  ///
  /// This is the strongest form of "a pen is in play": the pen is literally on the glass, drawing,
  /// at the moment the contact arrives. On the owner's tablet the S Pen's contacts arrive as
  /// `PointerDeviceKind.stylus` — measured from the application's own log, `ink.contact.down ...
  /// kind=stylus width=0.0` — and this is the token that fires when a palm lands while he writes.
  static const String viewRefusalInkContactOpen = 'ink-contact-open';

  /// Stable token: the reason a contact was refused the view gesture BECAUSE A PEN WAS RECENTLY SEEN.
  ///
  /// **KEPT AS A NAME AND NO LONGER PRODUCED, and the correction it records is the point of keeping
  /// it.** Until the tablet run that froze the owner's document, [refuseViewGestureTouch] answered
  /// this token for every touch that arrived while [stylusInPlay] was true — that is, for one second
  /// after any pen contact OR pen hover, whenever the ink mode was on. On his tablet the pen is in
  /// his hand for the whole session, so the window was effectively always open and the two-finger pan
  /// of owner decision D34 was refused for the entire session: a gate that never opens is a document
  /// that cannot be moved, and that is exactly what he reported. The window was written to catch a
  /// palm landing between two strokes; a palm is ONE contact, and D34's gesture needs TWO, so the
  /// refusal was buying protection it could not deliver while costing the only pan there was.
  ///
  /// Nothing produces this token now; a stored record that carries it was written by a build before
  /// this correction, which is why the name stays rather than being deleted.
  static const String viewRefusalStylusInPlay = 'stylus-in-play';

  /// Stable token: a contact of a kind that is not a touch was offered to the view gesture.
  ///
  /// The recogniser filters these out before it asks, so this is a safety net rather than the usual
  /// path: it keeps the answer total, so a caller that forgot the filter still gets a refusal and a
  /// name instead of a silent admission.
  static const String viewRefusalNotATouch = 'not-a-touch';

  /// The pointers of the contacts that are drawing right now whose kind is a STYLUS.
  ///
  /// Held separately from [_assemblers] because the view gesture asks a different question of it:
  /// the assembler map answers "is something writing", while this answers "is the PEN writing", and
  /// only the second can be a reason to refuse a two-finger gesture. A stylus pointer can never be
  /// one of the gesture's own touches — the recogniser counts touches only — so a refusal on this
  /// signal can never forbid the gesture to its own first finger. See [refuseViewGestureTouch].
  final Set<int> _openStylusPointers = <int>{};

  /// How many contacts this layer refused a place in the two-finger view gesture.
  ///
  /// Kept beside [_dropped] and for the same reason: a refusal that exists only in a log line is a
  /// refusal nobody can count after the run, and the published state is what a driving tool reads.
  int _viewGestureRefused = 0;

  /// How many contacts were refused a place in the two-finger view gesture.
  int get viewGestureRefusalCount => _viewGestureRefused;

  // PURPOSE: Answer whether one contact may become part of the two-finger view gesture, and name the
  //          reason when it must not. It is the ONE place where "may this contact move the page?" is
  //          answered, so the recogniser holds no second copy of the palm rule and cannot drift from
  //          the one the pen and the eraser are routed by.
  // INPUTS: kind — the engine's pointer kind. width — the contact width in logical pixels, as the
  //         framework reports it. time — the contact's own timestamp, in the same base the strokes
  //         use. It is carried for the width arbitration and for the refusal record; it no longer
  //         gates anything, see below.
  // OUTPUTS: Null when the contact may join the gesture, otherwise a stable reason token: the palm
  //          rule's own [InkPalmRule.reasonPalmLikeWidth], [viewRefusalInkContactOpen] or
  //          [viewRefusalNotATouch].
  //
  //          THE ORDER OF THE TESTS IS THE ORDER OF THE REASONS, and the palm first: a palm that
  //          lands while a pen is writing is refused FOR BEING A PALM, which is the fact the musician
  //          can act on, rather than as a side effect of the pen being down.
  //
  //          WHAT "A PEN IS IN PLAY" MEANS HERE, AND WHY THE WEAKER HALF OF IT WAS REMOVED. A pen is
  //          observable in this application in two strengths: it is a contact whose KIND the platform
  //          calls a stylus and it is on the glass right now — the strongest — or it was SEEN within
  //          the last second, as a contact or as a hover. The first is still a refusal. **The second
  //          is not, and its removal is a measured correction rather than a preference.** The rule
  //          used to refuse every touch that arrived inside that one-second window while the ink mode
  //          was on, on the theory that a palm landing between two pen strokes would be caught by it.
  //          The owner's own report is what falsified it: he holds the pen for the whole session, so
  //          the window is effectively always open on his tablet, and the two-finger pan that owner
  //          decision D34 gave him was refused for the whole session — a gate that never opens is a
  //          document that cannot be moved. A palm is ONE contact and this gesture needs TWO, so the
  //          window was paying for the only pan he had with protection it could not actually deliver.
  //          The pen-on-the-glass test below still covers the case A64 reported, because a hand
  //          resting on the glass does so WHILE the pen is writing, and while the pen is writing
  //          there is an open stylus contact.
  //
  //          The rule deliberately does NOT refuse merely because SOME stroke is open, and the
  //          first version of it did. With the ink mode on, a touch draws (A61's decision for this
  //          panel), so D34's own two fingers open a stroke on the first finger and the gesture
  //          exists exactly to take the page over from it; a gate on "any open stroke" forbade
  //          two-finger panning in the one mode where a writing musician wants it, and the file's own
  //          test caught it. A STYLUS contact is different in kind, not in degree: the recogniser
  //          never counts a stylus, so refusing on it can never forbid the gesture to its own finger.
  //
  //          WHAT REMAINS UNPROTECTED, AND WHY IT IS NAMED RATHER THAN HIDDEN. (a) A palm that rests
  //          on the glass while the pen is LIFTED is no longer refused by the proximity window, so a
  //          palm the panel reports as two contacts can now pan the page. It moves the view and
  //          nothing else, and the scene bar's reset returns it. That is the price of the removal,
  //          and it was paid because the alternative was a frozen document. (b) On a platform whose
  //          stylus fusion reports the pen's contacts as touches AND reports no contact width, none
  //          of these signals separates a pen from a finger: the pen opens no stylus contact and the
  //          palm's width arrives as zero. That is the same limitation `docs/sdd.md` A61 recorded,
  //          and it is not something this rule can close from here.
  //
  //          THE WIDTH IS ARBITRATED BY THE SAME FUNCTION THE INK RULE USES, framework value first
  //          and the raw browser's only when the framework reported none, so the pixels a palm is
  //          judged by here are the pixels it is judged by there.
  // KEYWORDS: view-gesture-admission, palm-rule-reuse, pen-on-glass, stylus-contact, window-removed,
  //           single-authority, instrumented-refusal, measured-limit, d34
  /// Returns the reason [kind]/[width] may not join the view gesture, or null when it may.
  String? refuseViewGestureTouch({
    required PointerDeviceKind kind,
    required double width,
    required double time,
  }) {
    if (kind != PointerDeviceKind.touch) {
      _viewGestureRefused++;
      return viewRefusalNotATouch;
    }
    final double decidingWidth = contactWidthFor(
      time: time,
      frameworkWidth: width,
    );
    if (InkPalmRule.isPalmLikeWidth(decidingWidth)) {
      _viewGestureRefused++;
      return InkPalmRule.reasonPalmLikeWidth;
    }
    if (_openStylusPointers.isNotEmpty) {
      _viewGestureRefused++;
      return viewRefusalInkContactOpen;
    }
    return null;
  }

  // PURPOSE: Begin drawing a contact that the rule admitted.
  // INPUTS: pointer — the engine's pointer id, which is the identity of this contact. page — the
  //         layout being drawn on. kind — the pointer kind. position — where the contact landed, in
  //         the widget's pixels. pressure and time — the first sample's values.
  // OUTPUTS: True when a stroke was opened. False in one of two cases, and the log names which:
  //          the page carries no bar to anchor to, in which case the contact is tracked as refused
  //          and no stroke will be committed; or the two-finger view gesture owns the contacts, in
  //          which case the contact is the pan and must not become ink (owner decision D34). A second
  //          contact with the same pointer id replaces the first, because one pointer id cannot be
  //          two contacts and the older one is a leaked stroke rather than a real second hand.
  //          The `ink.stroke.begin` line reports WHICH rule chose the anchor (`basis=`) and how far
  //          into the margin the stroke began (`margin_px=`), because "the mark was kept" and "the
  //          mark was hung on the nearest bar" are two different facts a report must be able to
  //          state separately.
  // KEYWORDS: begin-stroke, anchor-resolution, admitted-contact, replace-guard, margin-writing
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
    // TWO FINGERS CANNOT WRITE (owner decision D34). While the view gesture owns the contacts a
    // contact must not open a stroke — including the FIRST of the two fingers, if the recognizer
    // awarded itself the gesture before this event was routed. The refusal is logged with its own
    // reason and is deliberately NOT counted in [_dropped]: that counter means "the page had no bar
    // to anchor to", and folding a second meaning into it would make both unreadable. See
    // [setViewGestureActive] for why a stroke already open is abandoned rather than completed.
    if (_viewGestureActive) {
      debugPrint(
        'ink.stroke.refused pointer=$pointer kind=${captureKind.token} '
        'reason=view-gesture-active '
        'surface=(${position.x.toStringAsFixed(1)},'
        '${position.y.toStringAsFixed(1)})',
      );
      return false;
    }
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
        'reason=page-has-no-bar surface=(${position.x.toStringAsFixed(1)},'
        '${position.y.toStringAsFixed(1)}) scale=${page.scale}',
      );
      return false;
    }
    _assemblers[pointer] = assembler;
    if (captureKind.isStylus) {
      _openStylusPointers.add(pointer);
    }
    _lastPointWasInk = true;
    _refreshLive(page);
    // THE PAGE POINT IS PRINTED BESIDE THE SURFACE POINT AND THE VIEW, because that pair is the
    // whole of "the pen wrote where it was put": the surface coordinate is where the glass was
    // touched, the page coordinate is what the anchor rule was given, and the view is what turned
    // one into the other. Reading only the anchor cannot show that the transform was inverted
    // rather than guessed, which is exactly the defect (A47) this evidence is here to rule out.
    final LayoutOffset pagePoint = page.pagePointOf(position);
    debugPrint(
      'ink.stroke.begin pointer=$pointer kind=${captureKind.token} '
      'anchor=${assembler.anchor} basis=${assembler.anchorBasis?.token ?? 'none'} '
      'margin_px=${assembler.anchorDistancePx.toStringAsFixed(1)} '
      'surface=(${position.x.toStringAsFixed(1)},${position.y.toStringAsFixed(1)}) '
      'page_point=(${pagePoint.x.toStringAsFixed(1)},'
      '${pagePoint.y.toStringAsFixed(1)}) '
      'scale=${page.scale} zoom=${page.zoom.toStringAsFixed(3)} '
      'pan=(${page.pan.x.toStringAsFixed(1)},${page.pan.y.toStringAsFixed(1)}) '
      'pressure=${pressure.toStringAsFixed(2)}',
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
    _openStylusPointers.remove(pointer);
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
    _documentEdits++;
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
    // RECOGNITION RUNS LAST, AFTER THE STROKE IS IN THE LOG, and only when the musician turned it on.
    // Last, because the detector weighs this stroke against the page's other ink and the stroke it
    // just wrote has to be one of the neighbours; after the append, because the append is the fact
    // that has to exist whatever recognition decides, and a detector that throws must not be able to
    // lose the ink. With the switch off this is one boolean read and nothing else.
    //
    // AND THE NOTE READER'S CALL IS DELIBERATELY ABSENT FROM HERE, WHICH IS A DECISION AND NOT AN
    // OMISSION. [recogniseMelodyNotes] exists, is measured and works — but it writes `(beat, step,
    // pitch)` through `note.insert`, and the owner removed that shape as a class: «Запись сама по
    // себе структурированная единица. Относительное ее положение — нет. Сетка НЕ квантизована».
    // Wiring it here would put the representation he rejected INTO THE FILE while the replacement is
    // still being decided, so the call comes back in this one place when the model is settled — and
    // not before. The reader, its provenance and its gates are untouched by that decision, because
    // they measure ink and not addresses.
    if (recognitionEnabled) {
      recogniseBarDivisions(page);
    }
    return stroke;
  }

  // PURPOSE: Look for bar divisions in the ink on [page] and record what it finds as STRUCTURE, so
  //          that a line the musician drew comes back as an ideal line the document holds.
  //
  //          A RECOGNISED DIVISION IS A STRUCTURAL UNIT, NOT A REDRAWING OF HIS STROKE. The event it
  //          appends is `division.set`; the stroke stays exactly where it was, which is D37 rule 5
  //          and the reason a misrecognition can be undone at all. The division carries the id of
  //          the stroke it came from, which is what lets the painter hide that one piece of ink
  //          while recognition is on and show it again the moment the switch goes off or the
  //          division is rejected.
  //
  //          ONLY THE STROKE NAMED BY [onlyStrokeId] IS CONSIDERED, and that is a decision about
  //          repair rather than about cost. A whole-page pass would re-recognise a division the
  //          musician had already deleted, every time he wrote anything else, which would make the
  //          one-action repair a joke. A stroke he writes again is a stroke he means again.
  // INPUTS: page — the layout on screen, which is what resolves each anchor to a page position and
  //         what every row's height is read from. onlyStrokeId — the stroke whose commit triggered
  //         this pass; null means the whole page, which is what a probe wants and the app does not.
  // OUTPUTS: The divisions the page now holds, newest last, also kept in [lastRecognisedDivisions]
  //          for a caller that reports them. The document is changed ONLY when a candidate was found
  //          and was not already known: no rejection is recorded anywhere, so a stroke the detector
  //          refuses leaves the document byte-identical to what it was before the pass.
  // KEYWORDS: recognition, bar-division, structure-from-ink, op-log-write, dedupe, repair-aware,
  //           off-by-default, d37
  /// Looks for divisions in the ink of [page] and records them through the log.
  List<BarDivision> recogniseBarDivisions(
    PageLayout page, {
    String? onlyStrokeId,
  }) {
    final List<InkStroke> strokes = _session.document.strokes;
    if (strokes.isEmpty) {
      _lastRecognised = _session.document.divisions;
      return _lastRecognised;
    }
    final List<PlacedInkStroke> placed = placeInkStrokes(page, strokes);
    final Map<String, BarlineFrame> frames = barlineFramesOfPage(page);
    List<PlacedBarlineCandidate> found = const <PlacedBarlineCandidate>[];
    for (final PlacedInkStroke one in placed) {
      if (onlyStrokeId != null && one.stroke.id != onlyStrokeId) {
        continue;
      }
      final BarlineVerdict verdict = measureBarlineStroke(
        stroke: one,
        strokes: placed,
        barFrames: frames,
      );
      final BarlineCandidate? candidate = verdict.candidate;
      if (candidate == null) {
        debugPrint(
          'barline.refused id=${one.stroke.id} '
          'gate=${verdict.rejection?.token} ${verdict.measurement}',
        );
        continue;
      }
      debugPrint(
        'barline.found id=${one.stroke.id} '
        'band=${verdict.measurement.band?.kind.token ?? 'none'} '
        'x=${candidate.centreX.toStringAsFixed(1)} '
        'ink_height=${verdict.measurement.height.toStringAsFixed(1)} '
        'line_height=${candidate.height.toStringAsFixed(1)} '
        '${verdict.measurement}',
      );
      found = <PlacedBarlineCandidate>[
        ...found,
        PlacedBarlineCandidate(candidate: candidate, origin: one.origin),
      ];
    }
    if (found.isEmpty) {
      _lastRecognised = _session.document.divisions;
      return _lastRecognised;
    }
    final List<BarDivision> next = List<BarDivision>.of(
      _session.document.divisions,
    );
    for (final PlacedBarlineCandidate placedCandidate in found) {
      final BarlineCandidate candidate = placedCandidate.candidate;
      final bool known = next.any(
        (BarDivision division) => division.cameFrom(candidate.strokeId),
      );
      if (known) {
        continue;
      }
      next.add(
        BarDivision(
          // The stroke's own id, so that the division and the ink it came from can never be
          // confused for two different marks, and so that a reader of the file can follow one to
          // the other without a second table.
          id: 'division-${candidate.strokeId}',
          place: AnchoredPlace(
            anchor: candidate.anchor,
            offsetX: candidate.centreX,
            offsetY: candidate.top,
          ),
          height: candidate.height,
          sourceStrokeId: candidate.strokeId,
        ),
      );
    }
    if (next.length == _session.document.divisions.length) {
      _lastRecognised = _session.document.divisions;
      return _lastRecognised;
    }
    _session.apply(
      DivisionSetEvent(
        docId: _session.docId,
        seq: _session.seq,
        from: _session.document.divisions,
        to: next,
      ),
    );
    _documentEdits++;
    _lastRecognised = next;
    debugPrint(
      'barline.divisions count=${next.length} seq=${_session.seq} '
      'ids=${next.map((BarDivision division) => division.sourceStrokeId).join(',')}',
    );
    return next;
  }

  // PURPOSE: Read the NOTES out of the ink on [page] and record them as STRUCTURE — the same one
  //          organ the musician turned on, now reading a second kind of mark.
  //
  //          WHY THIS IS THE SAME PASS AS [recogniseBarDivisions] AND NOT A FEATURE BESIDE IT. The
  //          owner keeps ONE switch for recognition as a whole (RU «Распознавание: ВКЛ/ВЫКЛ»): his
  //          rule is that a musician whose recognition works badly turns it off and keeps working,
  //          and two controls would mean two things to turn off and a page that is half-recognised
  //          with nothing on screen saying which half. So both readers hang off [recognitionEnabled]
  //          and neither has a switch of its own.
  //
  //          WHAT IT WRITES, AND THE HONEST BOUND. One `note.insert` per accepted head, carrying the
  //          beat the head stands in and its order inside that beat — never a duration, never an
  //          accidental (see `melody_note_writer.dart`, whose `recognisedNoteValue` carries the whole
  //          of that reasoning). A note whose address the bar already holds is SKIPPED, so
  //          recognising the same ink twice writes nothing, and a correction the musician made by
  //          hand survives the next pass.
  //
  //          WHY ONLY ONE BAR WHEN A STROKE IS NAMED. The reader's input is a BAR — its ink, its
  //          staff frame, its beat columns — so the unit of work is a bar and not a stroke. Reading
  //          only the bar the new stroke landed in is what makes a pass cost one bar rather than a
  //          page, and it is also what keeps a rejection durable in every OTHER bar: a pass that
  //          re-read the whole page on every stroke would re-write every note the musician had
  //          rejected elsewhere. A stroke whose anchor resolves to no bar costs no read at all.
  // INPUTS: page — the layout on screen. onlyStrokeId — the stroke whose commit triggered the pass;
  //         null means every bar of the page, which is what switching recognition on wants.
  // OUTPUTS: What the pass wrote, as one [MelodyNoteWrite] per bar that had ink: the notes added,
  //          the addresses already spoken for, and the value each added note carries. The document
  //          is changed only by the `note.insert` events, and [recognisedNoteStrokeIds] gains the
  //          ink of every head that now has a note, so the screen hides that ink in the same frame.
  //          A bar that yields no head is left alone entirely, and nothing is ever deleted.
  // KEYWORDS: recognition, note-reader, structure-from-ink, op-log-write, one-bar-pass,
  //           idempotent, off-by-default, d37, d28, a78
  /// Reads the notes of the page's staff ink and records them through the log.
  MelodyNoteWrite recogniseMelodyNotes(
    PageLayout page, {
    String? onlyStrokeId,
  }) {
    // WHICH BAR THE TRIGGERING STROKE BELONGS TO, if the caller named one. The anchor is the address
    // the ink was stored against, which is the document's own answer to "where is this stroke" and
    // the same answer the renderer uses, so the bar read here is the bar drawn there.
    EventAnchor? onlyAnchor;
    if (onlyStrokeId != null) {
      for (final InkStroke stroke in _session.document.strokes) {
        if (stroke.id == onlyStrokeId) {
          onlyAnchor = stroke.anchor;
          break;
        }
      }
    }
    MelodyNoteWrite total = const MelodyNoteWrite.none(recognisedNoteValue);
    for (final PlacedBar placed in page.bars) {
      if (onlyAnchor != null &&
          (onlyAnchor.sectionId != placed.sectionId ||
              onlyAnchor.bar != placed.barIndex)) {
        continue;
      }
      final String key = _barKey(placed.sectionId, placed.barIndex);
      final MelodyNoteReading reading = readMelodyNotesOfBar(
        page: page,
        strokes: _session.document.strokes,
        sectionId: placed.sectionId,
        barIndex: placed.barIndex,
      );
      if (reading.heads.isEmpty) {
        _noteReadings.remove(key);
        continue;
      }
      // THE MUSICIAN'S REJECTIONS ARE APPLIED HERE, in the layer that holds them, rather than inside
      // the writer: `chart_core` writes what a reading says, and "the musician said no to this
      // address" is a session decision that the document has nowhere to keep.
      final List<MelodyNoteHead> accepted = <MelodyNoteHead>[
        for (final MelodyNoteHead head in reading.heads)
          if (!_rejectedNoteAddresses.contains(
            _noteAddressKey(
              placed.sectionId,
              placed.barIndex,
              head.beat,
              head.orderInBeat,
            ),
          ))
            head,
      ];
      final MelodyNoteReading wanted = MelodyNoteReading(
        sectionId: reading.sectionId,
        barIndex: reading.barIndex,
        heads: accepted,
        refusals: reading.refusals,
      );
      final MelodyNoteWrite write = writeRecognisedNotes(
        session: _session,
        reading: wanted,
      );
      _noteReadings[key] = wanted;
      // EVERY accepted head whose address the bar now HOLDS is drawn as structure, so its ink is
      // hidden while recognition is on — whether this pass wrote the note or found it already
      // written, because either way the note on the page is the structure and not the hand.
      for (final MelodyNoteHead head in accepted) {
        if (_session.existingNoteAt(
              sectionId: placed.sectionId,
              barIndex: placed.barIndex,
              beat: head.beat,
              step: head.orderInBeat,
            ) ==
            null) {
          continue;
        }
        _recognisedNoteStrokes.addAll(head.strokeIds);
      }
      debugPrint(
        'note.read section=${placed.sectionId} bar=${placed.barIndex} '
        'heads=${reading.heads.length} accepted=${accepted.length} '
        'written=${write.written.length} '
        'present=${write.alreadyPresent.length} '
        'refused=${reading.refusals.length} '
        'ink=${accepted.fold<int>(0, (int sum, MelodyNoteHead head) => sum + head.strokeIds.length)}',
      );
      for (final BeatNote note in write.written) {
        debugPrint(
          'note.found section=${placed.sectionId} bar=${placed.barIndex} '
          'beat=${note.beat} step=${note.step} pitch=${note.pitch} '
          'value=${note.value} accidental=none duration=not-read',
        );
      }
      for (final MelodyNoteRefusal refusal in reading.refusals) {
        debugPrint(
          'note.refused section=${placed.sectionId} bar=${placed.barIndex} '
          'gate=${refusal.reason.token} x=${refusal.x.toStringAsFixed(1)} '
          'y=${refusal.y.toStringAsFixed(1)}',
        );
      }
      total = MelodyNoteWrite(
        written: <BeatNote>[...total.written, ...write.written],
        alreadyPresent: <BeatNote>[
          ...total.alreadyPresent,
          ...write.alreadyPresent,
        ],
        value: write.value,
      );
    }
    return total;
  }

  // PURPOSE: Give a recognised note its handwriting back with ONE tap, which is the repair the
  //          owner's rule puts on a wrong recognition (D37 rule 2) and the exact counterpart of
  //          [toggleDivisionAt].
  //
  //          THE TAP LANDS ON THE HANDWRITING, WHICH IS NOT ON SCREEN, and that is deliberate. With
  //          recognition on the ink is hidden, so a musician cannot point at it — but he CAN point at
  //          the wrong note he sees, and the ink that produced it lies under that very spot because
  //          the structure was drawn where the head was read. The hit test therefore runs against the
  //          DOCUMENT's strokes, exactly as the eraser's does, and the answer is the same one the
  //          reader gave: this stroke is part of that head.
  // INPUTS: page — the layout on screen. surfacePoint — where the musician tapped, in the surface
  //         logical pixels the hit test speaks.
  // OUTPUTS: `rejected` when a recognised note was deleted and its ink given back, `rejected-none`
  //          when the head was found but its address held no note (already undone), or null when the
  //          tap hit no recognised head at all — in which case the tap goes on to mean a selection.
  //          The deleted note is one `note.delete` event, so undo puts it back; the INK is never
  //          touched (D37 rule 5) and the address is remembered so no later pass rewrites it.
  // KEYWORDS: repair, one-action, reject, note, ink-hit-test, d37, undoable
  /// Rejects the recognised note on the ink at [surfacePoint], and reports what it did.
  String? rejectRecognisedNoteAt({
    required PageLayout page,
    required LayoutOffset surfacePoint,
  }) {
    final List<InkStroke> strokes = _session.document.strokes;
    if (strokes.isEmpty || _noteReadings.isEmpty) {
      return null;
    }
    final InkEraseHit? hit = hitTestInkErase(
      strokes: strokes,
      page: page,
      surfacePoint: surfacePoint,
    );
    if (hit == null) {
      return null;
    }
    for (final MelodyNoteReading reading in _noteReadings.values) {
      for (final MelodyNoteHead head in reading.heads) {
        if (!head.strokeIds.contains(hit.stroke.id)) {
          continue;
        }
        final bool deleted = _session.deleteNoteAt(
          sectionId: reading.sectionId,
          barIndex: reading.barIndex,
          beat: head.beat,
          step: head.orderInBeat,
        );
        _rejectedNoteAddresses.add(
          _noteAddressKey(
            reading.sectionId,
            reading.barIndex,
            head.beat,
            head.orderInBeat,
          ),
        );
        _recognisedNoteStrokes.removeAll(head.strokeIds);
        if (deleted) {
          _documentEdits++;
        }
        debugPrint(
          'note.rejected id=${hit.stroke.id} section=${reading.sectionId} '
          'bar=${reading.barIndex} beat=${head.beat} step=${head.orderInBeat} '
          'pitch=${head.pitch} deleted=$deleted '
          'ink=${head.strokeIds.join('+')} seq=${_session.seq}',
        );
        return deleted ? 'rejected' : 'rejected-none';
      }
    }
    return null;
  }

  /// The address a rejection is filed under: the bar, the beat and the position inside the beat.
  static String _noteAddressKey(
    String sectionId,
    int barIndex,
    int beat,
    int step,
  ) => '$sectionId\u0000$barIndex\u0000$beat\u0000$step';

  // PURPOSE: Let a rejection die with the ink that provoked it, so that a musician who rubs out a
  //          misread note and draws another at the same place is listened to the second time.
  // INPUTS: strokeId — the stroke the eraser has just removed from the document.
  // OUTPUTS: Nothing; the layer's own sets are edited. The stroke leaves
  //          [recognisedNoteStrokeIds] because there is nothing left to hide, and any address whose
  //          head was made of that stroke leaves [_rejectedNoteAddresses], which is what makes the
  //          next pass able to read a fresh mark at that spot. A stroke that was part of no head
  //          changes nothing, so the eraser stays the tool it was.
  // KEYWORDS: rejection-lifetime, erase, ink-removed, second-chance, one-action-repair
  void _forgetErasedNoteInk(String strokeId) {
    _recognisedNoteStrokes.remove(strokeId);
    final List<String> forgotten = <String>[];
    for (final MapEntry<String, MelodyNoteReading> entry
        in _noteReadings.entries) {
      for (final MelodyNoteHead head in entry.value.heads) {
        if (!head.strokeIds.contains(strokeId)) {
          continue;
        }
        _rejectedNoteAddresses.remove(
          _noteAddressKey(
            entry.value.sectionId,
            entry.value.barIndex,
            head.beat,
            head.orderInBeat,
          ),
        );
        forgotten.add(
          '${entry.value.sectionId}#${entry.value.barIndex}'
          '.${head.beat}.${head.orderInBeat}',
        );
      }
    }
    if (forgotten.isNotEmpty) {
      debugPrint(
        'note.rejection.forgotten ink=$strokeId '
        'addresses=${forgotten.join(',')} '
        'rejected=${_rejectedNoteAddresses.length}',
      );
    }
  }

  /// The key a bar's reading is filed under, matching the one the reader builds.
  static String _barKey(String sectionId, int barIndex) =>
      '$sectionId\u0000$barIndex';

  // PURPOSE: Promote or reject a bar division with ONE tap, which is the repair path the owner's
  //          rule requires for both of the ways recognition can be wrong.
  //
  //          BOTH ERRORS GET THE SAME GESTURE, AND THAT IS THE POINT. A missed division leaves a bar
  //          too long and a spurious one splits a bar that was whole; each is repaired by pointing
  //          at the mark and having the application change its mind about THAT mark. A tap on ink
  //          that is already a division rejects it (and the handwriting comes back into view); a tap
  //          on ink that is not one makes it a division. One action each way, no menu, no mode.
  // INPUTS: page — the layout on screen. surfacePoint — where the musician tapped, in the surface
  //         logical pixels the hit test speaks (the caller converts; see [_select]).
  // OUTPUTS: What the tap did, as a token for the log and for the screen's own report, or null when
  //          it hit no ink at all and the tap should go on to mean a selection. The document is
  //          changed at most once per call, so undo takes the whole repair back in one step.
  // KEYWORDS: repair, one-action, promote, reject, division, ink-hit-test, both-errors
  /// Promotes or rejects the division on the ink at [surfacePoint], and reports which.
  String? toggleDivisionAt({
    required PageLayout page,
    required LayoutOffset surfacePoint,
  }) {
    final List<InkStroke> strokes = _session.document.strokes;
    if (strokes.isEmpty) {
      return null;
    }
    final InkEraseHit? hit = hitTestInkErase(
      strokes: strokes,
      page: page,
      surfacePoint: surfacePoint,
    );
    if (hit == null) {
      return null;
    }
    final List<BarDivision> divisions = _session.document.divisions;
    final int existing = divisions.indexWhere(
      (BarDivision division) => division.cameFrom(hit.stroke.id),
    );
    if (existing >= 0) {
      final List<BarDivision> next = <BarDivision>[
        for (int index = 0; index < divisions.length; index++)
          if (index != existing) divisions[index],
      ];
      _session.apply(
        DivisionSetEvent(
          docId: _session.docId,
          seq: _session.seq,
          from: divisions,
          to: next,
        ),
      );
      _documentEdits++;
      debugPrint(
        'barline.rejected id=${hit.stroke.id} from=${divisions.length} '
        'to=${next.length} seq=${_session.seq}',
      );
      return 'rejected';
    }
    final List<BarDivision> next = <BarDivision>[
      ...divisions,
      BarDivision(
        id: 'division-${hit.stroke.id}',
        // DRAWN, not RECOGNISED: the musician said so, and D37 rule 4 requires the application to
        // be able to tell the two levels apart. Its geometry is still the ink's own, because a
        // division he points at is the line he drew.
        source: DivisionSource.drawn,
        place: AnchoredPlace(
          anchor: hit.stroke.anchor,
          offsetX: _centreXOf(hit.stroke),
          offsetY: _topOf(hit.stroke),
        ),
        height: _heightOf(hit.stroke),
        sourceStrokeId: hit.stroke.id,
      ),
    ];
    _session.apply(
      DivisionSetEvent(
        docId: _session.docId,
        seq: _session.seq,
        from: divisions,
        to: next,
      ),
    );
    _documentEdits++;
    debugPrint(
      'barline.promoted id=${hit.stroke.id} from=${divisions.length} '
      'to=${next.length} seq=${_session.seq}',
    );
    return 'promoted';
  }

  /// The horizontal centre of [stroke]'s bounding box, in its anchor-local pixels.
  static double _centreXOf(InkStroke stroke) {
    double minX = double.infinity;
    double maxX = -double.infinity;
    for (final InkPoint point in stroke.points) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
    }
    return (minX + maxX) / 2;
  }

  /// The top of [stroke]'s bounding box, in its anchor-local pixels.
  static double _topOf(InkStroke stroke) {
    double top = double.infinity;
    for (final InkPoint point in stroke.points) {
      top = math.min(top, point.y);
    }
    return top;
  }

  /// The height of [stroke]'s bounding box, in its anchor-local pixels.
  static double _heightOf(InkStroke stroke) {
    double top = double.infinity;
    double bottom = -double.infinity;
    for (final InkPoint point in stroke.points) {
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    // A one-point mark cannot divide anything, and a division of no height is a state the model
    // refuses; the smallest honest line is one nib tall.
    return math.max(bottom - top, stroke.size > 0 ? stroke.size : 3);
  }

  // PURPOSE: Abandon a drawing contact without committing anything, which is what the platform
  //          means when it cancels a pointer: the contact was taken away rather than finished.
  // INPUTS: pointer — the contact.
  // OUTPUTS: Nothing.
  // KEYWORDS: cancel, discard, pointer-cancel, repaint-tick
  /// Abandons a drawing contact without committing anything.
  void cancelStroke(int pointer) {
    final InkStrokeAssembler? assembler = _assemblers.remove(pointer);
    _openStylusPointers.remove(pointer);
    assembler?.cancel();
    _live.clear();
    _liveRevision.value++;
    debugPrint('ink.stroke.cancel pointer=$pointer dropped=$_dropped');
  }

  // PURPOSE: Arm the eraser for one contact. From here the contact deletes nothing: it COLLECTS the
  //          strokes it passes over, and the lift is what writes the deletions. It is the down half
  //          of a gesture that works the way a rubber works — the musician may put the eraser down
  //          anywhere and drag it through his ink — and the reason nothing is deleted here is that a
  //          gesture can still turn out to be the page's own two-finger pan (see the file header).
  // INPUTS: pointer — the contact the rule admitted. page — the layout on screen, which resolves
  //         every stroke's anchor and carries the scale; it is captured for the whole gesture, so a
  //         page re-engraved while the hand is down cannot make the trail's boxes and its exact
  //         distances describe two different pages. position — where it landed, in the surface
  //         logical pixels the hit test speaks. reason — which of [erasesByMode],
  //         [erasesByStylusButton] or [erasesByStylusEraserEnd] chose the eraser, carried into the
  //         log so that "the mode was on" and "the pen's button was held" stay two separate facts.
  // OUTPUTS: Nothing. [lastPointWasInk] becomes true, so the widget that routes a lift does not also
  //          treat this contact as a selection. A second contact with the same pointer id replaces
  //          the first, exactly as [beginStroke] does: one pointer id cannot be two contacts. The
  //          trail is built from the document's strokes AS THEY ARE NOW, so a stroke committed later
  //          cannot be crossed by this gesture, and the down point is sampled immediately so the
  //          stroke under the eraser disappears the moment it lands.
  // KEYWORDS: erase-arm, trail, drag-erase, contact-tracking, selection-suppression, reason-token
  /// Arms the eraser for the contact [pointer] that landed at [position].
  void beginErase({
    required int pointer,
    required PageLayout page,
    required LayoutOffset position,
    String reason = erasesByMode,
  }) {
    // The same D34 gate the pen half carries: a contact that is part of a two-finger gesture is not
    // aiming the eraser, so nothing is armed and the lift will not delete a stroke.
    if (_viewGestureActive) {
      debugPrint(
        'ink.erase.refused pointer=$pointer reason=view-gesture-active '
        'at=(${position.x.toStringAsFixed(1)},${position.y.toStringAsFixed(1)})',
      );
      return;
    }
    _erasePointer = pointer;
    _eraseAim = position;
    _eraseReason = reason;
    _lastPointWasInk = true;
    final InkEraseTrail trail = InkEraseTrail(
      page: page,
      strokes: _session.document.strokes,
    );
    _eraseTrail = trail;
    debugPrint(
      'ink.erase.arm pointer=$pointer by=$reason '
      'at=(${position.x.toStringAsFixed(1)},${position.y.toStringAsFixed(1)}) '
      'strokes=${_session.document.strokes.length} '
      'step_px=${InkEraseAim.pathStepPx.toStringAsFixed(1)}',
    );
    _noteCrossed(pointer: pointer, hits: trail.addSample(position));
  }

  // PURPOSE: Offer one more point of the dragging eraser, which is what makes the ink under it go
  //          away while the hand is still down. It is the whole of "rub out what I wrote, by
  //          dragging, in the way a rubber works".
  // INPUTS: pointer — the contact. position — where it is now, in surface logical pixels.
  // OUTPUTS: Nothing. A move for a contact that is not the armed one is dropped silently, which is
  //          the ordinary case for the first move of a contact the rule refused. What the sample
  //          crossed is logged and ticked through [_noteCrossed].
  // KEYWORDS: erase-move, drag-collect, preview, no-writing, silent-when-absent
  /// Offers one more sample of the dragging eraser's path.
  void moveErase({required int pointer, required LayoutOffset position}) {
    final InkEraseTrail? trail = _eraseTrail;
    if (_erasePointer != pointer || trail == null) {
      return;
    }
    _noteCrossed(pointer: pointer, hits: trail.addSample(position));
  }

  // PURPOSE: Record the strokes one sample newly crossed, so that every removal the gesture will
  //          make is a line in the log with the order it was reached in, and so the preview repaints
  //          ONCE per sample rather than once per stroke.
  // INPUTS: pointer — the contact, for the log. hits — the strokes this sample added, in the order
  //         the path reached them, newest last in the trail's own list.
  // OUTPUTS: Nothing when nothing was crossed, which is the common case and costs one comparison.
  //          Otherwise one `ink.erase.cross` line per stroke and one raised repaint tick.
  // KEYWORDS: erase-cross, order, instrumentation, one-tick-per-sample, preview
  void _noteCrossed({required int pointer, required List<InkEraseHit> hits}) {
    if (hits.isEmpty) {
      return;
    }
    final int before = (_eraseTrail?.crossed.length ?? 0) - hits.length;
    for (int index = 0; index < hits.length; index++) {
      final InkEraseHit hit = hits[index];
      debugPrint(
        'ink.erase.cross pointer=$pointer order=${before + index + 1} '
        'id=${hit.stroke.id} index=${hit.index} '
        'distance=${hit.surfaceDistance.toStringAsFixed(3)} '
        'strokes=${_session.document.strokes.length}',
      );
    }
    _liveRevision.value++;
  }

  // PURPOSE: Finish an erase contact, which is where the drag becomes a fact: every stroke the
  //          contact crossed is deleted through the operation log, IN THE ORDER IT WAS CROSSED, so
  //          that undo restores them one at a time exactly as they were and in the reverse of the
  //          order the hand made. It is the erase counterpart of [endStroke] and the only place the
  //          eraser touches the document.
  // INPUTS: pointer — the contact that is lifting. position — where it lifted, in surface logical
  //         pixels, which is the last point of the path: a tap's down and up are the same point, so
  //         a tap still erases, and a drag is closed at the edge of the band rather than at whatever
  //         move the platform happened to deliver last.
  // OUTPUTS: The hits that were removed, in the order they were crossed; empty when the pointer was
  //          not armed, when nothing was crossed, or when the document no longer held a stroke the
  //          trail named. N deletions append N events, so putting all N back costs N undos — see the
  //          file header for why that is the accepted cost and what the alternative would change.
  //          Nothing here writes a stroke: the eraser appends deletions and never ink.
  // KEYWORDS: erase-commit, op-log-delete, whole-stroke, ordered, undo-per-stroke, preview-clear
  /// Ends an erase contact, deleting every stroke it crossed, and returns what it removed.
  List<InkEraseHit> endErase({
    required int pointer,
    required LayoutOffset position,
  }) {
    if (_erasePointer != pointer) {
      return const <InkEraseHit>[];
    }
    final InkEraseTrail? trail = _eraseTrail;
    final LayoutOffset? aim = _eraseAim;
    final String? reason = _eraseReason;
    // THE LIFT POINT IS SAMPLED BEFORE THE TRAIL IS DROPPED, so the last stretch of the gesture
    // counts. A platform may report the last movement of a contact many pixels before its lift, and
    // a stroke that is visibly under the rubber when the hand comes up must not survive because no
    // move event happened to land on it.
    final List<InkEraseHit> already = trail == null
        ? const <InkEraseHit>[]
        : List<InkEraseHit>.of(trail.crossed);
    final List<InkEraseHit> atLift =
        trail?.addSample(position) ?? const <InkEraseHit>[];
    final List<InkEraseHit> crossed = <InkEraseHit>[...already, ...atLift];
    _clearErase();
    if (crossed.isEmpty) {
      _lastErase = <String, Object?>{
        'ids': const <String>[],
        'count': 0,
        'aim': aim == null ? const <double>[] : <double>[aim.x, aim.y],
        'strokes': _session.document.strokes.length,
      };
      debugPrint(
        'ink.erase.miss pointer=$pointer by=${reason ?? 'none'} '
        'aim=(${aim?.x.toStringAsFixed(1) ?? '-'},${aim?.y.toStringAsFixed(1) ?? '-'}) '
        'strokes=${_session.document.strokes.length}',
      );
      return const <InkEraseHit>[];
    }
    final List<InkEraseHit> removed = <InkEraseHit>[];
    // THE ONE-ACTION REPAIR FOR A DIVISION THE DETECTOR SHOULD NOT HAVE FOUND, and it lives here
    // because the eraser is the tool a musician already has in his hand when he wants a mark gone.
    // With recognition ON, a stroke that a division was recognised from is not deleted: the DIVISION
    // is rejected and the handwriting comes back into view, which is the ink D37 rule 5 requires the
    // file to keep. It costs one action, it cannot destroy what he wrote as a side effect of
    // correcting the application, and a second rub removes the ink if that is what he meant.
    //
    // With recognition OFF this branch is dead, so the eraser is exactly the tool it was.
    final Set<String> rejected = <String>{};
    for (int index = 0; index < crossed.length; index++) {
      final InkEraseHit hit = crossed[index];
      if (recognitionEnabled) {
        final List<BarDivision> divisions = _session.document.divisions;
        final int existing = divisions.indexWhere(
          (BarDivision division) => division.cameFrom(hit.stroke.id),
        );
        if (existing >= 0) {
          _session.apply(
            DivisionSetEvent(
              docId: _session.docId,
              seq: _session.seq,
              from: divisions,
              to: <BarDivision>[
                for (int at = 0; at < divisions.length; at++)
                  if (at != existing) divisions[at],
              ],
            ),
          );
          rejected.add(hit.stroke.id);
          debugPrint(
            'barline.rejected-by-eraser pointer=$pointer id=${hit.stroke.id} '
            'divisions=${_session.document.divisions.length} seq=${_session.seq}',
          );
          continue;
        }
      }
      final bool erased = _session.eraseStroke(hit.stroke.id);
      if (erased) {
        removed.add(hit);
        // ONLY WHILE NOTES ARE BEING RECOGNISED, so that with the switch off the eraser is exactly
        // the tool it was: one boolean read and no bookkeeping on the gesture path. The bookkeeping
        // itself is a set removal and cannot touch the document.
        if (recognitionEnabled) {
          _forgetErasedNoteInk(hit.stroke.id);
        }
      }
      debugPrint(
        'ink.erase.stroke pointer=$pointer order=${index + 1} '
        'id=${hit.stroke.id} index=${hit.index} '
        'distance=${hit.surfaceDistance.toStringAsFixed(3)} removed=$erased '
        'strokes=${_session.document.strokes.length} seq=${_session.seq}',
      );
    }
    _lastEraseRejectedRecognition = rejected.isNotEmpty;
    _lastErase = <String, Object?>{
      'ids': removed.map((InkEraseHit hit) => hit.stroke.id).toList(),
      'count': removed.length,
      'crossed': crossed.length,
      'undoDepth': _session.undoDepth,
      'aim': aim == null ? const <double>[] : <double>[aim.x, aim.y],
      'strokes': _session.document.strokes.length,
    };
    _documentEdits += removed.length;
    debugPrint(
      'ink.erase.commit pointer=$pointer by=${reason ?? 'none'} '
      'crossed=${crossed.length} removed=${removed.length} '
      'strokes=${_session.document.strokes.length} '
      'seq=${_session.seq} undo_depth=${_session.undoDepth}',
    );
    // The document moved under the frame that was drawn while the hand was down, so the ink layer
    // must repaint even if no rebuild follows: a drag does not resolve as a tap, and the tap path is
    // what would otherwise carry the change to the screen.
    _liveRevision.value++;
    return removed;
  }

  // PURPOSE: Drop an armed erase contact without deleting anything, which is what a platform
  //          pointer-cancel means, what a mode change does to a contact armed under the old mode,
  //          and what the two-finger view gesture does to a first finger that landed on ink.
  // INPUTS: pointer — the contact that was cancelled.
  // OUTPUTS: Nothing. The trail and the preview go with it, so the ink the rubber had already
  //          hidden comes back on the next repaint. The last-erase record is left as it was, because
  //          a cancelled contact did not erase anything and overwriting the record would describe a
  //          removal that never happened.
  // KEYWORDS: erase-cancel, discard, pointer-cancel, preview-restore, no-record
  /// Abandons an armed erase contact without deleting anything.
  void cancelErase(int pointer) {
    if (_erasePointer != pointer) {
      return;
    }
    _clearErase();
    debugPrint('ink.erase.cancel pointer=$pointer');
  }

  /// Clears the armed-erase state, showing again anything the preview had hidden.
  void _clearErase() {
    final bool hadPreview = _eraseTrail?.crossed.isNotEmpty ?? false;
    _erasePointer = null;
    _eraseAim = null;
    _eraseTrail = null;
    _eraseReason = null;
    if (hadPreview) {
      _liveRevision.value++;
    }
  }

  // PURPOSE: Rebuild the live preview from the open assemblers, so the stroke under the pen is
  //          visible before it is committed.
  // INPUTS: page — the layout, used to resolve each open stroke's anchor rectangle.
  // OUTPUTS: Nothing. The list is rebuilt rather than mutated so a painter holding the previous list
  //          keeps a value rather than seeing it change underneath it. The repaint tick is raised
  //          here and nowhere else on this path, so the screen's listener is called exactly when the
  //          preview has something new to draw.
  // KEYWORDS: live-preview, rebuild, anchor-resolution, immutability, repaint-tick
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
    _liveRevision.value++;
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
