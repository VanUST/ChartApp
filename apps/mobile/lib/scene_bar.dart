// PURPOSE: Be the strip above the chart that says and drives the one thing a musician can still
//          change about the page's presentation — its magnification — and nothing else. It is what
//          the scene bar became when the owner cut the application back to drawing: the position,
//          the tempo, the style, the key badge, the repeats and the page-mode switch were all
//          removed with the musical editing they served, and the zoom control, which is part of
//          NAVIGATION rather than of the music, stayed.
// INPUTS: zoom — the magnification actually on the glass, which is the drawn scale and not the
//         stored one; zoomLocked — whether the musician has pinned that number; compact — whether
//         the bar must fit a narrow surface, which drops the caption under the number but never the
//         buttons; and the three callbacks the controls invoke.
// OUTPUTS: A [Widget]. Nothing here reads or writes the document: every value is presentation, so
//          this bar cannot dirty a chart and cannot be undone. A surface that supplies no
//          [onZoomIn] or [onZoomOut] gets the button disabled rather than missing, because a
//          control that disappears moves the ones beside it.
// KEYWORDS: scene-bar, zoom, view-lock, navigation, chrome, presentation-only
//
// WHY THE NUMBER IS THE DRAWN SCALE AND NOT THE STORED ONE. While the view is locked the zoom is
// derived from the engraving, and a reading that showed the stored value would say ×1.0 over a page
// drawn at ×1.4. The bar reports what is on the glass, so the number and the page cannot disagree.
import 'package:chart_core/chart_core.dart' as core;
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'ui_kit.dart';

/// How a song is fitted onto the surface it is drawn on.
///
/// The MODE ITSELF survives the reset because the page still has to decide how to fit a chart on a
/// pane, and a phone and a tablet still decide differently. What was removed is the SWITCH: the
/// musician no longer chooses, because the choice was a scene-bar field and the owner removed those.
enum PageMode {
  /// Every system of the song on one page, scaled down to fit.
  fit,

  /// As many pages as the chart needs, at a legible scale.
  pages,
}

/// The width below which a surface gets the scene bar's narrow form.
const double sceneBarTabletWidth = 600;

/// The height below which a surface is too short for the scene bar's full form.
const double sceneBarTabletHeight = 600;

/// Names [key] in the language the surface is set to, which is what a chart list states about a
/// chart's own file.
///
/// A KEY IS DATA THE IMPORT CARRIES, not a control: this function only spells it, and nothing in the
/// application can change one any more.
String localizedKeyName(AppLocalizations l10n, core.Key key) =>
    key.mode == core.Mode.major
    ? l10n.keyNameMajor('${key.tonic}')
    : l10n.keyNameMinor('${key.tonic}');

/// The strip above the chart: the magnification, whether it is pinned, and the buttons that drive it.
class SceneBar extends StatelessWidget {
  /// Creates the bar for [zoom], pinned when [zoomLocked].
  const SceneBar({
    super.key,
    required this.zoom,
    required this.zoomLocked,
    this.compact = false,
    this.onZoomIn,
    this.onZoomOut,
    required this.onZoomReset,
  });

  /// The magnification on the glass, at or above 1.
  final double zoom;

  /// Whether the musician pinned the drawn scale, which is what stops a pinch from moving it.
  final bool zoomLocked;

  /// Whether the bar must fit a surface too narrow to carry a caption under each value.
  final bool compact;

  /// Raises the magnification, or null when the surface must not offer it.
  final VoidCallback? onZoomIn;

  /// Lowers the magnification, or null when the surface must not offer it.
  final VoidCallback? onZoomOut;

  /// Returns the view to the magnification the page was engraved at.
  final VoidCallback onZoomReset;

  /// The reading under the number: pinned or free, which is the state the buttons leave behind.
  String _caption(AppLocalizations l10n) =>
      zoomLocked ? l10n.zoomLockedTooltip : l10n.sceneCaptionZoom;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: UiKit.spaceL,
        vertical: UiKit.spaceS,
      ),
      child: Row(
        children: <Widget>[
          // The number itself is the reset: a musician who has lost the view wants the known
          // magnification back, and the number naming the current one is where he looks for it.
          Tooltip(
            message: l10n.zoomResetTooltip,
            child: InkWell(
              key: const ValueKey<String>('scene-zoom-reset'),
              onTap: onZoomReset,
              borderRadius: BorderRadius.circular(UiKit.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: UiKit.spaceS,
                  vertical: UiKit.spaceXs,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '×${zoom.toStringAsFixed(1)}',
                      style: text.titleSmall,
                      key: const ValueKey<String>('scene-zoom-value'),
                    ),
                    if (!compact)
                      Text(
                        _caption(l10n),
                        style: text.labelSmall,
                        key: const ValueKey<String>('scene-zoom-caption'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: UiKit.spaceS),
          _ZoomButton(
            fieldKey: 'scene-zoom-out',
            glyph: '−',
            tooltip: l10n.zoomOutTooltip,
            onTap: onZoomOut,
          ),
          _ZoomButton(
            fieldKey: 'scene-zoom-in',
            glyph: '+',
            tooltip: l10n.zoomInTooltip,
            onTap: onZoomIn,
          ),
        ],
      ),
    );
  }
}

/// One zoom button, sized for a thumb and disabled when its action is unavailable.
class _ZoomButton extends StatelessWidget {
  /// Creates the button labelled [glyph].
  const _ZoomButton({
    required this.fieldKey,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
  });

  /// The widget key a probe or a widget test looks the control up by.
  final String fieldKey;

  /// The glyph the button shows.
  final String glyph;

  /// The sentence the tooltip states.
  final String tooltip;

  /// What the button does, or null when it is unavailable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      key: ValueKey<String>(fieldKey),
      onPressed: onTap,
      icon: Text(glyph, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}
