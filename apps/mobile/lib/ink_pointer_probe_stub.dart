// PURPOSE: Give every target that is not a browser an ink input probe that measures nothing, so the
//          application can call one install function and read one report without a conditional of
//          its own and without a `dart:js_interop` import that would not compile here.
// INPUTS: An observed sample callback, which this implementation never calls.
// OUTPUTS: An [InkProbeControl] whose `supported` is false, whose counters are zero and whose
//          `report` is an empty map. Zero and empty mean "not measured" on this target and are never
//          presented as a measurement: the report says `supported: false` in the same map.
// KEYWORDS: probe-stub, not-measured, no-op, compile-time-seam, honest-zero
import 'ink_pointer_probe_contract.dart';

/// The non-browser implementation of the ink input probe.
abstract final class InkInputProbe {
  /// Installs nothing and returns an inert control.
  static InkProbeControl install({
    required void Function(InkProbeSample sample) onRawSample,
  }) => InkProbeControl.stub();
}
