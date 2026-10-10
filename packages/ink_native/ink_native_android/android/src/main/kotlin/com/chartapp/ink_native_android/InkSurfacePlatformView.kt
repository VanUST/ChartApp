// PURPOSE: Bridge the ink surface into Flutter's platform-view machinery, so the drawing view is
//          created by Flutter at the right moment and disposed when Flutter drops it, and so the
//          plugin learns about the view without the view knowing about Flutter.
// INPUTS: The platform-view registry's creation parameters, which carry the mode the Dart side
//         chose (`hybridComposition`), and a callback the plugin uses to attach itself.
// OUTPUTS: A PlatformView wrapping the surface, and one call to the creation callback per view
//          created. `dispose` releases the surface's frame callback and its bitmap.
// KEYWORDS: platform-view, view-factory, hybrid-composition, disposal, lifecycle
package com.chartapp.ink_native_android

import android.content.Context
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** The view type the Dart side must ask for; the two sides must agree on this exact string. */
const val INK_SURFACE_VIEW_TYPE: String = "ink_native_android/surface"

/** The creation-parameter key carrying which platform-view mode the Dart side selected. */
const val PLATFORM_VIEW_MODE_KEY: String = "platformViewMode"

// PURPOSE: Present the ink surface as a Flutter PlatformView and forward its disposal, so the
//          native surface's Choreographer callback and bitmap cannot outlive the widget tree.
// INPUTS: The surface built by [InkSurfaceViewFactory].
// OUTPUTS: [getView] returns that surface; [dispose] tears it down.
// KEYWORDS: platform-view, wrapper, disposal
class InkSurfacePlatformView(
    private val surface: InkSurfaceView,
) : PlatformView {
    override fun getView(): View = surface

    override fun dispose() {
        surface.dispose()
    }
}

// PURPOSE: Build ink surfaces for Flutter, reading the platform-view mode out of the creation
//          parameters so the surface reports what actually happened rather than a constant the
//          native side assumed.
// INPUTS: [onCreated] — invoked once per surface, on the platform thread, before it is returned.
// OUTPUTS: A new [InkSurfacePlatformView] wrapping a new [InkSurfaceView]. An absent or
//          non-string mode parameter yields the mode `unknown`, which a bench report can then
//          show, instead of being silently reported as hybrid composition.
// KEYWORDS: platform-view-factory, creation-params, honest-mode, view-registration
class InkSurfaceViewFactory(
    private val onCreated: (InkSurfaceView) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *>
        val mode = (parameters?.get(PLATFORM_VIEW_MODE_KEY) as? String) ?: "unknown"
        val surface = InkSurfaceView(context, mode)
        onCreated(surface)
        return InkSurfacePlatformView(surface)
    }
}
