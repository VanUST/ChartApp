// PURPOSE: Declare the abstract ink surface and its registration point, so the app drives one
//          API on every platform and a platform package opts in by implementing this class
//          rather than by the app branching on `Platform.isIOS`.
// INPUTS: None at declaration. At runtime the current implementation is set through
//         `InkNativePlatform.instance`.
// OUTPUTS: An abstract class whose methods return Futures that complete when the native side
//          has applied the change, and broadcast-able streams: `onStrokeCommitted` for finished
//          strokes, plus `onLatencySample` and `onPalmObservation` for the bench. Calling a
//          method with no implementation registered throws [UnimplementedError]; the app-facing
//          package installs a desktop no-op so that a desktop build degrades instead of
//          crashing.
// KEYWORDS: platform-interface, ink-native, registration-token, federated-plugin, stream
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ink_types.dart';

/// The ink surface every platform implementation must provide.
abstract class InkNativePlatform extends PlatformInterface {
  /// Creates an implementation. Subclasses must extend, not implement, this class: the token
  /// in the superclass constructor is what makes [instance] reject a foreign object.
  InkNativePlatform() : super(token: _token);

  static final Object _token = Object();

  static InkNativePlatform? _instance;

  /// The implementation in use.
  ///
  /// Throws [UnimplementedError] when nothing has been registered. The app-facing `ink_native`
  /// package registers a desktop no-op, so on a supported platform this getter is only
  /// reachable before that registration runs.
  static InkNativePlatform get instance {
    final InkNativePlatform? current = _instance;
    if (current == null) {
      throw UnimplementedError(
        'No InkNativePlatform implementation is registered. On desktop import '
        'package:ink_native/ink_native.dart, which installs a no-op implementation; on a '
        'device the platform package registers itself at startup.',
      );
    }
    return current;
  }

  /// Replaces the implementation. [PlatformInterface.verifyToken] rejects any object that did
  /// not extend [InkNativePlatform], so a mock cannot be installed by mistake in production
  /// and an implementation cannot be swapped for a structurally similar foreign class.
  static set instance(InkNativePlatform value) {
    PlatformInterface.verifyToken(value, _token);
    _instance = value;
  }

  /// True when an implementation has been registered.
  static bool get isRegistered => _instance != null;

  /// Whether this implementation can actually draw.
  ///
  /// False for the desktop no-op installed by the app-facing package. The editor reads this to
  /// decide whether to offer the ink tools at all, which is why it is a value and not an
  /// exception: on a desktop build the absence of a pen is a normal state, not a failure, and
  /// the rest of the editor must keep working.
  bool get supportsInk;

  /// Prepares the native surface and its resources.
  ///
  /// Must be awaited before any other call. Calling it twice must be harmless, because a
  /// platform view can be rebuilt on a hot reload or a rotation.
  Future<void> initialize();

  /// Selects the active drawing [tool].
  Future<void> setTool(InkTool tool);

  /// Applies the shared scroll/zoom [transform].
  ///
  /// The app calls this with the same mapping it gave the chart canvas, which is what keeps a
  /// stroke aligned with the bar it was drawn over.
  Future<void> setTransform(InkViewTransform transform);

  /// Replaces the strokes currently shown with [strokes].
  ///
  /// Implementations may assume this is called only for strokes belonging to the document on
  /// screen; loading the whole document is not required.
  Future<void> loadStrokes(Iterable<InkStrokeBlob> strokes);

  /// Returns the strokes currently drawn.
  ///
  /// The result is the input to persistence: the app pairs each blob with the anchor it was
  /// captured against and stores them as ink_blobs rows.
  Future<List<InkStrokeBlob>> exportStrokes();

  /// Reports each stroke as the native surface finishes it.
  ///
  /// Emits after the stroke is committed to the native model, not per input event, so the
  /// listener does not run on the drawing hot path.
  Stream<CommittedStroke> get onStrokeCommitted;

  // ---------------------------------------------------------------------------------------
  // Measurement surface.
  //
  // These four members exist because input-to-photon latency is a property of the hardware
  // path and can only be measured on the device, so the device has to be able to say what it
  // measured. They are added to this contract rather than kept inside one platform package
  // because the bench that reads them is the app's, and a bench that reached into
  // `ink_native_android` directly would stop compiling the day an iOS pen has to be measured
  // the same way. Nothing in the drawing path reads them.
  // ---------------------------------------------------------------------------------------

  /// Reports one drawn input sample per emission, with the time it was expected to be shown.
  ///
  /// Emits after a stroke is finished rather than per input event, for the same reason
  /// [onStrokeCommitted] does: a channel call per sample would itself be on the drawing hot
  /// path and would change the number being measured.
  ///
  /// Implementations that cannot measure latency emit nothing, and [describeSurface] says so,
  /// rather than emitting a fabricated zero.
  Stream<InkLatencySample> get onLatencySample;

  /// Reports what the surface observed about each stroke's contact geometry.
  ///
  /// This carries an observation, not a decision: [InkPalmObservation.drawAdmitted] records
  /// what the surface did with a contact whose raw tool type it could see, and the absence of
  /// any observation is not evidence that no palm touched the glass.
  Stream<InkPalmObservation> get onPalmObservation;

  /// Describes what this surface measures and on which clock.
  ///
  /// Must be callable before [initialize]; an unsupported implementation answers with a
  /// description that names itself as having no native surface, so a caller never has to
  /// distinguish "not measured yet" from "cannot be measured".
  Future<InkSurfaceInfo> describeSurface();

  /// A directory this surface can write bench logs to, or null when it has none.
  ///
  /// The log is written by the Dart side, which owns the bench format, so this answers only
  /// where the bytes may go. A null answer means the bench must be read from a live console
  /// instead of from a file, which is why it is reported rather than thrown.
  Future<String?> benchLogDirectory();
}
