// PURPOSE: Provide the implementation used on platforms without a native ink surface — Linux,
//          Windows, iOS, the web, and any target whose native package has not claimed the slot. It
//          exists so that the absence of a pen is an ordinary state the editor can display,
//          instead of an exception that reaches the widget tree. On the web it is not a placeholder
//          for a missing binding: a browser implementation would be a third implementation of this
//          contract, and writing it before the raw pointer behaviour has been measured would fix
//          its design on a guess, so the honest answer there is "no surface yet".
// INPUTS: None. Every mutating method accepts its arguments and ignores them.
// OUTPUTS: [supportsInk] is false; [exportStrokes] answers with an empty list rather than null;
//          [onStrokeCommitted], [onLatencySample] and [onPalmObservation] are permanently empty
//          streams, so a listener waits forever rather than being told a stroke or a sample
//          arrived. [describeSurface] answers with a description that names itself as having no
//          native surface, and [benchLogDirectory] answers null, so a bench run on a desktop or in
//          a browser prints "no surface" instead of reporting a latency of zero. Nothing here
//          throws for a call made in the wrong order, because a build with no pen has no ordering
//          to enforce.
// KEYWORDS: ink-native, no-op, desktop, web, unsupported, empty-stream, graceful-degradation
import 'package:ink_native_platform_interface/ink_native_platform_interface.dart';

/// An ink surface that accepts every call and draws nothing.
///
/// The answer on every platform whose native package has not claimed the slot, the web included:
/// `supportsInk` is false rather than a claim the surface cannot keep, so a caller that asks
/// whether it can draw gets a truthful no.
class UnsupportedInkPlatform extends InkNativePlatform {
  /// Creates the no-op implementation.
  UnsupportedInkPlatform();

  @override
  bool get supportsInk => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setTool(InkTool tool) async {}

  @override
  Future<void> setTransform(InkViewTransform transform) async {}

  @override
  Future<void> loadStrokes(Iterable<InkStrokeBlob> strokes) async {}

  @override
  Future<List<InkStrokeBlob>> exportStrokes() async => const <InkStrokeBlob>[];

  @override
  Stream<CommittedStroke> get onStrokeCommitted =>
      const Stream<CommittedStroke>.empty();

  @override
  Stream<InkLatencySample> get onLatencySample =>
      const Stream<InkLatencySample>.empty();

  @override
  Stream<InkPalmObservation> get onPalmObservation =>
      const Stream<InkPalmObservation>.empty();

  @override
  Future<InkSurfaceInfo> describeSurface() async => const InkSurfaceInfo(
    // Named `none` rather than a plausible-looking mode: a reader who sees this in a bench
    // report must be able to tell that no surface was present, not that one was misconfigured.
    platformViewMode: 'none',
    presentationSource: InkPresentationSource.vsyncPlusDelay,
    apiLevel: 0,
    refreshRateHz: 0,
    clockOffsetMs: 0,
    clockOffsetDriftMs: 0,
    deviceModel: '',
    androidRelease: '',
    eventTimePrecision: 'unknown',
    usedTimelinePoster: false,
    // Zero, not a plausible default: with no surface there is no density and no palm rule in
    // force, and a bench report that showed a real threshold here would claim a rule that never
    // ran.
    displayDensity: 0,
    palmWidthThreshold: 0,
    palmStylusProximityWindowMs: 0,
    stylusHoverEventCount: 0,
  );

  @override
  Future<String?> benchLogDirectory() async => null;
}
