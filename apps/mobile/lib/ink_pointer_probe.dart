// PURPOSE: Name the one thing about the ink input probe that differs between the web target and
//          every other target — whether the browser's own pointer stream can be observed at all —
//          and let the app stay unaware of it. The probe exists because the decision this increment
//          had to take was "does Flutter Web deliver enough for the pen to draw, or does the raw
//          browser stream have to be bridged in?", and that question can only be answered by reading
//          BOTH streams on a real page.
//
//          It observes and never acts: the DOM listener it installs is passive, it calls no
//          `preventDefault`, and it does not stop propagation, so Flutter's own input path is
//          untouched by the instrument that measures it. That is the property that makes a
//          measurement taken with it a measurement of a product rather than of a modified one.
// INPUTS: A callback for each raw sample, so a Dart-side accumulator can hold the numbers without
//         crossing the JavaScript boundary once per sample.
// OUTPUTS: [InkInputProbe.install], with the same name and the same meaning on every target and a
//          different answer on each:
//
//            | Symbol                              | Desktop / mobile          | Browser                |
//            |-------------------------------------|---------------------------|------------------------|
//            | `InkInputProbe.install(...)`         | an inert control          | installs a JS handle   |
//            | `InkProbeControl.supported`          | false                     | true                   |
//            | `InkProbeControl.report()`           | an empty map              | the measured values    |
//
// KEYWORDS: ink, pointer-events, js-interop, conditional-export, platform-seam, measurement, web
//
// WHY A CONDITIONAL EXPORT AND NOT A RUNTIME CHECK. `dart:js_interop` compiles only for the web, so
// a branch inside one file would not compile elsewhere even when it is never taken. Choosing the
// implementation at compile time is what lets a desktop build exclude the browser entirely, and
// `dart.library.js_interop` is the condition rather than `dart.library.html` because the browser
// implementation imports the modern interop that a future `--wasm` build can also compile.
//
// Running a probe on a target with no browser is not an error: an application installs one on every
// target because the call site must not be platform-conditional, and the stub's answer is an honest
// "not measured" rather than a zero that looks like a measurement.
/// A library of this package's own, so the conditional exports below have something to attach to.
library;

import 'dart:convert';

import 'ink_pointer_probe_contract.dart';

export 'ink_pointer_probe_contract.dart' show InkProbeControl, InkProbeSample;
export 'ink_pointer_probe_stub.dart'
    if (dart.library.js_interop) 'ink_pointer_probe_web.dart'
    show InkInputProbe;

/// Publishes [state] as the application's ink state, which the probe's `report()` returns under
/// `ink`.
///
/// A named wrapper rather than a direct field write, so a caller cannot leave a tool with a line it
/// cannot parse: the value is checked here, at the moment it is stored.
///
/// THE CHECK IS A SHAPE CHECK AND A DEBUG-TIME ROUND TRIP, NOT A PARSE IN THE SHIPPED BUILD. It used
/// to be `jsonDecode(state)` unconditionally, and that was half the cost of the whole pen defect: the
/// only caller produces the value with `jsonEncode` from a map it just built, so the parse could not
/// fail, while decoding a multi-megabyte line twice per stroke was measured at 33 % of a publication
/// that reached 2.8 s. A validating parse of a string this file produced itself is a check that
/// cannot be false being paid for at the price of the most expensive operation in the application.
/// The shape check below is what a release build keeps, because it is true of every JSON object and
/// catches the one mistake a caller can actually make — handing over something that is not one. The
/// full parse is kept inside an `assert`, so every test run still proves the line round-trips.
///
/// NOTHING IN THE APPLICATION READS THIS BACK. It is a one-way handoff to whatever is inspecting the
/// page, and it carries no state the application itself consults.
void publishInkProbeState(String? state) {
  if (state == null) {
    InkProbeControl.publishedInkState = null;
    return;
  }
  final String trimmed = state.trimLeft();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    return;
  }
  assert(
    () {
      jsonDecode(state);
      return true;
    }(),
    'the published ink state must be a JSON object that parses back to itself',
  );
  InkProbeControl.publishedInkState = state;
}
