// PURPOSE: Draw the scene bar — the one line a musician reads on stage: where they are in the
//          playlist, how fast the tune is, what it is, what key it is being shown in, how many
//          repeats it carries, and whether the whole song is on one page. Every reading control
//          lives here so the performance surface has one place to look, and the key badge is the
//          handle that opens the twelve-key grid.
// INPUTS: The displayed position, the displayed song (already transposed for the screen), the
//         interval it was transposed by, the current page mode, and the callbacks that open the
//         key grid and change the mode.
// OUTPUTS: A dark, high-contrast bar. It wraps onto more lines rather than clipping or scrolling,
//          so every field stays visible and tappable on a phone as well as a tablet.
// KEYWORDS: scene-bar, performance-surface, pos-over-n, bpm, style, key-badge, repeats,
//           fit-pages-toggle, dark-surface, arm-length
//
// WHY IT IS DARK AND LARGE. This is the surface a musician reads in a dark room from an arm's
// length away, so the bar carries its own colours instead of following the application theme, and
// no text is smaller than 16 logical pixels except the one-word captions. The chart page itself
// stays white: paper is what a chart page looks like, and this bar is chrome around it.

import 'package:chart_core/chart_core.dart';
import 'package:flutter/material.dart';

/// How a song is placed on the surface it is read on (owner decision D13).
enum PageMode {
  /// Every system of the song on one page, scaled down to fit.
  ///
  /// The default in the editor on a tablet: a whole tune on one screen is what a reader wants
  /// while working, and the fit reports honestly when the song is too long to stay legible.
  fit,

  /// The song paginated at the surface's own size, one page at a time.
  ///
  /// The default on a phone, where a fitted page of a long tune would be unreadable, and the
  /// scene default once a setlist exists.
  pages,
}

/// The dark background of the scene bar.
const Color sceneBarColor = Color(0xFF0B1622);

/// The colour of the scene bar's values.
const Color sceneBarTextColor = Color(0xFFF5F8FB);

/// The colour of the scene bar's small captions.
const Color sceneBarCaptionColor = Color(0xFF8FA8C0);

/// The accent used for the key badge and the active page mode.
const Color sceneBarAccent = Color(0xFFFFC857);

/// The width from which a surface counts as a tablet for the default page mode.
const double sceneBarTabletWidth = 600;

/// The scene bar: position, tempo, style, key badge, repeats and the page-mode toggle.
class SceneBar extends StatelessWidget {
  /// Creates a scene bar for one displayed song.
  const SceneBar({
    super.key,
    required this.position,
    required this.songCount,
    required this.song,
    required this.semitones,
    required this.pageMode,
    required this.onOpenKeyGrid,
    required this.onPageModeChanged,
  });

  /// The displayed song's one-based position in the loaded playlist.
  final int position;

  /// How many songs the loaded playlist holds.
  final int songCount;

  /// The song as displayed, already transposed, whose key, tempo and style are shown.
  final Song song;

  /// The interval from the written key that produced [song], in semitones.
  final int semitones;

  /// The page mode currently in force.
  final PageMode pageMode;

  /// Called when the key badge is pressed, to open the twelve-key grid.
  final VoidCallback onOpenKeyGrid;

  /// Called when the musician picks the other page mode.
  final ValueChanged<PageMode> onPageModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('scene-bar'),
      color: sceneBarColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _Field(
            fieldKey: 'scene-bar-pos',
            caption: 'POS',
            value: '$position/$songCount',
          ),
          _separator(),
          _Field(
            fieldKey: 'scene-bar-bpm',
            caption: 'BPM',
            value: song.tempo > 0 ? '${song.tempo}' : '—',
          ),
          _separator(),
          _Field(
            fieldKey: 'scene-bar-style',
            caption: 'STYLE',
            value: song.style.isEmpty ? '—' : song.style,
          ),
          _separator(),
          _KeyBadge(
            key: const ValueKey<String>('scene-bar-key-badge'),
            song: song,
            semitones: semitones,
            onTap: onOpenKeyGrid,
          ),
          _separator(),
          _Field(
            fieldKey: 'scene-bar-repeat',
            caption: 'REPEATS',
            value: repeatSummary(song),
          ),
          _separator(),
          _PageModeToggle(mode: pageMode, onChanged: onPageModeChanged),
        ],
      ),
    );
  }

  /// The thin rule between two fields, so the eye separates values without a heavy border.
  Widget _separator() =>
      Container(width: 1, height: 34, color: const Color(0xFF24405C));
}

/// The summary of the repeats and alternative endings a song carries.
///
/// A musician standing in front of a chart wants to know before starting whether the tune repeats
/// and how many endings there are. The count is of the bars that START a repeated passage, the
/// brackets drawn, and the `%` bars, which is what can be seen on the page; expanding the passage
/// into a play order is a different question the model does not yet answer.
///
/// [song] with no repeat sign at all returns `none`, so an absence is stated rather than shown as
/// an empty field.
String repeatSummary(Song song) {
  int passages = 0;
  int voltas = 0;
  int previousBars = 0;
  for (final Section section in song.sections) {
    for (final Bar bar in section.bars) {
      if (bar.startsRepeat) {
        passages++;
      }
      if (bar.volta != null) {
        voltas++;
      }
      if (bar.repeatPrevious != RepeatPrevious.none) {
        previousBars++;
      }
    }
  }
  final List<String> parts = <String>[];
  if (passages > 0) {
    parts.add('$passages×');
  }
  if (voltas > 0) {
    parts.add('$voltas volta');
  }
  if (previousBars > 0) {
    parts.add('$previousBars %');
  }
  return parts.isEmpty ? 'none' : parts.join(' · ');
}

/// One captioned value in the bar.
class _Field extends StatelessWidget {
  /// Creates a field with a [caption] above its [value], carrying [fieldKey] for tests.
  const _Field({
    required this.fieldKey,
    required this.caption,
    required this.value,
  });

  /// The value.
  final String value;

  /// The one-word caption above it.
  final String caption;

  /// The widget key the tests find this field by.
  final String fieldKey;

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey<String>(fieldKey),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        caption,
        style: const TextStyle(
          color: sceneBarCaptionColor,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
      Text(
        value,
        style: const TextStyle(
          color: sceneBarTextColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// The key the chart is shown in, and the handle that opens the twelve-key grid.
class _KeyBadge extends StatelessWidget {
  /// Creates a badge for [song] shown at [semitones] from the written key.
  const _KeyBadge({
    super.key,
    required this.song,
    required this.semitones,
    required this.onTap,
  });

  /// The displayed song.
  final Song song;

  /// The interval from the written key.
  final int semitones;

  /// Called when the badge is pressed.
  final VoidCallback onTap;

  /// The badge label: the key and the interval a musician would say, in that order.
  ///
  /// The interval is always shown, including `+0 st` in the written key, because a musician thinks
  /// in both a key and a distance, and a hidden zero would make "written" and "moved" look alike.
  String get label => '${song.key} · ${semitones > 0 ? '+' : ''}$semitones st';

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sceneBarAccent, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'KEY · tap to transpose',
            style: TextStyle(
              color: sceneBarCaptionColor,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: sceneBarAccent,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The FIT | PAGES control.
class _PageModeToggle extends StatelessWidget {
  /// Creates a toggle showing [mode] and reporting picks to [onChanged].
  const _PageModeToggle({required this.mode, required this.onChanged});

  /// The mode currently in force.
  final PageMode mode;

  /// Called with the other mode when it is picked.
  final ValueChanged<PageMode> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('scene-bar-page-mode'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text(
        'PAGE',
        style: TextStyle(
          color: sceneBarCaptionColor,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
      Row(
        children: <Widget>[
          _ModeButton(
            fieldKey: 'scene-bar-mode-fit',
            text: 'FIT',
            active: mode == PageMode.fit,
            onTap: () => onChanged(PageMode.fit),
          ),
          _ModeButton(
            fieldKey: 'scene-bar-mode-pages',
            text: 'PAGES',
            active: mode == PageMode.pages,
            onTap: () => onChanged(PageMode.pages),
          ),
        ],
      ),
    ],
  );
}

/// One half of the page-mode toggle.
class _ModeButton extends StatelessWidget {
  /// Creates a button labelled [text], active when [active], calling [onTap] when pressed.
  const _ModeButton({
    required this.fieldKey,
    required this.text,
    required this.active,
    required this.onTap,
  });

  /// The label.
  final String text;

  /// Whether this is the mode in force.
  final bool active;

  /// Called when the button is pressed.
  final VoidCallback onTap;

  /// The widget key the tests find this button by.
  final String fieldKey;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey<String>(fieldKey),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? sceneBarAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? sceneBarAccent : sceneBarCaptionColor,
          width: 1.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? sceneBarColor : sceneBarTextColor,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
