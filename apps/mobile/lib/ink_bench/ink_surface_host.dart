// PURPOSE: Put the native Android ink surface on screen as a real view in the Android hierarchy, so
//          the digitizer's motion events reach it with their own timestamps and its frame is the
//          same frame Flutter presents. It is the only widget in the bench that knows a platform
//          view exists.
// INPUTS: Nothing; it is sized by its parent.
// OUTPUTS: A platform view in hybrid composition, or a visible error box when the view cannot be
//          created. The chosen mode is passed to the native side and echoed back in
//          `describeSurface`, so a mode that did not take effect shows up in the report instead of
//          being assumed.
// KEYWORDS: platform-view, hybrid-composition, expensive-android-view, input-path, bench-surface
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The Android platform-view type that renders the ink surface.
///
/// This string has to match the value the Kotlin factory registers and the constant the Dart
/// plugin publishes. It is repeated here rather than imported so that the app does not depend on a
/// platform package, and a drift is not silent: a wrong type produces no view at all, and
/// `describeSurface` then reports `platformViewMode: none`, which the bench screen shows.
const String inkSurfaceViewTypeName = 'ink_native_android/surface';

/// The platform-view mode this app asks for, echoed back by the surface for the report.
const String hybridCompositionMode = 'hybridComposition';

/// Hosts the native ink surface.
class InkSurfaceHost extends StatelessWidget {
  /// Creates the host.
  const InkSurfaceHost({super.key, this.onCreated});

  /// Called on the Dart side once the platform view has been created.
  ///
  /// Needed because the surface's own description cannot be read before the view exists: the
  /// native plugin has no surface to describe until Flutter asks it for one, so a bench that read
  /// the description at startup would report `platformViewMode: none` on a device where the view
  /// was about to appear.
  final VoidCallback? onCreated;

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: inkSurfaceViewTypeName,
      onCreatePlatformView: _createPlatformView,
      surfaceFactory: _buildSurface,
    );
  }

  PlatformViewController _createPlatformView(
    PlatformViewCreationParams params,
  ) {
    // `initExpensiveAndroidView` is hybrid composition: the surface is inserted as a child in the
    // Android view hierarchy rather than rendered into a texture and composited by Flutter's
    // renderer. That is the path the ink latency budget assumes, because it avoids a texture copy
    // and one possible extra frame between the native frame and the presented frame.
    return PlatformViewsService.initExpensiveAndroidView(
        id: params.id,
        viewType: params.viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: const <String, Object?>{
          'platformViewMode': hybridCompositionMode,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onFocus: () => params.onFocusChanged(true),
      )
      ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
      ..addOnPlatformViewCreatedListener((int id) => onCreated?.call())
      ..create();
  }

  static Widget _buildSurface(
    BuildContext context,
    PlatformViewController controller,
  ) {
    return AndroidViewSurface(
      controller: controller as AndroidViewController,
      // Empty on purpose: claiming a gesture here would make Flutter's arena compete with the
      // native view for the pen, and a forwarded touch is later than a direct one.
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.opaque,
    );
  }
}
