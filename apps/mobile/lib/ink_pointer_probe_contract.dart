// PURPOSE: Define the two values the ink input probe moves between the browser and the app — one
//          raw browser sample, and the handle that reads the counters — in a file both
//          implementations of the conditional export can share. It exists because the export must
//          present the SAME types on every target: an app that reads a report on the web and on the
//          desktop must not need two names for it.
// INPUTS: Values produced by the browser implementation, or by nobody on a target that has no
//         browser.
// OUTPUTS: Immutable values. A control that could not install reports `supported: false` and its
//          counters are zero, which mean "not measured" and are never presented as a measurement.
// KEYWORDS: probe-contract, sample, control, report, honest-zero, conditional-export
import 'dart:convert';

/// The handle an installed probe returns, so the app can reset it and read what it measured.
class InkProbeControl {
  /// Creates the inert control a target with no browser returns.
  InkProbeControl.stub()
    : supported = false,
      _reset = _noop,
      _report = _emptyReport;

  /// Creates a control backed by a real browser probe.
  ///
  /// The two callbacks are supplied by the browser implementation, so nothing above this layer has
  /// to know that a JavaScript object exists.
  InkProbeControl.measured({required this._reset, required this._report})
    : supported = true;

  /// Whether a browser stream is actually being observed on this target.
  final bool supported;

  final void Function() _reset;
  final Map<String, Object?> Function() _report;

  /// What the application last published about its ink, as a JSON line, or null before it published.
  ///
  /// A static rather than a field because the probe is created before any chart exists, while the
  /// state only becomes meaningful once one is on screen. Nothing in the application reads it back:
  /// it exists so a browser-driving tool has ONE entry point — the probe's own `report()` — that
  /// answers both "what did the browser deliver" and "what is in the document".
  ///
  /// THE DOCUMENT TITLE WAS TRIED FIRST AND DOES NOT WORK. Flutter's `Title` widget rewrites it on
  /// every rebuild, so a state published there is overwritten within one frame. The application's own
  /// `window` handle has no such owner, and it IS reachable from the main JavaScript world an
  /// automated browser runs its own code in.
  static String? publishedInkState;

  /// Discards everything measured so far, so a run can mark the moment its own input began.
  void reset() => _reset();

  /// The probe's OWN measurements, with nothing folded in, ready to serialise.
  ///
  /// THIS IS THE ONE A CALLER INSIDE THE APPLICATION MUST USE, and the reason is a cycle that cost
  /// the pen its whole first stroke budget. The application's ink state describes the document, and
  /// one of the things it carries is what the browser delivered — that is [report] here. But [report]
  /// folds the LAST PUBLISHED ink state back in under `ink`, so an application that read [report] in
  /// order to build the next state would publish a state containing the previous one, and the one
  /// before that inside it. Measured on the owner's tablet: the published line reached 42.7 million
  /// characters after thirty-nine strokes, growing by a full copy of the document per stroke, and the
  /// serialisation of it took 2.8 s per stroke — which starved the input queue until a one-second
  /// gesture was delivered as two events. A state cannot contain itself; this getter is the half that
  /// makes that true, and [report] keeps its fold for a tool that wants both halves in one call.
  Map<String, Object?> get counters => _report();

  /// The measurements as a plain map, ready to be written to a log or serialised into a page.
  ///
  /// The ink state the application published is folded in under `ink`, so one call answers both
  /// halves of a verification. It is parsed from its JSON line here rather than held as a map,
  /// because that is the shape it is published in and a second representation is a second thing
  /// that could disagree with the first.
  ///
  /// NOT FOR THE APPLICATION'S OWN USE: the published state is built by the application, so reading
  /// it back inside the state's own construction is a cycle. Use [counters] there.
  Map<String, Object?> report() {
    final Map<String, Object?> measured = _report();
    final String? ink = publishedInkState;
    if (ink == null) {
      return measured;
    }
    return <String, Object?>{...measured, 'ink': jsonDecode(ink)};
  }

  static void _noop() {}

  static Map<String, Object?> _emptyReport() => <String, Object?>{};
}

/// Reads the application's ink state at the moment it is called, or an empty map when no chart is on
/// screen.
///
/// A function pointer rather than a stored map because a map would be a second copy of the document
/// list, and a copy goes stale exactly when it matters — right after input. The application assigns
/// this once, and both the browser handle and a test can call it.
Map<String, Object?> Function() inkStateReader = noInkStatePublished;

/// Reads how many strokes the document holds at the moment it is called.
int Function() strokeCountReader = noStrokesPublished;

/// Reads what Flutter's own pointer stream delivered, at the moment it is called.
///
/// Separate from [inkStateReader] because that map already contains the same tallies, and a report
/// that embedded itself would nest one copy per call — which is what an earlier shape of this file
/// did, growing the answer without bound while still looking like a report.
Map<String, Object?> Function() inkInputCountersReader = noInkStatePublished;

/// Reads the geometry of the page on screen: the surface it is drawn into and the rectangle of every
/// cell it holds, in the SURFACE's coordinates.
///
/// It exists because a verification aiming a pen at a chart has to know where the chart actually is.
/// Working that out from an image is estimating; the page already knows, in the same units the input
/// arrives in, so the answer is asked for rather than measured off a picture. The value reported is
/// the rectangle a stroke drawn there would anchor to, which is what makes a run able to say "the
/// stroke landed on bar 3 cell 2" and check it.
Map<String, Object?> Function() pageGeometryReader = noInkStatePublished;

/// The reader a screen clears itself out of on dispose, so a disposed state is never asked for its
/// document again.
Map<String, Object?> noInkStatePublished() => const <String, Object?>{};

/// The stroke count a screen clears itself out of on dispose.
int noStrokesPublished() => 0;

/// One sample as the BROWSER delivered it, before any framework mapped it.
///
/// Carried because the question the probe answers is a comparison: the browser's value and Flutter's
/// value for the same physical event are two different numbers, and a report that held only one of
/// them could not settle whether the framework preserved the other.
class InkProbeSample {
  /// Creates one raw sample.
  const InkProbeSample({
    required this.pointerType,
    required this.pressure,
    required this.tiltXDegrees,
    required this.tiltYDegrees,
    required this.width,
    required this.isCoalesced,
    required this.eventType,
    required this.browserTimeMs,
  });

  /// The browser's `pointerType`: `pen`, `touch` or `mouse`.
  final String pointerType;

  /// The browser's `pressure`, nominally in `[0, 1]`.
  final double pressure;

  /// The browser's `tiltX` in degrees, or 0 when the platform reported none.
  final double tiltXDegrees;

  /// The browser's `tiltY` in degrees, or 0 when the platform reported none.
  final double tiltYDegrees;

  /// The browser's `width` (contact geometry) in CSS pixels, or 0 when reported none.
  final double width;

  /// Whether this sample came from `getCoalescedEvents` rather than from the event itself.
  final bool isCoalesced;

  /// The DOM event type this sample arrived under: `pointerdown`, `pointermove` or `pointerup`.
  final String eventType;

  /// The browser's own `timeStamp` for the event, in milliseconds.
  ///
  /// Carried because the framework's own event for the same physical contact has the same stamp
  /// converted by the engine, and the contact width has to be matched to the framework's event
  /// through a time both of them state. When the browser states none, this holds the value of
  /// `performance.now()` read at the moment the event arrived, which is measured from the same origin
  /// as `timeStamp` and is therefore still comparable.
  final double browserTimeMs;
}
