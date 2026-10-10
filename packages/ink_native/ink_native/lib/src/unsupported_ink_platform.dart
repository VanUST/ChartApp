// PURPOSE: Provide the implementation used on platforms without a native ink surface — Linux,
//          Windows and any target whose native package has not claimed the slot. It exists so
//          that the absence of a pen is an ordinary state the editor can display, instead of an
//          exception that reaches the widget tree.
// INPUTS: None. Every mutating method accepts its arguments and ignores them.
// OUTPUTS: [supportsInk] is false; [exportStrokes] answers with an empty list rather than null;
//          [onStrokeCommitted] is a permanently empty stream, so a listener waits forever
//          rather than being told a stroke arrived. Nothing here throws for a call made in the
//          wrong order, because a desktop build has no ordering to enforce.
// KEYWORDS: ink-native, no-op, desktop, unsupported, empty-stream, graceful-degradation
import 'package:ink_native_platform_interface/ink_native_platform_interface.dart';

/// An ink surface that accepts every call and draws nothing.
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
}
